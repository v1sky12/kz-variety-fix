-- Build an independent map copy; never edit the supplied map or visual geometry.
local Repair = {}
function Repair.prepare(source,Data,unit)
    assert(source and source:IsA("Model"),"Map model missing")
    assert(#Data.ladderSurfaces>0,"Source ladder surfaces missing")
    local map=source:Clone()
    assert(map,"Map cannot be cloned: enable Archivable")
    map.Name="KZ_Variety_CS2_ROBLOX_V18"
    local ok,err=pcall(function()
        map:PivotTo(source:GetPivot())
        local old=map:FindFirstChild("__KZ_LadderCollisions")
        if old then old:Destroy() end
        local folder=Instance.new("Folder")
        folder.Name="__KZ_LadderCollisions";folder.Parent=map
        local meshes=0
        for _,part in ipairs(map:GetDescendants()) do
            if part:IsA("MeshPart") and part.Name:match("^CS2_LADDERS_") then
                part.CanCollide=false
                meshes=meshes+1
            end
        end
        assert(meshes>0,"No CS2_LADDERS meshes: map layout differs; repair cancelled")
        map:SetAttribute("KZStudsPerCSUnit",unit)
        for i,surface in ipairs(Data.ladderSurfaces) do
            local a,b=surface.bounds[1],surface.bounds[2]
            local part=Instance.new("Part")
            part.Name=string.format("SourceLadder_%03d",i)
            part.Size=Vector3.new(math.max(.05,(b[2]-a[2])*unit),
                (b[3]-a[3])*unit,math.max(.05,(b[1]-a[1])*unit))
            local centre={(a[1]+b[1])/2,(a[2]+b[2])/2,(a[3]+b[3])/2}
            part.CFrame=CFrame.new(Data.worldPoint(map,centre))*map:GetPivot().Rotation
            part.Anchored=true;part.CanCollide=true;part.CanTouch=false
            part.CanQuery=true;part.CastShadow=false;part.Transparency=1
            part.CustomPhysicalProperties=PhysicalProperties.new(.7,0,0,100,100)
            part:SetAttribute("KZLadderSurfaceId",surface.id)
            part.Parent=folder
        end
        map:SetAttribute("KZLadderCollisionRevision",18)
        map:SetAttribute("KZLadderVisualMeshCount",meshes)
        map:SetAttribute("KZLadderSurfaceCount",#Data.ladderSurfaces)
    end)
    if not ok then map:Destroy();error(err) end
    return map
end
return Repair
