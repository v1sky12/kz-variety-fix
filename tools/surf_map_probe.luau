local c=require('./lune_context').open('kz_variety_fix.rbxl')
local B=c.load('KZBrushCollision');local Core=c.load('KZClassicCore');local Motor=c.load('KZBrushMotor');local Data=c.load('KZMapData')
local V=c.roblox.Vector3.new
local brushes={};local byPart={}
for _,p in c.map:GetDescendants() do
 if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') then
  local b=B.fromPart(p);brushes[#brushes+1]=b;byPart[p.Name]=b
 end
end
local world=B.world(brushes);local half=V(16,36,16)*c.unit
local records={};local tested=0
for _,b in brushes do
 local part=b.id
 if part.Size.Magnitude>8 then
  for _,plane in b.planes do
   local n=plane.n
   if n.Y>.15 and n.Y<.7 then
    local support=math.abs(n.X)*half.X+n.Y*half.Y+math.abs(n.Z)*half.Z
    local p=b.origin+n*(plane.d+support+.01)
    local touch=world:trace(p,-n*.03,half)
    if not touch.startSolid and touch.fraction<1 and touch.normal and touch.normal:Dot(n)>.999 then
     local tangent=V(n.Z,0,-n.X).Unit
     for _,sign in {-1,1} do
      local lastContacts={}
      local adapter={trace=function(_,...) return world:trace(...) end,
       move=function(_,...) local q,v,contacts,stuck,planes=world:move(...);lastContacts=contacts;return q,v,contacts,stuck,planes end}
      local m=Motor.new(adapter,Core,p,c.unit);m.v=tangent*800*c.unit*sign
      local previous=m.v.Magnitude;local min=800;local stucks=0;local contacts=0;local lastNormal
      local sudden=false;local history={}
      for tick=1,64 do
       local _,stuck=m:tick({wish=V(0,0,0),side=0},1/128,{})
       if stuck then stucks+=1 end
       local speed=V(m.v.X,0,m.v.Z).Magnitude/c.unit
       if m.surfNormal then contacts+=1 end
       if speed<min then min=speed end
       if previous>400*c.unit and m.v.Magnitude<1*c.unit then sudden=true end
       previous=m.v.Magnitude
       if tick<5 or stuck or speed<50 then
        local contacts={}
        for _,contact in lastContacts do contacts[#contacts+1]={part=contact.brush and contact.brush.id.Name,normal={contact.normal.X,contact.normal.Y,contact.normal.Z},fraction=contact.fraction} end
        history[#history+1]={tick=tick,position={m.p.X,m.p.Y,m.p.Z},velocity={m.v.X,m.v.Y,m.v.Z},stuck=stuck,normal=m.surfNormal and {m.surfNormal.X,m.surfNormal.Y,m.surfNormal.Z},contacts=contacts}
       end
      end
      local rec={part=part.Name,normal={n.X,n.Y,n.Z},sign=sign,minSpeed=min,stuck=stucks,contactTicks=contacts,suddenStop=sudden}
      if sudden or stucks>0 then rec.history=history end
      records[#records+1]=rec;tested+=1
      if tested%100==0 then print('SURF MAP',tested) end
     end
     break
    end
   end
  end
 end
end
c.fs.writeFile('/tmp/kz-surf-probe.json',c.serde.encode('json',records,true))
local stopped,stuck=0,0
for _,r in records do if r.suddenStop then stopped+=1 end;if r.stuck>0 then stuck+=1 end end
print('SURF MAP RESULT',tested,'sudden stops',stopped,'startsolid cases',stuck)
assert(stuck==0,'Surf traversal entered solid geometry; inspect /tmp/kz-surf-probe.json')
