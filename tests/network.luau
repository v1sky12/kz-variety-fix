Data.zones={}
local passed,failed=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed+=1;print('PASS '..name) else failed+=1;print('FAIL '..name..': '..tostring(err)) end
end
local function near(a,b) assert(math.abs(a-b)<1e-5,tostring(a)..' ~= '..tostring(b)) end
local p,r=makePlayer(1)
local p2,r2=makePlayer(2)
local s=server.states[p]
local function step(dt) serverClock+=dt;RunService.Heartbeat:Fire(dt) end
local function last(kind,player)
    for i=#sent,1,-1 do if sent[i].kind==kind and (not player or sent[i].player==player) then return sent[i] end end
end
test('server receives virtual horizontal speed when native velocity is zero',function()
    server.action(p,'Motion',{character=p.Character,teleportSerial=0,sequence=1,feet=Vector3.zero,velocity=Vector3.new(300,0,400)})
    step(.02);near(p:GetAttribute('KZServerSpeedUnits'),500);assert(p:GetAttribute('KZServerGrounded'))
end)
test('ascending player is not server-grounded by zero native velocity',function()
    step(.05)
    server.action(p,'Motion',{character=p.Character,teleportSerial=0,sequence=2,feet=Vector3.zero,velocity=Vector3.new(0,200,0)})
    step(.02);assert(not p:GetAttribute('KZServerGrounded'))
end)
test('reordered motion packet cannot rewind state',function()
    step(.05)
    server.action(p,'Motion',{character=p.Character,teleportSerial=0,sequence=1,feet=Vector3.zero,velocity=Vector3.zero})
    near(s.motion.velocity.Y,200)
end)
test('motion from obsolete character is rejected',function()
    step(.05)
    server.action(p,'Motion',{character={},teleportSerial=0,sequence=3,feet=Vector3.zero,velocity=Vector3.zero})
    near(s.motion.velocity.Y,200)
end)
test('stale motion expires instead of keeping stale HUD speed',function() step(.4);near(p:GetAttribute('KZServerSpeedUnits'),0) end)
test('server state and telemetry belong to each individual player',function()
    server.action(p2,'Motion',{character=p2.Character,teleportSerial=0,sequence=1,feet=Vector3.zero,velocity=Vector3.new(600,0,0)})
    step(.02);near(p2:GetAttribute('KZServerSpeedUnits'),600);near(p:GetAttribute('KZServerSpeedUnits'),0)
end)
test('Source absolute Z push sets Roblox vertical component',function()
    local e={id='up',properties={timer_push_condition_jump_event='1',timer_push_amount='0 0 500',timer_push_abs_speed_z='1'}}
    server.push(p,s,e,'jump_event')
    local event=last('Push',p);near(event.args[1].Y,500);assert(event.args[2][2]);assert(event.args[4][3])
end)
test('delayed push cancelled on teleport cannot fire later',function()
    local e={id='cancel',properties={timer_push_condition_start_touch='1',timer_push_delay='1',timer_push_cancel_on_teleport='1'}}
    server.push(p,s,e,'start_touch');assert(s.pushPendingById.cancel)
    server.moveTo(p,s,{0,0,0},nil,true,false);assert(not s.pushPendingById.cancel)
    near(#s.pushPending,0)
end)
test('uncancelled delayed push survives teleport with new serial',function()
    step(.1)
    local e={id='keep',properties={timer_push_condition_start_touch='1',timer_push_delay='1',timer_push_cancel_on_teleport='0',timer_push_amount='0 0 100'}}
    server.push(p,s,e,'start_touch');server.moveTo(p,s,{0,0,0},nil,true,false)
    near(#s.pushPending,1);near(s.pushPending[1].serial,s.teleportSerial)
    step(1.01);local event=last('Push',p);near(event.args[1].Y,100);near(event.args[3],s.teleportSerial);near(#s.pushPending,0)
end)
test('new attempt clears delayed pushes and cooldowns',function()
    server.push(p,s,{id='new',properties={timer_push_condition_touch='1',timer_push_delay='1'}},'touch')
    server.startRun(p,s);near(#s.pushPending,0);assert(next(s.pushTimes)==nil)
end)
test('Source I/O stays chronological after a delayed frame',function()
    local e={id='io',connections={
        {outputName='OnStartTouch',targetName='!activator',inputName='addattribute',overrideParam='filter',delay='0'},
        {outputName='OnStartTouch',targetName='!activator',inputName='removeattribute',overrideParam='filter',delay='.1'},
    }}
    server.outputs(p,s,e,'OnStartTouch');step(.3);assert(s.attributes.filter==nil)
end)
test('state snapshots publish changed per-player zone state',function()
    server.applyOutput(p,s,{targetName='!activator',inputName='addattribute',overrideParam='test'})
    step(.02);local event=last('ZoneState',p);assert(event.args[1].attributes.test==1)
    assert(not server.states[p2].attributes.test)
end)
test('warp carries authoritative destination and preserves CP yaw',function()
    step(.1);r.CFrame=CFrame.new(Vector3.new(0,36,0),.8)
    local before=r.CFrame.LookVector
    server.moveTo(p,s,{10,20,30},nil,true,false)
    local event=last('Warp',p);assert(typeof(event.args[5])=='CFrame')
    near((event.args[5].Position-r.Position).Magnitude,0);near((before-r.CFrame.LookVector).Magnitude,0)
end)
test('thin teleport trigger cannot be skipped between server frames',function()
    step(.1)
    Data.byName.sweptDestination={origin={200,0,0},angles={0,0,0}}
    local e={id='thin',class='trigger_teleport',triggerType=0,bounds={{-1,-20,-1},{1,20,1}},properties={target='sweptDestination'}}
    Data.zones={e};s.previousFeet=nil
    r.CFrame=CFrame.new(Data.worldPoint(serverMap,{-100,0,0})+Vector3.new(0,36,0));step(.02)
    local serial=s.teleportSerial
    r.CFrame=CFrame.new(Data.worldPoint(serverMap,{100,0,0})+Vector3.new(0,36,0));step(.02)
    near(s.teleportSerial,serial+1);near(Data.feetSource(serverMap,r,{HipHeight=35}).X,200)
    Data.zones={}
end)
test('passing delayed zone briefly does not satisfy full delay',function()
    step(.1)
    local e={id='delayedThin',class='trigger_multiple',triggerType=10,bounds={{-1,-20,-1},{1,20,1}},
        properties={timer_teleport_destination='sweptDestination',timer_teleport_delay='.5'}}
    Data.zones={e};s.previousFeet=nil
    r.CFrame=CFrame.new(Data.worldPoint(serverMap,{-100,0,0})+Vector3.new(0,36,0));step(.02)
    local serial=s.teleportSerial
    r.CFrame=CFrame.new(Data.worldPoint(serverMap,{100,0,0})+Vector3.new(0,36,0));step(.02)
    near(s.teleportSerial,serial);assert(s.touches.delayedThin==nil);assert(not s.inside.delayedThin)
    Data.zones={}
end)
test('overdue delayed absolute pushes are sent in chronological order',function()
    server.push(p,s,{id='firstDelayed',properties={timer_push_condition_touch='1',timer_push_delay='.1',timer_push_amount='100 0 0',timer_push_abs_speed_x='1'}},'touch')
    server.push(p,s,{id='secondDelayed',properties={timer_push_condition_touch='1',timer_push_delay='.2',timer_push_amount='200 0 0',timer_push_abs_speed_x='1'}},'touch')
    step(.3);near(last('Push',p).args[1].Z,-200)
end)
test('fallback resets motion/jump numbering while retaining single-bhop rules',function()
    s.lastSingle='block';s.lastClientJumpId=50;s.motion={received=serverClock,velocity=Vector3.new(10,0,0)}
    server.action(p,'MotorReset',{character=p.Character,teleportSerial=s.teleportSerial})
    assert(s.motion==nil and s.lastClientJumpId==nil);assert(s.lastSingle=='block')
end)
print(string.format('NETWORK RESULT %d passed, %d failed',passed,failed))
assert(failed==0,'network regressions failed')
