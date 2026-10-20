-- Actual map/motor/server code with fixture services, not a Studio/network test.
local c=require('./lune_context').open('kz_variety_fix.rbxl')
local R=c.roblox;local V=R.Vector3.new
local Data=c.load('KZMapData');local B=c.load('KZBrushCollision')
local Core=c.load('KZClassicCore');local Motor=c.load('KZBrushMotor')
local brushes={}
for _,p in c.map:GetDescendants() do
 if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') then brushes[#brushes+1]=B.fromPart(p) end
end
local world=B.world(brushes)
local fixture=c.fs.readFile('tests/server_fixture.luau'):gsub('local function typeof%(value%)','local function fixtureTypeof(value)')
local setup=[=[
groundWorld=world
function serverMap:GetPivot() return realMap:GetPivot() end
function serverMap:GetAttribute(n) return realMap:GetAttribute(n) end
function serverMap:GetDescendants() return realMap:GetDescendants() end
function serverMap:FindFirstChild(n) return realMap:FindFirstChild(n) end
]=]
local source=fixture..setup..'\nlocal server=(function()\n'..c.fs.readFile('src/KZClassicGameplay.luau')..'\nreturn {states=states,action=action}\nend)()\n'
source..=[=[
local records={};local cases=0
for _,water in Data.zones do if water.class=='func_water' then
 local a,b=Data.waterBounds(realMap,water)[1],Data.waterBounds(realMap,water)[2]
 local covered=0
 for _,rig in {RigTypes.R6,RigTypes.R15} do for _,height in {72,54} do
  local start
  for _,fx in {.5,.1,.9,.2,.8} do for _,fy in {.5,.1,.9,.2,.8} do
   local feet={a[1]+(b[1]-a[1])*fx,a[2]+(b[2]-a[2])*fy,math.max(a[3]+12,b[3]-height*.75)}
   local p=Data.worldPoint(realMap,feet)+Vector3.new(0,height/2*unit,0)
   local forbidden=false
   for _,e in Data.zones do if e.class=='trigger_teleport' then
    local from=Vector3.new(feet[1],feet[2],feet[3]-8)
    local to=Vector3.new(feet[1],feet[2],b[3]-height*.5+10)
    if Data.sweepIntersects(e.bounds,from,to,height) then forbidden=true;break end
   end end
   if not forbidden and not start and not world:trace(p,Vector3.zero,Vector3.new(16,height/2,16)*unit).startSolid then start=p end
  end end
  assert(start,'no clear hull in water '..water.id)
  local player,root=makePlayer(1000+cases);local state=server.states[player]
  local h=player.Character:FindFirstChildOfClass('Humanoid')
  h.RigType=rig;h.HipHeight=rig==RigTypes.R6 and 0 or 2;root.Parent=player.Character
  local standing=Data.standingHeight(root,h)
  local m=Motor.new(world,Core,start,unit);m.height=height;m.duck=height==54
  local peak=-math.huge;local accepted=0;local warps=0;local wetFrames=0
  for tick=1,640 do
   local feet=Data.sourcePoint(realMap,m:feet())
   local zone=Data.modifiers(realMap,feet,height,state)
   -- Initially sink for a short interval, then hold Space while touching water.
   local jump=tick>8
   local _,stuck=m:tick({wish=Vector3.zero,swim=Vector3.zero,jump=jump,duck=height==54},1/128,zone)
   assert(not stuck,'water hull entered solid '..water.id)
   feet=Data.sourcePoint(realMap,m:feet());peak=math.max(peak,feet.Z)
   if zone.waterLevel>0 then wetFrames+=1 end
   root.CFrame=CFrame.new(m:feet()+Vector3.new(0,standing,0))
   serverClock+=1/128
   if tick%7==0 then
    server.action(player,'Motion',{character=player.Character,teleportSerial=state.teleportSerial,
     sequence=tick,feet=feet,velocity=m.v,view=Vector3.new(0,0,-1),height=height})
    if state.motionSequence==tick then accepted+=1 end
   end
   local oldSerial=state.teleportSerial
   RunService.Heartbeat:Fire(1/128)
   if state.teleportSerial~=oldSerial then warps+=1 end
  end
  assert(accepted>80,'server rejected rig motion '..water.id)
  assert(warps==0,'map trigger interrupted swimming '..water.id)
  assert(peak>b[3]-height*.5+2,'Space failed to surface '..water.id)
  assert(wetFrames>100,'water detection disappeared '..water.id)
  cases+=1;covered+=1
  records[#records+1]={id=water.id,rig=tostring(rig),height=height,peak=peak,surface=b[3],acceptedMotion=accepted,warps=warps,wetFrames=wetFrames}
  Players.PlayerRemoving:Fire(player)
 end end
 assert(covered==4)
end end
-- Original catch volumes must still work; the free-column tests above must
-- not succeed by silently disabling the map's underwater/overhead teleports.
local catches=0
for _,feet in {Vector3.new(2902,-4956,-819.5),Vector3.new(3088,-4956,-800)} do
 local player,root=makePlayer(2000+catches);local state=server.states[player]
 local h=player.Character:FindFirstChildOfClass('Humanoid');h.RigType=RigTypes.R15;h.HipHeight=2
 root.CFrame=CFrame.new(Data.worldPoint(realMap,{feet.X,feet.Y,feet.Z})+Vector3.new(0,3,0))
 serverClock+=.05
 server.action(player,'Motion',{character=player.Character,teleportSerial=0,sequence=1,
  feet=feet,velocity=Vector3.zero,view=Vector3.new(0,0,-1),height=72})
 RunService.Heartbeat:Fire(.05)
 assert(state.teleportSerial==1,'Original water catch stopped teleporting')
 Players.PlayerRemoving:Fire(player);catches+=1
end
return {tests=cases,boundaryTests=catches,cases=records,nativeStudio=false}
]=]
local result=c.luau.load(source,{debugName='water_server_probe',environment={Vector3=R.Vector3,CFrame=R.CFrame,
 RigTypes=R.Enum.HumanoidRigType,Data=Data,Core=Core,Blocks=c.load('KZBlockController'),Bhop=c.load('KZBhop'),
 Motor=Motor,world=world,realMap=c.map,unit=c.unit,warn=print}})()
c.fs.writeFile('/tmp/kz-water-server.json',c.serde.encode('json',result,true))
print('WATER SERVER PASS',result.tests,'all 11 volumes, R6/R15, standing/crouched;',result.boundaryTests,'original catches; service fixtures')
