-- Run in Play CLIENT Command Bar. Temporary query shape; map/character are not edited.
local Probe = {}
function Probe.run()
    local player = game:GetService("Players").LocalPlayer
    assert(player, "Select CLIENT context in Play")
    local character = player.Character; assert(character, "Character missing")
    local root = character:FindFirstChild("HumanoidRootPart")
    local h = character:FindFirstChildOfClass("Humanoid")
    local hull = character:FindFirstChild("KZSourceHull")
    assert(root and h and hull, "KZ character/hull missing")
    local unit = root:GetAttribute("KZStudsPerCSUnit") or .07101916666666667
    print("[KZ_STUCK] BEGIN", "position", root.Position, "velocity", root.AssemblyLinearVelocity)
    print("[KZ_STUCK] state", h:GetState().Name, "anchored", root.Anchored,
        "platformStand", h.PlatformStand, "health", h.Health)
    for _, key in ipairs({"KZGrounded", "KZOwnsAirPhysics", "KZOnLadder", "KZLadderEdgeState", "KZLadderId",
        "KZSurfing", "KZSurfPart", "KZSurfNormal", "KZSurfSeamRetries", "KZBlockingPart", "KZInputMagnitude", "KZJumpNeedsRelease", "KZTakeoffSeparated",
        "KZInteriorOverlapCount", "KZOverlapRecoveryCount", "KZLastOverlapParts",
        "KZLastOverlapRecoveryStuds", "KZLandingWindow", "KZHumanoidState", "KZInWater", "KZGravityMultiplier"}) do
        print("[KZ_STUCK]", key, root:GetAttribute(key))
    end
    print("[KZ_STUCK] crouched", player:GetAttribute("KZCrouched"),
        "airDuck", player:GetAttribute("KZAirDuck"),
        "spectating", player:GetAttribute("KZSpectatingUserId"), "hull", hull.Size)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true
    params.CollisionGroup = hull.CollisionGroup
    params.MaxParts = 32
    local shape = Instance.new("Part")
    shape.Name = "__KZStuckQuery"
    shape.Anchored = true; shape.CanCollide = false; shape.CanTouch = false
    shape.CanQuery = false; shape.Transparency = 1
    shape.Size = Vector3.new(math.max(.01, hull.Size.X-.06),
        math.max(.01, hull.Size.Y-.06), math.max(.01, hull.Size.Z-.06))
    local querySize = shape.Size
    shape.CFrame = hull.CFrame
    params.FilterDescendantsInstances = {character, shape}
    shape.Parent = workspace
    local ok, overlaps = pcall(function() return workspace:GetPartsInPart(shape, params) end)
    shape:Destroy()
    local paths = {}
    if ok then
        table.sort(overlaps, function(a, b) return a:GetFullName() < b:GetFullName() end)
        print("[KZ_STUCK] exact interior overlaps", #overlaps)
        for _, part in ipairs(overlaps) do
            paths[#paths+1] = part:GetFullName()
            local fidelity = part:IsA("MeshPart") and part.CollisionFidelity.Name or "primitive"
            print("[KZ_STUCK] OVERLAP", part:GetFullName(), part.ClassName,
                "size", part.Size, "position", part.Position, "fidelity", fidelity)
        end
    else print("[KZ_STUCK] overlap query failed", overlaps) end
    local cast = RaycastParams.new()
    cast.FilterType = Enum.RaycastFilterType.Exclude
    cast.FilterDescendantsInstances = {character}
    cast.RespectCanCollide = true; cast.CollisionGroup = hull.CollisionGroup
    for _, direction in ipairs({Vector3.new(1,0,0),Vector3.new(-1,0,0),
        Vector3.new(0,0,1),Vector3.new(0,0,-1),Vector3.new(0,1,0)}) do
        local hit = workspace:Blockcast(hull.CFrame, querySize, direction * .25, cast)
        if hit then print("[KZ_STUCK] NEAR", direction, hit.Instance:GetFullName(),
            "distance units", hit.Distance/unit, "normal", hit.Normal) end
    end
    print("[KZ_STUCK] END — overlaps/near hits are measurements; nearby parts alone do not prove a faulty collider")
    return {state=h:GetState().Name, onLadder=root:GetAttribute("KZOnLadder"), overlaps=paths}
end
return Probe
