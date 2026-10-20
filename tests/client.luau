Data.zones={}
local passed,failed=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed+=1;print('PASS '..name) else failed+=1;print('FAIL '..name..': '..tostring(err)) end
end
local function near(a,b) assert(math.abs(a-b)<1e-5,tostring(a)..' ~= '..tostring(b)) end
local function last(kind)
    for i=#sent,1,-1 do if sent[i].kind==kind then return sent[i] end end
end
player.Character=character
client.setup(character)
test('brush setup takes ownership and compiles actual floor brush',function()
    assert(client.session() and not humanoid.EvaluateStateMachine)
    assert(player:GetAttribute('KZClassicMotorActive'));assert(fallback.destroyed)
end)
test('Warp-before-attribute applies exact short teleport and keeps speed',function()
    local s=client.session();s.motor.v=Vector3.new(400,0,0)
    Net.OnClientEvent:Fire('Warp',1,nil,false,Vector3.zero,CFrame.new(Vector3.new(1,36.001,0)))
    near(s.motor:feet().X,1);near(s.motor.v.X,400)
    RunService.PostSimulation:Fire(0);near(s.motor.v.X,400);near(s.serial,1)
end)
test('attribute-before-Warp preserves original speed exactly once',function()
    local s=client.session();player:SetAttribute('KZTeleportSerial',2)
    RunService.PostSimulation:Fire(0);near(s.motor.v.X,0)
    Net.OnClientEvent:Fire('Warp',2,nil,false,Vector3.zero,CFrame.new(Vector3.new(2,36.001,0)))
    near(s.motor.v.X,400);near(s.motor:feet().X,2)
    Net.OnClientEvent:Fire('Warp',2,nil,true,Vector3.zero,CFrame.new(Vector3.new(99,36.001,0)))
    near(s.motor:feet().X,2)
end)
test('absolute vertical push wins over additive push in same tick',function()
    local s=client.session();s.motor.v=Vector3.zero
    Net.OnClientEvent:Fire('Push',Vector3.new(0,500,0),{false,true,false},2,{false,false,true})
    Net.OnClientEvent:Fire('Push',Vector3.new(0,100,0),{false,false,false},2)
    RunService.PostSimulation:Fire(1/128);near(s.motor.v.Y,500-800/128)
end)
test('client publishes real virtual velocity with ordered motion id',function()
    local s=client.session();s.nextMotion=0;RunService.PostSimulation:Fire(0)
    local event=last('Motion');assert(event.args[1].character==character)
    near(event.args[1].teleportSerial,2);near(event.args[1].velocity.Y,s.motor.v.Y)
end)
test('client synchronizes ladder attachment for bhop state reset',function()
    local s=client.session();local saved=Data.ladderSurfaces
    Data.ladderSurfaces={{id=1,axis=1,bounds={{0,-32,0},{1,32,200}}}}
    s.motor.p=Vector3.new(0,36.001,0);s.motor.v=Vector3.zero;root.CFrame=CFrame.new(s.motor.p)
    keys.W=true;RunService.PostSimulation:Fire(1/128);keys.W=false
    local event=last('LadderAttach');assert(event and event.args[1].id==1);assert(s.ladder)
    Data.ladderSurfaces=saved
end)
test('held Space detaches a ladder even when Space was already held on approach',function()
    local s=client.session();local saved=Data.ladderSurfaces
    local ladder={id=2,axis=1,bounds={{0,-500,0},{1,500,500}}}
    Data.ladderSurfaces={ladder};s.ladder=ladder;s.ladderUntil=0;s.jumpHeld=true
    s.motor.p=Vector3.new(0,136,0);s.motor.v=Vector3.zero
    local takeoff,takeoffTime=s.motor:feet(),s.motor.time
    client.ladderStep(s,{jump=true,view=Vector3.new(0,0,-1),right=Vector3.new(1,0,0),axis=1,side=0},1/128,{})
    assert(s.ladder==nil and s.motor.flight and s.motor.flight.kind=='LAJ')
    near((s.motor.flight.start-takeoff).Magnitude,0);near(s.motor.flight.time,takeoffTime)
    near(s.motor.v.Magnitude,270);Data.ladderSurfaces=saved
end)
test('long horizontal ladder permits lateral travel without vertical drift',function()
    local s=client.session();local saved=Data.ladderSurfaces
    local ladder={id=3,axis=1,bounds={{0,-500,0},{1,500,500}}}
    Data.ladderSurfaces={ladder};s.ladder=ladder;s.ladderUntil=0
    s.motor.p=Vector3.new(0,136,0);s.motor.v=Vector3.zero
    for _=1,100 do client.ladderStep(s,{view=Vector3.new(0,0,-1),right=Vector3.new(1,0,0),axis=0,side=1},1/128,{}) end
    near(s.motor.p.X,200*100/128);near(s.motor.p.Y,136);assert(s.ladder==ladder)
    Data.ladderSurfaces=saved
end)
test('ladder crouch changes the swept hull and uses the actual forced posture speed',function()
    local s=client.session();local saved=Data.ladderSurfaces
    local ladder={id=4,axis=1,bounds={{0,-500,0},{1,500,500}}}
    Data.ladderSurfaces={ladder};s.ladder=ladder;s.ladderUntil=0
    s.motor.p=Vector3.new(0,136,0);s.motor.height=72;s.motor.duck=false;s.motor.grounded=false
    local movement={view=Vector3.new(0,0,-1),right=Vector3.new(1,0,0),axis=0,side=1,duck=true}
    client.ladderStep(s,movement,1/128,{})
    assert(s.motor.duck and s.motor.height==54);near(s.motor.v.X,68)
    movement.duck=false;client.ladderStep(s,movement,1/128,{forceDuck=true})
    assert(s.motor.duck and s.motor.height==54);near(s.motor.v.X,68)
    client.ladderStep(s,movement,1/128,{forceUnduck=true})
    assert(not s.motor.duck and s.motor.height==72);near(s.motor.v.X,200)
    Data.ladderSurfaces=saved
end)
test('keyboard water input follows camera pitch while dry wish stays horizontal',function()
    local s=client.session();local frame=workspace.CurrentCamera.CFrame
    workspace.CurrentCamera.CFrame={LookVector=Vector3.new(.8,-.6,0)};keys.W=true
    local input=client.readInput(s)
    near(input.wish.Y,0);near(input.wish.Magnitude,1);near(input.swim.Y,-.6)
    keys.W=false;workspace.CurrentCamera.CFrame=frame
end)
test('warp clears the cached landing direction before the next jump',function()
    local s=client.session();s.motor.landingVelocity=Vector3.new(450,0,0)
    s.motor.water=true
    s.motor.baseVelocity=Vector3.new(95,0,0)
    Net.OnClientEvent:Fire('Warp',3,nil,true,Vector3.zero,CFrame.new(Vector3.new(0,36.001,0)))
    assert(s.motor.landingVelocity==nil and s.motor.landingSpeed==nil and not s.motor.water)
    near(s.motor.baseVelocity.Magnitude,0)
end)
test('brush motor ignores the compatibility conveyor impulse to avoid adding it twice',function()
    local s=client.session();s.pushes={}
    Net.OnClientEvent:Fire('Push',Vector3.new(95,0,0),{false,false,false},s.serial,nil,'LegacyConveyor')
    assert(#s.pushes==0)
end)
test('one second of movement produces the same fixed ticks at 30 60 144 and 240 FPS',function()
    local original=workspace.CurrentCamera.CFrame
    workspace.CurrentCamera.CFrame={LookVector=Vector3.new(0,0,-1)};keys.W=true
    local reference
    for _,fps in ipairs({30,60,144,240}) do
        root.CFrame=CFrame.new(Vector3.new(0,36.001,0));client.setup(character)
        for _=1,fps do RunService.PostSimulation:Fire(1/fps) end
        local s=client.session();near(s.motor.time,1)
        if reference then near((s.motor.p-reference).Magnitude,0) else reference=s.motor.p end
    end
    keys.W=false;workspace.CurrentCamera.CFrame=original
end)
test('character removal restores humanoid state and releases query resources',function()
    player.CharacterRemoving:Fire(character)
    assert(client.session()==nil);assert(humanoid.EvaluateStateMachine)
    assert(root:GetAttribute('KZMovementBuild')==nil and root:GetAttribute('KZMovementBackend')==nil)
end)
test('R6 starts at real feet and Space swims through an upper-body water contact',function()
    local savedFind=character.FindFirstChild
    character.FindFirstChild=function(_,name) if name=='Left Leg' then return {Size=Vector3.new(1,2,1)} end end
    humanoid.RigType='R6';humanoid.HipHeight=0;root.CFrame=CFrame.new(Vector3.new(0,3.001,0))
    client.setup(character)
    local s=assert(client.session(),'R6 setup falsely intersected the floor')
    near(s.standing,3);near(s.motor:feet().Y,.001)
    Data.zones={{id='headContact',class='func_water',bounds={{-100,-100,48},{100,100,168}},properties={}}}
    keys.Space=true
    for _=1,512 do RunService.PostSimulation:Fire(1/128) end
    keys.Space=false
    assert(client.session()==s and s.motor:feet().Y>130,'Space did not raise the R6 swimmer')
    assert(root:GetAttribute('KZWaterLevel')>0,'water hint telemetry was missing')
    Data.zones={};character.FindFirstChild=savedFind;humanoid.RigType=nil;humanoid.HipHeight=35
    root.CFrame=CFrame.new(Vector3.new(0,36.001,0));client.setup(character)
end)
test('fallback releases mutex before enabling saved motor',function()
    client.setup(character)
    client.fallback('forced test failure')
    assert(last('MotorReset').args[1].character==character)
    assert(not player:GetAttribute('KZClassicMotorActive'))
    assert(fallback.Disabled==false and script.Disabled==true)
    assert(root:GetAttribute('KZMovementBuild')==nil and root:GetAttribute('KZMovementBackend')=='KZClassicFallback')
    assert(player:GetAttribute('KZBrushFallbackReason')=='forced test failure')
end)
print(string.format('CLIENT RESULT %d passed, %d failed',passed,failed))
assert(failed==0,'client regressions failed')
