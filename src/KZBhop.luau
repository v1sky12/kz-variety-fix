-- 11 multibhop, 12 single bhop, 13 sequential bhop.
-- State belongs to one player; the map itself is never globally disabled.
local Bhop={}
function Bhop.clearContacts(s)
    s.bhopContacts={};s.bhopContact=nil;s.bhopSince=nil
end
function Bhop.reset(s)
    s.lastSingle=nil;s.bhopVisited={};s.bhopIgnoreUntil=0
    s.bhopAwaitDepartureUntil=nil;s.bhopServerTakeoff=nil
    Bhop.clearContacts(s)
end
function Bhop.retainContacts(s,touched)
    for id in pairs(s.bhopContacts or {}) do
        if not touched[id] then s.bhopContacts[id]=nil end
    end
end
function Bhop.land(s,id,kind,time,delay)
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
function Bhop.takeoff(s,id,kind,time)
    if kind==12 and s.lastSingle==id then return true end
    if kind==13 and (s.bhopVisited or {})[id] then return true end
    if kind==11 then s.lastSingle=id
    elseif kind==12 then s.lastSingle=id
    elseif kind==13 then
        s.lastSingle=id;s.bhopVisited=s.bhopVisited or {};s.bhopVisited[id]=true
    else Bhop.reset(s) end
    Bhop.clearContacts(s);s.bhopIgnoreUntil=time+.08
    return false
end
return Bhop
