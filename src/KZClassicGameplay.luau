-- kz_variety_fix / Classic KZ gameplay. ServerScriptService.
-- Source I/O, zone bounds and destinations are recovered from the supplied VMAP.
-- Records below are session records for this Roblox server, not CYBERSHOKE records.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local PhysicsService = game:GetService("PhysicsService")
local shared = ReplicatedStorage:WaitForChild("KZClassic", 15)
assert(shared, "Install KZClassic shared modules first")
local Data = require(shared:WaitForChild("KZMapData"))
local Core = require(shared:WaitForChild("KZClassicCore"))
local Net = shared:WaitForChild("Action")
local map = Data.findMap(workspace) or workspace:WaitForChild("KZ_Variety_CS2_ROBLOX_V21",15)
assert(map and map:IsA("Model"), "Active V21/V20/V19/V18/V17 map is missing")
Data.addPracticeZones(map)
Data.addBlockZones(map)
local unit = Data.unitFor(map)
local states, records, connections = {}, {}, {}
local sessionBest
local function connect(event, fn)
    local c = event:Connect(fn); connections[#connections + 1] = c; return c
end
local function number(v, fallback) return tonumber(v) or fallback end
local function validView(v)
    return typeof(v)=="Vector3" and v.X==v.X and v.Y==v.Y and v.Z==v.Z and v.Magnitude>=.9 and v.Magnitude<=1.1
end
local function now() return workspace:GetServerTimeNow() end
local function attr(player, name, value) player:SetAttribute("KZ" .. name, value) end
local function message(player, text) Net:FireClient(player, "Message", text) end
local function characterParts(player)
    local c = player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if not h or not r or h.Health <= 0 then return end
    return c, h, r
end
local Blocks=require(shared:WaitForChild("KZBlockController"))
local function grounded(player)
    local c, h, r = characterParts(player)
    if not r then return false end
    local state=states[player]
    local motion=state and state.motion
    local velocity=motion and now()-motion.received<.3 and motion.velocity or r.AssemblyLinearVelocity
    if velocity.Y>140*unit then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {map}
    params.RespectCanCollide = true
    params.CollisionGroup = r.CollisionGroup
    -- Match the motor's 32-unit footprint, 2-unit ground probe and walkable
    -- normal. A centre ray incorrectly reports air when standing on an edge.
    local height=motion and now()-motion.received<.3 and motion.height or (state and state.crouched and 54 or 72)
    local feet=r.Position-Vector3.new(0,Data.standingHeight(r,h),0)
    local water=Data.modifiers(map,Data.sourcePoint(map,feet),height,state)
    if water.water or water.waterLevel>0 and velocity.Y>0 then return false end
    local center=feet+Vector3.new(0,(height/2+.05)*unit,0)
    local adapter={trace=function(_,position,delta,half)
        local native=workspace:Blockcast(CFrame.new(position),half*2,delta,params)
        local fraction=native and math.clamp(native.Distance/delta.Magnitude,0,1) or 1
        return {fraction=fraction,normal=native and native.Normal,position=position+delta*fraction}
    end}
    local hit=Core.traceGround(adapter,center,Vector3.new(0,-2.05*unit,0),Vector3.new(15.999,height/2-.001,15.999)*unit,unit)
    return hit.fraction<1 and hit.normal and hit.normal.Y>=Core.Profile.WalkableNormal or false
end
local function resetCheckpoints(player, s, resetTeleports)
    s.checkpoints = {}; s.index = 0
    if resetTeleports~=false then s.teleports=0 end
    attr(player, "CheckpointIndex", 0); attr(player, "CheckpointCount", 0)
    attr(player, "TeleportCount", s.teleports)
end
local function resetMapState(s)
    s.attributes, s.disabled, s.fired, s.inside, s.touches, s.pending = {}, {}, {}, {}, {}, {}
    s.pushPending, s.pushPendingById, s.pushTimes = {}, {}, {}
    s.lastClientJumpId=nil;s.motion=nil;s.motionSequence=nil;s.lastMotionAt=nil;s.sentRevision=nil
    s.mapRevision=(s.mapRevision or 0)+1;s.previousFeet=nil
    s.activatorName = ""; Blocks.reset(s)
end
local function publishRecords()
    local sorted = {}
    for id, best in pairs(records) do sorted[#sorted + 1] = {id = id, time = best} end
    table.sort(sorted, function(a, b) return a.time < b.time end)
    for _, player in ipairs(Players:GetPlayers()) do
        attr(player, "WorldRecordSeconds", sessionBest)
        attr(player, "Rank", nil); attr(player, "RankTotal", #sorted)
        for rank, entry in ipairs(sorted) do if entry.id == player.UserId then attr(player, "Rank", rank) end end
    end
end
local function startRun(player, s, crossingTime)
    if s.spectating then return end
    s.start = crossingTime or now(); s.elapsed = 0; s.runState = "Running"; s.runId = s.runId + 1
    resetCheckpoints(player, s)
    Blocks.reset(s);s.pushPending={};s.pushPendingById={};s.pushTimes={}; s.invalid = false
    attr(player, "RunId", s.runId); attr(player, "RunState", "Running")
    attr(player, "RunStartTime", s.start); attr(player, "RunElapsed", 0)
    attr(player, "Stage", 1); attr(player, "RunCategory", "PRO")
end
local function stopRun(player, s, status, crossingTime)
    if s.runState == "Running" then s.elapsed = math.max(0,(crossingTime or now()) - s.start) end
    s.runState = status
    attr(player, "RunState", status); attr(player, "RunElapsed", s.elapsed)
end
local function finishRun(player, s, crossingTime)
    if s.runState ~= "Running" then return end
    stopRun(player, s, "Finished",crossingTime)
    local category = s.teleports == 0 and "PRO" or "TP"
    attr(player, "RunCategory", category)
    message(player, string.format("%s: %.3f s · CP %d · TP %d", category, s.elapsed, #s.checkpoints, s.teleports))
    -- Compare only uninterrupted PRO runs; practice teleports have a separate PB.
    if category == "PRO" and not s.invalid then
        records[player.UserId] = math.min(records[player.UserId] or math.huge, s.elapsed)
        sessionBest = math.min(sessionBest or math.huge, s.elapsed)
        attr(player, "PersonalBestSeconds", records[player.UserId]); publishRecords()
    elseif category == "TP" then
        s.tpBest = math.min(s.tpBest or math.huge, s.elapsed)
        attr(player, "TPPersonalBestSeconds", s.tpBest)
    end
end
local function moveTo(player, s, destination, angles, resetSpeed, countPractice, relative)
    local c, h, r = characterParts(player)
    if not r or now() < (s.lastWarp or 0) + .08 then return false end
    s.lastWarp = now()
    local feet = Data.worldPoint(map, destination)
    if relative then feet = feet + relative end
    local target = feet + Vector3.new(0, Data.standingHeight(r,h) + .015, 0)
    local yaw = math.rad((angles and angles[2]) or 0)
    local forward = angles and map:GetPivot():VectorToWorldSpace(Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))) or r.CFrame.LookVector
    local oldVelocity = s.motion and now()-s.motion.received<.3 and s.motion.velocity or r.AssemblyLinearVelocity
    r.CFrame = CFrame.lookAt(target, target + forward)
    r.AssemblyLinearVelocity = resetSpeed and Vector3.zero or oldVelocity
    r.AssemblyAngularVelocity = Vector3.zero
    s.teleportSerial = s.teleportSerial + 1
    Blocks.reset(s)
    attr(player, "TeleportSerial", s.teleportSerial)
    -- Client acknowledges every warp, including short checkpoint teleports.
    Net:FireClient(player, "Warp", s.teleportSerial, angles, resetSpeed, oldVelocity,r.CFrame)
    s.motion=nil;s.motionSequence=nil;s.sentRevision=nil;s.wasGrounded=false;s.groundSince=nil;s.previousFeet=nil
    for i=#(s.pushPending or {}),1,-1 do
        local pending=s.pushPending[i]
        if pending.cancelOnTeleport then
            s.pushPendingById[pending.id]=nil;table.remove(s.pushPending,i)
        else pending.serial=s.teleportSerial end
    end
    s.inside, s.touches, s.pending = {}, {}, {}
    if countPractice then
        s.teleports = s.teleports + 1; attr(player, "TeleportCount", s.teleports)
        if s.runState == "Running" then attr(player, "RunCategory", "TP") end
    end
    return true
end
local function startDestination()
    return Data.byName.climb_start
end
local function setCrouch(player, s, wanted)
    local c, h, r = characterParts(player)
    if not r or not s.hull or not s.hull.Parent or s.crouched == wanted then return end
    local normalHeight, duckHeight = 72 * unit, 54 * unit
    local delta = normalHeight - duckHeight
    if not wanted then
        local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {c}; params.RespectCanCollide = true
        params.CollisionGroup = r.CollisionGroup
        local direction = s.airDuck and not grounded(player) and -delta or delta
        local hit = workspace:Blockcast(s.hull.CFrame, s.hull.Size - Vector3.new(.02, .02, .02),
            Vector3.new(0, direction, 0), params)
        if hit then return end -- Stay crouched below a ceiling.
    end
    local height = wanted and duckHeight or normalHeight
    -- Keep the assembly root and foot plane fixed. Writing a server CFrame
    -- during client-owned movement rewinds X/Z to a delayed server position.
    local standing = s.normalStanding
    s.airDuck = wanted and not grounded(player) or false
    s.crouched = wanted
    h.HipHeight = Data.hipHeight(r,h,standing)
    s.hull.Size = Vector3.new(32 * unit, height, 32 * unit)
    s.hullWeld.C0 = Data.hullOffset(map,r,height,standing)
    attr(player, "AirDuck", s.airDuck)
    attr(player, "Crouched", wanted)
end
local function installHull(player, s, c)
    local h = c:WaitForChild("Humanoid", 10); local r = c:WaitForChild("HumanoidRootPart", 10)
    if not h or not r or player.Character ~= c then return end
    s.wasGrounded = false; s.groundSince = nil
    s.originalAutoRotate = h.AutoRotate
    s.normalStanding = Data.standingHeight(r,h)
    s.crouched = false; s.crouchWanted = false; s.airDuck=false
    attr(player, "AirDuck", false); attr(player, "Crouched", false)
    s.originalParts = {}
    local function partAdded(part)
        if not part:IsA("BasePart") or part.Name == "KZSourceHull" then return end
        s.originalParts[part] = {collide = part.CanCollide, group = part.CollisionGroup}
        part.CanCollide = false; part.CollisionGroup = "KZClassicPlayers"
    end
    for _, part in ipairs(c:GetDescendants()) do partAdded(part) end
    if s.partConnection then s.partConnection:Disconnect() end
    s.partConnection = c.DescendantAdded:Connect(partAdded)
    local hull = Instance.new("Part"); hull.Name = "KZSourceHull"
    hull.Size = Vector3.new(32 * unit, 72 * unit, 32 * unit)
    hull.Transparency = 1; hull.Massless = true; hull.CanCollide = true
    hull.CanTouch = false; hull.CanQuery = false; hull.CastShadow = false
    hull.CollisionGroup = "KZClassicPlayers"
    hull.CustomPhysicalProperties = PhysicalProperties.new(.7, 0, 0, 100, 100)
    hull.CFrame = r.CFrame * Data.hullOffset(map,r,hull.Size.Y,s.normalStanding)
    hull.Parent = c
    local weld = Instance.new("Weld"); weld.Name = "KZSourceHullWeld"
    weld.Part0 = r; weld.Part1 = hull
    weld.C0 = Data.hullOffset(map,r,hull.Size.Y,s.normalStanding); weld.Parent = hull
    s.hull, s.hullWeld = hull, weld
    attr(player, "SourceHullReady", true)
    h.AutoRotate = false
    local dest = startDestination()
    if dest then s.lastWarp = nil; moveTo(player, s, dest.origin, dest.angles, true, false) end
    connect(h.Died, function()
        if s.runState == "Running" then stopRun(player, s, "Aborted") end
    end)
end
pcall(function() PhysicsService:RegisterCollisionGroup("KZClassicPlayers") end)
PhysicsService:CollisionGroupSetCollidable("KZClassicPlayers", "KZClassicPlayers", false)

local function applyOutput(player, s, connection)
    local target, input, value = connection.targetName, connection.inputName:lower(), connection.overrideParam
    s.mapRevision=(s.mapRevision or 0)+1
    if target == "!activator" then
        value = (value or ""):gsub("%[PR#%]", "")
        if input == "addattribute" then s.attributes[value] = 1
        elseif input == "removeattribute" then s.attributes[value] = nil
        elseif input == "addoutput" then s.activatorName = value:match("targetname%s+(.+)") or s.activatorName end
    else
        local e = Data.byName[target]
        if not e then return end
        if input == "enable" then s.disabled[e.id] = false
        elseif input == "disable" then s.disabled[e.id] = true end
        -- Arbitrary server console commands from the source map are not executed.
    end
end
local function outputs(player, s, e, event, crossingTime)
    for i, connection in ipairs(e.connections or {}) do
        if connection.outputName == event then
            local key = e.id .. ":" .. i
            local limit = number(connection.timesToFire, -1)
            if limit < 0 or (s.fired[key] or 0) < limit then
                s.fired[key] = (s.fired[key] or 0) + 1
                s.outputSequence=(s.outputSequence or 0)+1
                local delay=number(connection.delay,0)
                if delay<=0 then applyOutput(player,s,connection)
                else s.pending[#s.pending + 1] = {due = (crossingTime or now()) + delay, connection = connection,order=s.outputSequence} end
            end
        end
    end
end
local function teleportEntity(player, s, e)
    local p = e.properties
    local dest,isCheckpoint = Blocks.resolveDestination(e,s.checkpoints,s.index,Data.byName)
    if not dest then return false end
    local _, h, r = characterParts(player)
    local relative
    if p.timer_teleport_relative == "1" and r then
        relative = r.Position - Vector3.new(0,Data.standingHeight(r,h),0) - Data.worldPoint(map, e.origin)
    end
    if isCheckpoint then s.crouchWanted=dest.crouched;if dest.crouched then setCrouch(player,s,true) end end
    local moved=moveTo(player, s, dest.origin, p.timer_teleport_use_dest_angles == "0" and nil or dest.angles,
        p.timer_teleport_reset_speed ~= "0", isCheckpoint, relative)
    if moved and isCheckpoint and not dest.crouched then setCrouch(player,s,false) end
    return moved
end
local function push(player, s, e, condition)
    local p = e.properties
    if p["timer_push_condition_" .. condition] ~= "1" then return end
    local time = now()
    s.pushTimes = s.pushTimes or {}
    s.pushPendingById = s.pushPendingById or {}
    if s.pushPendingById[e.id] then return end
    if time < (s.pushTimes[e.id] or -math.huge) then return end
    s.pushTimes[e.id] = time + math.max(0,number(p.timer_push_delay,0)) + math.max(0,number(p.timer_push_cooldown,.1))
    local x, y, z = (p.timer_push_amount or "0 0 0"):match("([^ ]+) +([^ ]+) +([^ ]+)")
    local amount = Data.worldVector(map, {number(x, 0), number(y, 0), number(z, 0)})
    -- Source push flags are ordered X/Y/Z. Delay is measured from the
    -- qualifying touch/jump event, and pending pushes are cleared by teleports.
    local absolute = {p.timer_push_abs_speed_x == "1",
        p.timer_push_abs_speed_y == "1", p.timer_push_abs_speed_z == "1"}
    local delay = math.max(0, number(p.timer_push_delay, 0))
    if delay > 0 then
        s.pushPending = s.pushPending or {}
        s.pushPendingById[e.id] = true
        s.pushSequence=(s.pushSequence or 0)+1
        s.pushPending[#s.pushPending + 1] = {id=e.id, due=time+delay, amount=amount,order=s.pushSequence,
            absolute=absolute, serial=s.teleportSerial,cancelOnTeleport=p.timer_push_cancel_on_teleport~="0"}
    else
        Net:FireClient(player, "Push", amount, {absolute[2],absolute[3],absolute[1]}, s.teleportSerial,absolute)
    end
end
local function legacyPush(player,s,e,duration)
    local pitch,yaw=(e.properties.pushdir or '0 0 0'):match('([^ ]+) +([^ ]+)')
    pitch,yaw=math.rad(number(pitch,0)),math.rad(number(yaw,0))
    local speed=number(e.properties.speed,100)*duration
    local velocity=Data.worldVector(map,{math.cos(pitch)*math.cos(yaw)*speed,
        math.cos(pitch)*math.sin(yaw)*speed,-math.sin(pitch)*speed})
    Net:FireClient(player,'Push',velocity,{false,false,false},s.teleportSerial)
end
local function action(player, name, payload)
    local s = states[player]; if not s then return end
    local time = now()
    if name=="MotorReset" then
        local c=characterParts(player)
        if type(payload)=="table" and c and payload.character==c and payload.teleportSerial==s.teleportSerial
            and time>=(s.lastBackendReset or -math.huge)+.1 then
            s.lastBackendReset=time;s.motion=nil;s.motionSequence=nil;s.lastMotionAt=nil;s.lastClientJumpId=nil
        end
        return
    end
    if name == "Motion" then
        local c,h,r=characterParts(player)
        if not r or type(payload)~="table" or payload.character~=c or payload.teleportSerial~=s.teleportSerial
            or type(payload.sequence)~="number" or payload.sequence%1~=0 or payload.sequence<1
            or payload.sequence<=(s.motionSequence or 0) or payload.sequence>1e12
            or typeof(payload.feet)~="Vector3" or typeof(payload.velocity)~="Vector3" then return end
        local v,f=payload.velocity,payload.feet
        if v.X~=v.X or v.Y~=v.Y or v.Z~=v.Z or f.X~=f.X or f.Y~=f.Y or f.Z~=f.Z
            or v.Magnitude>6100*unit or f.Magnitude>1000000 then return end
        local reported=Data.worldPoint(map,{f.X,f.Y,f.Z})
        local actual=r.Position-Vector3.new(0,Data.standingHeight(r,h),0)
        if (reported-actual).Magnitude>256*unit or time<(s.lastMotionAt or -math.huge)+.025 then return end
        local view=payload.view
        if view~=nil and not validView(view) then return end
        if payload.height~=nil and payload.height~=54 and payload.height~=72 then return end
        if not s.motion then s.sentRevision=nil end
        s.motion={velocity=v,received=time,view=view,height=payload.height or (s.crouched and 54 or 72)};s.motionSequence=payload.sequence;s.lastMotionAt=time
        return
    end
    if name == "Crouch" then
        if type(payload) ~= "boolean" then return end
        -- Retain the latest intent even if a fast release is rate-limited.
        s.crouchWanted = payload
        if time >= (s.lastCrouchAction or 0) + .03 then
            s.lastCrouchAction = time
        end
        return
    end
    local bucket = name == "LadderAttach" and "lastLadderAttachAction" or "lastAction"
    if name ~= "Jump" and time < (s[bucket] or 0) + .08 then return end
    s[bucket] = time
    local c, h, r = characterParts(player)
    if not r then return end
    local feet = Data.feetSource(map, r, h)
    local mods = Data.modifiers(map, feet, s.crouched and 54 or 72,s)
    if name == "Spectate" then
        if payload == nil or payload == 0 then
            s.spectating = nil; attr(player, "SpectatingUserId", nil)
            r.Anchored = s.beforeSpectateAnchored or false
            r.AssemblyLinearVelocity = Vector3.zero
        elseif type(payload) == "number" and payload ~= player.UserId and Players:GetPlayerByUserId(payload) then
            if s.runState == "Running" then stopRun(player, s, "Aborted") end
            if not s.spectating then s.beforeSpectateAnchored = r.Anchored end
            s.spectating = payload
            attr(player, "SpectatingUserId", payload); r.Anchored = true
        end
        return
    end
    if s.spectating then return end
    if name == "LadderAttach" then
        if typeof(payload)~="table" or type(payload.id)~="number" or payload.id~=payload.id
            or payload.id%1~=0 or payload.id<1 or payload.id>10000
            or payload.teleportSerial~=s.teleportSerial then return end
        local height=s.crouched and 54 or 72
        local reported
        for _,ladder in ipairs(Data.ladderSurfaces) do
            if ladder.id==payload.id then reported=ladder;break end
        end
        if not reported or Data.findLadder(feet,height,reported)~=reported then return end
        for _,e in ipairs(Data.zones) do
            local kind=e.triggerType
            if Blocks.isBhop(e) and Data.active(e,s)
                and Data.filterPass(e.properties.filtername,s) and Data.bhopIntersects(e,feet,height) then return end
        end
        Blocks.reset(s)
        return
    elseif name == "Restart" then
        local dest = startDestination(); if dest then s.lastWarp=nil;moveTo(player, s, dest.origin, dest.angles, true, false) end
        stopRun(player, s, "Ready"); resetCheckpoints(player, s); resetMapState(s)
    elseif name == "Checkpoint" then
        if mods.disableCheckpoints or not grounded(player) then message(player, "Checkpoint requires solid ground"); return end
        local source = Data.feetSource(map, r, h)
        if #s.checkpoints >= 256 then message(player, "Checkpoint limit: 256"); return end
        local view=s.motion and time-s.motion.received<.3 and s.motion.view or r.CFrame.LookVector
        if type(payload)=="table" and validView(payload.view) then view=payload.view end
        local look=Data.sourceVector(map,view).Unit
        local angles={math.deg(-math.asin(math.clamp(look.Z,-1,1))),math.deg(math.atan2(look.Y,look.X)),0}
        s.checkpoints[#s.checkpoints + 1] = {source = {source.X, source.Y, source.Z}, crouched = s.crouched,angles=angles}
        s.index = #s.checkpoints
        attr(player, "CheckpointCount", #s.checkpoints); attr(player, "CheckpointIndex", s.index)
        message(player, "Checkpoint " .. s.index)
    elseif name == "Teleport" or name == "PreviousCP" or name == "NextCP" then
        if mods.disableTeleports or #s.checkpoints == 0 then return end
        if name == "PreviousCP" then s.index = math.max(1, s.index - 1)
        elseif name == "NextCP" then s.index = math.min(#s.checkpoints, s.index + 1) end
        local cp = s.checkpoints[s.index]
        if cp then
            s.crouchWanted = cp.crouched
            -- Shrink before warping into a duck CP; test standing at the destination.
            if cp.crouched then setCrouch(player, s, true) end
            moveTo(player, s, cp.source, cp.angles, true, true)
            if not cp.crouched then setCrouch(player, s, false) end
        end
        attr(player, "CheckpointIndex", s.index)
    elseif name == "Practice" or name=="RouteBlocks" then
        local origin=map:GetAttribute(name=="RouteBlocks" and "KZRouteBlocksOrigin" or "KZPracticeOrigin")
        if origin then
            stopRun(player,s,"Ready");resetCheckpoints(player,s)
            moveTo(player,s,{origin.X,origin.Y,origin.Z},nil,true,false)
            message(player,name=="RouteBlocks" and "Main route blocks: green Multi, orange Single, purple Sequential; blue pads reset the sequence"
                or "BHOP practice: green Multi, orange Single, purple Sequential")
        end
    elseif name == "Use" then
        for _, e in ipairs(Data.buttons) do
            if (r.Position - Data.worldPoint(map, e.origin)).Magnitude <= 80 * unit then
                if e.properties.targetname == "climb_startbutton" then startRun(player, s)
                elseif e.properties.targetname == "climb_endbutton" then finishRun(player, s) end
                return
            end
        end
    elseif name == "Jump" then
        -- Takeoff notification validates map block rules and nearby pushes.
        local report=payload
        local jumpId
        if typeof(payload)=="table" then
            jumpId=payload.jumpId
            if type(jumpId)~="number" or jumpId~=jumpId or jumpId<1 or jumpId>1000000000
                or (payload.character and payload.character~=c) or jumpId%1~=0 or payload.teleportSerial~=s.teleportSerial
                or jumpId<=(s.lastClientJumpId or 0) or typeof(payload.feet)~="Vector3" then return end
            report=payload.feet
            if report.X~=report.X or report.Y~=report.Y or report.Z~=report.Z
                or report.Magnitude>=1000000 then return end
        end
        if time < (s.lastJumpMessage or 0) + .1 then return end
        s.lastJumpMessage = time
        if jumpId then s.lastClientJumpId=jumpId end
        local jumpFeet=feet
        -- A bounded takeoff origin catches held-Space contacts that can fall
        -- entirely between server Heartbeats. It cannot set times or records.
        if typeof(report)=="Vector3" and report.X==report.X and report.Y==report.Y
            and report.Z==report.Z and report.Magnitude<1000000 then
            local world=Data.worldPoint(map,{report.X,report.Y,report.Z})
            local actual=Data.worldPoint(map,{feet.X,feet.Y,feet.Z})
            if (world-actual).Magnitude<=128*unit then jumpFeet=report end
        end
        local block
        for _,e in ipairs(Data.zones) do
            local kind=e.triggerType
            if Blocks.isBhop(e) and Data.active(e,s)
                and Data.filterPass(e.properties.filtername,s)
                and Data.bhopIntersects(e,jumpFeet,s.crouched and 54 or 72) then block=e;break end
        end
        local observed=s.bhopServerTakeoff
        local alreadyObserved=block and observed and observed.id==block.id and time-observed.time<=.5
        s.bhopServerTakeoff=nil
        if not alreadyObserved then
            if block then
                if Blocks.takeoff(s,block.id,block.triggerType,time) then
                    teleportEntity(player,s,block);return
                end
            else Blocks.takeoff(s,nil,nil,time) end
        end
        -- Client takeoff can arrive before the replicated root leaves ground.
        -- Defer stale standing contacts briefly, then require real departure
        -- or let normal block rules resume. No permanent client-owned state.
        if grounded(player) then s.bhopAwaitDepartureUntil=time+.35 end
        for _, e in ipairs(Data.zones) do
            if e.triggerType == 14 and Data.active(e,s) and Data.intersects(e.bounds, jumpFeet, s.crouched and 54 or 72)
                and Data.filterPass(e.properties.filtername, s) then push(player, s, e, "jump_event") end
        end
    end
end
local function setupPlayer(player)
    if states[player] then return end
    local s = {runState = "Ready", runId = 0, elapsed = 0, teleportSerial = 0, crouched = false}
    states[player] = s; resetMapState(s); resetCheckpoints(player, s)
    attr(player, "TimerAvailable", true); attr(player, "RunState", "Ready")
    attr(player, "CourseName", "Main"); attr(player, "CourseId", 1)
    attr(player, "StageTotal", nil); attr(player, "Stage", nil)
    attr(player, "RecordScope", "Session"); attr(player, "TeleportSerial", 0)
    connect(player.CharacterAdded, function(c)
        if s.runState == "Running" then stopRun(player, s, "Aborted") end
        s.spectating = nil; attr(player, "SpectatingUserId", nil)
        resetMapState(s); task.spawn(installHull, player, s, c)
    end)
    if player.Character then task.spawn(installHull, player, s, player.Character) end
    publishRecords()
end
connect(Players.PlayerAdded, setupPlayer)
connect(Players.PlayerRemoving, function(player)
    local s = states[player]
    if s and s.partConnection then s.partConnection:Disconnect() end
    states[player] = nil
    for observer, state in pairs(states) do
        if state.spectating == player.UserId then action(observer, "Spectate", 0) end
    end
end)
for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
connect(Net.OnServerEvent, function(player, name, payload)
    if type(name) == "string" then action(player, name, payload) end
end)
local commands = {cp = "Checkpoint", tp = "Teleport", r = "Restart", prev = "PreviousCP", next = "NextCP", practice = "Practice",blocks="RouteBlocks"}
for alias, name in pairs(commands) do
    local command = Instance.new("TextChatCommand"); command.Name = "KZClassic_" .. alias
    command.PrimaryAlias = "/" .. alias; command.SecondaryAlias = "!" .. alias
    command.Parent = TextChatService
    connect(command.Triggered, function(source)
        local player = Players:GetPlayerByUserId(source.UserId)
        if player then action(player, name) end
    end)
end
-- Build boundary events first, then process them in travelled order. A fast
-- player can leave start, enter finish and cross a teleport in one Heartbeat.
local function zoneEvents(s,feet,height,span,time)
    local events={}
    local canSweep=s.previousFeet and (feet-s.previousFeet).Magnitude<=6000*math.min(span,.25)+128
    local function add(e,phase,fraction,duration,inside,order)
        events[#events+1]={entity=e,phase=phase,time=time-span*(1-fraction),duration=duration,inside=inside,order=order}
    end
    for order,e in ipairs(Data.zones) do
        local kind=e.triggerType
        local bhop=Blocks.isBhop(e)
        local bounds=e.class=="func_water" and Data.waterBounds(map,e)
            or e.class=='func_conveyor' and Data.conveyorBounds(e) or e.bounds
        local inside=bhop and Data.bhopIntersects(e,feet,height) or not bhop and Data.intersects(bounds,feet,height)
        local enter,leave
        if canSweep and not bhop then enter,leave=Data.sweepIntersects(bounds,s.previousFeet,feet,height) end
        local passed=not inside and enter~=nil
        if inside or passed then
            local first=enter or (s.inside[e.id] and 0 or 1)
            local last=inside and 1 or leave
            local duration=span*math.max(0,last-first)
            if not s.inside[e.id] then add(e,1,first,0,inside,order) end
            local contact=bhop and 1 or first
            if kind==10 then
                local start=s.touches[e.id] or time-span*(1-first)
                contact=span>0 and math.max(first,(start+Blocks.describe(e).delay-(time-span))/span) or 1
            end
            if contact<=last+1e-9 then add(e,2,math.min(contact,last),duration,inside,order)
            elseif inside then add(e,2,1,duration,true,order) end
            if passed then add(e,3,last,0,false,order) end
        elseif s.inside[e.id] then add(e,3,leave or 1,0,false,order) end
    end
    table.sort(events,function(a,b)
        if a.time~=b.time then return a.time<b.time end
        if a.phase~=b.phase then return a.phase<b.phase end
        return a.order<b.order
    end)
    return events
end
local tickAccumulator = 0
connect(RunService.Heartbeat, function(dt)
    tickAccumulator = tickAccumulator + dt
    if tickAccumulator < 1 / 60 then return end
    local elapsedTick = tickAccumulator
    tickAccumulator = 0
    local time = now()
    for player, s in pairs(states) do
        local _, h, r = characterParts(player)
        if r and not s.spectating then
            local mods=Data.modifiers(map,Data.feetSource(map,r,h),s.crouched and 54 or 72,s)
            if s.crouchWanted ~= nil then setCrouch(player, s, not mods.forceUnduck and (mods.forceDuck or s.crouchWanted)) end
            local feet = Data.feetSource(map, r, h)
            local height=s.motion and time-s.motion.received<.3 and s.motion.height or (s.crouched and 54 or 72)
            local onGround = grounded(player)
            attr(player, "ServerGrounded", onGround)
            local velocity=s.motion and time-s.motion.received<.3 and s.motion.velocity or r.AssemblyLinearVelocity
            attr(player, "ServerSpeedUnits", Vector3.new(velocity.X,0,velocity.Z).Magnitude / unit)
            local departurePending=s.bhopAwaitDepartureUntil and time<s.bhopAwaitDepartureUntil
            local departureAcknowledged=departurePending and not onGround
            if not onGround or not departurePending then s.bhopAwaitDepartureUntil=nil end
            if onGround and not s.wasGrounded then s.groundSince = time end
            if not onGround then s.groundSince = nil end
            if not s.groundSince and onGround then s.groundSince = time end
            local touched, warped, bhopGround = {}, false, false
            local span=s.previousFeet and elapsedTick or 0
            local events=zoneEvents(s,feet,height,span,time)
            for _,event in ipairs(events) do
                local e=event.entity;local kind=e.triggerType;local crossingTime=event.time
                -- Delayed map I/O due before a boundary must affect that boundary.
                table.sort(s.pending,function(a,b) return a.due==b.due and a.order<b.order or a.due<b.due end)
                while s.pending[1] and s.pending[1].due<=crossingTime do
                    applyOutput(player,s,table.remove(s.pending,1).connection)
                end
                local eligible=Data.active(e,s) and Data.filterPass(e.properties.filtername,s)
                if event.phase==3 then
                    if s.touches[e.id] then
                        outputs(player,s,e,"OnEndTouch",crossingTime)
                        if kind==5 then startRun(player,s,crossingTime)
                        elseif kind==14 then push(player,s,e,"end_touch") end
                    end
                    s.touches[e.id]=nil;touched[e.id]=nil
                elseif eligible then
                    if event.inside then touched[e.id]=true end
                    if event.phase==1 then
                        s.touches[e.id]=crossingTime;outputs(player,s,e,"OnStartTouch",crossingTime)
                        Blocks.onEnter(s,e)
                        if kind==5 then stopRun(player,s,"Ready",crossingTime);resetCheckpoints(player,s)
                        elseif kind==6 then finishRun(player,s,crossingTime)
                        elseif kind==2 and s.runState=="Running" then resetCheckpoints(player,s,false)
                        elseif kind==9 then attr(player,"Stage",number(e.properties.timer_zone_stage_number,1))
                        elseif kind==14 then push(player,s,e,"start_touch") end
                        if e.class=='trigger_push' and e.properties.triggeronstarttouch=='1' then
                            legacyPush(player,s,e,1)
                        end
                    else
                        local triggerWarp=Blocks.shouldTeleport(s,e,crossingTime,onGround and not departurePending,s.touches[e.id])
                        if Blocks.isBhop(e) then
                            bhopGround=bhopGround or onGround
                            if s.wasGrounded and not onGround and not departureAcknowledged and time>=(s.bhopIgnoreUntil or 0) then
                                triggerWarp=Blocks.takeoff(s,e.id,kind,time)
                                if not triggerWarp then s.bhopServerTakeoff={id=e.id,time=time} end
                            end
                        end
                        if triggerWarp and teleportEntity(player,s,e) then warped=true;break end
                        if kind==14 then push(player,s,e,"touch") end
                        if e.class=="trigger_push" and e.properties.triggeronstarttouch~='1' then
                            legacyPush(player,s,e,event.duration)
                        elseif e.class=="func_conveyor" and onGround and not (s.motion and time-s.motion.received<.3) then
                            local _,yaw=(e.properties.movedir or "0 0 0"):match("([^ ]+) +([^ ]+)")
                            yaw=math.rad(number(yaw,0))
                            local speed=number(e.properties.speed,0)*event.duration
                            Net:FireClient(player,"Push",Data.worldVector(map,{math.cos(yaw)*speed,math.sin(yaw)*speed,0}),{false,false,false},s.teleportSerial,nil,'LegacyConveyor')
                        end
                    end
                end
            end
            if not warped then
                s.inside = touched
                if not onGround then Blocks.clearContacts(s)
                else
                    Blocks.retainContacts(s,touched)
                    if not bhopGround and not departurePending and time>=(s.bhopIgnoreUntil or 0) then Blocks.reset(s) end
                end
            end
            -- A delayed frame must still apply Source I/O chronologically.
            -- Reversing this list can leave a teleport disabled after Enable.
            table.sort(s.pending,function(a,b) return a.due==b.due and a.order<b.order or a.due<b.due end)
            while s.pending[1] and s.pending[1].due<=time do
                local pending=table.remove(s.pending,1)
                applyOutput(player,s,pending.connection)
            end
            table.sort(s.pushPending,function(a,b) return a.due==b.due and a.order<b.order or a.due<b.due end)
            while s.pushPending[1] and s.pushPending[1].due<=time do
                local pending=table.remove(s.pushPending,1)
                if pending.serial==s.teleportSerial then
                    Net:FireClient(player,"Push",pending.amount,{pending.absolute[2],pending.absolute[3],pending.absolute[1]},s.teleportSerial,pending.absolute)
                end
                s.pushPendingById[pending.id]=nil
            end
            s.wasGrounded = not warped and onGround
            if not warped then s.previousFeet=feet end
            -- Include I/O executed during this Heartbeat instead of delaying
            -- gravity/duck/filter prediction until the following server frame.
            if s.sentRevision~=s.mapRevision then
                Net:FireClient(player,"ZoneState",{disabled=s.disabled,attributes=s.attributes,activatorName=s.activatorName},nil,s.teleportSerial)
                s.sentRevision=s.mapRevision
            end
        end
    end
    for target in pairs(states) do
        local spectators = 0
        for _, s in pairs(states) do if s.spectating == target.UserId then spectators = spectators + 1 end end
        attr(target, "SpectatorCount", spectators)
    end
end)
connect(script.Destroying, function()
    for _, c in ipairs(connections) do c:Disconnect() end
    for player, s in pairs(states) do
        if s.partConnection then s.partConnection:Disconnect() end
        if s.hull then s.hull:Destroy() end
        if s.originalParts then
            for part, saved in pairs(s.originalParts) do
                if part.Parent then part.CanCollide = saved.collide; part.CollisionGroup = saved.group end
            end
        end
        local _, h, r = characterParts(player)
        if h and s.normalStanding then
            h.HipHeight = Data.hipHeight(r,h,s.normalStanding)
            h.AutoRotate = s.originalAutoRotate
        end
        attr(player, "Crouched", false); attr(player, "SourceHullReady", false)
        if r and s.spectating then r.Anchored = s.beforeSpectateAnchored or false end
        attr(player, "TimerAvailable", false)
    end
    for _, command in ipairs(TextChatService:GetChildren()) do
        if command:IsA("TextChatCommand") and command.Name:sub(1, 10) == "KZClassic_" then command:Destroy() end
    end
end)
print("KZ Classic V7.22 ready: hull water contact, R6 feet and uphill ramp trace retries")
