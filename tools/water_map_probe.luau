local c=require('./lune_context').open('kz_variety_fix.rbxl')
local B=c.load('KZBrushCollision');local Core=c.load('KZClassicCore');local Motor=c.load('KZBrushMotor');local Data=c.load('KZMapData')
local V=c.roblox.Vector3.new;local brushes={}
for _,p in c.map:GetDescendants() do
 if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') then brushes[#brushes+1]=B.fromPart(p) end
end
local world=B.world(brushes);local records={};local tests,failures=0,0
for _,water in Data.zones do
 if water.class=='func_water' then
  local a,b=Data.waterBounds(c.map,water)[1],Data.waterBounds(c.map,water)[2]
  local rec={id=water.id,clear=0,blocked=0,surfaced=0,sank=0,stuck=0,cases={}}
  for _,height in {72,54} do for _,fx in {.2,.5,.8} do for _,fy in {.2,.5,.8} do
   local z=b[3]-height*.5-1
   local feet=Data.worldPoint(c.map,{a[1]+(b[1]-a[1])*fx,a[2]+(b[2]-a[2])*fy,z})
   local center=feet+V(0,height/2*c.unit,0);local half=V(16,height/2,16)*c.unit
   if world:trace(center,V(0,0,0),half).startSolid then rec.blocked+=1
   else
    rec.clear+=1
    for _,rising in {true,false} do
     local m=Motor.new(world,Core,center,c.unit);m.height=height;m.duck=height==54
     local start=Data.sourcePoint(c.map,m:feet()).Z;local high,low=start,start;local stuck=0
     for tick=1,128 do
      local zone=Data.modifiers(c.map,Data.sourcePoint(c.map,m:feet()),height)
      local _,bad=m:tick({wish=V(0,0,0),swim=V(0,0,0),jump=rising,duck=height==54,side=0},1/128,zone)
      if bad then stuck+=1 end
      local point=Data.sourcePoint(c.map,m:feet());assert(point.Magnitude<1e6,'water motion became nonfinite')
      high=math.max(high,point.Z);low=math.min(low,point.Z)
     end
     if rising and high>start+2 then rec.surfaced+=1 end
     if not rising and low<start-2 then rec.sank+=1 end
     if stuck>0 then rec.stuck+=1;failures+=1 end
     rec.cases[#rec.cases+1]={height=height,x=fx,y=fy,rising=rising,high=high,low=low,start=start,stuck=stuck}
     tests+=1
    end
   end
  end end end
  print('WATER MAP',water.id,'clear',rec.clear,'blocked',rec.blocked,'rise',rec.surfaced,'sink',rec.sank,'stuck',rec.stuck)
  records[#records+1]=rec
  assert(rec.clear>0 and rec.surfaced>0,'Water volume has no accessible swimming sample: '..water.id)
 end
end
c.fs.writeFile('/tmp/kz-water-matrix.json',c.serde.encode('json',records,true))
print('WATER MATRIX',tests,'trajectories,',failures,'stuck cases')
assert(failures==0,'Water traversal entered collision geometry')
