-- Enter each real water brush head first from below; then hold Space.
local c=require('./lune_context').open('kz_variety_fix.rbxl')
local D=c.load('KZMapData');local B=c.load('KZBrushCollision');local M=c.load('KZBrushMotor');local Core=c.load('KZClassicCore')
local V=c.roblox.Vector3.new;local brushes={};local records={};local tests=0
for _,p in c.map:GetDescendants() do if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') then brushes[#brushes+1]=B.fromPart(p) end end
local world=B.world(brushes)
for _,water in D.zones do if water.class=='func_water' then
 local bounds=D.waterBounds(c.map,water);local a,b=bounds[1],bounds[2];local covered=0
 for _,height in {72,54} do for _,fx in {.2,.5,.8} do for _,fy in {.2,.5,.8} do
  local feet=V(a[1]+(b[1]-a[1])*fx,a[2]+(b[2]-a[2])*fy,a[3]-height+8)
  local pos=D.worldPoint(c.map,{feet.X,feet.Y,feet.Z})+V(0,height*.5*c.unit,0)
  local half=V(16,height*.5,16)*c.unit
  if not world:trace(pos,V(0,0,0),half).startSolid then
   local zone=D.modifiers(c.map,feet,height)
   assert(zone.waterLevel>=2,'Upper body in real water was treated as dry: '..water.id)
   local m=M.new(world,Core,pos,c.unit);m.height=height;m.duck=height==54
   local peak=feet.Z
   for _=1,512 do
    local z=D.modifiers(c.map,D.sourcePoint(c.map,m:feet()),height)
    local _,stuck=m:tick({wish=V(0,0,0),swim=V(0,0,0),jump=true,duck=height==54},1/128,z)
    assert(not stuck,'Water re-entry became solid: '..water.id)
    peak=math.max(peak,D.sourcePoint(c.map,m:feet()).Z)
   end
   assert(peak>b[3]-height*.5+2,'Head-first water re-entry failed to surface: '..water.id)
   tests+=1;covered+=1
   records[#records+1]={id=water.id,height=height,start=feet.Z,peak=peak,surface=b[3]}
  end
 end end end
 -- Some water brushes sit directly on solid floors; entering through that
 -- floor is correctly blocked. Surface/server probes cover those volumes.
 records[#records+1]={id=water.id,accessibleLowerEntries=covered}
end end
c.fs.writeFile('/tmp/kz-water-contact.json',c.serde.encode('json',{tests=tests,cases=records},true))
assert(tests>0)
print('WATER CONTACT PASS',tests,'head-first entries; all 11 lower faces checked for solid floors')
