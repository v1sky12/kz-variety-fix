local passed,failed=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed+=1;print('PASS '..name) else failed+=1;warn('FAIL '..name..': '..tostring(err)) end
end
local function near(a,b,eps) assert(math.abs(a-b)<(eps or 1e-5),tostring(a)..' ~= '..tostring(b)) end
local V=Vector3.new
local function input(jump) return {wish=Vector3.zero,jump=jump==true,duck=false,side=0} end
local function floorWorld()
    return {
        trace=function(_,p,d,h)
            if p.Y-h.Y < -.01 then return {startSolid=true,fraction=0,position=p} end
            if d.Y<0 and p.Y+d.Y-h.Y<=0 then
                local f=math.clamp((h.Y-p.Y)/d.Y,0,1)
                return {fraction=f,position=p+d*f,normal=V(0,1,0)}
            end
            return {fraction=1,position=p+d}
        end,
        move=function(_,p,v,h,dt)
            local q=p+v*dt
            if q.Y<h.Y then return V(q.X,h.Y,q.Z),V(v.X,0,v.Z),{{normal=V(0,1,0)}},false end
            return q,v,{},false
        end,
    }
end
local function map(yaw)
    local attrs={KZStudsPerCSUnit=1}
    return {GetPivot=function() return CFrame.new(V(0,0,0),yaw) end,GetAttribute=function(_,n) return attrs[n] end}
end
local function cube(x0,y0,z0,x1,y1,z1)
    local vv={}
    for _,x in ipairs({x0,x1}) do for _,y in ipairs({y0,y1}) do for _,z in ipairs({z0,z1}) do vv[#vv+1]=V(x,y,z) end end end
    return Collision.fromVertices(vv,'box')
end
test('ground friction matches CKZ stop speed',function() near(Core.friction(V(100,0,0),.01).X,94.8) end)
test('air accel caps projection, not existing speed',function()
    local v=Core.accelerate(V(500,0,0),V(0,0,1),250,100,1/128,30)
    near(v.X,500);near(v.Z,30)
end)
test('jump trajectory uses 800 gravity and 302 impulse',function()
    local m=Motor.new(floorWorld(),Core,V(0,36,0),1);m.grounded=true
    m:tick(input(true),1/128,{})
    near(m.v.Y,302-800/128)
    local peak=m:feet().Y
    while not m.grounded do m:tick(input(false),1/128,{});peak=math.max(peak,m:feet().Y) end
    near(peak,302*302/1600,.02);assert(m.result and m.result.valid)
end)
test('surf contact executes without undefined Core',function()
    local n=V(0,.6,.8)
    local w=floorWorld();w.trace=function(_,p,d) return {fraction=1,position=p+d} end
    w.move=function(_,p,v,_,dt) return p+v*dt,Core.clip(v,n),{{normal=n}},false end
    local m=Motor.new(w,Core,V(0,50,0),1);m.v=V(800,-20,-100)
    m:tick(input(false),1/128,{})
    assert(m.v:Dot(n)>=-1e-6,'surf correction re-entered ramp')
end)
test('surf correction never restores speed into a wall',function()
    local ramp,wall=V(0,.6,.8),V(-1,0,0)
    local w=floorWorld();w.trace=function(_,p,d) return {fraction=1,position=p+d} end
    w.move=function(_,p,v) return p,Vector3.zero,{{normal=ramp},{normal=wall}},false end
    local m=Motor.new(w,Core,V(0,50,0),1);m.v=V(800,-20,-100)
    m:tick(input(false),1/128,{})
    assert(m.v:Dot(wall)>=-1e-6)
end)
test('bhop perf does not depend on jumpstats validity',function()
    local m=Motor.new(floorWorld(),Core,V(0,36,0),1)
    m.grounded=true;m.lastLand=0;m.lastValid=false;m.lastKind='LJ';m.v=V(450,0,0)
    m:tick(input(true),1/128,{disableJumpstats=true})
    near(m.v.X,(Core.perfSpeed(450,450,0,1/128)))
end)
test('air crouch raises feet by Source hull-height delta',function()
    local m=Motor.new(floorWorld(),Core,V(0,90,0),1)
    local feet=m:feet().Y;m:posture(true);near(m:feet().Y,feet+18);m:posture(false);near(m:feet().Y,feet)
end)
test('edge departure is reported even during initial categorization',function()
    local w=floorWorld();w.trace=function(_,p,d) return {fraction=1,position=p+d} end
    local m=Motor.new(w,Core,V(0,50,0),1);m.grounded=true
    m:tick(input(false),1/128,{})
    assert(m.flight and m.flight.kind=='EDGE' and not m.flight.valid)
end)
test('weirdjump drop history survives invalid edge statistics',function()
    local w=floorWorld();w.trace=function(_,p,d) return {fraction=1,position=p+d} end
    local m=Motor.new(w,Core,V(0,50,0),1);m.grounded=true;m:tick(input(false),1/128,{})
    assert(m.dropY~=nil,'invalidating edge erased drop history')
end)
test('water sinks without Space and rises with Space',function()
    local m=Motor.new(floorWorld(),Core,V(0,200,0),1)
    for _=1,10 do m:tick(input(false),1/128,{water=true}) end
    assert(m.water and m.v.Y<0)
    for _=1,20 do m:tick(input(true),1/128,{water=true}) end
    assert(m.v.Y>0)
end)
test('dry motor clears water telemetry on ladder transition',function()
    local m=Motor.new(floorWorld(),Core,V(0,200,0),1)
    m:tick(input(false),1/128,{water=true});m:tick(input(false),1/128,{})
    assert(m.water==false)
end)
test('brush trace detects deep starting overlap',function()
    local w=Collision.world({cube(-10,-10,-10,10,10,10)},8)
    assert(w:trace(V(0,0,0),V(0,0,0),V(1,1,1)).startSolid)
end)
test('brush boundary allows tangent travel and leaving wall',function()
    local b=cube(-10,-10,-10,0,10,10)
    assert(Collision.sweepBrush(b,V(1,0,0),V(0,0,5),V(1,1,1))==nil)
    assert(Collision.sweepBrush(b,V(1,0,0),V(5,0,0),V(1,1,1))==nil)
    assert(Collision.sweepBrush(b,V(1,0,0),V(-5,0,0),V(1,1,1)).fraction==0)
end)
test('two-plane corner preserves only allowed movement',function()
    local w=Collision.world({cube(5,-10,-10,10,10,10),cube(-10,-10,5,10,10,10)},8)
    local p,v,_,stuck=w:slide(V(0,0,0),V(100,0,100),V(1,1,1),.1)
    assert(not stuck and p.X<4.001 and p.Z<4.001);near(v.X,0);near(v.Z,0)
end)
test('single bhop reuse and two-player states are independent',function()
    local a,b={},{};Bhop.reset(a);Bhop.reset(b)
    assert(not Bhop.takeoff(a,'a',12,1));assert(Bhop.land(a,'a',12,2,.1))
    assert(not Bhop.land(b,'a',12,2,.1));Bhop.reset(a);assert(not Bhop.land(a,'a',12,3,.1))
end)
test('multi bhop allows reuse until map contact delay',function()
    local s={};Bhop.reset(s);Bhop.takeoff(s,'a',11,1)
    assert(not Bhop.land(s,'a',11,2,.125));assert(not Bhop.land(s,'a',11,2.125,.125))
    assert(Bhop.land(s,'a',11,2.126,.125))
end)
test('sequential bhop rejects previously visited block',function()
    local s={};Bhop.reset(s);Bhop.takeoff(s,'a',13,1);Bhop.takeoff(s,'b',13,2)
    assert(Bhop.land(s,'a',13,3,.1));Bhop.reset(s);assert(not Bhop.land(s,'a',13,4,.1))
end)
test('Source world coordinate transform round-trips with rotated map',function()
    local m=map(.7);local p=Data.worldPoint(m,{123,-456,789});local source=Data.sourcePoint(m,p)
    near(source.X,123);near(source.Y,-456);near(source.Z,789)
end)
test('water level changes surface without moving bottom',function()
    local e={id='water',bounds={{0,0,-100},{100,100,0}}}
    local m={GetAttribute=function() return 10 end}
    local b=Data.waterBounds(m,e);near(b[1][3],-100);near(b[2][3],10)
end)
test('disabled map modifier is ignored consistently',function()
    local saved=Data.zones
    Data.zones={{id='g',bounds={{-100,-100,-100},{100,100,100}},class='trigger_multiple',triggerType=1,properties={timer_modifier_gravity='.4'}}}
    local mods=Data.modifiers(map(0),V(0,0,0),72,{disabled={g=true},attributes={}})
    Data.zones=saved;near(mods.gravity,1)
end)
test('force-duck map modifier is exposed to motor',function()
    local saved=Data.zones
    Data.zones={{id='duck',bounds={{-100,-100,-100},{100,100,100}},class='trigger_multiple',triggerType=1,properties={timer_modifier_force_duck='1'}}}
    local mods=Data.modifiers(map(0),V(0,0,0),72)
    Data.zones=saved;assert(mods.forceDuck==true)
end)
test('actual map retains horizontal ladder span',function()
    local found=false
    for _,ladder in ipairs(Data.ladderSurfaces) do
        local a,b=ladder.bounds[1],ladder.bounds[2]
        if math.max(b[1]-a[1],b[2]-a[2])>300 then found=true end
    end
    assert(found)
end)
test('continuous real brush surf crosses seam without fallback or penetration',function()
    local function ramp(a,b)
        return Collision.fromVertices({V(a,-500,-100),V(b,-500,-100),V(a,-500,100),V(b,-500,100),
            V(a,400/3,-100),V(b,400/3,-100),V(a,-400/3,100),V(b,-400/3,100)},'ramp')
    end
    local w=Collision.world({ramp(-500,0),ramp(0,500)},64)
    local m=Motor.new(w,Core,V(-80,34.402/.6,0),1);m.v=V(800,0,0)
    local n=V(0,.6,.8);local touched=false
    for _=1,40 do
        local _,stuck=m:tick(input(false),1/128,{})
        assert(not stuck);assert(m.v.X==m.v.X and math.abs(m.v.X)>700)
        if m.surfNormal then touched=true;assert(m.v:Dot(n)>=-1e-5) end
    end
    assert(touched and m.p.X>0,'did not cross ramp seam')
end)
test('step solver climbs 16-unit step but cannot climb 20-unit wall',function()
    local h=V(16,36,16)
    for _,height in ipairs({16,20}) do
        local w=Collision.world({cube(-100,-10,-100,100,0,100),cube(20,0,-40,40,height,40)},64)
        local p,_,_,stuck=w:move(V(0,36.001,0),V(100,0,0),h,.1,true,18)
        assert(not stuck)
        if height==16 then assert(p.X>9.99 and p.Y>51.99) else assert(p.X<4.01 and p.Y<36.01) end
    end
end)
test('rotated map absolute Source X push preserves other Source components',function()
    local m=map(.9)
    local velocity=Data.worldVector(m,{100,200,300})
    local pushed=Data.applyPushes(m,velocity,{{amount=Data.worldVector(m,{500,0,0}),sourceFlags={true,false,false}}})
    local source=Data.sourceVector(m,pushed)
    near(source.X,500);near(source.Y,200);near(source.Z,300)
end)
test('absolute push component dominates later additive impulse',function()
    local m=map(.3)
    local velocity=Data.applyPushes(m,Vector3.zero,{
        {amount=Data.worldVector(m,{0,0,500}),sourceFlags={false,false,true}},
        {amount=Data.worldVector(m,{100,200,100}),sourceFlags={false,false,false}},
    })
    local source=Data.sourceVector(m,velocity);near(source.X,100);near(source.Y,200);near(source.Z,500)
end)
test('jumpstats counts turning direction changes and includes dead air in sync',function()
    local m=Motor.new(floorWorld(),Core,V(0,100,0),1);m:begin('LJ')
    m.airGain=1;m:observe(.1,1,{})
    m.airGain=0;m:observe(.1,0,{})
    m.airGain=1;m:observe(.1,-1,{})
    near(m.flight.strafes,2);near(m.flight.synced/m.flight.eligible*100,200/3)
end)
test('tiny imported seam overlap recovers inside a two-unit limit',function()
    local w=Collision.world({cube(-100,-10,-100,100,0,100)},64)
    local p=V(0,35.98,0);local recovered=w:recover(p,V(16,36,16),2)
    assert(recovered and (recovered-p).Magnitude<=2)
    assert(not w:trace(recovered,Vector3.zero,V(16,36,16)).startSolid)
end)
test('deep solid overlap fails recovery instead of teleporting through wall',function()
    local w=Collision.world({cube(-100,-100,-100,100,100,100)},64)
    assert(w:recover(V(0,0,0),V(16,36,16),2)==nil)
end)
test('filter with absent initial state cannot crash or enable modifier',function()
    local saved,old=Data.zones,Data.byName.testFilter
    Data.byName.testFilter={class='filter_activator_attribute_int',properties={filterattribute='test'}}
    Data.zones={{id='filterZone',bounds={{-100,-100,-100},{100,100,100}},class='trigger_multiple',triggerType=1,
        properties={timer_modifier_gravity='.4',filtername='testFilter'}}}
    local absent=Data.modifiers(map(0),V(0,0,0),72,{})
    local enabled=Data.modifiers(map(0),V(0,0,0),72,{attributes={test=1}})
    Data.zones=saved;Data.byName.testFilter=old
    near(absent.gravity,1);near(enabled.gravity,.4)
end)
test('ankle-deep water permits walking; waist-deep water enables swimming',function()
    local saved=Data.zones
    Data.zones={{id='water',bounds={{-100,-100,-100},{100,100,20}},class='func_water',triggerType=0,properties={}}}
    local ankle=Data.modifiers(map(0),V(0,0,0),72)
    local waist=Data.modifiers(map(0),V(0,0,-20),72)
    Data.zones=saved
    assert(ankle.waterLevel==1 and not ankle.water);assert(waist.waterLevel==2 and waist.water)
end)
test('swept trigger detects thin zone and rejects distant parallel segment',function()
    local bounds={{-1,-1,0},{1,1,2}}
    local enter,leave=Data.sweepIntersects(bounds,V(-100,0,0),V(100,0,0),72)
    near(enter,.415);near(leave,.585)
    assert(Data.sweepIntersects(bounds,V(-100,100,0),V(100,100,0),72)==nil)
end)
test('water acceleration does not include an extra air-strafe impulse',function()
    local m=Motor.new(floorWorld(),Core,V(0,200,0),1)
    m:tick({wish=V(1,0,0),side=0},1/128,{water=true,waterLevel=3})
    near(m.v.X,225*10/128)
end)
test('waist-deep water exits a real low ledge through hull sweeps',function()
    local w=Collision.world({cube(-100,-110,-100,150,-100,100),cube(20,-100,-100,150,30,100)},64)
    local m=Motor.new(w,Core,V(0,36,0),1)
    for _=1,40 do
        local swimming=m:feet().Y+36<=40
        local _,stuck=m:tick({wish=V(1,0,0),side=0},1/128,{water=swimming,waterLevel=swimming and 2 or 1})
        assert(not stuck)
    end
    assert(m.p.X>4 and m:feet().Y>=29.99,'failed to leave water at the ledge')
end)
test('steep surf correction obeys maximum velocity without pointing into ramp',function()
    local n=V(0,.001,math.sqrt(1-.001*.001))
    local w=floorWorld();w.trace=function(_,p,d) return {fraction=1,position=p+d} end
    w.move=function(_,p,v) return p,Core.clip(v,n),{{normal=n}},false end
    local m=Motor.new(w,Core,V(0,50,0),1);m.v=V(0,0,-3500)
    m:tick(input(false),1/128,{})
    assert(math.max(math.abs(m.v.X),math.abs(m.v.Y),math.abs(m.v.Z))<=3500.00001)
    assert(m.v:Dot(n)>=-1e-5)
end)
test('jumpstats corrects landing snap to sub-tick distance and airtime',function()
    local w=Collision.world({cube(-1000,-10,-100,1000,0,100)},128)
    local m=Motor.new(w,Core,V(0,36.001,0),1);m.grounded=true;m.v=V(250,0,0)
    m:tick(input(true),1/128,{})
    for _=1,150 do if m.result then break end;m:tick(input(false),1/128,{}) end
    assert(m.result and m.result.valid)
    near(m.result.distance,250*(302/400)+32,.01)
    near(m.result.duration,302/400,.0001)
end)
test('missed platform reports fail at takeoff plane before falling to lower floor',function()
    local w=Collision.world({cube(-100,-10,-100,20,0,100),cube(-100,-510,-100,1000,-500,100)},128)
    local m=Motor.new(w,Core,V(0,36.001,0),1);m.grounded=true;m.v=V(250,0,0)
    m:tick(input(true),1/128,{})
    for _=1,130 do if m.result then break end;m:tick(input(false),1/128,{}) end
    assert(m.result and not m.result.valid and m.result.reason=='MissedLanding')
    assert(not m.grounded);near(m.result.distance,220.75,.01)
    local serial=m.result.serial
    for _=1,200 do if m.grounded then break end;m:tick(input(false),1/128,{}) end
    assert(m.grounded);near(m.result.serial,serial)
end)
test('old wall contact cannot suppress speed on spatially separate ramp',function()
    local n=V(0,.6,.8)
    local w=floorWorld();w.trace=function(_,p,d) return {fraction=1,position=p+d} end
    w.move=function(_,p,v)
        return p,Core.clip(v*.5,n),{{normal=V(-1,0,0)},{normal=n}},false,{n}
    end
    local m=Motor.new(w,Core,V(0,50,0),1);m.v=V(800,0,0)
    m:tick(input(false),1/128,{})
    assert(math.sqrt(m.v.X*m.v.X+m.v.Z*m.v.Z)>=799.99)
    assert(m.v:Dot(n)>=-1e-6)
end)
test('anti-bhop delay uses strict CKZ boundary',function()
    local m=Motor.new(floorWorld(),Core,V(0,36,0),1)
    m.grounded=true;m.lastLand=0;m.time=.125-1/128
    assert(not m:tick(input(true),1/128,{antiBhop=.125}))
    assert(m:tick(input(true),1/128,{antiBhop=.125}))
end)
test('forced unduck wins simultaneous conflicting modifiers',function()
    local m=Motor.new(floorWorld(),Core,V(0,36,0),1);m.grounded=true;m:posture(true)
    m:tick({wish=Vector3.zero,duck=true},1/128,{forceDuck=true,forceUnduck=true})
    assert(not m.duck)
end)
test('walking off real platform preserves WJ classification on next takeoff',function()
    local w=Collision.world({cube(-100,-10,-100,1000,0,100),cube(-100,0,-100,20,32,100)},128)
    local m=Motor.new(w,Core,V(0,68.001,0),1);m.grounded=true;m.v=V(250,0,0)
    local left=false
    for _=1,250 do
        m:tick({wish=V(1,0,0),side=0},1/128,{})
        if not m.grounded then left=true end
        if left and m.grounded then break end
    end
    assert(left and m.grounded and m.weirdAt)
    m:tick({wish=V(1,0,0),side=0,jump=true},1/128,{})
    assert(m.flight and m.flight.kind=='WJ' and m.flight.valid)
end)
test('slide spends remaining time after five separate ramp contacts',function()
    local w=Collision.world({},64);local calls=0
    function w:trace(p,d)
        calls+=1
        local f=calls<=5 and .2 or 1
        return {fraction=f,position=p+d*f,normal=V(0,1,0)}
    end
    local p,v=w:slide(V(0,0,0),V(100,0,0),V(1,1,1),.1)
    near(p.X,10);near(v.X,100)
end)
test('repeated zero-fraction plane separates without injecting velocity',function()
    local w=Collision.world({},64)
    function w:trace(p,d)
        if p.Y<.001 and d.Magnitude>.01 then return {fraction=0,position=p,normal=V(0,1,0)} end
        return {fraction=1,position=p+d}
    end
    local p,v,_,stuck=w:slide(V(0,0,0),V(100,0,0),V(1,1,1),.1)
    assert(not stuck);near(p.X,10);near(v.X,100);near(v.Y,0)
    assert(p.Y<.01,'separation exceeded collision skin')
end)
test('primitive cache reuses respawn geometry and invalidates edited colliders',function()
    local part={Size=V(10,10,10),CFrame=CFrame.new(),Shape='Block'}
    function part:IsA(n) return n=='Part' end
    local a=Collision.fromPart(part);assert(Collision.fromPart(part)==a)
    part.Size=V(20,10,10);local b=Collision.fromPart(part);assert(b~=a);near(b.hi.X,10)
    part.CFrame=CFrame.new(V(100,0,0));local c=Collision.fromPart(part);assert(c~=b);near(c.lo.X,90)
end)
test('real brushes retain surf motion through changing ramp angles',function()
    local function ramp(a,b,nx)
        local vertices={}
        for _,x in ipairs({a,b}) do for _,z in ipairs({-200,200}) do
            vertices[#vertices+1]=V(x,-1000,z)
            vertices[#vertices+1]=V(x,-(nx*x+.8*z)/.6,z)
        end end
        return Collision.fromVertices(vertices,'transition')
    end
    for _,slope in ipairs({-.08,.08}) do
        local w=Collision.world({ramp(-500,0,0),ramp(0,500,slope)},64)
        local m=Motor.new(w,Core,V(-80,34.402/.6,0),1);m.v=V(800,0,0)
        for tick=1,40 do
            local _,stuck=m:tick(input(false),1/128,{})
            assert(not stuck,'ramp transition entered solid')
            assert(math.sqrt(m.v.X*m.v.X+m.v.Z*m.v.Z)>700,'ramp transition discarded speed slope='..slope..' tick='..tick..' p='..tostring(m.p)..' v='..tostring(m.v)..' normal='..tostring(m.surfNormal))
        end
        assert(m.p.X>0)
    end
end)
test('surf transitions remain stable at map scales and rotated headings',function()
    for _,unit in ipairs({.075,.1,1}) do for _,yaw in ipairs({0,.37,1.2}) do for _,slope in ipairs({-.08,.08}) do
        local rotation=CFrame.new(Vector3.zero,yaw)
        local function ramp(a,b,nx)
            local vertices={}
            for _,x in ipairs({a,b}) do for _,z in ipairs({-300,300}) do
                vertices[#vertices+1]=rotation:VectorToWorldSpace(V(x,-1000,z))*unit
                vertices[#vertices+1]=rotation:VectorToWorldSpace(V(x,-(nx*x+.8*z)/.6,z))*unit
            end end
            return Collision.fromVertices(vertices,'rotated transition')
        end
        local n=rotation:VectorToWorldSpace(V(0,.6,.8))
        local startY=(math.abs(n.X)*16+n.Y*36+math.abs(n.Z)*16)/n.Y+.03
        local w=Collision.world({ramp(-500,0,0),ramp(0,500,slope)},8)
        local m=Motor.new(w,Core,rotation:VectorToWorldSpace(V(-80,startY,0))*unit,unit)
        m.v=rotation:VectorToWorldSpace(V(800,0,0))*unit
        for tick=1,40 do
            local _,stuck=m:tick(input(false),1/128,{})
            assert(not stuck,'scaled transition entered solid')
            assert(math.sqrt(m.v.X*m.v.X+m.v.Z*m.v.Z)/unit>700,'scaled transition lost speed '..unit..' '..yaw..' '..slope..' '..tick)
        end
    end end end
end)
print(string.format('RESULT %d passed, %d failed',passed,failed))
assert(failed==0,'physics regressions failed')
