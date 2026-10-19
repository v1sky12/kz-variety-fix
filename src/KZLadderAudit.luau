-- Read-only map and character diagnostics; works in Edit or Play Client.
local Audit={}
function Audit.run()
    local Data=require(script.Parent.KZMapData)
    local map=Data.findMap(workspace)
    assert(map,"Active V21/V20/V19/V18/V17 map missing")
    local collidableMeshes,parts=0,0
    for _,part in ipairs(map:GetDescendants()) do
        if part:IsA("MeshPart") and part.Name:match("^CS2_LADDERS_") and part.CanCollide then
            collidableMeshes=collidableMeshes+1
        end
    end
    local folder=map:FindFirstChild("__KZ_LadderCollisions")
    if folder then parts=#folder:GetChildren() end
    print("[KZ_LADDER] map",map.Name,"revision",map:GetAttribute("KZLadderCollisionRevision"),
        "collidable ladder meshes",collidableMeshes,"source colliders",parts,"expected",#Data.ladderSurfaces)
    print("[KZ_MAP] environment revision",map:GetAttribute("KZEnvironmentRevision"),
        "water surfaces",map:GetAttribute("KZWaterSurfaceCount"),
        "water shell faces disabled",map:GetAttribute("KZWaterShellFacesDisabled"))
    local player=game:GetService("Players").LocalPlayer
    local character=player and player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local hum=character and character:FindFirstChildOfClass("Humanoid")
    if not root or not hum then print("[KZ_LADDER] map checked; character diagnostics require Play Client");return end
    local feet=Data.feetSource(map,root,hum)
    local ladder,normal=Data.findLadder(feet,player:GetAttribute("KZCrouched") and 54 or 72)
    print("[KZ_LADDER] source feet",feet,"candidate",ladder and ladder.id,"normal",normal,
        "attached",root:GetAttribute("KZOnLadder"),"active",root:GetAttribute("KZLadderId"),"edge",root:GetAttribute("KZLadderEdgeState"),
        "input",root:GetAttribute("KZInputMagnitude"),"velocity",root.AssemblyLinearVelocity)
    local hull=character:FindFirstChild("KZSourceHull")
    if hull then
        local relative=map:GetPivot():ToObjectSpace(hull.CFrame)
        print("[KZ_LADDER] hull map axes",relative.RightVector,relative.UpVector,relative.LookVector,"size",hull.Size)
    end
end
return Audit
