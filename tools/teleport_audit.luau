local c=require('./lune_context').open('kz_variety_fix.rbxl')
local Data=c.load('KZMapData');local B=c.load('KZBrushCollision');local Blocks=c.load('KZBlockController')
local V=c.roblox.Vector3.new;local brushes={}
for _,p in c.map:GetDescendants() do if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') then brushes[#brushes+1]=B.fromPart(p) end end
local world=B.world(brushes);local targets={};local results={};local count,bad,recoverable=0,0,0
local missing={}
for _,e in Data.zones do
 local d=Blocks.describe(e)
 if d and (d.kind==10 or Blocks.isBhop(d.kind)) and d.destination then targets[d.destination]=(targets[d.destination] or 0)+1 end
end
for name in targets do
 local dest=Data.byName[name]
 if dest and dest.origin then
  for _,height in {72,54} do
   local p=Data.worldPoint(c.map,dest.origin)+V(0,height/2*c.unit+.015,0)
   local half=V(16,height/2,16)*c.unit
   local hit=world:trace(p,V(0,0,0),half)
   count+=1
   if hit.startSolid then
    bad+=1;local q=world:recover(p,half,2*c.unit)
    if q then recoverable+=1 end
    local r={name=name,height=height,origin=dest.origin,part=hit.brush and hit.brush.id.Name,recoverable=q~=nil,offset=q and {(q.X-p.X)/c.unit,(q.Y-p.Y)/c.unit,(q.Z-p.Z)/c.unit}}
    results[#results+1]=r;print('BLOCKED DEST',name,height,r.part,'recoverable',r.recoverable,r.offset)
   end
  end
 else missing[#missing+1]=name;print('MISSING DESTINATION',name) end
end
c.fs.writeFile('/tmp/kz-teleport-audit.json',c.serde.encode('json',{count=count,blocked=bad,recoverable=recoverable,cases=results,missing=missing},true))
print('TELEPORT AUDIT',count,'poses,',bad,'blocked,',recoverable,'recoverable')
assert(#missing==0,'Original teleport destination is missing')
assert(bad==0,'Original teleport pose intersects primitive geometry')
