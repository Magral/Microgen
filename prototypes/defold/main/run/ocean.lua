local Random = require "main.run.rng"
local Ocean = {}
Ocean.__index = Ocean

local CURRENT_DIVISOR = 6
local DEPTH = {.55,.88,1.18}
local WAKE_LIFE = 1.8
local MOTES = 100
local MAX_WAKES = 96
local DEEP_BODIES = 8
local TAU = 2*math.pi
local fluid_view = hash("fluid_view")
local fluid_stage = hash("fluid_stage")

local function node(layer, texture, frame)
    local value = gui.new_box_node(vmath.vector3(),vmath.vector3())
    gui.set_layer(value,layer)
    gui.set_texture(value,texture)
    gui.play_flipbook(value,frame)
    gui.set_enabled(value,false)
    return value
end

local function place(n,x,y,w,h)
    gui.set_position(n,vmath.vector3(x,y,0))
    gui.set_size(n,vmath.vector3(w,h,0))
end

local function flow(x,y,time)
    return (math.sin(y*.0019+time*.23)+math.cos(x*.0011-y*.0008-time*.12))*12,
        (math.cos(x*.0018-time*.18)-math.sin(y*.001+time*.11))*12
end

local function wrap(p,c,v)
    return c+(p-c+v)%(v*2)-v
end

function Ocean.new(width,height,cx,cy)
    local background=node("water","liquid","liquid_flow")
    place(background,width*.5,height*.5,width,height)
    gui.set_material(background,"liquid")
    return setmetatable({width=width,height=height,cx=cx,cy=cy,background=background,
        particles={},depths={},wakes={},wake_nodes={},tracking={},points={},time=0,tick=0},Ocean)
end

function Ocean:reset(seed,x,y,scale,elapsed)
    self.seed,self.elapsed=seed,elapsed
    self.time,self.tick=0,0
    self.tracking,self.wakes={},{}
    local random=Random.new(seed+710917)
    for i=1,MOTES do
        local level=i<=60 and 1 or i<=90 and 2 or 3
        local depth=DEPTH[level]
        local item=self.particles[i]
        if not item then
            item = {node=node("deepwater","water_details","water_haze")}
            if level==3 then item.top=node("water_surface","water_details","water_haze") end
            self.particles[i]=item
        end
        item.level,item.depth=level,depth
        local sx,sy=self.width*.65/(scale*depth),self.height*.70/(scale*depth)
        item.x,item.y=x+random:randf_range(-sx,sx),y+random:randf_range(-sy,sy)
        item.r=random:randf_range(.9,2.5)
        item.phase=random:randf()*TAU
        item.vx,item.vy=flow(item.x,item.y,0)
        local size=item.r*(level==1 and 1.5 or level==2 and 6 or 14)
        gui.set_size(item.node,vmath.vector3(size,size,0))
        local color=level==1 and vmath.vector4(.53,.8,.74,.15)
            or level==2 and vmath.vector4(.50,.87,.81,.22) or vmath.vector4(.57,.9,.87,.09)
        gui.set_color(item.node,color)
        if item.top then
            local top_size=item.r*11
            gui.set_size(item.top,vmath.vector3(top_size,top_size,0))
            gui.set_color(item.top,vmath.vector4(.48,.87,.85,.055))
        end
    end
    for i=1,DEEP_BODIES do
        local item=self.depths[i]
        if not item then
            item={node=node("deepwater","water_details","water_far_body")}
            gui.set_color(item.node,vmath.vector4(.015,.085,.11,.28))
            self.depths[i]=item
        end
        item.phase=random:randf()*TAU
        item.x=x+random:randf_range(-self.width,self.width)/(scale*.38)
        item.y=y+random:randf_range(-self.height,self.height)/(scale*.38)
        item.r=random:randf_range(60,150)
    end
end

function Ocean:track(key,p,radius)
    local previous=self.tracking[key]
    if not previous then self.tracking[key]={x=p.x,y=p.y,distance=0,tick=self.tick};return end
    previous.tick=self.tick
    local dx,dy=p.x-previous.x,p.y-previous.y
    previous.x,previous.y=p.x,p.y
    local squared=dx*dx+dy*dy
    if self.dt<=0 or squared>=10000 then return end
    local distance=math.sqrt(squared)
    previous.distance=previous.distance+distance
    if distance/self.dt<10 or previous.distance<=radius*.7 then return end
    previous.distance=0
    if #self.wakes>=MAX_WAKES then table.remove(self.wakes,1) end
    local vx,vy=flow(p.x,p.y,self.time)
    self.wakes[#self.wakes+1]={x=p.x,y=p.y,r=radius,age=0,angle=-math.deg(math.atan2(dy,dx)),vx=vx,vy=vy}
end

function Ocean:begin(sim,x,y,scale)
    local elapsed=sim.elapsed or 0
    if self.sim~=sim or self.seed~=sim.world.seed_value then
        self:reset(sim.world.seed_value,x,y,scale,elapsed)
        self.sim=sim
    end
    local dt=math.min(.1,math.max(0,elapsed-self.elapsed))
    self.elapsed,self.dt=elapsed,dt
    self.time,self.tick=self.time+dt,self.tick+1
    gui.set_enabled(self.background,true)
    gui.set(self.background,fluid_view,vmath.vector4(x-self.cx/scale,y-(self.height-self.cy)/scale,self.width/scale,self.height/scale))
    gui.set(self.background,fluid_stage,vmath.vector4(self.time,sim.world.boundary_phase,sim.world.w*sim.world.tile_size*.5,0))
    return dt
end

local function show_point(states,n,x,y,w,h,margin)
    local visible=x>=-margin and x<=w+margin and y>=-margin and y<=h+margin
    local state=states[n]
    if not state then state={position=vmath.vector3(),visible=false};states[n]=state end
    if state.visible~=visible then
        gui.set_enabled(n,visible)
        state.visible=visible
    end
    if visible and (state.position.x~=x or state.position.y~=y) then
        state.position.x,state.position.y=x,y
        gui.set_position(n,state.position)
    end
    return visible
end

function Ocean:draw(x,y,scale)
    local dt,tick,time=self.dt,self.tick,self.time
    local w,h=self.width,self.height
    for _,item in ipairs(self.depths) do
        item.x=wrap(item.x,x,w*.80/(scale*.38))
        item.y=wrap(item.y,y,h*.85/(scale*.38))
        local tx,ty=self.cx+(item.x-x)*scale*.38,self.cy-(item.y-y)*scale*.38
        local radius=item.r*(.90+math.sin(time*.12+item.phase)*.06)
        if show_point(self.points,item.node,tx,ty,w,h,radius*1.6) then
            gui.set_rotation(item.node,vmath.vector3(0,0,math.deg(item.phase+math.sin(time*.07+item.phase)*.05)))
            gui.set_size(item.node,vmath.vector3(radius*2,radius*1.4,0))
        end
    end
    for i,item in ipairs(self.particles) do
        if (tick+i)%CURRENT_DIVISOR==0 then item.vx,item.vy=flow(item.x,item.y,time) end
        local depth=item.depth
        item.x=wrap(item.x+item.vx*dt*depth,x,w*.65/(scale*depth))
        item.y=wrap(item.y+item.vy*dt*depth,y,h*.70/(scale*depth))
        local tx,ty=self.cx+(item.x-x)*scale*depth,self.cy-(item.y-y)*scale*depth
        show_point(self.points,item.node,tx,ty,w,h,item.r*8)
        if item.top then show_point(self.points,item.top,tx,ty,w,h,item.r*8) end
    end
    for i=#self.wakes,1,-1 do
        local wake=self.wakes[i]
        wake.age=wake.age+dt
        if wake.age>=WAKE_LIFE then table.remove(self.wakes,i)
        else
            if (tick+i)%4==0 then wake.vx,wake.vy=flow(wake.x,wake.y,time) end
            wake.x,wake.y=wake.x+wake.vx*dt*.35,wake.y+wake.vy*dt*.35
        end
    end
    for i,wake in ipairs(self.wakes) do
        local n=self.wake_nodes[i]
        if not n then n=node("deepwater","water_details","water_wake");self.wake_nodes[i]=n end
        local age=wake.age/WAKE_LIFE
        local radius=wake.r*scale*(.65+age*.50)
        if show_point(self.points,n,self.cx+(wake.x-x)*scale,self.cy-(wake.y-y)*scale,w,h,radius*3) then
            gui.set_size(n,vmath.vector3(radius*(.9+age*1.35),radius*(2.7+age*3.1),0))
            gui.set_rotation(n,vmath.vector3(0,0,wake.angle))
            gui.set_color(n,vmath.vector4(.45,.8,.76,.22*(1-age)^2))
        end
    end
    for i=#self.wakes+1,#self.wake_nodes do
        local n=self.wake_nodes[i]
        local state=self.points[n]
        if state and state.visible then gui.set_enabled(n,false);state.visible=false end
    end
    if tick%30==0 then
        for id,item in pairs(self.tracking) do
            if tick-item.tick>30 then self.tracking[id]=nil end
        end
    end
end

function Ocean:hide()
    gui.set_enabled(self.background,false)
    self.points={}
    for _,item in ipairs(self.particles) do
        gui.set_enabled(item.node,false)
        if item.top then gui.set_enabled(item.top,false) end
    end
    for _,item in ipairs(self.depths) do gui.set_enabled(item.node,false) end
    for _,n in ipairs(self.wake_nodes) do gui.set_enabled(n,false) end
end

return Ocean
