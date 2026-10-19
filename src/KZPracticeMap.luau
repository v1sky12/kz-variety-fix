-- Optional practice area outside the original map bounds; original route retained.
local Practice={}
function Practice.prepare(source,data,unit,plan)
    local visualNames={}
    for _,record in ipairs(plan and plan.renderOnlyMeshes or {}) do
        local part=source:FindFirstChild(record.name,true)
        assert(part and part:IsA("MeshPart"),"Missing audited render-only mesh: "..record.name)
        local centre=data.sourcePoint(source,part.Position)
        local a,b=record.bounds[1],record.bounds[2]
        assert(math.abs(centre.X-(a[1]+b[1])/2)<.1
            and math.abs(centre.Y-(a[2]+b[2])/2)<.1
            and math.abs(centre.Z-(a[3]+b[3])/2)<.1,"Render-only mesh position changed")
        assert(math.abs(part.Size.X-record.size[1])<.1*unit
            and math.abs(part.Size.Y-record.size[2])<.1*unit
            and math.abs(part.Size.Z-record.size[3])<.1*unit,"Render-only mesh size changed")
        visualNames[#visualNames+1]=record.name
    end
    local box,size=source:GetBoundingBox()
    local maxX=-math.huge
    for _,x in ipairs({-1,1}) do for _,y in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
        local corner=box:PointToWorldSpace(Vector3.new(size.X*x,size.Y*y,size.Z*z)*.5)
        maxX=math.max(maxX,data.sourcePoint(source,corner).X)
    end end end
    local start=math.ceil((maxX+512)/128)*128
    local map=source:Clone();map.Name="KZ_Variety_CS2_ROBLOX_V22"
    map:PivotTo(source:GetPivot())
    for _,name in ipairs(visualNames) do
        local part=map:FindFirstChild(name,true)
        part.CanCollide=false;part.CanQuery=false;part.CanTouch=false
    end
    map:SetAttribute("KZRenderOnlyCollisionFixes",#visualNames)
    local buttons=Instance.new("Folder");buttons.Name="__KZ_ButtonCollisions";buttons.Parent=map
    for _,record in ipairs(plan and plan.buttonColliders or {}) do
        local a,b=record.bounds[1],record.bounds[2]
        local p=Instance.new("Part");p.Name=record.name;p.Anchored=true
        p.Size=Vector3.new(b[2]-a[2],b[3]-a[3],b[1]-a[1])*unit
        p.CFrame=CFrame.new(data.worldPoint(map,{(a[1]+b[1])/2,(a[2]+b[2])/2,(a[3]+b[3])/2}))*map:GetPivot().Rotation
        p.Transparency=1;p.CanCollide=true;p.CanQuery=true;p.CanTouch=false
        p:SetAttribute("KZSourceEntityId",record.sourceId);p.Parent=buttons
    end
    local old=map:FindFirstChild("__KZ_BhopPractice")
    if old then old:Destroy() end
    local folder=Instance.new("Folder");folder.Name="__KZ_BhopPractice";folder.Parent=map
    local function part(name,a,b,color)
        local p=Instance.new("Part");p.Name=name;p.Anchored=true
        p.Size=Vector3.new(b[2]-a[2],b[3]-a[3],b[1]-a[1])*unit
        p.CFrame=CFrame.new(data.worldPoint(map,{(a[1]+b[1])/2,(a[2]+b[2])/2,(a[3]+b[3])/2}))*map:GetPivot().Rotation
        p.CanCollide=true;p.CanTouch=false;p.CanQuery=true
        p.Material=Enum.Material.Concrete;p.Color=color
        p.CustomPhysicalProperties=PhysicalProperties.new(.7,0,0,100,100)
        p.Parent=folder;return p
    end
    part("Start",{start-96,-128,-32},{start+64,512,0},Color3.fromRGB(70,90,100))
    part("CatchFloor",{start-128,-160,-112},{start+1008,544,-96},Color3.fromRGB(45,50,55))
    part("Finish",{start+880,-128,-32},{start+1008,512,0},Color3.fromRGB(70,110,90))
    local types={11,12,13};local labels={"Multi","Single","Sequential"}
    local colors={Color3.fromRGB(65,145,100),Color3.fromRGB(185,120,55),Color3.fromRGB(115,95,185)}
    for lane=1,3 do
        local y=(lane-1)*192
        for i=1,5 do
            local x=start+160+(i-1)*160
            local block=part(labels[lane].."_"..i,{x-32,y-32,-32},{x+32,y+32,0},colors[lane])
            block:SetAttribute("KZBhopType",types[lane]);block:SetAttribute("KZBhopDelay",.1)
            block:SetAttribute("KZSourceBoundsMin",Vector3.new(x-32,y-32,0))
            block:SetAttribute("KZSourceBoundsMax",Vector3.new(x+32,y+32,2))
        end
        local gui=Instance.new("BillboardGui");gui.Name=labels[lane].."Label"
        gui.Size=UDim2.fromOffset(160,32);gui.StudsOffset=Vector3.new(0,4,0);gui.MaxDistance=80
        local marker=part(labels[lane].."Marker",{start-40,y-4,0},{start-32,y+4,8},colors[lane])
        marker.CanCollide=false;marker.CanQuery=false
        gui.Adornee=marker;gui.Parent=marker
        local text=Instance.new("TextLabel");text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1
        text.Text=labels[lane].." BHOP";text.TextColor3=Color3.fromRGB(230,235,240)
        text.TextSize=18;text.Font=Enum.Font.GothamMedium;text.Parent=gui
    end
    map:SetAttribute("KZPracticeOrigin",Vector3.new(start,0,4))
    map:SetAttribute("KZPracticeRevision",22)
    return map
end
return Practice
