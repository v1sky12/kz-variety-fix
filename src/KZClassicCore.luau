-- Classic KZ formulas adapted from KZGlobalTeam/cs2kz-metamod.
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Roblox contact handling is separate; this module uses CS units and seconds.
local Core = {}
Core.Profile = {
    GroundSpeed = 250, GroundAccel = 6.5, GroundFriction = 5.2, StopSpeed = 80,
    AirAccel = 100, AirWishSpeed = 250, AirCap = 30,
    Gravity = 800, JumpImpulse = 302, MaxVelocity = 3500,
    PreBonus = 26, PreBuildTime = 0.5, PreHistoryWindow = 0.02,
    PreMinAngle = 2, PreFullAngle = 15.5, PreDecayRate = 3,
    PreExponent = 0.5, PreLandingGrace = 0.25,
    PerfWindow = 0.02, BhopMultiplier = 51.5, BhopLandingPenalty = 75,
}
local P = Core.Profile
local normalizeFactor = P.BhopMultiplier * math.log(P.GroundSpeed + P.PreBonus)
    - (P.GroundSpeed + P.PreBonus)
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
function Core.newPre()
    return {left = 0, right = 0, bonus = 0, time = 0, history = {}, average = 0}
end
function Core.preGain(s)
    return P.PreBonus * (math.max(s.left, s.right) / P.PreBuildTime) ^ P.PreExponent
end
function Core.accelerate(v, wish, wishSpeed, acceleration, dt, projectionCap)
    if wish.Magnitude < 1e-6 then return v end
    -- CKZ/CS2: cap the projected wishspeed, while acceleration uses the
    -- uncapped wishspeed (the behavior used by cs2kz-metamod jumpstats).
    local projectionLimit = projectionCap or wishSpeed
    local available = projectionLimit - v:Dot(wish)
    if available <= 0 then return v end
    local accelerationSpeed = acceleration * wishSpeed * dt
    return v + wish * math.min(available, accelerationSpeed)
end
function Core.friction(v, dt)
    local speed = v.Magnitude
    if speed < 1e-6 then return Vector3.zero end
    local after = math.max(0, speed - math.max(speed, P.StopSpeed) * P.GroundFriction * dt)
    return v * (after / speed)
end
function Core.updatePre(s, v, wish, grounded, dt, groundAge)
    s.time = s.time + dt
    local h = s.history
    while h[1] and h[1].time + P.PreHistoryWindow < s.time do table.remove(h, 1) end
    if grounded then
        local angle = 0
        if v.Magnitude > 1e-6 and wish.Magnitude > 1e-6 then
            local d = v.Unit
            angle = math.deg(math.atan2(d.X * wish.Z - d.Z * wish.X, d:Dot(wish)))
        end
        h[#h + 1] = {time = s.time, duration = dt, angle = angle}
    end
    local sum, duration = 0, 0
    for _, sample in ipairs(h) do
        sum = sum + sample.angle * sample.duration
        duration = duration + sample.duration
    end
    local avg = duration > 0 and sum / duration or 0
    s.average = avg
    if grounded and groundAge > P.PerfWindow then
        local speed = clamp(v.Magnitude, 0, P.GroundSpeed)
        local recover = speed > 0 and
            (s.bonus / P.PreBonus * P.GroundSpeed / speed) ^ (1 / P.PreExponent) * P.PreBuildTime or 0
        s.left, s.right = math.min(s.left, recover), math.min(s.right, recover)
        local reward = clamp(math.abs(avg) / P.PreFullAngle, 0, 1) * dt
        local penalty = groundAge > P.PreLandingGrace and dt * P.PreDecayRate or 0
        s.left = clamp(s.left + (avg > P.PreMinAngle and reward or -penalty), 0, P.PreBuildTime)
        s.right = clamp(s.right + (avg < -P.PreMinAngle and reward or -penalty), 0, P.PreBuildTime)
        s.bonus = Core.preGain(s) * speed / P.GroundSpeed
    else
        -- Pre-keep: equalize the weaker direction without inventing extra gain.
        if s.left < s.right then s.left = math.min(s.left + dt, s.right)
        else s.right = math.min(s.right + dt, s.left) end
    end
    return Core.preGain(s)
end
function Core.step(v, wish, grounded, dt, pre, groundAge, speedFactor)
    local bonus = Core.updatePre(pre, v, wish, grounded, dt, groundAge or math.huge)
    if grounded then
        v = Core.friction(v, dt)
        return Core.accelerate(v, wish, (P.GroundSpeed + bonus) * (speedFactor or 1), P.GroundAccel, dt)
    end
    return Core.accelerate(v, wish, P.AirWishSpeed, P.AirAccel, dt, P.AirCap)
end
function Core.perfSpeed(landingSpeed, takeoffSpeed, bonus, groundTime)
    local speed = math.max(landingSpeed, takeoffSpeed)
    if groundTime < 0 or groundTime > P.PerfWindow then return takeoffSpeed, false end
    local baseline = P.GroundSpeed + bonus
    if speed > baseline then
        local reduced = (P.BhopMultiplier - groundTime * P.BhopLandingPenalty)
            * math.log(speed) - normalizeFactor
        speed = math.max(baseline, math.min(speed, reduced))
    end
    return speed, true
end
function Core.clip(v, normal)
    local into = v:Dot(normal)
    return into < 0 and v - normal * into or v
end
-- The compatibility motor writes only X/Z. Project a tilted wall normal
-- into that same plane before clipping, so dropping Y cannot restore inward speed.
function Core.clipHorizontal(v, normals)
    local out = Vector3.new(v.X, 0, v.Z)
    local planes = {}
    for _, normal in ipairs(normals) do
        local n = Vector3.new(normal.X, 0, normal.Z)
        if n.Magnitude > 1e-6 then
            n = n.Unit
            planes[#planes + 1] = n
            out = Core.clip(out, n)
            for _, prior in ipairs(planes) do
                -- In a closed two-plane corner the horizontal intersection is zero.
                -- A second projection must not reintroduce motion into the first wall.
                if out:Dot(prior) < -1e-6 then return Vector3.zero end
            end
        end
    end
    return out
end
-- Resolve intended movement into a vertical ladder plane.
-- Matches the Source decomposition: inward movement becomes upward movement.
function Core.ladderVelocity(input, normal)
    local tangent=Vector3.new(-normal.Z,0,normal.X)
    local into=input:Dot(normal)
    local sideways=input:Dot(tangent)
    local incidence=math.sqrt(sideways*sideways+into*into)
    if incidence>1e-6 and into/incidence < -.707 then sideways=sideways*.2 end
    return tangent*sideways+Vector3.new(0,input.Y-into,0)
end
return Core
