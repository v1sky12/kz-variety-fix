-- Contact velocity projection; Roblox remains responsible for position integration.
-- All arguments use studs, seconds and world-space normals.
local Surf = {}
local function cross(a,b)
    return Vector3.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X)
end
function Surf.clip(velocity, planes)
    for _,normal in ipairs(planes) do
        local into=velocity:Dot(normal)
        if into < 0 then
            local candidate=velocity-normal*into
            local clear=true
            for _,other in ipairs(planes) do
                if candidate:Dot(other)<-1e-6 then clear=false;break end
            end
            if clear then return candidate end
        end
    end
    local clear=true
    for _,normal in ipairs(planes) do
        if velocity:Dot(normal)<-1e-6 then clear=false;break end
    end
    if clear then return velocity end
    -- Two surfaces share a crease. Project onto it rather than repeatedly
    -- projecting into one wall and then back into the other.
    if #planes==2 then
        local direction=cross(planes[1],planes[2])
        if direction.Magnitude>1e-6 then
            direction=direction.Unit
            local candidate=direction*velocity:Dot(direction)
            for _,normal in ipairs(planes) do
                if candidate:Dot(normal)<-1e-6 then return Vector3.zero end
            end
            return candidate
        end
    end
    return Vector3.zero
end
-- CKZ SlopeFix: downward landing energy may become horizontal speed only
-- on a standable slope and only when the projection increases 2D speed.
-- The vertical landing component stays under the grounded motor's control.
function Surf.landing(velocity,normal)
    if not normal or normal.Y<.7 or normal.Y>=1 or velocity.Y>=0 then return velocity,false end
    local into=velocity:Dot(normal)
    if into>=0 then return velocity,false end
    local projected=velocity-normal*into
    local oldSpeed2=velocity.X*velocity.X+velocity.Z*velocity.Z
    local newSpeed2=projected.X*projected.X+projected.Z*projected.Z
    if newSpeed2+1e-9<oldSpeed2 then return velocity,false end
    return Vector3.new(projected.X,velocity.Y,projected.Z),true
end
function Surf.trace(world,frame,size,displacement,params,unit,lastNormal)
    local hit=world:Blockcast(frame,size,displacement,params)
    if not hit or not lastNormal or displacement.Magnitude<1e-6
        or hit.Normal:Dot(lastNormal)>=.999 then return hit,false end
    local offset=math.max(.005,unit*.03125)
    local proof=world:Blockcast(frame+lastNormal*offset,size,lastNormal*(-offset*3),params)
    if not proof or proof.Normal:Dot(lastNormal)<.999 then return hit,false end
    local retry=world:Blockcast(frame+lastNormal*offset,size,displacement,params)
    local progress=(retry and retry.Distance or displacement.Magnitude)-(hit.Distance or 0)
    if progress>offset and (not retry or retry.Normal:Dot(lastNormal)>=.99 or progress>unit) then
        return retry,true
    end
    return hit,false
end
function Surf.resolve(world,hull,velocity,dt,unit,params,previousNormal)
    if not hull or not world.Blockcast then return velocity,nil,nil end
    if previousNormal and velocity:Dot(previousNormal)>1e-5 then previousNormal=nil end
    local skin=math.max(.012,unit*.25)
    local size=hull.Size-Vector3.new(skin*2,skin*2,skin*2)
    local frame=hull.CFrame
    local planes={}
    local normal,part
    local retries=0
    -- The small downward probe bridges the collision solver's separation.
    -- It never snaps the player and cannot attract a jump moving off a ramp.
    local support=world:Blockcast(frame,size,Vector3.new(0,-skin*4,0),params)
    if support and support.Normal.Y>0 and support.Normal.Y<.7
        and velocity:Dot(support.Normal)<=1e-5 then
        planes[1]=support.Normal;normal=support.Normal;part=support.Instance
        velocity=Surf.clip(velocity,planes)
    end
    local remaining=math.min(math.max(dt,0),.05)
    for _=1,4 do
        local displacement=velocity*remaining
        if displacement.Magnitude<1e-6 then break end
        local hit,retried=Surf.trace(world,frame,size,displacement,params,unit,normal or previousNormal)
        if retried then
            retries=retries+1
            if not normal then
                normal=previousNormal;planes[#planes+1]=normal
                velocity=Surf.clip(velocity,planes)
            end
        end
        if not hit then break end
        local n=hit.Normal
        -- Flat ground/steps have their own grounded motor. Vertical walls
        -- are only included here once a ramp contact has been established.
        local ramp=n.Y>0 and n.Y<.7
        if not ramp and not normal then break end
        if n.Y>=.7 then break end
        if velocity:Dot(n)>=-1e-6 then break end
        -- A sweep predicts future contact. Removing its inward velocity now
        -- would stop the hull short of the ramp/wall forever. Only planes
        -- already within the full hull's skin may constrain this frame.
        local gap=math.max(0,hit.Distance or 0)*math.max(0,-displacement.Unit:Dot(n))
        local inset=skin*(math.abs(n.X)+math.abs(n.Y)+math.abs(n.Z))
        if gap>inset+math.max(.005,unit*.03125) then break end
        if ramp then normal=n;part=hit.Instance end
        local duplicate=false
        for _,prior in ipairs(planes) do if prior:Dot(n)>.9999 then duplicate=true end end
        if not duplicate then planes[#planes+1]=n end
        -- Keep queries at the physical hull. Advancing a virtual hull here
        -- could impose a second plane before Roblox reaches that corner.
        velocity=Surf.clip(velocity,planes)
        if duplicate then break end
    end
    return velocity,normal,part,retries
end
return Surf
