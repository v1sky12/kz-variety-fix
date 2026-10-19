-- Contact at a ladder's upper edge. Read-only hull casts, no map edits/teleports.
local Edge={}
function Edge.resolve(world,hull,feet,ladder,normal,vertical,exitSpeed,dt,unit,params)
    local top=ladder.bounds[2][3]
    if vertical<=0 or feet.Z+vertical*dt < top-1 then return vertical,0,nil end
    local function hold(state,target)
        -- A small active-contact margin handles frame overshoot; velocity brings
        -- feet back inside the source face, without changing the root CFrame.
        local v=math.min(vertical,((target or top-.75)-feet.Z)/math.max(dt,1e-5))
        return math.max(-200,v),0,state
    end
    if not hull or not world.Blockcast then return hold("TopUnverifiedHold") end
    if exitSpeed<=0 then return hold("TopTangentHold") end
    local raise=math.max(0,top+1-feet.Z)*unit
    local size=hull.Size-Vector3.new(.02,.02,.02)
    if raise>.001 then
        local hit=world:Blockcast(hull.CFrame,size,Vector3.new(0,raise,0),params)
        if hit and hit.Distance<raise-.01 then
            return hold("TopCeilingHold",math.min(top-.75,feet.Z+math.max(0,hit.Distance-.01)/unit))
        end
    end
    local offset=Vector3.new(0,raise,0)
    local wall=world:Blockcast(hull.CFrame+offset,size,normal*(-32*unit),params)
    if wall then return hold("TopWallHold") end
    -- Transfer onto a clear ledge by velocity, after checking the full hull.
    return vertical,exitSpeed,"TopClearExit"
end
return Edge
