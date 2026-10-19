-- Crouch changes the visible body and camera; it never teleports the assembly.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local poses = {}
local rotations = {
    LeftHip = -65, RightHip = -65, LeftKnee = 110, RightKnee = 110,
    LeftAnkle = -45, RightAnkle = -45, Waist = 12,
}
local function restore(pose)
    for joint, original in pairs(pose.joints) do
        if joint.Parent then joint.C0 = original end
    end
    if pose.humanoid and pose.humanoid.Parent then
        pose.humanoid.CameraOffset = pose.cameraOffset
    end
end
local connection = RunService.PreSimulation:Connect(function(dt)
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local pose = poses[player]
        if pose and pose.character ~= character then restore(pose); poses[player] = nil; pose = nil end
        if character then
            local h = character:FindFirstChildOfClass("Humanoid")
            if not pose and h then
                pose = {character = character, humanoid = h, alpha = 0,
                    cameraOffset = h.CameraOffset, joints = {}, bodyRoot = nil}
                for _, joint in ipairs(character:GetDescendants()) do
                    if joint:IsA("Motor6D") then
                        if rotations[joint.Name] then pose.joints[joint] = joint.C0
                        elseif joint.Name == "Root" or joint.Name == "RootJoint" then
                            pose.joints[joint] = joint.C0; pose.bodyRoot = joint
                        end
                    end
                end
                poses[player] = pose
            end
            if pose then
                local root = character:FindFirstChild("HumanoidRootPart")
                local unit = root and root:GetAttribute("KZStudsPerCSUnit") or .07101916666666667
                local target = player:GetAttribute("KZCrouched") and 1 or 0
                pose.alpha = pose.alpha + (target - pose.alpha) * (1 - math.exp(-15 * math.max(0, dt)))
                local lower = 18 * unit * pose.alpha
                for joint, original in pairs(pose.joints) do
                    if joint.Parent then
                        if joint == pose.bodyRoot then joint.C0 = original + Vector3.new(0, -lower, 0)
                        else joint.C0 = original * CFrame.Angles(math.rad(rotations[joint.Name]) * pose.alpha, 0, 0) end
                    end
                end
                pose.humanoid.CameraOffset = pose.cameraOffset + Vector3.new(0, -lower, 0)
            end
        end
    end
    for player, pose in pairs(poses) do if not player.Parent then restore(pose); poses[player] = nil end end
end)
script.Destroying:Connect(function()
    connection:Disconnect()
    for _, pose in pairs(poses) do restore(pose) end
end)
