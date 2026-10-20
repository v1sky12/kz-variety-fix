-- Actual basin boundaries, holding Space + forward until a standable bank.
-- No injected waterLevel and no starting on the bank itself.
local c=require('./lune_context').open('kz_variety_fix.rbxl')
local Data=c.load('KZMapData');local B=c.load('KZBrushCollision')
local Core=c.load('KZClassicCore');local Motor=c.load('KZBrushMotor')
local V=c.roblox.Vector3.new;local brushes={}
for _,part in c.map:GetDescendants() do
 if part:IsA('BasePart') and part.CanCollide and not part:IsA('MeshPart') then
  brushes[#brushes+1]=B.fromPart(part)
 end
end
local world=B.world(brushes);local records,closedSides={},{};local eligible,passed,failed=0,0,0
for _,water in Data.zones do if water.class=='func_water' then
 local a,b=Data.waterBounds(c.map,water)[1],Data.waterBounds(c.map,water)[2]
 for _,height in {72,54} do for axis=1,2 do for _,sign in {-1,1} do for _,along in {.2,.5,.8} do
  local other=axis==1 and 2 or 1
  local p={(a[1]+b[1])/2,(a[2]+b[2])/2,b[3]-height/2-.5}
  p[axis]=sign==1 and b[axis]-32 or a[axis]+32
  p[other]=a[other]+(b[other]-a[other])*along
  local target=table.clone(p);target[axis]=sign==1 and b[axis]+20 or a[axis]-20;target[3]=b[3]+4
  local half=V(16,height/2,16)*c.unit
  local start=Data.worldPoint(c.map,p)+V(0,height/2*c.unit,0)
  local bankStart=Data.worldPoint(c.map,target)+V(0,height/2*c.unit,0)
  local bank=world:trace(bankStart,V(0,-8*c.unit,0),half)
  if not bank.startSolid and bank.fraction<1 and bank.normal.Y>=Core.Profile.WalkableNormal
   and not world:trace(start,V(0,0,0),half).startSolid then
   -- A floor behind a tall wall is not an exit. Check the passage at bank
   -- height independently of the motor's water-jump eligibility calculation.
   local across=V(start.X,bank.position.Y+c.unit,start.Z)
   local passage=world:trace(across,V(bankStart.X-across.X,0,bankStart.Z-across.Z),half)
   if passage.startSolid or passage.fraction<1 then
    closedSides[#closedSides+1]={id=water.id,height=height,axis=axis,sign=sign,along=along,
     wall=passage.brush and passage.brush.id.Name}
    continue
   end
   local dir={0,0,0};dir[axis]=sign
   local wish=Data.worldVector(c.map,dir).Unit
   local m=Motor.new(world,Core,start,c.unit);m.height=height;m.duck=height==54
   local reached,stuck,launches=false,0,0;local peak=p[3]
   local bankFeet=Data.sourcePoint(c.map,bank.position-V(0,height/2*c.unit,0)).Z
   for _=1,512 do
    local before=m.waterJumpUntil
    local zone=Data.modifiers(c.map,Data.sourcePoint(c.map,m:feet()),height)
    local _,solid=m:tick({wish=wish,swim=wish,jump=true,duck=height==54},1/128,zone)
    if solid then stuck+=1;break end
    if m.waterJumpUntil and m.waterJumpUntil~=before then launches+=1 end
    local source=Data.sourcePoint(c.map,m:feet());peak=math.max(peak,source.Z)
    if source.Z>=bankFeet-.1 and source[axis==1 and 'X' or 'Y']*sign>=(sign==1 and b[axis] or -a[axis])-15 then
     reached=true;break
    end
   end
   local record={id=water.id,height=height,axis=axis,sign=sign,along=along,
    start=p,bankHeight=bankFeet,peak=peak,launched=launches,reached=reached,stuck=stuck}
   records[#records+1]=record;eligible+=1
   if reached and stuck==0 then passed+=1 else failed+=1;print('WATER EXIT FAILED',water.id,height,axis,sign,along,peak,launches,stuck) end
  end
 end end end end
end end
c.fs.writeFile('/tmp/kz-water-exits.json',c.serde.encode('json',{eligible=eligible,passed=passed,failed=failed,cases=records,closedSides=closedSides},true))
print('WATER EXIT RESULT',passed,'of',eligible,'open banks;',failed,'failures;',#closedSides,'sides behind actual walls')
assert(eligible>=10,'Not enough accessible banks were sampled')
assert(failed==0,'Swimmer could not leave a standable bank; inspect /tmp/kz-water-exits.json')
