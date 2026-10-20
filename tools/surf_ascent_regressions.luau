-- Actual float32 WedgeParts, microscopic uphill seams and a free ramp crest.
local R=require('@lune/roblox');local fs=require('@lune/fs');local luau=require('@lune/luau')
local V=R.Vector3.new;local CF=R.CFrame
local B=luau.load(fs.readFile('src/KZBrushCollision.luau'),{environment={Vector3=R.Vector3,CFrame=CF,Enum=R.Enum}})()
local Core=luau.load(fs.readFile('src/KZClassicCore.luau'),{environment={Vector3=R.Vector3}})()
local M=luau.load(fs.readFile('src/KZBrushMotor.luau'),{environment={Vector3=R.Vector3}})()
local tests=0;local retries=0
for _,unit in {.07101916666666667,.1,1} do for _,yaw in {0,.37,1.2} do
 local frame=CF.new(-128,250,140)*CF.Angles(0,yaw,0)
 local normal=frame:VectorToWorldSpace(V(-.8,.6,0))
 local support=16*math.abs(normal.X)+36*normal.Y+16*math.abs(normal.Z)
 local function ramp(a,b,rise)
  local p=R.Instance.new('WedgePart');p.Size=V(200,(b-a)*4/3,b-a)*unit
  p.CFrame=frame*CF.new((a+b)/2*unit,((a+b)/2*4/3+rise)*unit,0,0,0,1,0,1,0,-1,0,0)
  return B.fromPart(p)
 end
 for _,rise in {0,.0001,.001,.005,.01,.02,.1,1} do
  local world=B.world({ramp(-400,0,0),ramp(0,100,rise)},64*unit)
  local start=frame:PointToWorldSpace(V(-100,(support-80+.002)/.6,0)*unit)
  local m=M.new(world,Core,start,unit);m.v=frame:VectorToWorldSpace(V(480,640,0))*unit
  for _=1,110 do
   local _,stuck=m:tick({wish=V(0,0,0)},1/128,{})
   assert(not stuck,'uphill trace became solid')
  end
  local p=frame:PointToObjectSpace(m.p)/unit
  if rise<=.02 then
   assert(p.X>140 and m.v.Y>0,'micro seam discarded upward momentum: '..unit..'/'..yaw..'/'..rise..' at '..tostring(p))
  else assert(p.X<0,'ramp retry bypassed a real raised edge') end
  tests+=1;retries+=world.rampRetries or 0
 end
 local wall=R.Instance.new('Part');wall.Size=V(4,1000,200)*unit;wall.CFrame=frame*CF.new(2*unit,250*unit,0)
 local w=B.world({ramp(-400,0,0),ramp(0,100,0),B.fromPart(wall)},64*unit)
 local m=M.new(w,Core,frame:PointToWorldSpace(V(-100,(support-80+.002)/.6,0)*unit),unit)
 m.v=frame:VectorToWorldSpace(V(480,640,0))*unit
 for _=1,110 do m:tick({wish=V(0,0,0)},1/128,{}) end
 assert(frame:PointToObjectSpace(m.p).X/unit<0,'ramp retry crossed a wall')
 tests+=1
end end
print('SURF ASCENT PASS',tests,'rotated/scaled real wedge trajectories; bounded retries',retries)
