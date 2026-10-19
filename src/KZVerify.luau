local function run()
-- Studio Command Bar in PLAY CLIENT context; read-only.
local player = game:GetService("Players").LocalPlayer
assert(player, "Select Client context in Play first")
local character = player.Character; assert(character, "Character missing")
local root = character:FindFirstChild("HumanoidRootPart"); assert(root, "Root missing")
local hull = character:FindFirstChild("KZSourceHull"); assert(hull, "Source hull missing: check KZClassicGameplay server Output")
local unit = root:GetAttribute("KZStudsPerCSUnit"); assert(unit, "Movement telemetry missing")
print("Profile", root:GetAttribute("KZMovementProfile"), "stud/unit", unit)
print("Speed", root:GetAttribute("KZSpeedUnits"), "pre bonus", root:GetAttribute("KZPreBonusUnits"))
print("Hull", hull.Size, "standing 32/72/32 units", Vector3.new(32, 72, 32) * unit)
print("Last jump", root:GetAttribute("KZLastJumpDistanceUnits"), "height", root:GetAttribute("KZLastJumpHeightStuds"),
    "duration", root:GetAttribute("KZLastJumpDuration"), "valid", root:GetAttribute("KZLastJumpValid"), "reason", root:GetAttribute("KZLastJumpInvalidReason"))
print("Crouched", player:GetAttribute("KZCrouched"), "standing offset", root:GetAttribute("KZStandingHeightStuds"))
print("Ladder", root:GetAttribute("KZOnLadder"), "contact", root:GetAttribute("KZLadderId"),
    "edge",root:GetAttribute("KZLadderEdgeState"),"last step units", root:GetAttribute("KZLastStepHeightUnits"))
print("Surf",root:GetAttribute("KZSurfing"),root:GetAttribute("KZSurfNormal"),root:GetAttribute("KZSurfPart"))
print("Timer", player:GetAttribute("KZRunState"), "CP", player:GetAttribute("KZCheckpointCount"),
    "TP", player:GetAttribute("KZTeleportCount"), "record scope", player:GetAttribute("KZRecordScope"))
print("Map geometry/collision verification still requires walking the actual route in Studio.")

end
return {run = run}
