-- Recover only from confirmed interior overlap to a recent, nearby clear pose.
-- No map edits, arbitrary upward lifts, or checkpoint teleports.
local Recovery = {}
Recovery.__index = Recovery
function Recovery.new()
    return setmetatable({elapsed=0}, Recovery)
end
function Recovery:destroy()
    if self.query then self.query:Destroy() end
    self.query=nil; self.root=nil; self.clear=nil; self.elapsed=0; self.previous=nil
end
function Recovery:tick(world, character, root, dt, unit, serial, allowed)
    local hull=character:FindFirstChild("KZSourceHull")
    if not hull then return nil end
    if self.root~=root or self.serial~=serial then
        self:destroy(); self.root=root; self.serial=serial
    end
    if not self.query then
        self.query=Instance.new("Part")
        self.query.Name="__KZRecoveryQuery"
        self.query.Anchored=true; self.query.CanCollide=false
        self.query.CanTouch=false; self.query.CanQuery=false; self.query.Transparency=1
        self.params=OverlapParams.new()
        self.params.FilterType=Enum.RaycastFilterType.Exclude
        self.params.FilterDescendantsInstances={character,self.query}
        self.params.RespectCanCollide=true; self.params.MaxParts=16
        self.query.Parent=world
    end
    self.params.CollisionGroup=hull.CollisionGroup
    self.query.Size=Vector3.new(math.max(.01,hull.Size.X-.06),
        math.max(.01,hull.Size.Y-.06),math.max(.01,hull.Size.Z-.06))
    self.query.CFrame=hull.CFrame
    local travelled=self.previous and (root.Position-self.previous).Magnitude or math.huge
    self.previous=root.Position
    local overlaps=world:GetPartsInPart(self.query,self.params)
    root:SetAttribute("KZInteriorOverlapCount",#overlaps)
    if #overlaps==0 then
        self.clear=root.Position; self.elapsed=0
        return nil
    end
    -- Ordinary edge contacts while jumping/moving belong to the physics solver.
    -- Recover only when real displacement has stopped, after takeoff grace.
    local stalled=dt>0 and travelled<=unit*2*dt
    local vertical=root.AssemblyLinearVelocity.Y
    if allowed==false or not stalled or math.abs(vertical)>2 then
        self.elapsed=0
        return nil
    end
    self.elapsed=self.elapsed+math.min(dt,.05)
    if not self.clear or self.elapsed<.12 then return nil end
    local delta=self.clear-root.Position
    -- A stale pose must never become a remote teleport or skip a map obstacle.
    if delta.Magnitude>32*unit or delta.Magnitude<.001 then return nil end
    self.query.CFrame=hull.CFrame+delta
    if #world:GetPartsInPart(self.query,self.params)>0 then return nil end
    local names={}
    for _,part in ipairs(overlaps) do names[#names+1]=part:GetFullName() end
    root.CFrame=root.CFrame+delta
    self.previous=root.Position
    local velocity=root.AssemblyLinearVelocity
    local inward=velocity:Dot(delta.Unit)
    if inward<0 then velocity=velocity-delta.Unit*inward end
    root.AssemblyLinearVelocity=velocity
    self.elapsed=0
    root:SetAttribute("KZOverlapRecoveryCount",(root:GetAttribute("KZOverlapRecoveryCount") or 0)+1)
    root:SetAttribute("KZLastOverlapParts",table.concat(names," | "))
    root:SetAttribute("KZLastOverlapRecoveryStuds",delta.Magnitude)
    return delta
end
return Recovery
