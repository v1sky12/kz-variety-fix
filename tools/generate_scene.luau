-- Deterministic scene additions and narrowly declared property edits.
-- Never serialize the full place: existing references and backup data survive.
local process=require('@lune/process')
local c=require('./lune_context').open(process.args[1] or 'kz_variety_fix.rbxl')
local Data=c.load('KZMapData');local Blocks=c.load('KZBlockController');local B=c.load('KZBrushCollision');local Core=c.load('KZClassicCore')
local R=c.roblox;local V=R.Vector3.new
local ids=c.serde.decode('json',c.fs.readFile(assert(process.args[2],'Pass the prepared instance-ID JSON path')))
-- Map children use dots in some imported mesh names, so form the hierarchy explicitly.
local function fullPath(p)
 local names={}
 while p and p~=c.game do table.insert(names,1,p.Name);p=p.Parent end
 return table.concat(names,'/')
end
local patches,edits={},{}
local function patch(target,properties)
 local id=assert(ids[fullPath(target)],'Target not in active map: '..fullPath(target))
 local p=patches[id]
 if not p then
  p=target:Clone();p:ClearAllChildren();p.Parent=nil;p.Name='Target_'..id;patches[id]=p
  edits[tostring(id)]={path=fullPath(target),properties={}}
 end
 for _,name in properties do
  if name~='AttributesSerialize' then p[name]=target[name] end
  if not table.find(edits[tostring(id)].properties,name) then table.insert(edits[tostring(id)].properties,name) end
 end
 return p
end
-- Sequence resets belong to the established practice entry and finish pads.
-- No Sequential trigger exists on the imported main route.
local root=R.Instance.new('Folder');root.Name='__KZ_BlockZones'
root:SetAttribute('KZPlacementRevision',1)
for _,name in {'Start','Finish'} do
 local platform=assert(c.map:FindFirstChild('__KZ_BhopPractice'):FindFirstChild(name))
 local centre=Data.sourcePoint(c.map,platform.CFrame.Position)
 local sx,sy=platform.Size.Z/c.unit/2,platform.Size.X/c.unit/2
 local top=centre.Z+platform.Size.Y/c.unit/2
 local p=R.Instance.new('Part');p.Name='PracticeReset_'..name
 p.Size=V(platform.Size.X,2*c.unit,platform.Size.Z)
 p.CFrame=R.CFrame.new(Data.worldPoint(c.map,{centre.X,centre.Y,top+1}))*c.map:GetPivot().Rotation
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Transparency=1;p.CastShadow=false
 p:SetAttribute('KZBlockType','Reset');p:SetAttribute('KZBlockId','practice_reset_'..name)
 p:SetAttribute('KZSourceBoundsMin',V(centre.X-sx,centre.Y-sy,top))
 p:SetAttribute('KZSourceBoundsMax',V(centre.X+sx,centre.Y+sy,top+2));p.Parent=root
end
local placements={};local brushes={}
for _,p in c.map:GetDescendants() do
 if p:IsA('BasePart') and p.CanCollide and not p:IsA('MeshPart') and not p:IsA('PartOperation') then
  local b=B.fromPart(p);if b then brushes[#brushes+1]=b end
 end
end
local world=B.world(brushes)
local original=0
for _,e in Data.zones do
 local d=Blocks.describe(e)
 if d and e.bounds and d.kind~=0 then
  original+=1
  local a,b=e.bounds[1],e.bounds[2]
  local p=R.Instance.new('Part');p.Name=string.format('%03d_%s_%s',original,d.type,e.id:sub(1,8))
  p.Size=V(math.max(.001,(b[2]-a[2])*c.unit),math.max(.001,(b[3]-a[3])*c.unit),math.max(.001,(b[1]-a[1])*c.unit))
  p.CFrame=R.CFrame.new(Data.worldPoint(c.map,{(a[1]+b[1])/2,(a[2]+b[2])/2,(a[3]+b[3])/2}))*c.map:GetPivot().Rotation
  p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Transparency=1;p.CastShadow=false
  p:SetAttribute('KZBlockType',d.type);p:SetAttribute('KZBlockId',e.id)
  p:SetAttribute('KZSourceEntityId',e.id)
  p:SetAttribute('KZSourceBoundsMin',V(a[1],a[2],a[3]));p:SetAttribute('KZSourceBoundsMax',V(b[1],b[2],b[3]))
  p:SetAttribute('KZBlockDelay',d.delay);p:SetAttribute('KZAntiBhopTime',d.antiBhop)
  p:SetAttribute('KZDisabled',e.properties.startdisabled=='1')
  p:SetAttribute('KZResetSpeed',d.resetSpeed)
  if d.destination then p:SetAttribute('KZDestination',d.destination) end
  p.Parent=root
  local record={id=e.id,type=d.type,kind=d.kind,bounds=e.bounds,zonePart=p.Name,destination=d.destination,delay=d.delay}
  if Blocks.isBhop(e) then
   local center=Data.worldPoint(c.map,{(a[1]+b[1])/2,(a[2]+b[2])/2,b[3]+40})
   local hit=world:trace(center,V(0,-(b[3]-a[3]+12)*c.unit,0),V(16,36,16)*c.unit)
   if not hit.startSolid and hit.fraction<1 and hit.brush then
    local feet=Data.sourcePoint(c.map,hit.position-V(0,36*c.unit,0))
    if feet.Z>=a[3]-3.2 and feet.Z<=b[3]+3.2 then
     local support=hit.brush.id
     record.support=fullPath(support);record.supportFeet={feet.X,feet.Y,feet.Z}
     local s=patch(support,{'AttributesSerialize'})
     local previous=s:GetAttribute('KZSurfaceTriggerIds')
     local sourceIds=previous and string.split(previous,',') or {}
     if not table.find(sourceIds,e.id) then sourceIds[#sourceIds+1]=e.id end
     table.sort(sourceIds);s:SetAttribute('KZSurfaceTriggerIds',table.concat(sourceIds,','))
     s:SetAttribute('KZSurfaceMechanic',d.type)
    end
   end
   if not record.support and e.id=='b5fa7457-631a-4fed-b09d-34386d634bed' then
    -- This tall zone touches the hull from the side of an adjacent platform;
    -- its centre is intentionally inside a wall. Verified by a full footprint
    -- scan, not by moving the zone or assigning the whole platform its rules.
    local center=Data.worldPoint(c.map,{256,-3540,-940})
    local hit=Core.traceGround(world,center,V(0,-2*c.unit,0),V(16,36,16)*c.unit,c.unit)
    if not hit.startSolid and hit.fraction<1 and hit.normal and hit.normal.Y>=Core.Profile.WalkableNormal then
     local feet=Data.sourcePoint(c.map,hit.position-V(0,36*c.unit,0))
     if Data.bhopIntersects(e,feet,72) then
      record.support=fullPath(hit.brush.id);record.supportFeet={feet.X,feet.Y,feet.Z};record.supportKind='partial_hull_overlap'
     end
    end
   end
  end
  placements[#placements+1]=record
 end
end
-- Original water depth is defined by the VMAP volume, never by a floor's top.
local waterId='b8bf3397-ec7a-408c-9e94-2baa7f87f642'
local m=patch(c.map,{'AttributesSerialize'})
m:SetAttribute(Data.waterLevelAttribute(waterId),nil)
m:SetAttribute('KZBlockPlacementRevision',1)
m:SetAttribute('KZWaterDepthRevision',1)
local floor=assert(c.map:FindFirstChild('V16_Collision_00964',true))
local floorPatch=patch(floor,{'CanCollide','CanQuery','CanTouch'})
floorPatch.CanCollide=true;floorPatch.CanQuery=true;floorPatch.CanTouch=false
-- This plate extends beyond the lower water and therefore was missed by the
-- old full-face match. Keep its dry portion while opening the liquid area.
local openingId='8c2b1b6f-0b26-422b-92d1-eed9b753bea5'
local lid=assert(c.map:FindFirstChild('V16_Collision_00956',true))
local lidPatch=patch(lid,{'CanCollide','CanQuery','CanTouch'})
lidPatch.CanCollide=false;lidPatch.CanQuery=false;lidPatch.CanTouch=false
local opening=R.Instance.new('Folder');opening.Name='__KZ_WaterOpeningFix'
m:SetAttribute('KZWaterOpeningRevision',1)
local lo,hi
for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
 local q=Data.sourcePoint(c.map,lid.CFrame:PointToWorldSpace(V(x,y,z)*lid.Size*.5))
 lo=lo and V(math.min(lo.X,q.X),math.min(lo.Y,q.Y),math.min(lo.Z,q.Z)) or q
 hi=hi and V(math.max(hi.X,q.X),math.max(hi.Y,q.Y),math.max(hi.Z,q.Z)) or q
end end end
local dryBounds={{lo.X,lo.Y,lo.Z},{hi.X,-1008,hi.Z}}
local da,db=dryBounds[1],dryBounds[2]
assert(db[2]>da[2] and math.abs(hi.Y+856)<.01 and math.abs(hi.Z+704)<.01,'Water lid geometry differs')
local dryEdge=R.Instance.new('Part');dryEdge.Name='WaterOpeningDryEdge'
dryEdge.Size=V(db[2]-da[2],db[3]-da[3],db[1]-da[1])*c.unit
dryEdge.CFrame=R.CFrame.new(Data.worldPoint(c.map,{(da[1]+db[1])/2,(da[2]+db[2])/2,(da[3]+db[3])/2}))*c.map:GetPivot().Rotation
dryEdge.Anchored=true;dryEdge.Transparency=1;dryEdge.CastShadow=false
dryEdge.CanCollide=true;dryEdge.CanQuery=true;dryEdge.CanTouch=false
dryEdge.CollisionGroup=lid.CollisionGroup
if lid.CustomPhysicalProperties then dryEdge.CustomPhysicalProperties=lid.CustomPhysicalProperties end
dryEdge:SetAttribute('KZWaterOpeningSourceId',openingId);dryEdge.Parent=opening
local dry=c.map:FindFirstChild('WaterOpeningDryFloor',true)
if dry then
 local p=patch(dry,{'CanCollide','CanQuery','CanTouch'});p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
end
for _,p in c.map:FindFirstChild('__KZ_WaterSurfaces'):GetChildren() do
 if p:GetAttribute('KZWaterSourceId')==waterId then
  local q=patch(p,{'CFrame'})
  q.CFrame=R.CFrame.new(Data.worldPoint(c.map,{2208,-928,-576-.025/c.unit/2}))*c.map:GetPivot().Rotation
 end
end
local patchArray={};local sorted={}
for id in patches do sorted[#sorted+1]=id end;table.sort(sorted)
for _,id in sorted do patchArray[#patchArray+1]=patches[id] end
local counts={};local supported=0
for _,p in placements do counts[p.type]=(counts[p.type] or 0)+1;if p.support then supported+=1 end end
local manifest={revision=1,mapPath=fullPath(c.map),mapId=ids[fullPath(c.map)],rootName=root.Name,
 originalZones=original,counts=counts,verifiedBhopSupports=supported,edits=edits,
 additions={{file='block_zones.rbxm',rootName=root.Name},{file='water_opening.rbxm',rootName=opening.Name}},
 waterOpening={id=openingId,originalPlate=fullPath(lid),dryBounds=dryBounds}}
c.fs.writeFile('scene/block_zones.rbxm',R.serializeModel({root}))
c.fs.writeFile('scene/water_opening.rbxm',R.serializeModel({opening}))
c.fs.writeFile('scene/property_edits.rbxm',R.serializeModel(patchArray))
c.fs.writeFile('scene/manifest.json',c.serde.encode('json',manifest,true)..'\n')
c.fs.writeFile('scene/placements.json',c.serde.encode('json',placements,true)..'\n')
print('PLACED ORIGINAL ZONES',original,'BHOP SUPPORTS',supported,'PATCH TARGETS',#patchArray)
print(c.serde.encode('json',counts))
