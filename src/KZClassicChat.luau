-- Local numeric jump results; no user text is broadcast to other players.
local Players=game:GetService("Players")
local TextChatService=game:GetService("TextChatService")
local StarterGui=game:GetService("StarterGui")
local player=Players.LocalPlayer
local enabled=true
local connection
local characterConnection
local destroyed=false
local allowed={LJ=true,BH=true,MBH=true,WJ=true,LAJ=true}
local records={} -- Personal records for this client session; survive character respawns.
local function display(text)
    local channels=TextChatService:FindFirstChild("TextChannels")
    local channel=channels and (channels:FindFirstChild("RBXGeneral") or channels:FindFirstChild("RBXSystem"))
    if channel then
        pcall(function() channel:DisplaySystemMessage(text,"KZJumpstats") end)
    else
        -- Supports places still configured with legacy chat.
        pcall(function() StarterGui:SetCore("ChatMakeSystemMessage",{Text=text,
            Color=Color3.fromRGB(120,210,255)}) end)
    end
end
local function attach(character)
    if destroyed then return end
    if connection then connection:Disconnect();connection=nil end
    local root=character:WaitForChild("HumanoidRootPart",10)
    if not root or destroyed or player.Character~=character then return end
    local lastSerial=root:GetAttribute("KZLastJumpSerial")
    connection=root:GetAttributeChangedSignal("KZLastJumpSerial"):Connect(function()
        local serial=root:GetAttribute("KZLastJumpSerial")
        if serial==lastSerial then return end
        lastSerial=serial
        if not root:GetAttribute("KZLastJumpValid") then return end
        local distance=root:GetAttribute("KZLastJumpDistanceUnits")
        if type(distance)~="number" or distance~=distance or distance<0 or distance>500 then return end
        local kind=root:GetAttribute("KZLastJumpType")
        if not allowed[kind] then return end
        local record=not records[kind] or distance>records[kind]
        if record then records[kind]=distance end
        player:SetAttribute("KZPersonalBest"..kind,records[kind])
        root:SetAttribute("KZLastJumpNewRecord",record)
        if not enabled then return end
        display((record and "[PB] " or "")..string.format("[KZ] %s: %.2f units | pre %.1f | max %.1f | %d strafes | sync %.1f%%",
            root:GetAttribute("KZLastJumpType") or "LJ",distance,
            root:GetAttribute("KZLastJumpPreUnits") or 0,
            root:GetAttribute("KZLastJumpMaxUnits") or 0,
            root:GetAttribute("KZLastJumpStrafes") or 0,
            root:GetAttribute("KZLastJumpSync") or 0))
    end)
end
characterConnection=player.CharacterAdded:Connect(attach)
if player.Character then task.spawn(attach,player.Character) end
local command=Instance.new("TextChatCommand")
command.Name="KZJumpstatsToggle";command.PrimaryAlias="/togglejs";command.SecondaryAlias="!togglejs"
command.Parent=TextChatService
command.Triggered:Connect(function(source)
    if source and source.UserId~=player.UserId then return end
    enabled=not enabled;display("[KZ] Jumpstats "..(enabled and "ON" or "OFF"))
end)
script.Destroying:Connect(function()
    destroyed=true
    if characterConnection then characterConnection:Disconnect() end
    if connection then connection:Disconnect() end
    command:Destroy()
end)
