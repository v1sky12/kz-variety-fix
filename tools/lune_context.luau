-- Offline tooling only: real Roblox datatypes/Instances, not engine services.
local fs=require('@lune/fs')
local roblox=require('@lune/roblox')
local luau=require('@lune/luau')
local serde=require('@lune/serde')
local Context={}
function Context.open(path)
    local game=roblox.deserializePlace(fs.readFile(path))
    roblox.implementMethod('Instance','WaitForChild',function(self,name)
        return assert(self:FindFirstChild(name),'Offline child missing: '..name)
    end)
    roblox.implementMethod('Model','GetPivot',function(self) return self.WorldPivotData or roblox.CFrame.identity end)
    local world=game:FindFirstChildOfClass('Workspace')
    local map=world:FindFirstChild('KZ_Variety_CS2_ROBLOX_V22')
    assert(map,'Active calibrated map missing')
    local shared=game:FindFirstChildOfClass('ReplicatedStorage'):FindFirstChild('KZClassic')
    local loaded={}
    local loadModule
    loadModule=function(target)
        if type(target)=='string' then target=shared:FindFirstChild(target) end
        assert(target and target:IsA('ModuleScript'),'ModuleScript missing')
        if loaded[target]~=nil then return loaded[target] end
        local environment={Vector3=roblox.Vector3,CFrame=roblox.CFrame,Enum=roblox.Enum,Color3=roblox.Color3,
            Instance=roblox.Instance,PhysicalProperties=roblox.PhysicalProperties,
            script=target,require=loadModule,game={GetService=function(_,service)
                assert(service=='HttpService','Offline service unavailable: '..service)
                return {JSONDecode=function(_,s) return serde.decode('json',s) end}
            end}}
        local source=fs.readFile('src/'..target.Name..'.luau')
        local result=luau.load(source,{debugName=target.Name,environment=environment})()
        loaded[target]=result
        return result
    end
    return {game=game,world=world,map=map,shared=shared,load=loadModule,roblox=roblox,
        fs=fs,serde=serde,luau=luau,unit=map:GetAttribute('KZStudsPerCSUnit')}
end
return Context
