local function signal()
    local out={callbacks={}}
    function out:Connect(fn)
        local c={active=true};function c:Disconnect() self.active=false end
        self.callbacks[#self.callbacks+1]={fn=fn,c=c};return c
    end
    function out:Fire(...) for _,entry in ipairs(self.callbacks) do if entry.c.active then entry.fn(...) end end end
    return out
end
local typeof=function(v) local m=type(v)=='table' and getmetatable(v);return m and m.__type or type(v)=='table' and v.__type or type(v) end
local attrs={KZTeleportSerial=0}
local player={CharacterAdded=signal(),CharacterRemoving=signal()}
function player:GetAttribute(k) return attrs[k] end
function player:SetAttribute(k,v) attrs[k]=v end
local keys={}
local UIS={WindowFocusReleased=signal(),WindowFocused=signal(),InputChanged=signal()}
function UIS:GetFocusedTextBox() return nil end
function UIS:IsKeyDown(key) return keys[key]==true end
local RunService={PreSimulation=signal(),PostSimulation=signal()}
local sent={}
local Net={OnClientEvent=signal()}
function Net:FireServer(kind,...) sent[#sent+1]={kind=kind,args={...}} end
local fallback={Disabled=true,Destroy=function(self) self.destroyed=true end}
local template={Clone=function() fallback={Disabled=true};return fallback end}
local shared={}
function shared:WaitForChild(n) return n=='Action' and Net or n end
function shared:FindFirstChild(n) if n=='KZBrushFallbackSource' then return template end end
local require=function(n)
    return ({KZMapData=Data,KZClassicCore=Core,KZBrushCollision=Collision,KZBrushMotor=Motor})[n] or error(n)
end
local rootAttrs={}
local root=setmetatable({_cf=CFrame.new(Vector3.new(0,36.001,0)),Size=Vector3.new(2,2,2),AssemblyMass=1,CanCollide=false}, {
    __index=function(self,k) if k=='Position' then return self._cf.Position elseif k=='CFrame' then return self._cf end end,
    __newindex=function(self,k,v) if k=='CFrame' then rawset(self,'_cf',v) else rawset(self,k,v) end end,
})
function root:SetAttribute(k,v) rootAttrs[k]=v end
function root:GetAttribute(k) return rootAttrs[k] end
function root:IsA(n) return n=='BasePart' end
local humanoid={HipHeight=35,Health=100,EvaluateStateMachine=true,AutoRotate=true,WalkSpeed=16}
local hull={CanCollide=true,CollisionGroup='Default',IsA=function(_,n) return n=='BasePart' end}
local character={DescendantAdded=signal()}
function character:WaitForChild(n) return ({Humanoid=humanoid,HumanoidRootPart=root,KZSourceHull=hull})[n] end
function character:GetDescendants() return {root,hull} end
root.Parent=character;humanoid.Parent=character;hull.Parent=character
local floor={Anchored=true,CanCollide=true,Shape='Block',Size=Vector3.new(10000,10,10000),CFrame=CFrame.new(Vector3.new(0,-5,0))}
function floor:IsA(n) return n=='BasePart' or n=='Part' end
function floor:GetFullName() return 'Map.Floor' end
function floor:GetAttribute() return nil end
local clientMap={}
function clientMap:GetAttribute(n) if n=='KZStudsPerCSUnit' then return 1 end end
function clientMap:GetPivot() return CFrame.new() end
function clientMap:GetDescendants() return {floor} end
local workspace={Gravity=800,CurrentCamera={CFrame=CFrame.new()}}
function workspace:FindFirstChild(n) if n:sub(1,10)=='KZ_Variety' then return clientMap end end
local ReplicatedStorage={WaitForChild=function() return shared end}
local services={Players={LocalPlayer=player},UserInputService=UIS,RunService=RunService,ReplicatedStorage=ReplicatedStorage}
local game={GetService=function(_,n) return assert(services[n],n) end}
local Enum={KeyCode=setmetatable({}, {__index=function(_,n) return n end}),ActuatorRelativeTo={World='World'},PartType={Block='Block'},UserInputType={MouseWheel='MouseWheel'}}
local Instance={new=function() return {Destroy=function(self) self.destroyed=true end} end}
local task={spawn=function(fn,...) fn(...) end,wait=function() end}
local script={Destroying=signal(),Parent={FindFirstChild=function(_,n) if n=='KZBrushFallback' and not fallback.destroyed then return fallback end end}}
