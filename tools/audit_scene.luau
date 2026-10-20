local Context=require('./lune_context')
local c=Context.open('kz_variety_fix.rbxl')
local Data=c.load('KZMapData')
local B=c.load('KZBrushCollision')
local count,failed,byClass=0,{},{}
local brushes,meshes={},{}
local started=os.clock()
for _,p in c.map:GetDescendants() do
    if p:IsA('BasePart') and p.CanCollide then
        count+=1;byClass[p.ClassName]=(byClass[p.ClassName] or 0)+1
        if p:IsA('MeshPart') or p:IsA('PartOperation') or p:IsA('Part') and p.Shape~=c.roblox.Enum.PartType.Block then
            meshes[#meshes+1]=p:GetFullName()
        else
            local ok,brush=pcall(B.fromPart,p)
            if ok then brushes[#brushes+1]=brush else failed[#failed+1]={name=p:GetFullName(),reason=tostring(brush)} end
        end
        if count%1000==0 then print('COMPILE',count,os.clock()-started,'failures',#failed) end
    end
end
print('COMPILED',count,#brushes,'MESHES',#meshes,'FAILED',#failed,'seconds',os.clock()-started)
c.fs.writeFile('/tmp/kz-map-audit.json',c.serde.encode('json',{count=count,primitives=#brushes,meshes=meshes,failures=failed,classes=byClass,pivot={c.map:GetPivot():GetComponents()},unit=c.unit},true))
assert(#failed==0,'Real map collider construction failed; inspect /tmp/kz-map-audit.json')
