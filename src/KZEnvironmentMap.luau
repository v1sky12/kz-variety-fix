-- Prepare a complete independent copy. Fail before changing the active map.
local Repair = {}
function Repair.prepare(source,Data,unit,plan)
    assert(source and source:IsA("Model"),"Map model missing")
    assert(#plan.waters==11,"Water repair plan is incomplete")
    local map=source:Clone()
    assert(map,"Map cannot be cloned: enable Archivable")
    local ok,err=pcall(function()
        map:PivotTo(source:GetPivot())
        map:SetAttribute("KZStudsPerCSUnit",unit)
        local colliders=map:FindFirstChild("__V17_Collision",true)
        assert(colliders and #colliders:GetChildren()==16059,
            "Precise map collision geometry differs; repair cancelled")
        local candidates={}
        for _,p in ipairs(map:GetDescendants()) do
            candidates[p.Name]=candidates[p.Name] or {}
            table.insert(candidates[p.Name],p)
        end
        local used={}
        local function match(record,allowDuplicateGeometry)
            local a,b=record.bounds[1],record.bounds[2]
            local centre=Vector3.new((a[1]+b[1])/2,(a[2]+b[2])/2,(a[3]+b[3])/2)
            local size=Vector3.new(record.size[1],record.size[2],record.size[3])*(unit/plan.unit)
            local found
            for _,p in ipairs(candidates[record.name] or {}) do
                if not used[p] and p:IsA(record.kind) and (Data.sourcePoint(map,p.Position)-centre).Magnitude<.08
                    and (p.Size-size).Magnitude<.08*unit then
                    local localRotation=map:GetPivot():ToObjectSpace(p.CFrame).Rotation
                    local r=record.rotation
                    local x=localRotation:VectorToWorldSpace(Vector3.new(1,0,0))
                    local y=localRotation:VectorToWorldSpace(Vector3.new(0,1,0))
                    if (x-Vector3.new(r[1][1],r[2][1],r[3][1])).Magnitude<.0001
                        and (y-Vector3.new(r[1][2],r[2][2],r[3][2])).Magnitude<.0001 then
                        assert(not found or allowDuplicateGeometry,"Ambiguous repair target: "..record.name)
                        found=found or p
                    end
                end
            end
            assert(found,"Repair target missing or moved: "..record.name)
            used[found]=true
            return found
        end
        local wall=match(plan.referenceWall)
        assert(wall.CanCollide and wall:IsDescendantOf(colliders),"Precise ladder wall missing")
        local worldMesh=match(plan.worldMesh)
        local visuals,shells,levelFloors={},{},{}
        for _,water in ipairs(plan.waters) do
            if water.levelReference then
                local floor=match(water.levelReference)
                assert(floor.CanCollide and floor:IsDescendantOf(colliders),"Water level reference floor missing")
                levelFloors[water.id]=floor
            end
            for _,record in ipairs(water.visuals) do visuals[#visuals+1]=match(record,true) end
            for _,record in ipairs(water.shells) do
                local p=match(record)
                assert(p:IsDescendantOf(colliders),"Water shell is outside precise geometry")
                shells[#shells+1]=p
            end
        end
        assert(#visuals==21 and #shells==62,"Water targets differ; repair cancelled")
        assert(#candidates[visuals[1].Name]==21,"Unexpected water visual geometry; repair cancelled")
        worldMesh.CanCollide=false
        worldMesh.CanTouch=false;worldMesh.CanQuery=false
        worldMesh:SetAttribute("KZCollisionReplacedBy","__V17_Collision")
        for _,p in ipairs(visuals) do
            p.Transparency=1;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
        end
        -- Remove full faces of water brushes, including false bottoms.
        -- Separate basin geometry and partial platforms are outside this exact plan.
        for _,p in ipairs(shells) do p.CanCollide=false;p.CanTouch=false;p.CanQuery=false end
        local old=map:FindFirstChild("__KZ_WaterSurfaces")
        if old then old:Destroy() end
        local folder=Instance.new("Folder");folder.Name="__KZ_WaterSurfaces";folder.Parent=map
        local oldCorrections=map:FindFirstChild("__KZ_WaterCorrections")
        if oldCorrections then oldCorrections:Destroy() end
        local corrections=Instance.new("Folder");corrections.Name="__KZ_WaterCorrections";corrections.Parent=map
        for i,water in ipairs(plan.waters) do
            local a,b=water.bounds[1],water.bounds[2]
            local level=b[3]
            if water.levelReference then
                -- The floor defines the bottom, not the water surface. Lowering
                -- this volume to the floor made a 40-unit pool ankle deep.
                map:SetAttribute(Data.waterLevelAttribute(water.id),nil)
                local original=levelFloors[water.id]
                original.CanCollide=true;original.CanTouch=false;original.CanQuery=true
            end
            local p=Instance.new("Part")
            p.Name=string.format("WaterSurface_%02d",i)
            p.Size=Vector3.new((b[2]-a[2])*unit,.025,(b[1]-a[1])*unit)
            p.CFrame=CFrame.new(Data.worldPoint(map,{(a[1]+b[1])/2,(a[2]+b[2])/2,level-.025/unit/2}))*map:GetPivot().Rotation
            p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
            p.CastShadow=false;p.Material=Enum.Material.Glass
            p.Color=Color3.fromRGB(18,126,164);p.Transparency=.42;p.Reflectance=.12
            p:SetAttribute("KZWaterSourceId",water.id);p.Parent=folder
        end
        map.Name="KZ_Variety_CS2_ROBLOX_V21"
        map:SetAttribute("KZEnvironmentRevision",21)
        map:SetAttribute("KZWaterDepthRevision",1)
        map:SetAttribute("KZWaterSurfaceCount",11)
        map:SetAttribute("KZWaterLidsDisabled",10)
        map:SetAttribute("KZWaterVisualsHidden",#visuals)
        map:SetAttribute("KZWaterShellFacesDisabled",#shells)
    end)
    if not ok then map:Destroy();error(err) end
    return map
end
return Repair
