-- Original Luau implementation of convex hull / swept AABB collision.
-- Plane convention: n dot point <= d. Primitive sweep is analytic; MeshParts use Roblox geometric queries.
local B={}
local axes={Vector3.new(1,0,0),Vector3.new(0,1,0),Vector3.new(0,0,1)}
local function support(n,h) return math.abs(n.X)*h.X+math.abs(n.Y)*h.Y+math.abs(n.Z)*h.Z end
local function minv(a,b) return Vector3.new(math.min(a.X,b.X),math.min(a.Y,b.Y),math.min(a.Z,b.Z)) end
local function maxv(a,b) return Vector3.new(math.max(a.X,b.X),math.max(a.Y,b.Y),math.max(a.Z,b.Z)) end
function B.fromVertices(vertices,id)
    assert(#vertices>=4,'A brush needs at least four vertices')
    local planes,faces={},{}
    local lo,hi=vertices[1],vertices[1]
    for _,v in ipairs(vertices) do lo=minv(lo,v);hi=maxv(hi,v) end
    local function add(n,face)
        if n.Magnitude<1e-8 then return end
        n=n.Unit
        local d=-math.huge
        for _,v in ipairs(vertices) do d=math.max(d,n:Dot(v)) end
        for _,p in ipairs(planes) do if p.n:Dot(n)>.999999 and math.abs(p.d-d)<1e-6 then return end end
        planes[#planes+1]={n=n,d=d}
        if face then faces[#faces+1]={n=n,d=d} end
    end
    -- Supporting face planes of the convex hull.
    for i=1,#vertices-2 do for j=i+1,#vertices-1 do for k=j+1,#vertices do
        local n=(vertices[j]-vertices[i]):Cross(vertices[k]-vertices[i])
        if n.Magnitude>1e-8 then
            n=n.Unit;local d=n:Dot(vertices[i]);local positive,negative=false,false
            for _,v in ipairs(vertices) do local q=n:Dot(v)-d;positive=positive or q>1e-6;negative=negative or q< -1e-6 end
            if not (positive and negative) then add(positive and -n or n,true) end
        end
    end end end
    assert(#faces>=4,'Degenerate brush')
    for _,a in ipairs(axes) do add(a);add(-a) end
    -- Edges are vertex pairs sharing two supporting faces. Their cross-products
    -- with hull axes are the missing bevel normals in the Minkowski sum.
    for i=1,#vertices-1 do for j=i+1,#vertices do
        local shared=0
        for _,f in ipairs(faces) do
            if math.abs(f.n:Dot(vertices[i])-f.d)<1e-5 and math.abs(f.n:Dot(vertices[j])-f.d)<1e-5 then shared=shared+1 end
        end
        if shared>=2 then for _,axis in ipairs(axes) do
            local n=(vertices[j]-vertices[i]):Cross(axis);add(n);add(-n)
        end end
    end end
    return {planes=planes,lo=lo,hi=hi,id=id}
end
function B.fromPart(part)
    local v={};local h=part.Size*.5
    local function vertex(x,y,z) v[#v+1]=part.CFrame:PointToWorldSpace(Vector3.new(x*h.X,y*h.Y,z*h.Z)) end
    if part:IsA('WedgePart') then
        for _,x in ipairs({-1,1}) do vertex(x,-1,-1);vertex(x,-1,1);vertex(x,1,1) end
    elseif part:IsA('CornerWedgePart') then
        -- Roblox corner wedge has its high corner at local (-X,+Z).
        vertex(-1,-1,-1);vertex(1,-1,-1);vertex(-1,-1,1);vertex(1,-1,1);vertex(-1,1,1)
    elseif part:IsA('Part') and part.Shape==Enum.PartType.Block then
        for _,x in ipairs({-1,1}) do for _,y in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do vertex(x,y,z) end end end
    else return nil,'Unsupported collidable '..part.ClassName..': '..part:GetFullName() end
    return B.fromVertices(v,part)
end
function B.sweepBrush(brush,start,delta,half,skin)
    skin=skin or .001
    local enter,leave=-math.huge,1
    local normal;local outside=false;local deep=true
    for _,p in ipairs(brush.planes) do
        local distance=p.n:Dot(start)-p.d-support(p.n,half)
        local endDistance=distance+p.n:Dot(delta)
        if distance>0 then outside=true end
        if distance>=-skin then deep=false end
        if distance>0 and endDistance>=distance then return nil end
        if distance<=0 and endDistance<=0 then
            -- Entire segment stays inside this plane.
        elseif endDistance<distance then
            local t=(distance-skin)/(distance-endDistance)
            if t>enter then enter=t;normal=p.n end
        else leave=math.min(leave,distance/(distance-endDistance)) end
        if enter>leave then return nil end
    end
    if not outside then
        if deep then return {fraction=0,startSolid=true,allSolid=leave>=1,brush=brush} end
        -- Boundary contact only blocks movement into the brush, never away/tangent.
        for _,p in ipairs(brush.planes) do
            local q=p.n:Dot(start)-p.d-support(p.n,half)
            if q>=-skin and p.n:Dot(delta)>=-1e-9 then return nil end
        end
        for _,p in ipairs(brush.planes) do
            local q=p.n:Dot(start)-p.d-support(p.n,half)
            if q>=-skin and p.n:Dot(delta)<-1e-9 then normal=p.n;break end
        end
        return {fraction=0,normal=normal,brush=brush}
    end
    if enter<=leave and enter<1 and leave>0 then
        return {fraction=math.max(0,enter),normal=normal,brush=brush}
    end
end
local World={};World.__index=World
local function key(x,y,z) return x..','..y..','..z end
function B.world(brushes,cell,meshWorld,meshes,collisionGroup)
    local w=setmetatable({grid={},global={},cell=cell or 8,brushes=brushes},World)
    for _,b in ipairs(brushes) do
        local a,c=b.lo/w.cell,b.hi/w.cell
        local count=(math.floor(c.X)-math.floor(a.X)+1)*(math.floor(c.Y)-math.floor(a.Y)+1)*(math.floor(c.Z)-math.floor(a.Z)+1)
        if count>512 then w.global[#w.global+1]=b
        else for x=math.floor(a.X),math.floor(c.X) do for y=math.floor(a.Y),math.floor(c.Y) do for z=math.floor(a.Z),math.floor(c.Z) do
            local k=key(x,y,z);w.grid[k]=w.grid[k] or {};w.grid[k][#w.grid[k]+1]=b
        end end end end
    end
    if meshes and #meshes>0 then
        assert(meshWorld and meshWorld.Blockcast and meshWorld.GetPartsInPart,'Mesh geometry queries unavailable')
        local ray=RaycastParams.new()
        ray.FilterType=Enum.RaycastFilterType.Include;ray.FilterDescendantsInstances=meshes
        ray.RespectCanCollide=true;ray.CollisionGroup=collisionGroup or 'Default'
        local overlap=OverlapParams.new()
        overlap.FilterType=Enum.RaycastFilterType.Include;overlap.FilterDescendantsInstances=meshes
        overlap.RespectCanCollide=true;overlap.CollisionGroup=ray.CollisionGroup;overlap.MaxParts=1
        local query=Instance.new('Part')
        query.Name='KZBrushMeshQuery';query.Anchored=true;query.Transparency=1
        query.CanCollide=false;query.CanTouch=false;query.CanQuery=false
        query.CollisionGroup=ray.CollisionGroup
        w.meshWorld=meshWorld;w.meshRay=ray;w.meshOverlap=overlap;w.meshBox=query
        w.meshCount=#meshes
        query.Parent=meshWorld
    end
    return w
end
function World:destroy()
    if self.meshBox then self.meshBox:Destroy();self.meshBox=nil end
    self.meshWorld=nil
end
function World:candidates(start,delta,h)
    local lo=(minv(start,start+delta)-h)/self.cell;local hi=(maxv(start,start+delta)+h)/self.cell
    local out,seen={},{}
    local function add(b) if not seen[b] then seen[b]=true;out[#out+1]=b end end
    for _,b in ipairs(self.global) do add(b) end
    for x=math.floor(lo.X),math.floor(hi.X) do for y=math.floor(lo.Y),math.floor(hi.Y) do for z=math.floor(lo.Z),math.floor(hi.Z) do
        for _,b in ipairs(self.grid[key(x,y,z)] or {}) do add(b) end
    end end end
    return out
end
function World:trace(start,delta,h)
    local hit={fraction=1}
    for _,b in ipairs(self:candidates(start,delta,h)) do
        local r=B.sweepBrush(b,start,delta,h)
        if r and (r.startSolid or r.fraction<hit.fraction) then hit=r end
        if hit.startSolid then break end
    end
    if self.meshWorld and not hit.startSolid then
        local box=self.meshBox
        box.CFrame=CFrame.new(start)
        -- Blockcast omits initial intersections. Check actual occupied mesh
        -- volume first with a slightly inset, noncolliding query shape.
        box.Size=Vector3.new(math.max(.001,h.X*2-.006),math.max(.001,h.Y*2-.006),math.max(.001,h.Z*2-.006))
        local inside=self.meshWorld:GetPartsInPart(box,self.meshOverlap)
        if #inside>0 then
            hit={fraction=0,startSolid=true,allSolid=true,brush={id=inside[1]}}
        elseif delta.Magnitude>1e-8 then
            local native=self.meshWorld:Blockcast(CFrame.new(start),box.Size,delta,self.meshRay)
            if native then
                local fraction=math.max(0,(native.Distance-.001)/delta.Magnitude)
                if fraction<hit.fraction then
                    hit={fraction=fraction,normal=native.Normal,brush={id=native.Instance}}
                end
            end
        end
    end
    hit.position=start+delta*hit.fraction
    return hit
end
-- Resolve only tiny overlaps caused by imported seams or float rounding.
-- The bounded search cannot replace the collision sweep or cross a wall.
function World:recover(position,half,limit)
    if not self:trace(position,Vector3.zero,half).startSolid then return position end
    local directions={Vector3.new(0,1,0)}
    for x=-1,1 do for y=-1,1 do for z=-1,1 do
        if (x~=0 or y~=0 or z~=0) and not (x==0 and y==1 and z==0) then
            directions[#directions+1]=Vector3.new(x,y,z).Unit
        end
    end end end
    for _,fraction in ipairs({.0625,.125,.25,.5,1}) do
        for _,direction in ipairs(directions) do
            local candidate=position+direction*limit*fraction
            if not self:trace(candidate,Vector3.zero,half).startSolid then return candidate end
        end
    end
    return nil
end
function B.clip(v,n)
    local d=v:Dot(n)
    return d<0 and v-n*d or v
end
function World:slide(pos,vel,half,dt)
    local remaining=dt;local original=vel;local planes={};local contacts={}
    for _=1,4 do
        if vel.Magnitude<1e-8 then break end
        local t=self:trace(pos,vel*remaining,half)
        if t.startSolid then return pos,Vector3.zero,contacts,true,planes end
        pos=t.position
        if t.fraction==1 then break end
        if not t.normal then return pos,Vector3.zero,contacts,true,planes end
        t.timeFraction=1-remaining*(1-t.fraction)/dt
        contacts[#contacts+1]=t;remaining=remaining*(1-t.fraction)
        -- Source TryPlayerMove clears prior constraints after positive travel.
        -- Only contacts at the same position constrain a corner/crease together.
        if t.fraction>0 then planes={} end
        planes[#planes+1]=t.normal
        local nextVelocity
        for _,n in ipairs(planes) do
            local candidate=B.clip(vel,n);local clear=true
            for _,other in ipairs(planes) do if candidate:Dot(other)<-1e-7 then clear=false end end
            if clear then nextVelocity=candidate;break end
        end
        if not nextVelocity and #planes==2 then
            local crease=planes[1]:Cross(planes[2])
            if crease.Magnitude>1e-8 then crease=crease.Unit;nextVelocity=crease*vel:Dot(crease) end
        end
        vel=nextVelocity or Vector3.zero
        if vel:Dot(original)<=0 then vel=Vector3.zero;break end
    end
    return pos,vel,contacts,false,planes
end
function World:move(pos,vel,half,dt,grounded,stepHeight)
    local direct,dv,contacts,stuck,planes=self:slide(pos,vel,half,dt)
    if not grounded or stuck then return direct,dv,contacts,stuck,planes end
    local up=self:trace(pos,Vector3.new(0,stepHeight,0),half)
    if up.startSolid or up.fraction<1 then return direct,dv,contacts,stuck,planes end
    local raised,rv,rc,rs,rp=self:slide(up.position,vel,half,dt)
    local down=self:trace(raised,Vector3.new(0,-stepHeight-0.002,0),half)
    if rs or down.startSolid or down.fraction==1 or not down.normal or down.normal.Y<.7 then return direct,dv,contacts,stuck,planes end
    local function distance(p) local d=p-pos;return d.X*d.X+d.Z*d.Z end
    if distance(down.position)<=distance(direct) then return direct,dv,contacts,stuck,planes end
    rc[#rc+1]=down;rp[#rp+1]=down.normal;return down.position,Vector3.new(rv.X,dv.Y,rv.Z),rc,false,rp
end
return B
