local c=require('./lune_context').open('kz_variety_fix.rbxl')
local Data=c.load('KZMapData');local Core=c.load('KZClassicCore');local B=c.load('KZBrushCollision');local Motor=c.load('KZBrushMotor')
local V=c.roblox.Vector3.new;local brushes={}
for _,p in c.map:GetDescendants() do if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') then brushes[#brushes+1]=B.fromPart(p) end end
local world=B.world(brushes);local results={}
for _,e in Data.zones do
 if e.class=='func_conveyor' then
  local a,b=e.bounds[1],e.bounds[2];local rec={id=e.id,speed=tonumber(e.properties.speed),samples={}}
  for _,fx in {.25,.5,.75} do for _,fy in {.25,.5,.75} do
   local start=Data.worldPoint(c.map,{a[1]+(b[1]-a[1])*fx,a[2]+(b[2]-a[2])*fy,b[3]+52})
   local hit=Core.traceGround(world,start,V(0,-(b[3]-a[3]+32)*c.unit,0),V(16,36,16)*c.unit,c.unit)
   if not hit.startSolid and hit.fraction<1 and hit.normal and hit.normal.Y>=Core.Profile.WalkableNormal then
    local feet=Data.sourcePoint(c.map,hit.position-V(0,36*c.unit,0))
    local zone=Data.modifiers(c.map,feet,72)
    if zone.conveyor.Magnitude>0 then
     local m=Motor.new(world,Core,hit.position,c.unit);m.grounded=true
     local base=zone.conveyor;local p=m.p;local bad=false
     for _=1,32 do
      local z=Data.modifiers(c.map,Data.sourcePoint(c.map,m:feet()),m.height)
      local _,stuck=m:tick({wish=V(0,0,0),duck=false,jump=false},1/128,z)
      bad=bad or stuck
     end
     rec.samples[#rec.samples+1]={feet={feet.X,feet.Y,feet.Z},part=hit.brush.id.Name,
      distance=(m.p-p):Dot(base.Unit)/c.unit,speed=m.v.Magnitude/c.unit,grounded=m.grounded,stuck=bad}
    end
   end
  end end
  print('CONVEYOR',e.id,e.properties.speed,'accessible samples',#rec.samples)
  if #rec.samples==0 then rec.status='No accessible surface found by this offline sampling grid' end
  for _,sample in rec.samples do
   assert(not sample.stuck,'Conveyor traversal entered solid geometry')
   assert(math.abs(sample.distance-rec.speed*.25)<.2,'Conveyor applies acceleration instead of the declared transport speed')
  end
  results[#results+1]=rec
 end
end
c.fs.writeFile('/tmp/kz-conveyor-probe.json',c.serde.encode('json',results,true))
