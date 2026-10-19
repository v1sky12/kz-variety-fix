-- Services/signals are fixtures; the entire real server script runs below.
local serverClock=10
local function signal()
    local out={callbacks={}}
    function out:Connect(fn)
        local c={active=true}
        function c:Disconnect() self.active=false end
        self.callbacks[#self.callbacks+1]={fn=fn,connection=c}
        return c
    end
    function out:Fire(...)
        for _,entry in ipairs(self.callbacks) do if entry.connection.active then entry.fn(...) end end
    end
    return out
end
local function typeof(value)
    local mt=type(value)=='table' and getmetatable(value)
    return mt and mt.__type or type(value)=='table' and value.__type or type(value)
end
local sent={}
local Net={OnServerEvent=signal()}
function Net:FireClient(player,kind,...) sent[#sent+1]={player=player,kind=kind,args={...}} end
local Players={PlayerAdded=signal(),PlayerRemoving=signal()}
function Players:GetPlayers() return {} end
function Players:GetPlayerByUserId() return nil end
local serverMap={}
function serverMap:GetPivot() return CFrame.new() end
function serverMap:GetAttribute(n) if n=='KZStudsPerCSUnit' then return 1 end end
function serverMap:FindFirstChild() return nil end
function serverMap:IsA(name) return name=='Model' end
local workspace={Gravity=800}
function workspace:GetServerTimeNow() return serverClock end
function workspace:FindFirstChild(name) if name:sub(1,10)=='KZ_Variety' then return serverMap end end
function workspace:WaitForChild() return serverMap end
function workspace:Raycast(position,direction,params)
    assert(params.FilterDescendantsInstances[1]==serverMap,'ground queries must exclude other players')
    if position.Y+direction.Y<=0 and position.Y>=0 then return {Normal=Vector3.new(0,1,0)} end
end
local RunService={Heartbeat=signal()}
local TextChatService={}
function TextChatService:GetChildren() return {} end
local shared={}
function shared:WaitForChild(name) if name=='Action' then return Net else return name end end
local ReplicatedStorage={WaitForChild=function() return shared end}
local PhysicsService={RegisterCollisionGroup=function() end,CollisionGroupSetCollidable=function() end}
local services={Players=Players,RunService=RunService,ReplicatedStorage=ReplicatedStorage,TextChatService=TextChatService,PhysicsService=PhysicsService}
local game={GetService=function(_,name) return assert(services[name],name) end}
local require=function(name) return name=='KZMapData' and Data or name=='KZBhop' and Bhop or error(name) end
local RaycastParams={new=function() return {} end}
local Enum={RaycastFilterType={Include='Include',Exclude='Exclude'}}
local Instance={new=function() return {Triggered=signal()} end}
local task={spawn=function(fn,...) return fn(...) end}
local script={Destroying=signal()}
local function makePlayer(id)
    local attrs={}
    local player={UserId=id,CharacterAdded=signal()}
    function player:SetAttribute(k,v) attrs[k]=v end
    function player:GetAttribute(k) return attrs[k] end
    Players.PlayerAdded:Fire(player)
    local root=setmetatable({_cf=CFrame.new(Vector3.new(0,36,0)),Size=Vector3.new(2,2,2),AssemblyLinearVelocity=Vector3.zero,
        AssemblyAngularVelocity=Vector3.zero,CollisionGroup='KZClassicPlayers'}, {
        __index=function(self,k) if k=='Position' then return self._cf.Position elseif k=='CFrame' then return self._cf end end,
        __newindex=function(self,k,v) if k=='CFrame' then rawset(self,'_cf',v) else rawset(self,k,v) end end,
    })
    local humanoid={Health=100,HipHeight=35}
    player.Character={FindFirstChildOfClass=function() return humanoid end,FindFirstChild=function() return root end}
    return player,root
end
