-- Block mechanics only. Geometry, colour and obstacle shape do not select rules.
-- Pure per-player state: no Roblox services, character physics or map mutations.
local Controller={}
Controller.Types={Normal=0,Reset=3,AntiBhop=4,Teleport=10,MultiBhop=11,SingleBhop=12,SequentialBhop=13}
local names={}
for name,kind in pairs(Controller.Types) do names[kind]=name end
local function duration(value,fallback)
    local n=tonumber(value)
    return n and n==n and n>=0 and n<math.huge and n or fallback
end
function Controller.isBhop(entity)
    local kind=type(entity)=='table' and entity.triggerType or entity
    return kind==11 or kind==12 or kind==13
end
function Controller.describe(entity)
    local p=entity.properties or {}
    local kind=entity.triggerType or tonumber(p.timer_trigger_type) or 0
    if entity.class=='trigger_teleport' and kind==0 then kind=10 end
    local name=names[kind]
    if not name then return nil end
    return {id=entity.id,type=name,kind=kind,
        delay=duration(p.timer_teleport_delay,Controller.isBhop(kind) and .1 or 0),
        antiBhop=duration(p.timer_anti_bhop_time,.2),
        destination=p.timer_teleport_destination or p.target,
        toCheckpoint=p.kz_return_to_checkpoint=='1',resetSpeed=p.timer_teleport_reset_speed~='0'}
end
-- Explicit Roblox authoring adapter. The caller supplies Source-space bounds;
-- no colour, mesh shape, part name or visual dimensions imply a mechanic.
function Controller.fromAttributes(attributes)
    local name=attributes.KZBlockType
    if name==nil then return nil end
    if name=='NormalBlock' then name='Normal' end
    local kind=Controller.Types[name]
    if kind==nil then return nil,'Unknown KZBlockType: '..tostring(name) end
    local id=attributes.KZBlockId
    if type(id)~='string' or id=='' then return nil,'KZBlockId must be a nonempty unique string' end
    local p={timer_trigger_type=tostring(kind),startdisabled=attributes.KZDisabled==true and '1' or '0',
        timer_teleport_delay=tostring(duration(attributes.KZBlockDelay,Controller.isBhop(kind) and .1 or 0)),
        timer_anti_bhop_time=tostring(duration(attributes.KZAntiBhopTime,.2)),
        timer_teleport_reset_speed=attributes.KZResetSpeed==false and '0' or '1',
        kz_return_to_checkpoint=attributes.KZReturnToCheckpoint==true and '1' or '0'}
    local destination=attributes.KZDestination
    if destination~=nil and (type(destination)~='string' or destination=='') then return nil,'Invalid KZDestination' end
    p.timer_teleport_destination=destination
    if (kind==10 or Controller.isBhop(kind)) and not destination and p.kz_return_to_checkpoint~='1' then
        return nil,'Teleporting blocks require KZDestination or KZReturnToCheckpoint'
    end
    return {id='roblox_block_'..id,class='trigger_multiple',triggerType=kind,properties=p,connections={},blockType=name}
end
function Controller.jumpPolicy(entity)
    local d=Controller.describe(entity)
    if not d or d.type~='AntiBhop' then return 0,false end
    return d.antiBhop,d.antiBhop==0
end
function Controller.onEnter(s,entity)
    local d=Controller.describe(entity)
    if d and d.type=='Reset' then Controller.reset(s) end
end
function Controller.shouldTeleport(s,entity,time,onGround,since)
    local d=Controller.describe(entity)
    if not d then return false end
    if Controller.isBhop(d.kind) then return onGround and Controller.land(s,d.id,d.kind,time,d.delay) or false end
    return d.type=='Teleport' and since~=nil and time-since+1e-9>=d.delay
end
function Controller.resolveDestination(entity,checkpoints,index,byName)
    local d=Controller.describe(entity)
    if not d then return nil,false end
    if d.toCheckpoint then
        local cp=checkpoints and checkpoints[index]
        if cp then return {origin=cp.source,angles=cp.angles,crouched=cp.crouched},true end
    end
    return d.destination and byName[d.destination] or nil,false
end
function Controller.clearContacts(s)
    s.bhopContacts={};s.bhopContact=nil;s.bhopSince=nil
end
function Controller.reset(s)
    s.lastSingle=nil;s.bhopVisited={};s.bhopIgnoreUntil=0
    s.bhopAwaitDepartureUntil=nil;s.bhopServerTakeoff=nil
    Controller.clearContacts(s)
end
function Controller.retainContacts(s,touched)
    for id in pairs(s.bhopContacts or {}) do
        if not touched[id] then s.bhopContacts[id]=nil end
    end
end
function Controller.land(s,id,kind,time,delay)
    if time<(s.bhopIgnoreUntil or 0) then return false end
    s.bhopContacts=s.bhopContacts or {}
    local since=s.bhopContacts[id]
    if not since then since=time;s.bhopContacts[id]=since end
    s.bhopContact=id;s.bhopSince=since
    if kind==12 and s.lastSingle==id then return true end
    if kind==13 and (s.bhopVisited or {})[id] then return true end
    -- Every overlapping trigger keeps its own contact clock. CKZ uses the
    -- map delay, including values below .08, and a strict elapsed > delay.
    return time-since>math.max(0,delay or .1)
end
function Controller.takeoff(s,id,kind,time)
    if kind==12 and s.lastSingle==id then return true end
    if kind==13 and (s.bhopVisited or {})[id] then return true end
    if kind==11 then s.lastSingle=id
    elseif kind==12 then s.lastSingle=id
    elseif kind==13 then
        s.lastSingle=id;s.bhopVisited=s.bhopVisited or {};s.bhopVisited[id]=true
    else Controller.reset(s) end
    Controller.clearContacts(s);s.bhopIgnoreUntil=time+.08
    return false
end
return Controller
