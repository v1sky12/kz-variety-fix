-- KZ CS2 HUD v4.0 | LocalScript -> StarterPlayer/StarterPlayerScripts
-- Read-only movement observer. Does not write velocity, Humanoid movement,
-- camera, map, gravity or collisions. Works with V5; reads V6 diagnostics.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = {
    -- Unified V17 calibration, overridden by movement telemetry when present.
    StudsPerCSUnit = 0.07101916666666667,
    ReadV6Telemetry = true,
    ShowVitals = true,
    ShowCrosshair = false,
    HideRobloxHealth = true,
    Accent = Color3.fromRGB(145, 210, 239),
    Text = Color3.fromRGB(238, 245, 248),
    Muted = Color3.fromRGB(192, 213, 222),
    Panel = Color3.fromRGB(20, 24, 26),
    PanelTransparency = 0.80,
    Font = Enum.Font.Roboto,
    NumberFont = Enum.Font.RobotoMono,
    HUDScale = 1,
    RefreshHz = 30,
    CSOriginRoblox = Vector3.zero, -- Set only when the import transform is known.
    ShowPracticeButtons = false, -- F6/F7/F8 still work.
    ShowSpeedUnits = true,
    -- Exact names only. Add an OLD SPEED-ONLY ScreenGui here if it exists.
    -- Never add the name of a GUI containing unrelated controls.
    LegacySpeedGuiNames = {},
    ManualTimerKeys = {Start = Enum.KeyCode.F6, Finish = Enum.KeyCode.F7,
        Reset = Enum.KeyCode.F8},
}
local GUI_NAME = "KZ_CS2_HUD"
if playerGui:FindFirstChild(GUI_NAME) then
    warn("KZ HUD: already running; remove the duplicate LocalScript")
    return
end
local connections, hiddenLegacy = {}, {}
local alive = true
local oldHealthEnabled
local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end
local function new(class, parent, props)
    local object = Instance.new(class)
    for k, v in pairs(props or {}) do object[k] = v end
    object.Parent = parent
    return object
end
local gui = new("ScreenGui", playerGui, {
    Name = GUI_NAME, ResetOnSpawn = false, DisplayOrder = 25,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
})
gui:SetAttribute("KZHUDVersion", 4.0)
local canvas = new("Frame", gui, {Name = "Canvas", Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1})
local function panel(name, size, position, anchor)
    local frame = new("Frame", canvas, {Name = name, Size = UDim2.fromOffset(size.X, size.Y),
        Position = position, AnchorPoint = anchor, BackgroundColor3 = Config.Panel,
        BackgroundTransparency = Config.PanelTransparency, BorderSizePixel = 0})
    new("UIScale", frame, {Name = "ResponsiveScale"})
    new("UIGradient", frame, {Rotation = 90, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0)})})
    return frame
end
local function label(parent, name, text, x, y, w, h, size, color, font)
    return new("TextLabel", parent, {Name = name, Text = text,
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1, TextColor3 = color or Config.Text,
        Font = font or Config.Font, TextSize = size, TextStrokeTransparency = 0.65,
        TextStrokeColor3 = Color3.new(0, 0, 0), AutoLocalize = false})
end
local function line(parent, x, y, w, color)
    return new("Frame", parent, {Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, 1), BorderSizePixel = 0,
        BackgroundColor3 = color or Config.Accent, BackgroundTransparency = 0.55})
end
-- Speed lives inside the centered panel, immediately below Main.
local group = new("Frame", canvas, {Name = "BottomGroup",
    Size = UDim2.fromOffset(420, 244), AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -145), BackgroundTransparency = 1})
local groupScale = new("UIScale", group, {Name = "ResponsiveScale"})
local timerPanel = panel("MapTimer", Vector2.new(420, 244),
    UDim2.fromOffset(0, 0), Vector2.new(0, 0))
timerPanel.Parent = group
timerPanel.ResponsiveScale:Destroy() -- Shared scale; no double scaling.
new("UIStroke", timerPanel, {Color = Config.Accent, Thickness = 1,
    Transparency = 0.58})
local courseText = label(timerPanel, "Course", "「Main」  [#1]", 8, 6, 404, 25, 22,
    Color3.fromRGB(151, 220, 110), Enum.Font.RobotoCondensed)
local speedText = label(timerPanel, "HorizontalSpeed", "0", 48, 99, 148, 18, 16,
    Config.Accent, Enum.Font.RobotoCondensed)
local unitsLabel = label(timerPanel, "Units", "CS units/s", 8, 74, 404, 18, 14, Config.Muted)
unitsLabel.Visible = Config.ShowSpeedUnits
local timerText = label(timerPanel, "Time", "", 8, 32, 404, 42, 32,
    Color3.fromRGB(241, 193, 92), Config.NumberFont)
local specsText = label(timerPanel, "Spectators", "Specs: —", 196, 99, 176, 18, 16, Config.Text)
local stageRankText = label(timerPanel, "StageRank", "Stage: —/— · Rank: —/—", 8, 117, 404, 25, 19,
    Config.Text, Enum.Font.RobotoCondensed)
local recordsText = label(timerPanel, "Records", "|| PB: — || WR: — ||", 8, 142, 404, 23, 18,
    Config.Text, Enum.Font.RobotoCondensed)
line(timerPanel, 14, 171, 392)
local positionText = label(timerPanel, "Position", "POS: —   —   —", 8, 180, 404, 19, 14,
    Config.Text, Config.NumberFont)
local anglesText = label(timerPanel, "Angles", "ANG: —   —   —", 8, 200, 404, 19, 14,
    Config.Text, Config.NumberFont)
local checkpointsText = label(timerPanel, "Checkpoints", "CP: —/— TPs: —", 8, 221, 404, 19, 16,
    Config.Text, Enum.Font.RobotoCondensed)
label(canvas,"Build","KZ · V7.22",12,12,112,18,12,Config.Muted)
local waterHint=label(canvas,"WaterHint","Space — всплыть · W + Space — выйти на край",8,38,440,22,14,Config.Accent)
waterHint.Visible=false
local movementNotice=label(canvas,"MovementNotice","Новое движение не запустилось. Причина ошибки — в консоли F9.",8,64,560,22,14,Color3.fromRGB(245,170,100))
movementNotice.Visible=false
local controls = new("Frame", timerPanel, {Name = "PracticeControls",
    Position = UDim2.fromOffset(8, 246), Size = UDim2.fromOffset(404, 21), BackgroundTransparency = 1,
    Visible = Config.ShowPracticeButtons})
local function button(text, index)
    return new("TextButton", controls, {Name = text, Text = text,
        Position = UDim2.fromOffset(index * 134, 0), Size = UDim2.fromOffset(132, 21),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        TextSize = 14, Font = Config.Font, TextColor3 = Config.Muted, AutoLocalize = false})
end
local startButton, finishButton, resetButton = button("START / F6", 0), button("END / F7", 1), button("RESET / F8", 2)
local vitals = panel("Vitals", Vector2.new(238, 58), UDim2.new(0.26, 0, 1, -18), Vector2.new(0, 1))
vitals.BackgroundTransparency = 1
vitals.Visible = Config.ShowVitals
local vitalsLine = line(vitals, 8, 55, 222)
local healthIcon = new("Frame", vitals, {Position = UDim2.fromOffset(13, 26),
    Size = UDim2.fromOffset(18, 4), BorderSizePixel = 0, BackgroundColor3 = Config.Accent})
new("Frame", healthIcon, {Position = UDim2.fromOffset(7, -7), Size = UDim2.fromOffset(4, 18),
    BorderSizePixel = 0, BackgroundColor3 = Config.Accent})
local healthText = label(vitals, "Health", "—", 37, 0, 76, 52, 44, Config.Accent, Enum.Font.RobotoCondensed)
local armorIcon = label(vitals, "ArmorIcon", "◇", 122, 9, 30, 34, 27, Config.Accent)
local armorText = label(vitals, "Armor", "", 157, 0, 76, 52, 40, Config.Accent, Enum.Font.RobotoCondensed)
local crosshair = new("Frame", canvas, {Name = "Crosshair", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(2, 2),
    BorderSizePixel = 0, BackgroundColor3 = Config.Accent, Visible = Config.ShowCrosshair})
local stats = panel("Jumpstats", Vector2.new(340, 116), UDim2.new(1, -20, 1, -125), Vector2.new(1, 1))
local jumpTitle = label(stats, "Title", "LAST JUMP", 8, 4, 324, 20, 15, Config.Accent)
local jumpDistance = label(stats, "Distance", "—", 8, 24, 324, 28, 22, Config.Text, Config.NumberFont)
local jumpDetails = label(stats, "Details", "", 8, 54, 324, 54, 14, Config.Muted, Config.NumberFont)
jumpDetails.TextWrapped = true
local function resize()
    local size = canvas.AbsoluteSize
    local scale = math.clamp(math.min(size.X / 1920, size.Y / 1016), 0.85, 1.4) * Config.HUDScale
    scale = math.min(scale, math.max(0.2, (size.X - 32) / 420), math.max(0.2, size.Y / 380))
    groupScale.Scale = scale
    stats.ResponsiveScale.Scale = scale
    if size.X < 1100 then
        stats.AnchorPoint = Vector2.new(.5, 1)
        stats.Position = UDim2.new(.5, 0, 1, -(244 * scale + math.min(145 * scale, size.Y * .16) + 12))
    else
        stats.AnchorPoint = Vector2.new(1, 1)
        stats.Position = UDim2.new(1, -20, 1, -125)
    end
    group.Position = UDim2.new(0.5, 0, 1, -math.min(145 * scale, size.Y * 0.16))
    vitals.ResponsiveScale.Scale = scale
    vitals.Position = UDim2.new(size.X >= 1000 and 0.26 or 0, size.X >= 1000 and 0 or 16, 1, -18 * scale)
end
connect(canvas:GetPropertyChangedSignal("AbsoluteSize"), resize)
resize()
local function legacy(candidate)
    if candidate == gui or not candidate:IsA("ScreenGui") then return end
    if table.find(Config.LegacySpeedGuiNames, candidate.Name) then
        hiddenLegacy[candidate] = candidate.Enabled
        candidate.Enabled = false
    end
end
for _, object in ipairs(playerGui:GetChildren()) do legacy(object) end
connect(playerGui.ChildAdded, legacy)
if Config.ShowVitals and Config.HideRobloxHealth then
    task.spawn(function()
        for _ = 1, 10 do
            if not alive then return end
            local ok, enabled = pcall(function() return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Health) end)
            if ok then oldHealthEnabled = enabled end
            if pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) end) then return end
            task.wait(0.5)
        end
    end)
end

local function number(value)
    return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end
local function numericAttribute(object, name)
    local v = object and object:GetAttribute(name)
    return number(v) and v or nil
end
local function unitsPerStud(root)
    local scale = numericAttribute(root, "KZStudsPerCSUnit")
        or numericAttribute(workspace, "KZStudsPerCSUnit") or Config.StudsPerCSUnit
    return 1 / (scale > 0 and scale or Config.StudsPerCSUnit)
end
local function horizontal(v) return Vector3.new(v.X, 0, v.Z) end
local function fmt(v) return v and string.format("%.0f", v) or "—" end
local function timeText(seconds)
    local ms = math.floor(math.max(0, seconds) * 1000)
    return string.format("%02d:%02d.%03d", math.floor(ms / 60000), math.floor(ms / 1000) % 60, ms % 1000)
end
local character, humanoid, root
local generation = 0
local speed = 0
local manualState, manualStart, manualElapsed = "Ready", 0, 0
player:SetAttribute("KZShowJumpstats", true)
local function serverTimer() return player:GetAttribute("KZTimerAvailable") == true end
local function clearStats() speed = 0 end
local function manual(action)
    if serverTimer() or not humanoid or humanoid.Health <= 0 then return end
    if action == "Start" then
        manualState, manualStart, manualElapsed = "Running", os.clock(), 0
        clearStats()
    elseif action == "Finish" and manualState == "Running" then
        manualElapsed, manualState = os.clock() - manualStart, "Finished"
    elseif action == "Reset" then
        manualState, manualElapsed = "Ready", 0
        clearStats()
    end
end
connect(startButton.Activated, function() manual("Start") end)
connect(finishButton.Activated, function() manual("Finish") end)
connect(resetButton.Activated, function() manual("Reset") end)
connect(UIS.InputBegan, function(input, processed)
    if processed or UIS:GetFocusedTextBox() then return end
    for action, key in pairs(Config.ManualTimerKeys) do
        if input.KeyCode == key then manual(action) end
    end
end)
local function setup(newCharacter)
    generation = generation + 1
    local token = generation
    character, humanoid, root = nil, nil, nil
    clearStats()
    manualState, manualElapsed = "Ready", 0
    local h = newCharacter:WaitForChild("Humanoid", 10)
    local r = newCharacter:WaitForChild("HumanoidRootPart", 10)
    if token ~= generation or player.Character ~= newCharacter or not h or not r then return end
    character, humanoid, root = newCharacter, h, r
end
connect(player.CharacterAdded, setup)
connect(player.CharacterRemoving, function(old)
    if old ~= character then return end
    generation = generation + 1
    character, humanoid, root = nil, nil, nil
    clearStats()
    manualState, manualElapsed = "Ready", 0
end)
if player.Character then task.spawn(setup, player.Character) end
-- Read-only horizontal speed. No jump-stat block in the screenshot-style HUD.
connect(RunService.Heartbeat, function()
    waterHint.Visible=root~=nil and (numericAttribute(root,"KZWaterLevel") or 0)>0
    movementNotice.Visible=player:GetAttribute("KZBrushFallbackReason")~=nil
    if not root or not root.Parent or not humanoid then speed = 0; return end
    if humanoid.Health <= 0 then
        if manualState == "Running" then manualState, manualElapsed = "Aborted", os.clock() - manualStart end
        speed = 0
        return
    end
    local physicalSpeed = horizontal(root.AssemblyLinearVelocity).Magnitude * unitsPerStud(root)
    speed = Config.ReadV6Telemetry and numericAttribute(root, "KZSpeedUnits") or nil
    speed = speed or physicalSpeed
end)
local function datum(name)
    return numericAttribute(player, name) or numericAttribute(workspace, name)
end
local function integer(value)
    return value and string.format("%.0f", math.max(0, value)) or "—"
end
local function recordTime(seconds)
    if not seconds or seconds < 0 then return "—" end
    local cs = math.floor(seconds * 100 + 0.00001)
    return string.format("%02d:%02d.%02d", math.floor(cs / 6000), math.floor(cs / 100) % 60, cs % 100)
end
local function vectorAttribute(object, name)
    local v = object and object:GetAttribute(name)
    if typeof(v) == "Vector3" and number(v.X) and number(v.Y) and number(v.Z) then return v end
end
local function updateReferenceData()
    local course = player:GetAttribute("KZCourseName") or workspace:GetAttribute("KZCourseName")
    if typeof(course) ~= "string" or course == "" then course = "Main" end
    courseText.Text = "「" .. course .. "」  [#" .. integer(datum("KZCourseId") or 1) .. "]"
    specsText.Text = "Specs: " .. integer(datum("KZSpectatorCount"))
    stageRankText.Text = "Stage: " .. integer(datum("KZStage")) .. "/" .. integer(datum("KZStageTotal"))
        .. " · Rank: " .. integer(datum("KZRank")) .. "/" .. integer(datum("KZRankTotal"))
    recordsText.Text = "|| PB: " .. recordTime(datum("KZPersonalBestSeconds"))
        .. (player:GetAttribute("KZRecordScope") == "Session" and " || SR: " or " || WR: ") .. recordTime(datum("KZWorldRecordSeconds")) .. " ||"
    checkpointsText.Text = "CP: " .. integer(datum("KZCheckpointIndex")) .. "/"
        .. integer(datum("KZCheckpointCount")) .. " TPs: " .. integer(datum("KZTeleportCount"))
    local position = vectorAttribute(root, "KZSourcePosition")

    positionText.Text = position and string.format("POS: %.2f  %.2f  %.2f", position.X, position.Y, position.Z)
        or "POS: —   —   —"
    local angles = vectorAttribute(root, "KZSourceAngles")
    local camera = workspace.CurrentCamera
    if not angles and camera then
        local look = camera.CFrame.LookVector
        local _, _, roll = camera.CFrame:ToOrientation()
        local map = workspace:FindFirstChild("KZ_Variety_CS2_ROBLOX_V17")
        if map then look = map:GetPivot():VectorToObjectSpace(look) end
        local yaw = math.deg(math.atan2(-look.X, -look.Z))
        angles = Vector3.new(-math.deg(math.asin(math.clamp(look.Y, -1, 1))), yaw, math.deg(roll))
    end
    anglesText.Text = angles and string.format("ANG: %.2f  %.2f  %.2f", angles.X, angles.Y, angles.Z)
        or "ANG: —   —   —"
end
local lastRunId = player:GetAttribute("KZRunId")
connect(player:GetAttributeChangedSignal("KZRunId"), function()
    local id = player:GetAttribute("KZRunId")
    if id ~= lastRunId then lastRunId = id; clearStats() end
end)
local elapsedRender = 0
connect(RunService.RenderStepped, function(dt)
    elapsedRender = elapsedRender + dt
    if elapsedRender < 1 / Config.RefreshHz then return end
    elapsedRender = elapsedRender % (1 / Config.RefreshHz)
    speedText.Text = fmt(speed)
    speedText.TextColor3 = Config.Accent
    updateReferenceData()
    stats.Visible = player:GetAttribute("KZShowJumpstats") == true
    local last = numericAttribute(root, "KZLastJumpDistanceUnits")
    local valid = root and root:GetAttribute("KZLastJumpValid")
    jumpTitle.Text = (root and root:GetAttribute("KZLastJumpType") or "LAST JUMP") .. (last and (" #" .. fmt(numericAttribute(root, "KZLastJumpSerial"))) or "") .. (last and (valid and " · measured" or " · invalid") or "")
    local kind=root and root:GetAttribute("KZLastJumpType")
    local best=kind and player:GetAttribute("KZPersonalBest"..kind)
    jumpDistance.Text = last and string.format("%.2f u", last) or "—"
    if best then jumpDistance.Text=jumpDistance.Text..string.format(" · PB %.2f",best) end
    jumpDetails.Text = last and string.format("PRE %s · MAX %s · %s STRAFES\nSYNC %s%% · GAIN %s · LOSS %s",
        fmt(numericAttribute(root, "KZLastJumpPreUnits")), fmt(numericAttribute(root, "KZLastJumpMaxUnits")),
        fmt(numericAttribute(root, "KZLastJumpStrafes")), fmt(numericAttribute(root, "KZLastJumpSync")),
        fmt(numericAttribute(root, "KZLastJumpGainUnits")), fmt(numericAttribute(root, "KZLastJumpLossUnits"))) or "J: show / hide"
    local timedByServer = serverTimer()
    controls.Visible = Config.ShowPracticeButtons and not timedByServer
    local panelHeight = controls.Visible and 270 or 244
    timerPanel.Size = UDim2.fromOffset(420, panelHeight)
    group.Size = UDim2.fromOffset(420, panelHeight)
    local elapsed, status
    if timedByServer then
        status = player:GetAttribute("KZRunState") or "Ready"
        local start = numericAttribute(player, "KZRunStartTime") or 0
        elapsed = status == "Running" and math.max(0, workspace:GetServerTimeNow() - start)
            or numericAttribute(player, "KZRunElapsed") or 0
    else
        status = manualState
        elapsed = status == "Running" and os.clock() - manualStart or manualElapsed
    end
    -- Screenshot-style run time in whole seconds; precise elapsed time remains internal.
    timerText.Text = (status == "Running" or status == "Finished") and timeText(elapsed) or ""
    healthText.Text = humanoid and fmt(math.max(0, humanoid.Health)) or "—"
    healthText.TextColor3 = humanoid and humanoid.Health <= 25 and Color3.fromRGB(239, 117, 100) or Config.Accent
    local armor = numericAttribute(character, "Armor") or numericAttribute(player, "Armor")
    armorIcon.Visible, armorText.Visible = armor ~= nil, armor ~= nil
    armorText.Text = armor and fmt(math.max(0, armor)) or ""
    vitals.Size = UDim2.fromOffset(armor and 238 or 119, 58)
    vitalsLine.Size = UDim2.fromOffset(armor and 222 or 103, 1)
end)
local function cleanup()
    if not alive then return end
    alive = false
    for _, c in ipairs(connections) do c:Disconnect() end
    for object, enabled in pairs(hiddenLegacy) do
        if object.Parent then object.Enabled = enabled end
    end
    if oldHealthEnabled ~= nil then
        pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, oldHealthEnabled) end)
    end
    if gui.Parent then gui:Destroy() end
end
connect(script.Destroying, cleanup)
connect(gui.Destroying, cleanup)
