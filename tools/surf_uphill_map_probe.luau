-- Uphill trajectories on the complete primitive map. Real ceilings/walls can
-- stop a trajectory: record their contacts rather than treating that as a bug.
local c=require('./lune_context').open('kz_variety_fix.rbxl')
local B=c.load('KZBrushCollision');local Core=c.load('KZClassicCore');local M=c.load('KZBrushMotor')
local V=c.roblox.Vector3.new;local brushes={}
for _,p in c.map:GetDescendants() do if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') then brushes[#brushes+1]=B.fromPart(p) end end
local world=B.world(brushes);local half=V(16,36,16)*c.unit
local cases={};local stucks=0;local drops=0
for _,b in brushes do if b.id.Size.Magnitude>8 then for _,face in b.planes do
 local n=face.n
 if n.Y>.15 and n.Y<.7 then
  local support=math.abs(n.X)*half.X+n.Y*half.Y+math.abs(n.Z)*half.Z
  local start=b.origin+n*(face.d+support+.01)
  local touch=world:trace(start,-n*.03,half)
  if not touch.startSolid and touch.fraction<1 and touch.normal and touch.normal:Dot(n)>.999 then
   local contacts={}
   local adapter={trace=function(_,...) return world:trace(...) end,move=function(_,...) local p,v,ct,s,pl=world:move(...);contacts=ct;return p,v,ct,s,pl end}
   local m=M.new(adapter,Core,start,c.unit);m.v=(V(0,1,0)-n*n.Y).Unit*1200*c.unit
   local history={};local previous=m.v
   for tick=1,128 do
    local _,stuck=m:tick({wish=V(0,0,0)},1/128,{})
    if stuck then stucks+=1 end
    if stuck or m.v.Magnitude<previous.Magnitude*.8 then
     local hit={}
     for _,contact in contacts do hit[#hit+1]={part=contact.brush and contact.brush.id.Name,normal={contact.normal.X,contact.normal.Y,contact.normal.Z}} end
     history[#history+1]={tick=tick,grounded=m.grounded,stuck=stuck,contacts=hit}
    end
    previous=m.v
   end
   if #history>0 then drops+=1 end
   cases[#cases+1]={ramp=b.id.Name,events=history}
   break
  end
 end
end end end
c.fs.writeFile('/tmp/kz-surf-uphill.json',c.serde.encode('json',{tests=#cases,startSolid=stucks,trajectoriesWithLoss=drops,cases=cases,nativeStudio=false},true))
assert(stucks==0,'Uphill map trajectory entered solid')
print('SURF UPHILL MAP',#cases,'trajectories,',stucks,'start-solid; contact losses recorded',drops,'(includes real walls/ceilings)')
