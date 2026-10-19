-- Only Roblox value types are substituted. Physics/gameplay modules are real.
local V = {}
local mt = {}
mt.__type='Vector3'
function V.new(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},mt) end
function mt.__index(v,key)
    if key=='Magnitude' then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
    if key=='Unit' then return v/v.Magnitude end
    if key=='Dot' then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
    if key=='Cross' then return function(a,b) return V.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end end
end
function mt.__add(a,b) return V.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
function mt.__sub(a,b) return V.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
function mt.__unm(a) return V.new(-a.X,-a.Y,-a.Z) end
function mt.__mul(a,b) if type(a)=='number' then a,b=b,a end return V.new(a.X*b,a.Y*b,a.Z*b) end
function mt.__div(a,b) return V.new(a.X/b,a.Y/b,a.Z/b) end
function mt.__tostring(a) return string.format('(%.6f, %.6f, %.6f)',a.X,a.Y,a.Z) end
V.zero=V.new(0,0,0)
local CF={}
function CF.new(position,yaw)
    position=position or V.zero; yaw=yaw or 0
    local c,s=math.cos(yaw),math.sin(yaw)
    local cf={Position=position,Rotation=true,__type='CFrame',LookVector=V.new(-s,0,-c)}
    function cf:VectorToWorldSpace(v) return V.new(c*v.X+s*v.Z,v.Y,-s*v.X+c*v.Z) end
    function cf:VectorToObjectSpace(v) return V.new(c*v.X-s*v.Z,v.Y,s*v.X+c*v.Z) end
    function cf:PointToWorldSpace(v) return self:VectorToWorldSpace(v)+position end
    function cf:PointToObjectSpace(v) return self:VectorToObjectSpace(v-position) end
    return cf
end
function CF.lookAt(p,target)
    local v=(target-p).Unit
    return CF.new(p,math.atan2(-v.X,-v.Z))
end
return {Vector3=V,CFrame=CF}
