-- Geometry and authoring integration checks; not a Studio physics emulator.
local process=require('@lune/process')
local c=require('./lune_context').open(process.args[1] or 'kz_variety_fix.rbxl')
local Data=c.load('KZMapData');local B=c.load('KZBrushCollision');local Core=c.load('KZClassicCore');local Motor=c.load('KZBrushMotor')
local R=c.roblox;local V=R.Vector3.new
local manifest=c.serde.decode('json',c.fs.readFile('scene/manifest.json'))
local before=#Data.zones;Data.addPracticeZones(c.map);Data.addBlockZones(c.map)
local bindings=0
for _ in Data.blockBindings[c.map] do bindings+=1 end
assert(bindings==manifest.originalZones,'Not every placed original zone is bound')
assert(#Data.zones==before+23,'A placed original zone became a duplicate gameplay trigger')
local count=#Data.zones;Data.addPracticeZones(c.map);Data.addBlockZones(c.map)
assert(#Data.zones==count,'Repeated setup duplicated map zones')
local placed=assert(c.map:FindFirstChild('__KZ_BlockZones'))
for _,part in placed:GetChildren() do
 assert(part:IsA('Part') and part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery)
 local a,b=part:GetAttribute('KZSourceBoundsMin'),part:GetAttribute('KZSourceBoundsMax')
 local expected=Data.worldPoint(c.map,{(a.X+b.X)/2,(a.Y+b.Y)/2,(a.Z+b.Z)/2})
 assert((expected-part.CFrame.Position).Magnitude<.0001,'Zone visual is not at its declared Source position')
end
local brushes={}
for _,p in c.map:GetDescendants() do
 if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') then brushes[#brushes+1]=B.fromPart(p) end
end
local world=B.world(brushes)
local supported=0
for _,record in c.serde.decode('json',c.fs.readFile('scene/placements.json')) do
    if record.kind==11 or record.kind==12 then
        assert(record.supportFeet,'Bhop support has not been verified')
        local p=Data.worldPoint(c.map,record.supportFeet)+V(0,36*c.unit,0)
        local hit=Core.traceGround(world,p,V(0,-2*c.unit,0),V(16,36,16)*c.unit,c.unit)
        assert(not hit.startSolid and hit.fraction<1 and hit.normal.Y>=Core.Profile.WalkableNormal,'Bhop support is not standable')
        local source=Data.sourcePoint(c.map,hit.position-V(0,36*c.unit,0))
        assert(Data.bhopIntersects(record,source,72),'Standable support does not touch its original bhop trigger')
        supported+=1
    end
end
assert(supported==17 and supported==manifest.verifiedBhopSupports)
local route=assert(c.map:FindFirstChild('__KZ_RouteBlocks'),'Visible route blocks missing')
assert(#route:GetChildren()==22 and manifest.visibleRouteBlocks==22)
local routeTypes={}
for _,part in route:GetChildren() do
 assert(part:IsA('BasePart') and part.Anchored and part.CanCollide and part.Transparency==0,'Route block is invisible or has no collision')
 local kind=part:GetAttribute('KZBlockType') or part:GetAttribute('KZSurfaceMechanic')
 routeTypes[kind]=(routeTypes[kind] or 0)+1
end
assert(routeTypes.SingleBhop==9 and routeTypes.MultiBhop==8 and routeTypes.SequentialBhop==3 and routeTypes.Reset==2)
for _,record in c.serde.decode('json',c.fs.readFile('scene/route_blocks.json')) do
 local p=Data.worldPoint(c.map,record.supportFeet)+V(0,36*c.unit,0)
 local hit=Core.traceGround(world,p,V(0,-2*c.unit,0),V(16,36,16)*c.unit,c.unit)
 assert(not hit.startSolid and hit.fraction<1 and hit.normal.Y>=Core.Profile.WalkableNormal,'Visible route block is not standable: '..record.part)
 assert(hit.brush.id.Parent==route,'Visible route block has no physical support: '..record.part)
end
local waterId='b8bf3397-ec7a-408c-9e94-2baa7f87f642'
assert(c.map:GetAttribute(Data.waterLevelAttribute(waterId))==nil,'Water surface is still pinned to its floor')
assert(c.map:FindFirstChild('V16_Collision_00964',true).CanCollide,'Water floor was removed')
local feet=Data.worldPoint(c.map,{2208,-928,-613.17})
local m=Motor.new(world,Core,feet+V(0,36*c.unit,0),c.unit)
local highest=-math.huge
for tick=1,256 do
 local source=Data.sourcePoint(c.map,m:feet());local zone=Data.modifiers(c.map,source,m.height)
 local jumped,stuck=m:tick({wish=V(0,0,0),swim=V(0,0,0),jump=true,duck=false,side=0},1/128,zone)
 assert(not jumped,'Swim was converted into a grounded 302-unit jump')
 assert(not stuck,'Swimmer entered solid geometry')
 local z=Data.sourcePoint(c.map,m:feet()).Z;highest=math.max(highest,z)
end
assert(highest> -607 and highest< -600,'Swimmer failed to reach the surface or received an extra jump impulse')
local half=V(16,36,16)*c.unit
local function downAt(y)
 return world:trace(Data.worldPoint(c.map,{2208,y,-654}),V(0,-30*c.unit,0),half)
end
assert(not c.map:FindFirstChild('V16_Collision_00956',true).CanCollide,'Lower water remains covered')
local liquid=downAt(-928);assert(not liquid.startSolid and liquid.fraction==1,'Water opening is blocked')
local dry=downAt(-1108);assert(not dry.startSolid and dry.fraction<1,'Adjacent dry floor was removed')
assert(dry.brush.id.Name=='WaterOpeningDryEdge','Dry edge does not use the declared replacement')
print('SCENE PASS',bindings,'original bindings,',#placed:GetChildren(),'placed zones,',supported,'bhop supports, no duplicates; swimmer peak',highest,'CS units; lower water open and dry edge solid')
