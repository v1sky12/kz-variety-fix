-- Fixed tick motor: duck -> categorize -> half gravity -> jump -> accel/move
-- -> categorize -> remaining half gravity. Inputs and map zones are adapters.
local M={};M.__index=M
local function flat(v) return Vector3.new(v.X,0,v.Z) end
function M.new(world,core,position,unit)
    return setmetatable({world=world,core=core,p=position,v=Vector3.zero,unit=unit,
        height=72,duck=false,pre=core.newPre(),groundAge=math.huge,time=0,
        grounded=false,lastLand=-math.huge,lastKind=nil,lastValid=false,count=0,serial=0},M)
end
function M:half() return Vector3.new(16,self.height/2,16)*self.unit end
function M:feet() return self.p-Vector3.new(0,self.height/2*self.unit,0) end
function M:categorize(sliding)
    self.groundNormal=nil
    if sliding then self.grounded=false;return end
    if self.v.Y>140*self.unit then self.grounded=false;return end
    local hit=self.core.traceGround(self.world,self.p,Vector3.new(0,-self.core.Profile.GroundProbe*self.unit,0),self:half(),self.unit)
    if hit.groundCorrected then self.groundCorrections=(self.groundCorrections or 0)+1 end
    self.grounded=not hit.startSolid and hit.fraction<1 and hit.normal and hit.normal.Y>=self.core.Profile.WalkableNormal or false
    if self.grounded then self.p=hit.position;self.groundNormal=hit.normal end
end
function M:stayOnGround()
    local profile=self.core.Profile
    local up=self.world:trace(self.p,Vector3.new(0,profile.GroundProbe*self.unit,0),self:half())
    if up.startSolid then return end
    local endpoint=self.p-Vector3.new(0,profile.StepHeight*self.unit,0)
    local down=self.core.traceGround(self.world,up.position,endpoint-up.position,self:half(),self.unit)
    if not down.startSolid and down.fraction>0 and down.fraction<1 and down.normal
        and down.normal.Y>=profile.WalkableNormal then self.p=down.position end
end
function M:slopeLanding(incoming,normal,planes)
    if not normal or normal.Y<self.core.Profile.WalkableNormal or normal.Y>=.999 or incoming.Y>=0 then return nil end
    local candidate=flat(self.core.clip(incoming,normal))
    if candidate.Magnitude<=flat(incoming).Magnitude+1e-5 then return nil end
    for _,n in ipairs(planes or {}) do
        if n.Y<self.core.Profile.WalkableNormal and candidate:Dot(n)<-math.max(1e-7,candidate.Magnitude*1e-6) then return nil end
    end
    return candidate
end
function M:posture(wanted)
    if self.duck==wanted then return true end
    local height=wanted and 54 or 72
    local position=self.p
    local shift=(self.grounded and height-self.height or self.height-height)/2*self.unit
    position=position+Vector3.new(0,shift,0)
    local half=Vector3.new(16,height/2,16)*self.unit
    if self.world:trace(position,Vector3.zero,half).startSolid then return false end
    self.p=position;self.height=height;self.duck=wanted
    return true
end
function M:invalidate(reason)
    if self.flight then self.flight.valid=false;self.flight.reason=self.flight.reason or reason end
end
function M:begin(kind,referenceY)
    local speed=flat(self.v).Magnitude/self.unit
    self.flight={kind=kind,start=self:feet(),referenceY=referenceY or self:feet().Y,
        time=self.time,pre=speed,max=speed,last=speed,peak=self:feet().Y,
        eligible=0,synced=0,strafes=1,side=0,gain=0,loss=0,valid=true,previousFeet=self:feet()}
end
function M:publish(f,feet,endTime,valid,reason)
    self.serial=self.serial+1
    self.result={kind=f.kind,valid=valid,reason=reason,
        distance=flat(feet-f.start).Magnitude/self.unit+(f.kind=='LAJ' and 0 or 32),
        pre=f.pre,max=f.max,gain=f.gain,loss=f.loss,peak=f.peak-f.start.Y,
        duration=endTime-f.time,strafes=f.strafes,sync=f.eligible>0 and f.synced/f.eligible*100 or 0,serial=self.serial}
end
function M:observe(dt,side,contacts,airStep)
    local f=self.flight
    if not f then return end
    local speed=flat(self.v).Magnitude/self.unit
    f.max=math.max(f.max,speed);f.peak=math.max(f.peak,self:feet().Y)
    if airStep==nil then airStep=not self.grounded end
    if airStep then
        local delta=self.airGain or speed-f.last
        if delta>0 then f.gain=f.gain+delta else f.loss=f.loss-delta end
        -- Dead-air and bad angles are part of the sync denominator in CKZ.
        f.eligible=f.eligible+dt
        if delta>1e-6 then f.synced=f.synced+dt end
        if side~=0 then
            if f.side~=0 and side~=f.side then f.strafes=f.strafes+1 end
            f.side=side
        end
    end
    f.last=speed
    for _,t in ipairs(contacts or {}) do
        if t.normal.Y<self.core.Profile.WalkableNormal then self:invalidate(t.normal.Y<-.1 and 'Ceiling' or 'WallOrSurf') end
    end
    if self.grounded and self.time>f.time then
        local feet=f.endFeet or self:feet();local endTime=f.endTime or self.time
        local duration=endTime-f.time
        local valid=f.valid and math.abs(feet.Y-f.referenceY)<=2*self.unit and duration>=.1 and duration<(f.kind=='LAJ' and 1.04 or .8)
        if not f.reportedFail then self:publish(f,feet,endTime,valid,valid and '' or f.reason or 'OffsetOrDuration') end
        self.lastKind=f.kind;self.lastValid=valid and not f.reportedFail;self.lastLand=self.time;self.flight=nil
    elseif not self.grounded and f.kind~='EDGE' and not f.reportedFail and self.time-f.time>.1 then
        local before,feet=f.previousFeet,self:feet()
        if before and before.Y>=f.referenceY and feet.Y<f.referenceY and self.v.Y<0 then
            local fraction=math.clamp((before.Y-f.referenceY)/(before.Y-feet.Y),0,1)
            local point=before+(feet-before)*fraction
            f.valid=false;f.reportedFail=true;f.reason=f.reason or 'MissedLanding'
            self:publish(f,point,self.time-dt+fraction*dt,false,f.reason)
        end
    end
    f.previousFeet=self:feet()
end
function M:tick(input,dt,zone)
    zone=zone or {};self.time=self.time+dt
    local profile=self.core.Profile
    local wasGround=self.grounded
    -- A shallow pool can end less than two units above its floor. Keep the
    -- ground probe from snapping an ascending swimmer back onto that floor
    -- immediately after waist water becomes ankle water.
    local function suppressGround()
        return zone.slide or zone.water or (zone.waterLevel or 0)>0 and self.v.Y>0
    end
    self:posture(not zone.forceUnduck and (zone.forceDuck or input.duck==true))
    self:categorize(suppressGround())
    local conveyor=self.grounded and not zone.water and zone.conveyor or Vector3.zero
    if self.grounded then self.v-=self.baseVelocity or Vector3.zero end
    self.baseVelocity=Vector3.zero
    if self.grounded and not wasGround then
        local projected=not zone.slide and self:slopeLanding(self.v,self.groundNormal,self.contactPlanes)
        if projected then self.v=Vector3.new(projected.X,self.v.Y,projected.Z) end
        self.lastLand=self.time;self.landingVelocity=flat(self.v);self.landingSpeed=self.landingVelocity.Magnitude/self.unit
        self:observe(0,0,{})
    end
    if self.grounded then self.groundAge=wasGround and self.groundAge+dt or 0 else self.groundAge=0 end
    if wasGround and not self.grounded and not self.flight then
        self.dropY=self:feet().Y;self:begin('EDGE',self.dropY);self:invalidate('EdgeDeparture')
    end
    if self.grounded and self.dropY then
        local drop=(self.dropY-self:feet().Y)/self.unit
        self.weirdAt=drop>2 and drop<=64 and self.time or nil;self.dropY=nil
    end
    local groundBefore=self.grounded
    local groundFeetY=self:feet().Y
    local waterJump=self.waterJumpUntil and self.time<self.waterJumpUntil
    if self.grounded or zone.waterLevel==0 or (zone.water and self.v.Y<0) then waterJump=false end
    if not waterJump then self.waterJumpUntil=nil;self.waterJumpVelocity=nil end
    local gravity=profile.Gravity*self.unit*(zone.gravity or 1)
    if zone.water and not waterJump then gravity=0 end
    self.v=self.v-Vector3.new(0,gravity*.5*dt,0)
    if self.grounded then self.v=flat(self.v) end
    local jumped=false
    if input.jump and self.grounded and not zone.disableJump and not zone.water
        and ((zone.antiBhop or 0)<=0 or self.time-self.lastLand>zone.antiBhop) then
        local kind='LJ'
        local chained=self.time-self.lastLand<=self.core.Profile.PerfWindow
        if self.weirdAt and self.time-self.weirdAt<=self.core.Profile.PerfWindow then kind='WJ'
        elseif chained and self.lastValid then
            if self.lastKind=='LJ' then kind='BH' elseif self.lastKind=='BH' or self.lastKind=='MBH' then kind='MBH' end
        end
        if chained then
            local takeoff=flat(self.v)/self.unit
            local landing=self.landingVelocity and self.landingVelocity/self.unit
                or takeoff.Magnitude>1e-6 and takeoff.Unit*(self.landingSpeed or takeoff.Magnitude) or Vector3.zero
            self.v=self.core.perfVelocity(landing,takeoff,self.core.preGain(self.pre),self.time-self.lastLand)*self.unit
        end
        self.v=self.v+Vector3.new(0,profile.JumpImpulse*self.unit*(zone.jump or 1)-gravity*.5*dt,0)
        self.grounded=false;self.weirdAt=nil;self.count=self.count+1;jumped=true
        self:begin(kind);self.flight.time=self.time-dt
        if chained and kind~='WJ' and self.lastKind and not self.lastValid then self:invalidate('InvalidChain') end
    end
    local speedFactor=self.duck and .34 or input.walk and .52 or 1
    local beforeAir=flat(self.v).Magnitude/self.unit
    local airStep=not self.grounded and not zone.water and not waterJump
    local xz
    if zone.water or waterJump then
        self.core.updatePre(self.pre,flat(self.v)/self.unit,input.wish,false,dt,self.groundAge)
        xz=flat(self.v)
    else
        xz=self.core.step(flat(self.v)/self.unit,input.wish,self.grounded and not zone.slide,dt,self.pre,self.groundAge,speedFactor)*self.unit
    end
    if waterJump and self.waterJumpVelocity then xz=self.waterJumpVelocity end
    self.v=Vector3.new(xz.X,self.v.Y,xz.Z)
    self.airGain=flat(self.v).Magnitude/self.unit-beforeAir
    self.water=zone.water==true
    if zone.water and not waterJump then
        self:invalidate('Water');self.grounded=false
        -- Source CheckJumpButton applies a swimming rise impulse each tick;
        -- it is separate from the 302-unit grounded jump.
        if input.jump then self.v=Vector3.new(self.v.X,profile.WaterRise*self.unit,self.v.Z) end
        -- WaterMove has its own acceleration: never add AirAccelerate first.
        self.v=self.core.waterMove(self.v/self.unit,input.swim or input.wish,input.jump,dt)*self.unit
        -- Source uses a 256-unit exit impulse and keeps pushing toward the
        -- bank after the first wall collision. A 225-unit impulse cannot lift
        -- standing feet from waist depth to a bank at the water surface.
        -- Check the entire exit hull and a standable landing before launching.
        if zone.waterLevel==2 and input.wish.Magnitude>.1 and self.v.Y>-180*self.unit then
            local probe=self:feet()+Vector3.new(0,18*self.unit,0)
            local half=Vector3.new(16,1,16)*self.unit
            local wall=self.world:trace(probe,input.wish*24*self.unit,half)
            if wall.fraction<1 and not wall.startSolid and wall.normal and wall.normal.Y<.1
                and wall.fraction*24<=4 then
                local rise=48*self.unit
                local up=self.world:trace(self.p,Vector3.new(0,rise,0),self:half())
                local clear=not up.startSolid and up.fraction==1
                    and self.world:trace(up.position,input.wish*24*self.unit,self:half())
                if clear and not clear.startSolid and clear.fraction==1 then
                    local landing=self.world:trace(clear.position,Vector3.new(0,-rise,0),self:half())
                    local climb=landing.position.Y-self.p.Y
                    gravity=profile.Gravity*self.unit*(zone.gravity or 1)
                    local maximum=profile.WaterJumpImpulse^2/(2*gravity)*self.unit^2
                    if not landing.startSolid and landing.fraction<1 and landing.normal
                        and landing.normal.Y>=profile.WalkableNormal and climb>0 and climb<maximum-.5*self.unit then
                        self.waterJumpUntil=self.time+profile.WaterJumpDuration;waterJump=true
                        self.waterJumpVelocity=-flat(wall.normal).Unit*profile.WaterJumpForward*self.unit
                        self.v=self.waterJumpVelocity+Vector3.new(0,profile.WaterJumpImpulse*self.unit-gravity*.5*dt,0)
                    end
                end
            end
        end
    end
    -- Friction and acceleration act relative to the conveyor. Add its motion
    -- once for the sweep; on takeoff this becomes ordinary airborne momentum.
    self.v+=conveyor
    if conveyor.Magnitude>1e-6 then self:invalidate('BaseVelocity') end
    local limit=profile.MaxVelocity*self.unit
    self.v=Vector3.new(math.max(-limit,math.min(limit,self.v.X)),math.max(-limit,math.min(limit,self.v.Y)),math.max(-limit,math.min(limit,self.v.Z)))
    local preMoveVelocity=self.v
    local contacts,stuck,activePlanes
    self.p,self.v,contacts,stuck,activePlanes=self.world:move(self.p,self.v,self:half(),dt,self.grounded,profile.StepHeight*self.unit)
    self.contactPlanes=activePlanes
    if stuck and self.world.recover then
        local recovered=self.world:recover(self.p,self:half(),2*self.unit)
        if recovered then
            self.p=recovered;self.v=preMoveVelocity;stuck=false
            self.recoveries=(self.recoveries or 0)+1;self:invalidate('SeamRecovery')
        end
    end
    -- Capture a walkable slope before categorize() flattens grounded velocity.
    -- Source slope-fix projects the incoming fall onto the plane and keeps
    -- the horizontal gain when the projection is faster than the landing.
    local landingNormal
    for _,contact in ipairs(contacts or {}) do
        local n=contact.normal
        if n and n.Y>=profile.WalkableNormal and n.Y<.999 and preMoveVelocity.Y<0 then landingNormal=n;break end
    end
    local landingVelocity=preMoveVelocity
    if groundBefore and not jumped and not zone.slide and not zone.water and not stuck then self:stayOnGround() end
    local movedFeet=self:feet()
    self:categorize(suppressGround())
    if not landingNormal and self.grounded and self.groundNormal and self.groundNormal.Y<.999
        and preMoveVelocity.Y<0 then landingNormal=self.groundNormal end
    if self.grounded and not groundBefore and self.flight then
        local f=self.flight;local landing
        for _,contact in ipairs(contacts or {}) do
            if contact.normal and contact.normal.Y>=profile.WalkableNormal and contact.timeFraction and contact.position then landing=contact;break end
        end
        if landing then
            f.endFeet=landing.position-Vector3.new(0,self.height/2*self.unit,0)
            f.endTime=self.time-dt+dt*landing.timeFraction
        else
            -- Categorize can snap the hull down by two units before the
            -- ballistic crossing. Correct stats without moving the character.
            local gap=movedFeet.Y-self:feet().Y
            local vy=preMoveVelocity.Y-gravity*.5*dt
            if gap>=0 and gap<=2.01*self.unit and vy<0 then
                local extra=gravity>0 and 2*gap/(math.sqrt(vy*vy+2*gravity*gap)-vy) or -gap/vy
                if extra<=dt*2 then
                    local projected=movedFeet+flat(preMoveVelocity)*extra
                    f.endFeet=Vector3.new(projected.X,self:feet().Y,projected.Z);f.endTime=self.time+extra
                end
            end
        end
    end
    if self.grounded and not groundBefore and landingNormal and not zone.slide then
        local projected=self:slopeLanding(landingVelocity,landingNormal,activePlanes)
        if projected then self.v=projected end
    end
    if self.grounded and not groundBefore then
        self.lastLand=self.time;self.landingVelocity=flat(self.v);self.landingSpeed=self.landingVelocity.Magnitude/self.unit
        if self.dropY then
            local drop=(self.dropY-self:feet().Y)/self.unit
            self.weirdAt=drop>2 and drop<=64 and self.time or nil;self.dropY=nil
        end
    elseif groundBefore and not self.grounded and not jumped and not self.flight then
        -- Walking off an edge is tracked as an invalid EDGE flight.
        self.dropY=groundFeetY
        self:begin('EDGE',groundFeetY)
        self:invalidate('EdgeDeparture')
    end
    if not self.grounded then self.v=self.v-Vector3.new(0,gravity*.5*dt,0) else self.v=flat(self.v) end
    if (zone.waterLevel or 0)>0 then self:invalidate('Water') end
    if zone.disableJumpstats or zone.slide or (zone.jump and zone.jump~=1) or (zone.gravity and zone.gravity~=1) then self:invalidate('MapModifier') end
    if stuck then self:invalidate('StartSolid') end
    self.surfNormal=nil;self.surfPart=nil
    -- Only planes remaining after the last positive sweep constrain the
    -- final velocity. Historical contacts still invalidate jumpstats, but
    -- must not constrain a later, spatially separate ramp transition.
    local normals=activePlanes
    if not normals then
        normals={}
        for _,contact in ipairs(contacts or {}) do if contact.normal then normals[#normals+1]=contact.normal end end
    end
    for _,n in ipairs(normals) do
        if n.Y>.0001 and (n.Y<profile.WalkableNormal or (zone.slide and n.Y<.999999)) then
            self.surfNormal=n
        end
    end
    if self.surfNormal then
        for _,contact in ipairs(contacts or {}) do
            if contact.normal and contact.normal:Dot(self.surfNormal)>.99999 then
                self.surfPart=contact.brush and contact.brush.id
            end
        end
    end
    -- Project remaining half-gravity into the active contact cone. Tangential
    -- momentum is retained by collision clipping; never rescale it to restore
    -- speed that was actually directed into a wall or an ascending ramp.
    if not self.grounded then self.v=self.core.clipPlanes(self.v,normals) end
    -- Preserve contact-plane direction if a steep ramp correction reaches
    -- the per-axis velocity limit. Independent axis clamps can re-enter it.
    local maximum=math.max(math.abs(self.v.X),math.abs(self.v.Y),math.abs(self.v.Z))
    if maximum>limit then self.v=self.v*(limit/maximum) end
    self.baseVelocity=self.grounded and conveyor or Vector3.zero
    self:observe(dt,input.turn or input.side or 0,contacts,airStep)
    return jumped,stuck
end
return M
