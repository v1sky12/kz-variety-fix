-- Run with Lune. Uses float32 Roblox Vector3 and full CFrame rotations.
local R=require('@lune/roblox');local fs=require('@lune/fs');local luau=require('@lune/luau')
local Core=luau.load(fs.readFile('src/KZClassicCore.luau'),{environment={Vector3=R.Vector3}})()
local B=luau.load(fs.readFile('src/KZBrushCollision.luau'),{environment={Vector3=R.Vector3,CFrame=R.CFrame,Enum=R.Enum}})()
local Motor=luau.load(fs.readFile('src/KZBrushMotor.luau'),{environment={Vector3=R.Vector3}})()
local V=R.Vector3.new
local projections,stops,worst=0,0,0
for heading=1,360 do for inclination=30,60 do
 local t,a=math.rad(heading),math.rad(inclination)
 local n=V(math.cos(t)*math.sin(a),math.cos(a),math.sin(t)*math.sin(a))
 local v=V(math.sin(t)*100,-10,-math.cos(t)*100)
 local out=Core.clipPlanes(v,{n})
 projections+=1
 if out.Magnitude<1 then stops+=1 end
 assert(out.Magnitude<=v.Magnitude+1e-4,'contact projection added energy')
 assert(out:Dot(n)>=-v.Magnitude*1e-6,'projected velocity re-entered plane')
 worst=math.min(worst,out:Dot(n))
end end
assert(stops==0,'float32 tangent projection discarded velocity '..stops..' times')
local slopeChecks=0;local motor=Motor.new({},Core,V(0,0,0),1)
for degrees=1,360 do
 local a=math.rad(degrees);local n=V(math.cos(a)*.6,.8,math.sin(a)*.6)
 local incoming=V(math.cos(a)*100,-300,math.sin(a)*100)
 local wall=V(-math.sin(a),0,math.cos(a))
 local projected=motor:slopeLanding(incoming,n,{wall})
 assert(projected and projected.Magnitude>200,'float32 wall tangent suppressed the downhill slope projection')
 slopeChecks+=1
end
local primitives=0
for _,class in {'Part','WedgePart','CornerWedgePart'} do
 for _,position in {V(-128,250,140),V(400,200,-400),V(1000,-1000,1000)} do
  for yaw=0,330,30 do for pitch=0,80,20 do
   local p=R.Instance.new(class);p.Size=V(.05,20,40)
   p.CFrame=R.CFrame.new(position)*R.CFrame.Angles(math.rad(pitch),math.rad(yaw),.37)
   local brush=B.fromPart(p);assert(brush and #brush.planes>=5)
   -- Ray from outside to the known bottom face, away from wedge edges.
   local bottom=p.CFrame:PointToWorldSpace(V(0,-10,0))
   local n=p.CFrame:VectorToWorldSpace(V(0,-1,0))
   local trace=B.sweepBrush(brush,bottom+n*.1,-n*.2,V(0,0,0),0)
   assert(trace and not trace.startSolid and math.abs(trace.fraction-.5)<.002,'rotated primitive lost its bottom face')
   assert(trace.normal:Dot(n)>.9999,'primitive returned a bevel in place of its bottom')
   primitives+=1
  end end
 end
end
print('FLOAT32 PASS',projections,'projections,',stops,'unwanted stops,',slopeChecks,'downhill wall tangents,',primitives,'rotated thin primitive traces; worst inward residual',worst)
