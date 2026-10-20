-- Full jump trajectories on the new line inside the original Multi room.
local c=require('./lune_context').open('kz_variety_fix.rbxl')
local Data=c.load('KZMapData');local B=c.load('KZBrushCollision')
local Core=c.load('KZClassicCore');local Motor=c.load('KZBrushMotor');local Blocks=c.load('KZBlockController')
local V=c.roblox.Vector3.new;local brushes={}
Data.addPracticeZones(c.map);Data.addBlockZones(c.map)
for _,p in c.map:GetDescendants() do
 if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') then brushes[#brushes+1]=B.fromPart(p) end
end
local world=B.world(brushes);local state={};Blocks.reset(state)
local stops={360,472,632,792,904};local record={jumps={},repeatRejected=false,resetCleared=false}
local function zoneAt(m)
 local feet=Data.sourcePoint(c.map,m:feet())
 for _,zone in Data.zones do
  if zone.id:sub(1,19)=='roblox_block_route_' and Data.bhopIntersects(zone,feet,m.height) then return zone end
 end
end
for index=1,#stops-1 do
 local m=Motor.new(world,Core,Data.worldPoint(c.map,{stops[index],-1064,-272+.001/c.unit})+V(0,36*c.unit,0),c.unit)
 m:categorize();assert(m.grounded,'Route entry has no ground')
 local start=zoneAt(m);assert(start,'Route block has no gameplay zone')
 Blocks.onEnter(state,start)
 if Blocks.isBhop(start) then assert(not Blocks.takeoff(state,start.id,start.triggerType,m.time),'Sequence rejected its first takeoff') end
 local speed=(stops[index+1]-stops[index])/(2*Core.Profile.JumpImpulse/Core.Profile.Gravity)
 m.v=Data.worldVector(c.map,{speed,0,0})
 local jumped,stuck=m:tick({wish=V(0,0,0),jump=true},1/128,Data.modifiers(c.map,Data.sourcePoint(c.map,m:feet()),72))
 assert(jumped and not stuck,'Route pad cannot be jumped from')
 local landed=false
 for _=1,128 do
  local _,solid=m:tick({wish=V(0,0,0),jump=false},1/128,Data.modifiers(c.map,Data.sourcePoint(c.map,m:feet()),72))
  assert(not solid,'Route jump entered solid geometry')
  if m.grounded then landed=true;break end
 end
 assert(landed,'Route jump has no landing')
 local feet=Data.sourcePoint(c.map,m:feet())
 assert(math.abs(feet.X-stops[index+1])<16 and math.abs(feet.Z+272)<.1,'Route jump missed the intended pad')
 local destination=zoneAt(m);assert(destination,'Route landing has no zone')
 record.jumps[#record.jumps+1]={from=stops[index],to=stops[index+1],landedX=feet.X,type=destination.blockType}
 if index==#stops-1 then
  Blocks.onEnter(state,destination);assert(next(state.bhopVisited)==nil,'Exit Reset did not clear visited pads');record.resetCleared=true
 else
  assert(not Blocks.land(state,destination.id,destination.triggerType,m.time,.1),'Unused Sequential pad rejected')
 end
end
local first
for _,zone in Data.zones do if zone.id=='roblox_block_route_Sequential_1' then first=zone end end
assert(first,'First Sequential trigger missing');Blocks.reset(state)
assert(not Blocks.takeoff(state,first.id,first.triggerType,0))
record.repeatRejected=Blocks.land(state,first.id,first.triggerType,1,.1)
assert(record.repeatRejected,'A reused Sequential pad was accepted')
c.fs.writeFile('/tmp/kz-route-blocks-probe.json',c.serde.encode('json',record,true))
print('ROUTE BLOCKS PASS',#record.jumps,'actual jump trajectories; repeat rejection and exit reset verified')
