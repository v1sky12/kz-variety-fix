-- Offline collision/motor fuzz. Native mesh queries and server triggers are not emulated.
local process=require('@lune/process')
local c=require('./lune_context').open('kz_variety_fix.rbxl')
local B=c.load('KZBrushCollision');local Core=c.load('KZClassicCore');local Motor=c.load('KZBrushMotor');local Data=c.load('KZMapData')
local V=c.roblox.Vector3.new
local seed=tonumber(process.args[1]) or 20261020
local limit=tonumber(process.args[2]) or 3000
local jumping=process.args[3]=='jump'
math.randomseed(seed)
local brushes={}
for _,p in c.map:GetDescendants() do
 if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') then brushes[#brushes+1]=B.fromPart(p) end
end
local world=B.world(brushes);local starts={};local half=V(16,36,16)*c.unit
for _,b in brushes do if b.id.Size.Magnitude>8 then
 for _,plane in b.planes do
  local n=plane.n
  if n.Y>.15 and n.Y<.7 then
   local support=math.abs(n.X)*half.X+n.Y*half.Y+math.abs(n.Z)*half.Z
   local p=b.origin+n*(plane.d+support+.01)
   local hit=world:trace(p,-n*.03,half)
   if not hit.startSolid and hit.fraction<1 and hit.normal and hit.normal:Dot(n)>.999 then
    starts[#starts+1]={position=p,normal=n,part=b.id.Name};break
   end
  end
 end
end end
-- Include actual block supports, accessible liquid and conveyor surfaces rather
-- than sampling only the large ramp faces.
local function addStart(part,position,grounded)
 if not world:trace(position,V(0,0,0),half).startSolid then
  starts[#starts+1]={position=position,normal=V(0,1,0),part=part,grounded=grounded}
 end
end
for _,record in c.serde.decode('json',c.fs.readFile('scene/placements.json')) do
 if record.supportFeet then
  addStart(record.support,Data.worldPoint(c.map,record.supportFeet)+V(0,36*c.unit,0),true)
 end
end
for _,zone in Data.zones do
 if zone.class=='func_water' then
  local a,b=Data.waterBounds(c.map,zone)[1],Data.waterBounds(c.map,zone)[2]
  addStart('water:'..zone.id,Data.worldPoint(c.map,{(a[1]+b[1])/2,(a[2]+b[2])/2,b[3]-1}),false)
 elseif zone.class=='func_conveyor' then
  local a,b=zone.bounds[1],zone.bounds[2]
  local p=Data.worldPoint(c.map,{(a[1]+b[1])/2,(a[2]+b[2])/2,b[3]+52})
  local hit=Core.traceGround(world,p,V(0,-(b[3]-a[3]+32)*c.unit,0),half,c.unit)
  if not hit.startSolid and hit.fraction<1 and hit.normal and hit.normal.Y>=Core.Profile.WalkableNormal then
   addStart('conveyor:'..zone.id,hit.position,true)
  end
 end
end
assert(#starts>0)
local function arr(v) return {v.X,v.Y,v.Z} end
local failures={};local recoveries,ticks,energyCases,groundCorrections=0,0,0,0
local begun=os.clock()
for index=1,limit do
 local start=starts[math.random(1,#starts)]
 local tangent=V(start.normal.Z,0,-start.normal.X)
 tangent=tangent.Magnitude>1e-6 and tangent.Unit or V(1,0,0)
 local across=V(-tangent.Z,0,tangent.X)
 local heading=(math.random()-.5)*math.pi*.8
 local sign=math.random(0,1)==0 and -1 or 1
 local direction=(tangent*math.cos(heading)+across*math.sin(heading))*sign
 local speed=({250,500,800,1500,3000})[math.random(1,5)]
 local vy=({-300,0,300})[math.random(1,3)]
 local m=Motor.new(world,Core,start.position,c.unit);m.v=(direction*speed+V(0,vy,0))*c.unit;m.grounded=start.grounded==true
 local initial={part=start.part,p=arr(m.p),v=arr(m.v),seed=seed,index=index,jumping=jumping,grounded=m.grounded}
 local history={};local failure
 for tick=1,64 do
  local duck=tick%24>=12
  local wish=tick%16>=8 and direction or V(0,0,0)
  local zone=Data.modifiers(c.map,Data.sourcePoint(c.map,m:feet()),m.height)
  local before=m.v.Magnitude/c.unit
  local jumped,stuck=m:tick({wish=wish,swim=wish,duck=duck,side=0,jump=jumping and tick%32<16},1/128,zone)
  ticks+=1
  local after=m.v.Magnitude/c.unit
  local inside=world:trace(m.p,V(0,0,0),m:half()).startSolid
  local bad=m.p.Magnitude~=m.p.Magnitude or m.v.Magnitude~=m.v.Magnitude or m.p.Magnitude>1000000
  if inside or stuck or bad then
   failure=inside and 'penetration' or stuck and 'unrecovered_startsolid' or 'nonfinite'
  end
  if not zone.water and (not zone.conveyor or zone.conveyor.Magnitude<1e-6)
    and not (m.waterJumpUntil and m.time<m.waterJumpUntil) and not jumped and after>before+40*(zone.gravity or 1)+.01 then
   energyCases+=1
  end
  history[#history+1]={tick=tick,p=arr(m.p),v=arr(m.v),height=m.height,ground=m.grounded,water=zone.water,stuck=stuck}
  if failure then break end
 end
 recoveries+=m.recoveries or 0
 groundCorrections+=m.groundCorrections or 0
 if failure then
  initial.failure=failure;initial.history=history;failures[#failures+1]=initial
  print('FAILURE',index,start.part,failure)
 end
 if index%100==0 or index==limit then
  local report={seed=seed,completed=index,limit=limit,ticks=ticks,starts=#starts,recoveries=recoveries,energyCases=energyCases,groundCorrections=groundCorrections,jumping=jumping,failures=failures,seconds=os.clock()-begun}
  c.fs.writeFile('/tmp/kz-stress-'..seed..'.json',c.serde.encode('json',report,true))
  print('STRESS',seed,index,'of',limit,'ticks',ticks,'failures',#failures,'recoveries',recoveries,'seconds',os.clock()-begun)
 end
end
assert(#failures==0,'Motor fuzz found reproducible collision failures; inspect saved corpus')
