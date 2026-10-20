-- Start at the deepest accessible sampled point, not already at waist level.
local c=require('./lune_context').open('kz_variety_fix.rbxl')
local Data=c.load('KZMapData');local B=c.load('KZBrushCollision')
local Core=c.load('KZClassicCore');local Motor=c.load('KZBrushMotor')
local V=c.roblox.Vector3.new;local brushes={}
for _,part in c.map:GetDescendants() do
 if part:IsA('BasePart') and part.CanCollide and not part:IsA('MeshPart') then brushes[#brushes+1]=B.fromPart(part) end
end
local world=B.world(brushes);local records={};local tests=0
for _,water in Data.zones do if water.class=='func_water' then
 local a,b=Data.waterBounds(c.map,water)[1],Data.waterBounds(c.map,water)[2]
 local cases=0
 for _,height in {72,54} do for _,fx in {.2,.5,.8} do for _,fy in {.2,.5,.8} do
  local half=V(16,height/2,16)*c.unit
  local start
  for _,z in {a[3]+3.2,b[3]-height*.5-1} do
   local p=Data.worldPoint(c.map,{a[1]+(b[1]-a[1])*fx,a[2]+(b[2]-a[2])*fy,z})+V(0,height/2*c.unit,0)
   if not world:trace(p,V(0,0,0),half).startSolid then start=p;break end
  end
  if start then
   local m=Motor.new(world,Core,start,c.unit);m.height=height;m.duck=height==54
   local peak=-math.huge;local startZ=Data.sourcePoint(c.map,m:feet()).Z
   for _=1,512 do
    local zone=Data.modifiers(c.map,Data.sourcePoint(c.map,m:feet()),height)
    local jumped,stuck=m:tick({wish=V(0,0,0),swim=V(0,0,0),jump=true,duck=height==54},1/128,zone)
    assert(not jumped and not stuck,'Rising swimmer jumped from ground or entered solid')
    peak=math.max(peak,Data.sourcePoint(c.map,m:feet()).Z)
   end
   local floatDepth=b[3]-peak
   assert(floatDepth<height*.5-2,'Space failed to reach the surface: '..water.id)
   assert(peak+height-8>b[3]+8,'Swimming view remained submerged: '..water.id)
   records[#records+1]={id=water.id,height=height,start=startZ,peak=peak,surface=b[3],floatDepth=floatDepth}
   tests+=1;cases+=1
  end
 end end end
 assert(cases>0,'No accessible surface test: '..water.id)
end end
c.fs.writeFile('/tmp/kz-water-surfaces.json',c.serde.encode('json',{tests=tests,cases=records},true))
print('WATER SURFACE PASS',tests,'bottom-to-surface trajectories across all 11 volumes')
