local passed,failed=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed+=1;print('PASS '..name) else failed+=1;print('FAIL '..name..': '..tostring(err)) end
end
local function entity(id,kind,delay)
    return {id=id,triggerType=kind,class='trigger_multiple',properties={timer_teleport_delay=tostring(delay or .1)}}
end
test('compatibility KZBhop resolves the same controller instance',function() assert(Bhop==Blocks) end)
test('normal block leaves movement and block state untouched on entry',function()
    local s={lastSingle='single',velocity=Vector3.new(700,0,0)}
    Blocks.onEnter(s,entity('normal',0))
    assert(s.lastSingle=='single' and s.velocity.X==700)
    assert(not Blocks.shouldTeleport(s,entity('normal',0),10,true,0))
end)
test('single permits first takeoff and rejects immediate reuse',function()
    local s={};Blocks.reset(s);local e=entity('single',12)
    assert(not Blocks.shouldTeleport(s,e,1,true,1))
    assert(not Blocks.takeoff(s,e.id,e.triggerType,1.01))
    assert(Blocks.shouldTeleport(s,e,2,true,2))
end)
test('multi allows repeated timely jumps and rejects standing too long',function()
    local s={};Blocks.reset(s);local e=entity('multi',11,.125)
    for time=1,5 do
        assert(not Blocks.shouldTeleport(s,e,time,true,time))
        assert(not Blocks.shouldTeleport(s,e,time+.125,true,time))
        assert(not Blocks.takeoff(s,e.id,e.triggerType,time+.125))
    end
    assert(not Blocks.shouldTeleport(s,e,6,true,6))
    assert(Blocks.shouldTeleport(s,e,6.126,true,6))
end)
test('single tracks the last bhop trigger while sequential keeps the whole chain',function()
    local s={};Blocks.reset(s);Blocks.takeoff(s,'single',12,1);Blocks.takeoff(s,'multi',11,2)
    assert(not Blocks.shouldTeleport(s,entity('single',12),3,true,3))
    Blocks.takeoff(s,'seq',13,4);Blocks.takeoff(s,'multi',11,5)
    assert(Blocks.shouldTeleport(s,entity('seq',13),6,true,6))
end)
test('sequential rejects A-B-A until reset',function()
    local s={};Blocks.reset(s)
    assert(not Blocks.takeoff(s,'a',13,1));assert(not Blocks.takeoff(s,'b',13,2))
    assert(Blocks.shouldTeleport(s,entity('a',13),3,true,3))
    Blocks.onEnter(s,entity('reset',3))
    assert(not Blocks.shouldTeleport(s,entity('a',13),4,true,4))
end)
test('airborne overlap does not consume a bhop block',function()
    local s={};Blocks.reset(s)
    assert(not Blocks.shouldTeleport(s,entity('single',12),100,false,0))
    assert(next(s.bhopContacts)==nil and s.lastSingle==nil)
end)
test('two players have independent used-block state',function()
    local a,b={},{};Blocks.reset(a);Blocks.reset(b);Blocks.takeoff(a,'single',12,1)
    assert(Blocks.shouldTeleport(a,entity('single',12),2,true,2))
    assert(not Blocks.shouldTeleport(b,entity('single',12),2,true,2))
end)
test('reset clears all per-sequence state and contact clocks',function()
    local s={};Blocks.reset(s);Blocks.takeoff(s,'single',12,1);Blocks.takeoff(s,'seq',13,2)
    Blocks.land(s,'multi',11,3,.1);s.bhopAwaitDepartureUntil=9;s.bhopServerTakeoff={}
    Blocks.onEnter(s,entity('reset',3))
    assert(s.lastSingle==nil and next(s.bhopVisited)==nil and next(s.bhopContacts)==nil)
    assert(s.bhopAwaitDepartureUntil==nil and s.bhopServerTakeoff==nil and s.bhopIgnoreUntil==0)
end)
test('anti-bhop uses a wait time or a full jump ban at zero',function()
    local e=entity('anti',4);e.properties.timer_anti_bhop_time='.2'
    local delay,disabled=Blocks.jumpPolicy(e);assert(delay==.2 and not disabled)
    e.properties.timer_anti_bhop_time='0';delay,disabled=Blocks.jumpPolicy(e);assert(delay==0 and disabled)
end)
test('anti-bhop shared definition reaches existing motor modifiers',function()
    local saved=Data.zones
    Data.zones={entity('anti',4)};Data.zones[1].properties.timer_anti_bhop_time='0'
    Data.zones[1].bounds={{-100,-100,-100},{100,100,100}}
    local mods=Data.modifiers(nil,Vector3.zero,72,{})
    Data.zones=saved;assert(mods.disableJump and mods.antiBhop==0)
end)
test('teleport waits until its configured contact deadline',function()
    local s={};local e=entity('tp',10,.5)
    assert(not Blocks.shouldTeleport(s,e,1.499,false,1))
    assert(Blocks.shouldTeleport(s,e,1.5,false,1))
    assert(not Blocks.shouldTeleport(s,e,100,false,nil))
end)
test('legacy named teleport resolves its explicit destination',function()
    local e=entity('tp',10);e.properties.timer_teleport_destination='dest'
    local target={origin={1,2,3}};local resolved,cp=Blocks.resolveDestination(e,{},0,{dest=target})
    assert(resolved==target and not cp)
end)
test('checkpoint teleport restores checkpoint pose and can use named fallback',function()
    local e=entity('tp',10);e.properties.kz_return_to_checkpoint='1';e.properties.timer_teleport_destination='fallback'
    local cp={source={1,2,3},angles={4,5,6},crouched=true}
    local result,practice=Blocks.resolveDestination(e,{cp},1,{})
    assert(practice and result.origin==cp.source and result.angles==cp.angles and result.crouched)
    local fallback={origin={7,8,9}};result,practice=Blocks.resolveDestination(e,{},0,{fallback=fallback})
    assert(result==fallback and not practice)
end)
test('missing teleport destination does not invent a warp',function()
    local e=entity('tp',10);e.properties.kz_return_to_checkpoint='1'
    assert(Blocks.resolveDestination(e,{},0,{})==nil)
end)
test('visual colour shape and obstacle category never assign mechanics',function()
    assert(Blocks.fromAttributes({Color='orange',Name='Single',KZObstacleType='SurfRamp'})==nil)
end)
test('explicit attributes support every requested mechanic',function()
    for name,kind in pairs(Blocks.Types) do
        local e,err=Blocks.fromAttributes({KZBlockType=name,KZBlockId=name,KZReturnToCheckpoint=true})
        assert(e and not err);assert(e.triggerType==kind and Blocks.describe(e).type==name)
    end
end)
test('bad configuration is rejected or given a finite default',function()
    local e,err=Blocks.fromAttributes({KZBlockType='SurfRamp',KZBlockId='x'});assert(not e and err)
    e,err=Blocks.fromAttributes({KZBlockType='SingleBhop',KZBlockId='x'});assert(not e and err)
    e,err=Blocks.fromAttributes({KZBlockType='Normal'});assert(not e and err)
    e=Blocks.fromAttributes({KZBlockType='MultiBhop',KZBlockId='x',KZReturnToCheckpoint=true,KZBlockDelay=math.huge})
    assert(Blocks.describe(e).delay==.1)
end)
test('imported block inventory retains original IDs and declared types',function()
    local counts={};local mappingTeleports=0
    for _,e in ipairs(Data.zones) do
        local d=Blocks.describe(e)
        if d then assert(d.id==e.id);counts[d.type]=(counts[d.type] or 0)+1 end
        if e.triggerType==10 then mappingTeleports+=1 end
    end
    assert(counts.SingleBhop==9 and counts.MultiBhop==8 and mappingTeleports==12)
    assert(not counts.SequentialBhop)
end)
local function part(attrs)
    return {IsA=function(_,kind) return kind=='BasePart' end,GetAttribute=function(_,name) return attrs[name] end,
        GetAttributes=function() return attrs end,GetFullName=function() return 'Test.Block' end}
end
local function customMap(parts) return {GetDescendants=function() return parts end} end
local function attrs(id,kind)
    return {KZBlockType=kind or 'SingleBhop',KZBlockId=id,KZReturnToCheckpoint=true,
        KZSourceBoundsMin=Vector3.new(0,0,0),KZSourceBoundsMax=Vector3.new(32,32,8)}
end
test('custom zones register only explicit Source bounds and register once',function()
    local saved=Data.zones;Data.zones={}
    local p=part(attrs('one'));local map=customMap({p,part({Color='orange'})})
    Data.addBlockZones(map);Data.addBlockZones(map)
    assert(#Data.zones==1 and Data.zones[1].id=='roblox_block_one')
    assert(Data.zones[1].bounds[2][3]==8 and p.Size==nil and p.CFrame==nil)
    Data.zones=saved
end)
test('duplicate custom IDs reject both zones rather than silently sharing state',function()
    local saved=Data.zones;Data.zones={}
    Data.addBlockZones(customMap({part(attrs('same')),part(attrs('same','MultiBhop'))}))
    assert(#Data.zones==0);Data.zones=saved
end)
test('invalid bounds do not infer a zone from platform dimensions',function()
    local saved=Data.zones;Data.zones={};local a=attrs('bad');a.KZSourceBoundsMin=Vector3.new(100,0,0)
    Data.addBlockZones(customMap({part(a)}));assert(#Data.zones==0);Data.zones=saved
end)
print(string.format('BLOCK RESULT %d passed, %d failed',passed,failed))
assert(failed==0,'block controller regressions failed')
