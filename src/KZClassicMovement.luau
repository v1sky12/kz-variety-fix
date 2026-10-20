-- Experimental replacement for the saved KZClassic client motor. Existing camera/HUD/CP remain.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
if player:GetAttribute("KZClassicMotorActive") then warn("KZ Classic duplicate motor"); return end
player:SetAttribute("KZClassicMotorActive", true)
local shared=game:GetService('ReplicatedStorage'):WaitForChild('KZClassic')
local B=require(shared:WaitForChild('KZBrushCollision'))
local Motor=require(shared:WaitForChild('KZBrushMotor'))
local Core=require(shared:WaitForChild('KZClassicCore'))
local Data=require(shared:WaitForChild('KZMapData'))
local Net=shared:WaitForChild('Action')
local released=false
local connections={};local generation=0;local session;local focused=true;local queued=-math.huge
local function connect(event,f) local c=event:Connect(f);connections[#connections+1]=c;return c end
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function restore()
    local s=session;session=nil
    if not s then return end
    if s.world and s.world.destroy then s.world:destroy() end
    if s.force then s.force:Destroy() end
    if s.attachment then s.attachment:Destroy() end
    if s.h.Parent then
        s.h.EvaluateStateMachine=s.evaluate;s.h.AutoRotate=s.rotate;s.h.WalkSpeed=s.walk
    end
    for part,value in pairs(s.parts) do if part.Parent then part.CanCollide=value end end
    if s.partConnection then s.partConnection:Disconnect() end
    if s.r.Parent then
        for _,name in ipairs({'KZMovementBackend','KZMovementBuild','KZBrushCount','KZBrushMeshQueryCount',
            'KZSurfing','KZSurfNormal','KZSurfPart','KZMapSlide','KZGroundCorrections','KZSeamRecoveries',
            'KZConveyorSpeedUnits','KZVirtualHullHeightUnits','KZBoundSourceZoneCount','KZMovementProfile','KZLadderId',
            'KZWaterLevel','KZWaterExiting'}) do
            s.r:SetAttribute(name,nil)
        end
    end
end
local function fallback(reason)
    local previous=session
    if previous then
        local serial=player:GetAttribute('KZTeleportSerial')
        if type(previous.serial)=='number' and (type(serial)~='number' or previous.serial>serial) then serial=previous.serial end
        Net:FireServer('MotorReset',{character=previous.character,teleportSerial=serial})
    end
    generation=generation+1
    restore()
    for _,c in ipairs(connections) do c:Disconnect() end
    warn('[KZ Brush] '..tostring(reason)..'; returning to saved KZClassic motor')
    player:SetAttribute('KZBrushFallbackReason',tostring(reason))
    if previous and previous.r.Parent then previous.r:SetAttribute('KZMovementBackend','KZClassicFallback') end
    local old=script.Parent:FindFirstChild('KZBrushFallback')
    if not old then
        local template=shared:FindFirstChild('KZBrushFallbackSource')
        if template then old=template:Clone();old.Disabled=true;old.Name='KZBrushFallback';old.Parent=script.Parent end
    end
    released=true;player:SetAttribute("KZClassicMotorActive",nil)
    if old then old.Disabled=false end
    script.Disabled=true
end
local function setup(character)
    generation=generation+1;local id=generation;restore()
    local h=character:WaitForChild('Humanoid',15);local r=character:WaitForChild('HumanoidRootPart',15)
    local hull=character:WaitForChild('KZSourceHull',15)
    if id~=generation then return end
    if not h or not r or not hull then fallback('Character/Source hull missing');return end
    local map=Data.findMap(workspace)
    if not map then fallback('Active calibrated map missing');return end
    local unit=Data.unitFor(map);local brushes,meshes={},{};local count=0
    Data.addPracticeZones(map)
    Data.addBlockZones(map)
    local boundZones=0
    for _ in pairs(Data.blockBindings[map] or {}) do boundZones+=1 end
    -- Build before changing character physics. Visual mesh bounds are never used.
    local ok,err=pcall(function()
        for _,part in ipairs(map:GetDescendants()) do
            if part:IsA('BasePart') and part.CanCollide then
                assert(part.Anchored,'Dynamic collider unsupported: '..part:GetFullName())
                if part:IsA('MeshPart') or part:IsA('PartOperation')
                    or (part:IsA('Part') and part.Shape~=Enum.PartType.Block) then meshes[#meshes+1]=part
                else local b,why=B.fromPart(part);assert(b,why);brushes[#brushes+1]=b end
                count=count+1
                if count%200==0 then task.wait();assert(id==generation,'Character changed during compile') end
            end
        end
        assert(count>0,'No supported map colliders')
    end)
    if not ok then if id==generation then fallback(err) end;return end
    if id~=generation or player.Character~=character then return end
    local world
    local standing=h.HipHeight+r.Size.Y/2
    local center=r.Position+Vector3.new(0,36*unit-standing,0)
    local ready,why=pcall(function()
        world=B.world(brushes,nil,workspace,meshes,hull.CollisionGroup)
        assert(not world:trace(center,Vector3.zero,Vector3.new(16,36,16)*unit).startSolid,'Spawn hull intersects geometry')
    end)
    if not ready then if world then world:destroy() end;fallback(why);return end
    local old=script.Parent:FindFirstChild('KZBrushFallback')
    if old then old:Destroy() end
    local s={character=character,h=h,r=r,map=map,unit=unit,standing=standing,world=world,
        motor=Motor.new(world,Core,center,unit),parts={},evaluate=h.EvaluateStateMachine,
        rotate=h.AutoRotate,walk=h.WalkSpeed,accumulator=0,serial=player:GetAttribute('KZTeleportSerial'),
        lastResult=0,lastForward=Vector3.new(0,0,-1),ladderUntil=0,
        pushes={},mapState={},motionSequence=0,nextMotion=0,nextLadder=0,clientJumpId=0}
    session=s
    local function partAdded(part)
        if part:IsA('BasePart') then s.parts[part]=part.CanCollide;part.CanCollide=false end
    end
    for _,part in ipairs(character:GetDescendants()) do partAdded(part) end
    s.partConnection=character.DescendantAdded:Connect(partAdded)
    h.EvaluateStateMachine=false;h.AutoRotate=false;h.WalkSpeed=0;h.Jump=false
    local attachment=Instance.new('Attachment');attachment.Name='KZBrushGravityAttachment';attachment.Parent=r
    local force=Instance.new('VectorForce');force.Name='KZBrushGravityCancel';force.Attachment0=attachment
    force.RelativeTo=Enum.ActuatorRelativeTo.World;force.ApplyAtCenterOfMass=true;force.Parent=r
    s.force=force;s.attachment=attachment
    r:SetAttribute('KZBrushCount',#brushes);r:SetAttribute('KZBrushMeshQueryCount',#meshes)
    r:SetAttribute('KZBoundSourceZoneCount',boundZones);r:SetAttribute('KZMovementProfile','CKZAdapted')
    player:SetAttribute('KZBrushFallbackReason',nil)
    r:SetAttribute('KZMovementBackend',#meshes>0 and 'BrushSweepMeshQueriesExperimental' or 'BrushSweepExperimental')
    print('[KZ Brush] compiled '..#brushes..' primitive brushes + '..#meshes..' MeshPart geometry queries; fixed 128 Hz; Studio playtest required')
end
local function readInput(s)
    local function key(name) return focused and not UIS:GetFocusedTextBox() and UIS:IsKeyDown(Enum.KeyCode[name]) end
    local camera=workspace.CurrentCamera
    local forward=camera and flat(camera.CFrame.LookVector) or s.lastForward
    local previousForward=s.lastForward
    if forward.Magnitude>.001 then s.lastForward=forward.Unit end
    local turn=previousForward.X*s.lastForward.Z-previousForward.Z*s.lastForward.X
    turn=math.abs(turn)>1e-7 and (turn>0 and 1 or -1) or 0
    forward=s.lastForward;local right=Vector3.new(-forward.Z,0,forward.X)
    local side=(key('D') and 1 or 0)-(key('A') and 1 or 0)
    local axis=(key('W') and 1 or 0)-(key('S') and 1 or 0)
    local wish=forward*axis+right*side
    local view=camera and camera.CFrame.LookVector or forward
    local swim=view*axis+right*side
    return {wish=wish.Magnitude>.001 and wish.Unit or Vector3.zero,side=side,turn=turn,
        swim=swim.Magnitude>.001 and swim.Unit or Vector3.zero,
        jump=key('Space') or (focused and not UIS:GetFocusedTextBox() and os.clock()<=queued),
        duck=key('LeftControl') or key('RightControl'),walk=key('LeftShift'),axis=axis,
        view=view,right=right,held=key('Space')}
end
local function resetWarp(s,velocity,reason)
    local m=s.motor
    m.p=s.r.Position+Vector3.new(0,m.height/2*s.unit-s.standing,0)
    m.v=velocity or Vector3.zero;m.flight=nil;m.dropY=nil;m.weirdAt=nil;m.lastValid=false;m.lastKind=nil
    m.waterJumpUntil=nil;m.waterJumpVelocity=nil;m.baseVelocity=Vector3.zero;m.pre=Core.newPre();m.lastLand=-math.huge;m.grounded=false;m.landingSpeed=nil;m.landingVelocity=nil;m.water=false
    m.surfNormal=nil;m.surfPart=nil;m.groundNormal=nil;m.contactPlanes=nil;m.groundAge=math.huge;s.pushes={}
    s.resetCount=(s.resetCount or 0)+1
    s.r:SetAttribute('KZBrushResetCount',s.resetCount)
    s.r:SetAttribute('KZBrushLastResetReason',reason or 'StateReset')
    s.accumulator=0;s.ladder=nil;s.serial=player:GetAttribute('KZTeleportSerial');queued=-math.huge
end
local function ladderStep(s,input,dt,zone)
    local m=s.motor
    m:posture(not zone.forceUnduck and (zone.forceDuck or input.duck==true))
    local feet=Data.sourcePoint(s.map,m:feet())
    m.water=zone.water==true
    local ladder,normal=Data.findLadder(feet,m.height,s.ladder)
    local previous=s.ladder
    if zone.water or m.time<s.ladderUntil then ladder=nil end
    if ladder then
        normal=Data.worldVector(s.map,{normal.X,normal.Y,0}).Unit
        local motion=input.view*input.axis+input.right*input.side
        local into=-flat(motion):Dot(normal)
        local attached=previous==ladder
        if attached and input.jump then
            local takeoff,takeoffTime=m:feet(),m.time
            s.ladder=nil;s.ladderUntil=m.time+.25;m.v=normal*Core.Profile.LadderJump*s.unit;queued=-math.huge
            m.time=m.time+dt
            m.p,m.v=s.world:slide(m.p,m.v,m:half(),dt)
            m:categorize()
            local a,b=ladder.bounds[1],ladder.bounds[2]
            local y=Data.worldPoint(s.map,{(a[1]+b[1])/2,(a[2]+b[2])/2,b[3]}).Y
            if not m.grounded then m:begin('LAJ',y);m.flight.start=takeoff;m.flight.time=takeoffTime end
            return true,true
        elseif attached or into>.15 then
            s.ladder=ladder;m:invalidate('Ladder');m.flight=nil;m.grounded=false;m.waterJumpUntil=nil;m.waterJumpVelocity=nil;m.surfNormal=nil;m.surfPart=nil
            m.contactPlanes=nil;m.groundNormal=nil;m.landingVelocity=nil;m.landingSpeed=nil
            m.baseVelocity=Vector3.zero
            m.time=m.time+dt;m.v=Core.ladderVelocity(motion*(m.duck and Core.Profile.LadderDuckSpeed or Core.Profile.LadderSpeed),normal)*s.unit
            local top=ladder.bounds[2][3]
            if m.v.Y>0 and feet.Z+m.v.Y/s.unit*dt>=top-.5 then
                local rise=math.max(0,top+1-feet.Z)*s.unit
                local up=s.world:trace(m.p,Vector3.new(0,rise,0),m:half())
                local across=up.fraction==1 and s.world:trace(up.position,-normal*32*s.unit,m:half())
                if into>.15 and across and not across.startSolid and across.fraction==1 then
                    s.ladder=nil;m.p=up.position;m.v=m.v-normal*200*s.unit
                else m.v=Vector3.new(m.v.X,math.max(-200*s.unit,math.min(m.v.Y,(top-.75-feet.Z)*s.unit/dt)),m.v.Z) end
            end
            m.p,m.v=s.world:slide(m.p,m.v,m:half(),dt)
            if not s.ladder then
                s.ladderUntil=m.time+.25
                local a,b=ladder.bounds[1],ladder.bounds[2]
                local y=Data.worldPoint(s.map,{(a[1]+b[1])/2,(a[2]+b[2])/2,b[3]}).Y
                m:categorize()
                if not m.grounded then m:begin('LAJ',y) end
            end
            return true
        else s.ladder=nil end
    else s.ladder=nil end
    if previous and not s.ladder then
        local a,b=previous.bounds[1],previous.bounds[2]
        local y=Data.worldPoint(s.map,{(a[1]+b[1])/2,(a[2]+b[2])/2,b[3]}).Y
        m:categorize()
        if not m.grounded then m:begin('LAJ',y) end
    end
    return false
end
local function telemetry(s)
    local m,r=s.motor,s.r
    r:SetAttribute('KZMovementBuild','2026-10-20-r2')
    r:SetAttribute('KZSeamRecoveries',m.recoveries or 0)
    r:SetAttribute('KZGroundCorrections',m.groundCorrections or 0)
    r:SetAttribute('KZSurfing',s.ladder==nil and m.surfNormal~=nil)
    r:SetAttribute('KZSurfNormal',s.ladder==nil and m.surfNormal or nil)
    r:SetAttribute('KZSurfPart',s.ladder==nil and m.surfPart and m.surfPart.Name or nil)
    r:SetAttribute('KZMapSlide',s.zoneSlide==true)
    r:SetAttribute('KZSpeedUnits',flat(m.v).Magnitude/s.unit)
    r:SetAttribute('KZInWater',m.water==true)
    r:SetAttribute('KZWaterLevel',s.zoneWaterLevel or 0)
    r:SetAttribute('KZWaterExiting',m.waterJumpUntil~=nil and m.time<m.waterJumpUntil)
    r:SetAttribute('KZWaterVerticalUnits',m.water and m.v.Y/s.unit or 0)
    r:SetAttribute('KZConveyorSpeedUnits',(m.baseVelocity or Vector3.zero).Magnitude/s.unit)
    r:SetAttribute('KZStudsPerCSUnit',s.unit);r:SetAttribute('KZMotorUnitsScale',s.unit)
    r:SetAttribute('KZHorizontalSpeedStuds',flat(m.v).Magnitude)
    if m.grounded then r:SetAttribute('KZPrestrafeUnits',flat(m.v).Magnitude/s.unit) end
    r:SetAttribute('KZPreGainUnits',Core.preGain(m.pre))
    r:SetAttribute('KZJumpCount',m.count);r:SetAttribute('KZOnLadder',s.ladder~=nil)
    r:SetAttribute('KZLadderId',s.ladder and s.ladder.id or nil)
    r:SetAttribute('KZVirtualHullHeightUnits',m.height)
    r:SetAttribute('KZSourcePosition',Data.sourcePoint(s.map,m:feet()))
    r:SetAttribute('KZGrounded',m.grounded);r:SetAttribute('KZOnGround',m.grounded);r:SetAttribute('KZLastTakeoffUnits',m.flight and m.flight.pre or r:GetAttribute('KZLastTakeoffUnits'))
    local f=m.result
    if f and f.serial~=s.lastResult then
        s.lastResult=f.serial
        r:SetAttribute('KZLastJumpType',f.kind);r:SetAttribute('KZLastJumpValid',f.valid)
        r:SetAttribute('KZLastJumpInvalidReason',f.reason);r:SetAttribute('KZLastJumpDistanceUnits',f.distance)
        r:SetAttribute('KZLastJumpPreUnits',f.pre);r:SetAttribute('KZLastJumpMaxUnits',f.max)
        r:SetAttribute('KZLastJumpStrafes',f.strafes);r:SetAttribute('KZLastJumpSync',f.sync)
        r:SetAttribute('KZLastJumpGainUnits',f.gain);r:SetAttribute('KZLastJumpLossUnits',f.loss)
        r:SetAttribute('KZLastJumpHeightStuds',f.peak);r:SetAttribute('KZLastJumpDuration',f.duration)
        r:SetAttribute('KZLastJumpSerial',f.serial)
    end
end
connect(UIS.WindowFocusReleased,function() focused=false;queued=-math.huge end)
connect(UIS.WindowFocused,function() focused=true end)
connect(UIS.InputChanged,function(input,processed)
    if not processed and input.UserInputType==Enum.UserInputType.MouseWheel and input.Position.Z~=0 then queued=os.clock()+.1 end
end)
connect(Net.OnClientEvent,function(kind,amount,set,serial,physicalVelocity,destination)
    local s=session;if not s then return end
    if kind=='Warp' then
        -- Warp payload: serial, angles, resetSpeed, old native velocity.
        -- Native velocity is zero for this CFrame motor. Preserve its own vector.
        if type(amount)~='number' or (s.lastWarpSerial and amount<=s.lastWarpSerial) then return end
        local carry=s.motor.v
        if s.pendingWarpSerial==amount and s.pendingWarpVelocity and os.clock()-(s.pendingWarpTime or 0)<.5 then carry=s.pendingWarpVelocity end
        if typeof(destination)=='CFrame' then s.r.CFrame=destination end
        resetWarp(s,serial==false and carry or Vector3.zero,serial==false and 'WarpKeepSpeed' or 'WarpResetSpeed')
        s.serial=amount;s.lastWarpSerial=amount;s.lastWarpTime=os.clock();s.lastWarpKeep=serial==false
        s.pendingWarpVelocity=nil;s.pendingWarpTime=nil;s.pendingWarpSerial=nil
    elseif kind=='ZoneState' and serial==s.serial then
        s.mapState=amount
    elseif kind=='Push' and serial==s.serial then
        if destination=='LegacyConveyor' then return end -- Base velocity is simulated locally.
        s.pushes[#s.pushes+1]={amount=amount,flags=set,sourceFlags=physicalVelocity}
    end
end)
connect(RunService.PreSimulation,function()
    local s=session;if not s or not s.r.Parent then return end
    for part in pairs(s.parts) do if part.Parent then part.CanCollide=false end end
    s.force.Force=Vector3.new(0,s.r.AssemblyMass*workspace.Gravity,0)
    s.r.AssemblyLinearVelocity=Vector3.zero;s.r.AssemblyAngularVelocity=Vector3.zero
end)
connect(RunService.PostSimulation,function(dt)
    local s=session;if not s or not s.r.Parent then return end
    if s.h.Health<=0 then restore();return end
    if player:GetAttribute('KZSpectatingUserId') or s.r.Anchored or s.h.Sit then
        resetWarp(s);return
    end
    local ok,err=pcall(function()
        local observed=player:GetAttribute('KZTeleportSerial')
        -- Attributes and RemoteEvents can arrive in either order. An older
        -- attribute must not undo an already handled Warp event.
        if observed~=s.serial and not (type(observed)=='number' and type(s.serial)=='number' and observed<s.serial) then
            if s.pendingWarpSerial~=observed then s.pendingWarpVelocity=s.motor.v;s.pendingWarpTime=os.clock();s.pendingWarpSerial=observed end
            resetWarp(s,nil,'TeleportSerialPending')
        end
        -- Network warps may arrive a frame before the serial attribute.
        local expected=s.motor:feet()+Vector3.new(0,s.standing,0)
        if (s.r.Position-expected).Magnitude>math.max(2,3500*s.unit*dt*2) then
            local recent=s.lastWarpTime and os.clock()-s.lastWarpTime<.5
            if not recent and not s.pendingWarpVelocity then s.pendingWarpVelocity=s.motor.v;s.pendingWarpTime=os.clock();s.pendingWarpSerial=type(s.serial)=='number' and s.serial+1 or nil end
            resetWarp(s,recent and s.lastWarpKeep and s.motor.v or nil,'ExternalPositionCorrection')
        end
        local input=readInput(s)
        s.accumulator=s.accumulator+math.min(dt,.25)
        local ticks=0
        -- Do not lose a physics tick to rounding at render rates whose frame
        -- duration cannot be represented exactly (30/60/144/240 FPS).
        while s.accumulator+1e-10>=1/128 and ticks<32 do
            local zone=Data.modifiers(s.map,Data.sourcePoint(s.map,s.motor:feet()),s.motor.height,s.mapState)
            s.zoneSlide=zone.slide==true
            s.zoneWaterLevel=zone.waterLevel
            if #s.pushes>0 then
                s.motor.v=Data.applyPushes(s.map,s.motor.v,s.pushes)
                s.motor:invalidate('Push');s.pushes={}
            end
            local climbing,ladderJump=ladderStep(s,input,1/128,zone)
            if ladderJump then input.jump=input.held end
            local jumped,stuck=false,false
            if not climbing then jumped,stuck=s.motor:tick(input,1/128,zone) end
            if stuck then error('Hull starts inside a brush') end
            if jumped then
                queued=-math.huge;input.jump=input.held;s.clientJumpId+=1
                Net:FireServer('Jump',{feet=s.motor.flight and Data.sourcePoint(s.map,s.motor.flight.start) or Data.sourcePoint(s.map,s.motor:feet()),
                    jumpId=s.clientJumpId,teleportSerial=s.serial,character=s.character})
            end
            if climbing and s.ladder and s.motor.time>=s.nextLadder then
                Net:FireServer('LadderAttach',{id=s.ladder.id,teleportSerial=s.serial})
                s.nextLadder=s.motor.time+.2
            end
            s.jumpHeld=input.held
            s.accumulator=math.max(0,s.accumulator-1/128);ticks=ticks+1
        end
        local position=s.motor:feet()+Vector3.new(0,s.standing,0)
        s.r.CFrame=CFrame.lookAt(position,position+s.lastForward)
        s.r.AssemblyLinearVelocity=Vector3.zero;s.r.AssemblyAngularVelocity=Vector3.zero
        telemetry(s)
        if os.clock()>=s.nextMotion then
            s.nextMotion=os.clock()+.05;s.motionSequence+=1
            Net:FireServer('Motion',{character=s.character,teleportSerial=s.serial,sequence=s.motionSequence,
                feet=Data.sourcePoint(s.map,s.motor:feet()),velocity=s.motor.v,view=input.view,height=s.motor.height})
        end
    end)
    if not ok then fallback(err) end
end)
connect(player.CharacterRemoving,function(c)
    if session and session.character==c then generation+=1;restore() end
end)
connect(player.CharacterAdded,function(c) task.spawn(setup,c) end)
if player.Character then task.spawn(setup,player.Character) end
connect(script.Destroying,function() if not released then player:SetAttribute("KZClassicMotorActive", nil) end;generation=generation+1;restore();for _,c in ipairs(connections) do c:Disconnect() end end)
