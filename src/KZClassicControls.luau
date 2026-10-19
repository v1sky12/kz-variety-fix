-- Standard Roblox camera is retained, including when following a spectator target.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local shared = game:GetService("ReplicatedStorage"):WaitForChild("KZClassic", 15)
assert(shared, "KZClassic shared folder missing")
local Net = shared:WaitForChild("Action")
local Data = require(shared:WaitForChild("KZMapData"))
local player = Players.LocalPlayer
local connections = {}
local windowFocused = true
local function connect(event, callback)
    local c = event:Connect(callback); connections[#connections + 1] = c; return c
end
local function say(text)
    local channels = game:GetService("TextChatService"):FindFirstChild("TextChannels")
    local general = channels and channels:FindFirstChild("RBXGeneral")
    if general then general:DisplaySystemMessage("[KZ] " .. text)
    else pcall(function() StarterGui:SetCore("SendNotification", {Title = "KZ", Text = text, Duration = 3}) end) end
end
local originalCameraMode = player.CameraMode
local function restoreCamera()
    local camera = workspace.CurrentCamera
    local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if camera and h then camera.CameraSubject = h end
    player.CameraMode = originalCameraMode
end
local function cycleSpectator()
    local candidates = {}
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            local h = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then candidates[#candidates + 1] = other end
        end
    end
    table.sort(candidates, function(a, b) return a.UserId < b.UserId end)
    if #candidates == 0 then say("No player to spectate"); return end
    local current = player:GetAttribute("KZSpectatingUserId")
    local nextIndex = 1
    for i, other in ipairs(candidates) do if other.UserId == current then nextIndex = i % #candidates + 1 end end
    Net:FireServer("Spectate", candidates[nextIndex].UserId)
end
local function duckWanted()
    return windowFocused and not UIS:GetFocusedTextBox() and (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl))
end
local bindings = {
    [Enum.KeyCode.C] = "Checkpoint", [Enum.KeyCode.V] = "Teleport",
    [Enum.KeyCode.R] = "Restart", [Enum.KeyCode.E] = "Use",
    [Enum.KeyCode.LeftBracket] = "PreviousCP", [Enum.KeyCode.RightBracket] = "NextCP",
}
connect(UIS.InputBegan, function(input, processed)
    if processed or UIS:GetFocusedTextBox() then return end
    if bindings[input.KeyCode] then
        local camera=workspace.CurrentCamera
        local payload=bindings[input.KeyCode]=="Checkpoint" and camera and {view=camera.CFrame.LookVector} or nil
        Net:FireServer(bindings[input.KeyCode],payload)
    elseif input.KeyCode == Enum.KeyCode.B then cycleSpectator()
    elseif input.KeyCode == Enum.KeyCode.N then Net:FireServer("Spectate", 0)
    elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then Net:FireServer("Crouch", true)
    elseif input.KeyCode == Enum.KeyCode.J then player:SetAttribute("KZShowJumpstats", not player:GetAttribute("KZShowJumpstats")) end
end)
connect(UIS.InputEnded, function(input)
    if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        Net:FireServer("Crouch", duckWanted())
    end
end)
connect(UIS.WindowFocusReleased, function()
    windowFocused = false; Net:FireServer("Crouch", false)
end)
connect(UIS.WindowFocused, function() windowFocused = true end)
connect(UIS.TextBoxFocused, function() Net:FireServer("Crouch", false) end)
connect(Net.OnClientEvent, function(kind, value, angles)
    if kind == "Message" then say(value)
    elseif kind == "Warp" and angles then
        local camera = workspace.CurrentCamera
        local map = Data.findMap(workspace)
        if camera and map then
            local yaw, pitch = math.rad(angles[2]), math.rad(angles[1])
            local look = map:GetPivot():VectorToWorldSpace(Vector3.new(
                -math.sin(yaw) * math.cos(pitch), -math.sin(pitch), -math.cos(yaw) * math.cos(pitch)))
            camera.CFrame = CFrame.lookAt(camera.CFrame.Position, camera.CFrame.Position + look)
        end
    end
end)
local duckAccumulator = 0
connect(RunService.Heartbeat, function(dt)
    local targetId = player:GetAttribute("KZSpectatingUserId")
    local camera = workspace.CurrentCamera
    if targetId then
        local target = Players:GetPlayerByUserId(targetId)
        local h = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
        if h and camera then
            camera.CameraSubject = h; player.CameraMode = Enum.CameraMode.Classic
        end
    elseif camera and player.Character then
        local h = player.Character:FindFirstChildOfClass("Humanoid")
        if h and camera.CameraSubject ~= h then restoreCamera() end
    end
    duckAccumulator = duckAccumulator + dt
    if duckAccumulator >= .2 then
        duckAccumulator = 0
        -- Retry standing after a low ceiling becomes clear; don't trap the player crouched.
        local wanted = duckWanted()
        if player:GetAttribute("KZCrouched") ~= wanted then Net:FireServer("Crouch", wanted) end
    end
end)
connect(script.Destroying, function()
    for _, c in ipairs(connections) do c:Disconnect() end
    Net:FireServer("Spectate", 0); Net:FireServer("Crouch", false)
    restoreCamera()
end)
say("C: checkpoint · V: teleport · R: restart · E: timer button · Ctrl: crouch · J: jumpstats · B/N: spectate/return")
