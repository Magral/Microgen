local Art = require "main.arena_art"
local BodyArt = require "main.body_art"
local Tissue = require "main.tissue_motion"
local Anatomy = require "main.anatomy"
local Fixture = require "main.arena_data"
local Genome = require "main.run.genome"

local Scene = {}
Scene.__index = Scene
local WIDTH, HEIGHT = Fixture.size[1], Fixture.size[2]
local CX, CY = WIDTH / 2, HEIGHT * .49
local GREEN = vmath.vector4(.39,.91,.64,1)
local PINK = vmath.vector4(1,.46,.52,1)
local ALERT = vmath.vector4(1,.53,.42,.58)
local WHITE = vmath.vector4(1,1,1,1)
local GOLD = vmath.vector4(1,.83,.45,1)
local ICE = vmath.vector4(.63,.92,1,1)
local FLUID_SIDE = 1024

local FRAMES = {
    prey = {"actor_00", "actor_03", "actor_10"},
    hunter = {"actor_01", "actor_07", "actor_14"},
    spitter = {"actor_02", "actor_06", "actor_12"},
    miniboss = {"actor_18"},
    boss = {"actor_18"},
}

local EFFECT_COLOR = {
    enemy_toxin = PINK, spore = vmath.vector4(.70,.51,.98,.7),
    poison = vmath.vector4(.66,.9,.33,.61), acid = GREEN,
    electric = ICE, barrier = ICE, assimilate = GREEN, pulse = ICE,
    enzymes = GOLD, infection = vmath.vector4(.68,1,.37,.8),
    tentacle = PINK, division = ICE, trail = GREEN,
}

local function position(node,x,y)
    gui.set_position(node,vmath.vector3(x,y,0))
end

local function size(node,w,h)
    gui.set_size(node,vmath.vector3(w,h,0))
end

local function box(layer)
    local node = gui.new_box_node(vmath.vector3(),vmath.vector3())
    gui.set_layer(node,layer)
    return node
end

local function sprite(slot, texture, frame)
    if slot.frame == frame and slot.texture == texture then return end
    gui.set_texture(slot.node,texture)
    gui.play_flipbook(slot.node,frame)
    slot.frame, slot.texture = frame,texture
end

local function pool(layer, label)
    return {layer=layer, slots={}, count=0, label=label}
end

local function take(group)
    local index = group.count + 1
    group.count = index
    local slot = group.slots[index]
    if not slot then
        local node
        if group.label then
            node = gui.new_text_node(vmath.vector3(),"")
            gui.set_font(node,"interface")
            gui.set_layer(node,group.layer)
        else
            node = box(group.layer)
        end
        slot = {node=node}
        group.slots[index] = slot
    end
    if slot.enabled==false then gui.set_enabled(slot.node,true) end
    slot.enabled=true
    return slot
end

local function finish(group)
    for index=group.count+1,#group.slots do
        local slot = group.slots[index]
        if slot.enabled then gui.set_enabled(slot.node,false) end
        slot.enabled=false
    end
    group.count = 0
end

local function frame_index(frame)
    return tonumber(frame:match("^actor_(%d+)$"))
end

local function color_at(alpha, color)
    return vmath.vector4(color.x,color.y,color.z,alpha)
end

local function smoothstep(lo,hi,value)
    local t=math.max(0,math.min(1,(value-lo)/(hi-lo)))
    return t*t*(3-2*t)
end

local function feeding_pose(sim,item,progress)
    local theta=item.entry_angle or 0
    local entry=item.entry_distance or item.r or 0
    local crossing=smoothstep(.12,.72,progress)
    local depth=math.min(sim:body_radius()*.32,entry*.35)
    local distance=entry+(depth-entry)*crossing
    local dissolve=smoothstep(.55,1,progress)
    return {x=sim.player.x+math.cos(theta)*distance,y=sim.player.y+math.sin(theta)*distance},1-dissolve*.96,1-dissolve
end

local function visibly_inside(x,y,padding)
    return x >= -padding and y >= -padding and x <= WIDTH+padding and y <= HEIGHT+padding
end

function Scene.new(tissue_atlas)
    return setmetatable({
        atlas=tissue_atlas, anatomy=Anatomy.new("anatomy"),
        fluid=pool("water"), walls=pool("substrate"), landmarks=pool("substrate"),
        fields=pool("fields"), organisms=pool("organisms"), objects=pool("objects"),
        effects=pool("effects"), labels=pool("feedback",true),
        player_pose=0, scale=1,
    },Scene)
end

function Scene:project(p)
    return CX+(p.x-self.x)*self.scale, CY-(p.y-self.y)*self.scale
end

function Scene:render_ground(sim)
    local world, scale = sim.world, self.scale
    local time = sim.elapsed or 0
    local side = FLUID_SIDE
    local scroll_x = self.x*.28 + time*2.4
    local scroll_y = self.y*.28 + time*1.7
    local tile_x, tile_y = scroll_x%side, scroll_y%side
    for row=0,math.ceil(HEIGHT/side) do
        for col=0,math.ceil(WIDTH/side) do
            local slot = take(self.fluid)
            sprite(slot,"terrain","fluid")
            position(slot.node,side*(col+.5)-tile_x, HEIGHT-side*(row+.5)+tile_y)
            size(slot.node,side+.4,side+.4)
        end
    end
    local tile = world.tile_size
    local x0 = math.max(0, math.floor((self.x-CX/scale-110)/tile))
    local x1 = math.min(world.w-1, math.floor((self.x+(WIDTH-CX)/scale+110)/tile))
    local y0 = math.max(0, math.floor((self.y-(HEIGHT-CY)/scale-110)/tile))
    local y1 = math.min(world.h-1, math.floor((self.y+CY/scale+110)/tile))
    for row=y0,y1 do
        for col=x0,x1 do
            if world.cells[row*world.w+col+1] == 1 then
                local wx, wy = (col+.5)*tile, (row+.5)*tile
                local index = (col*37+row*71+col*row*13) % 4
                local biome = world:biome(wx,wy)
                local slot = take(self.walls)
                sprite(slot,"terrain","wall_"..(biome-1).."_"..index)
                position(slot.node, CX+(wx-self.x)*scale, CY-(wy-self.y)*scale)
                if slot.scale~=scale then
                    size(slot.node,208*scale,208*scale)
                    slot.scale=scale
                end
            end
        end
    end
    for _,group in ipairs({world.nests, world.colonies}) do
        for _,mark in ipairs(group) do
            local x,y = self:project(mark.pos)
            if visibly_inside(x,y,100) then
                local slot = take(self.landmarks)
                sprite(slot,"cells","shield")
                position(slot.node,x,y)
                size(slot.node,tile*scale,tile*scale)
                gui.set_color(slot.node, mark.used and vmath.vector4(.42,.52,.56,.32)
                    or mark.stock and vmath.vector4(.39,1,.86,.70) or vmath.vector4(.94,.56,.32,.65))
            end
        end
    end
end

function Scene:draw_effect(group, frame, p, radius, color, angle)
    local x,y = self:project(p)
    local extent = radius*self.scale
    if not visibly_inside(x,y,extent) then return end
    local slot = take(group)
    sprite(slot,"cells",frame)
    position(slot.node,x,y)
    size(slot.node,extent*2,extent*2)
    gui.set_color(slot.node,color)
    gui.set_rotation(slot.node,vmath.vector3(0,0,angle or 0))
end

function Scene:draw_number(p, message, color, scale)
    local x,y = self:project(p)
    if not visibly_inside(x,y,50) then return end
    local slot = take(self.labels)
    gui.set_text(slot.node,message)
    gui.set_color(slot.node,color)
    gui.set_scale(slot.node,vmath.vector3(scale,scale,1))
    position(slot.node,x,y)
end

function Scene:draw_ray(origin,angle,length,color,thickness)
    local x,y=self:project(origin)
    local distance=length*self.scale
    local slot=take(self.effects)
    sprite(slot,"cells","speck")
    position(slot.node,x+math.cos(angle)*distance/2,y-math.sin(angle)*distance/2)
    size(slot.node,distance,thickness)
    gui.set_rotation(slot.node,vmath.vector3(0,0,-math.deg(angle)))
    gui.set_color(slot.node,color)
end

function Scene:draw_body(sim, actor, is_player, serial)
    local radius = is_player and sim:body_radius() or actor.r
    local options = FRAMES[actor.kind] or FRAMES.hunter
    local variant = (actor.id or serial or 1) % #options + 1
    local genome=is_player and sim.player_genome or actor.genome
    local frame, dimensions, source_radius
    if is_player or (genome and actor.kind~="boss" and actor.kind~="miniboss") then
        local family=genome and genome.family or 0
        frame, dimensions, source_radius="body_"..family,BodyArt[family+1],108
    else
        frame=options[variant]
        dimensions, source_radius=Art[frame],Fixture.actors[frame_index(frame)+1].radius/1.18
    end
    local body_position, shrink, opacity=actor.pos,1,1
    if actor.captured then
        body_position,shrink,opacity=feeding_pose(sim,actor,actor.engulf or 0)
    end
    local x,y = self:project(body_position)
    if not visibly_inside(x,y,radius*2*self.scale) then return end
    local slot = take(self.organisms)
    if slot.frame ~= frame then
        sprite(slot,"cells",frame)
        slot.pose = Tissue.attach(self.atlas,slot.node,frame)
    end
    local stretch = self.scale*radius/source_radius*shrink
    gui.set_color(slot.node,opacity==1 and WHITE or color_at(opacity,WHITE))
    local velocity = actor.vel or actor.velocity or {x=0,y=0}
    local phase = (sim.elapsed or 0)+(actor.phase or 0)
    local angle = -(actor.facing or 0)
    local facing_x, facing_y = math.cos(angle), math.sin(angle)
    local drift_x = (velocity.x*facing_x-velocity.y*facing_y)/145
    local drift_y = (-velocity.x*facing_y-velocity.y*facing_x)/145
    local overscan = slot.pose and Tissue.OVERSCAN or 1
    position(slot.node,x,y)
    size(slot.node,dimensions[1]*stretch*overscan,dimensions[2]*stretch*overscan)
    gui.set_rotation(slot.node,vmath.vector3(0,0,math.deg(angle)))
    local bite = is_player and math.min(1,sim.bite_flash or 0) or 0
    local infected = (actor.infection_time or actor.infect or 0)>0
    if is_player then
        local state=sim.tissue_pigment
        local stamp=state.density[1]
        if self.pigment_state~=state or self.pigment_stamp~=stamp then
            self.pigment_state,self.pigment_stamp=state,stamp
            self.player_pigment="#"..sim:body_color()
        end
    elseif slot.pigment_genome~=genome then
        slot.pigment_genome=genome
        slot.pigment_hex=genome and ("#"..Genome.colors(genome)[1])
    end
    local pigment=infected and "#bfdb6b" or (is_player and self.player_pigment or slot.pigment_hex)
    Tissue.update(slot.pose,phase,drift_x,drift_y,(bite>0 or actor.captured) and 1 or 0,0,
        bite,infected and .56 or (is_player and .67 or .40),pigment)
    if not is_player and not actor.captured and actor.max_hp and actor.hp < actor.max_hp then
        local bar = take(self.effects)
        sprite(bar,"cells","speck")
        local bx, by = x, y+radius*self.scale+20
        position(bar.node,bx,by)
        size(bar.node,math.max(2, actor.hp/actor.max_hp * radius*self.scale),5)
        gui.set_color(bar.node,PINK)
        gui.set_rotation(bar.node,vmath.vector3())
    end
    if not is_player and actor.max_hp and actor.hp>0 and not actor.captured then
        if actor.kind=="boss" and (actor.boss_windup or 0)>0 then
            local pattern=sim:boss_attack()
            for i=1,pattern.count do
                local angle=(actor.boss_angle or actor.facing or 0)+(i-1-(pattern.count-1)/2)*pattern.spread
                self:draw_ray(actor.pos,angle,390,ALERT,10)
            end
        elseif actor.kind=="boss" and (actor.boss_exposed or 0)>0 then
            self:draw_effect(self.effects,"shield",actor.pos,radius*1.24,GOLD,phase*77)
        elseif actor.max_hp and actor.hp and actor.kind~="boss" and not actor.active then
            local interaction=sim:interaction(actor)
            if interaction.eligible then
                self:draw_effect(self.effects,"shield",actor.pos,radius*1.25,vmath.vector4(.47,1,.68,.52),phase*22)
            end
        end
    end
end

function Scene:render(sim, breakup_time)
    self.x,self.y = sim.player.x,sim.player.y
    self.scale = math.min(WIDTH/1280, HEIGHT/720) * sim:view_zoom()
    self:render_ground(sim)
    local time = sim.elapsed or 0
    for _,field in ipairs(sim.fields) do
        self:draw_effect(self.fields,"field",field.pos,field.r*1.18,
            EFFECT_COLOR[field.kind] or GREEN,time*8)
    end
    for _,pickup in ipairs(sim.pickups) do
        local p,shrink,opacity=pickup.pos,1,1
        if pickup.captured then p,shrink,opacity=feeding_pose(sim,pickup,pickup.progress) end
        local tint=pickup.type=="heal" and GREEN or pickup.type=="core" and GOLD or ICE
        self:draw_effect(pickup.captured and self.effects or self.objects,"speck",p,
            (pickup.type=="heal" and 13 or 8)*shrink,color_at(opacity,tint),0)
    end
    for _,fragment in ipairs(sim.remains) do
        local p,shrink,opacity=fragment.pos,1,1
        if fragment.captured then p,shrink,opacity=feeding_pose(sim,fragment,fragment.progress) end
        local tint=(fragment.quality or 0) >= 2 and GOLD or PINK
        self:draw_effect(fragment.captured and self.effects or self.objects,"speck",p,
            (fragment.r or 9)*shrink,color_at(opacity,tint),(fragment.progress or 0)*80)
    end
    for _,cyst in ipairs(sim.cysts) do
        self:draw_effect(self.objects,"surge",cyst.pos,23,GOLD,time*20)
    end
    for index,resident in ipairs(sim.residents) do
        if not resident.dead and not resident.active then
            self:draw_body(sim,resident,false,index)
        end
    end
    for index,actor in ipairs(sim.enemies) do self:draw_body(sim,actor,false,index) end
    local player = self.player or {}
    self.player = player
    player.pos, player.vel, player.facing = sim.player,sim.player_velocity,sim.facing
    player.kind = "prey"
    self:draw_body(sim, player,true)
    gui.set_enabled(self.anatomy,true)
    Anatomy.update(self.anatomy,sim,CX,CY,sim:body_radius()*self.scale)
    for _,shot in ipairs(sim.shots) do
        self:draw_effect(self.effects,"speck",shot.pos,8,shot.hostile and PINK or ICE,0)
    end
    for _,fx in ipairs(sim.effects) do
        if fx.pos then
            local q = math.max(0,math.min(1,(fx.life or .2)/(fx.max or 1)))
            if fx.type=="damage" or fx.type=="heal" then
                local heal = fx.type=="heal"
                local value = fx.amount or 0
                local p = {x=fx.pos.x,y=fx.pos.y-(1-q)*44-25}
                self:draw_number(p,(heal and "+" or "−")..string.format("%.1f",value),heal and GREEN or PINK,.8)
            else
            local rgb = EFFECT_COLOR[fx.type] or ICE
            local radius = fx.r or 22
            if fx["end"] and (fx.type == "lash" or fx.type == "tentacle" or fx.type == "electric") then
                local finish_point = fx["end"]
                for i=1,4 do
                    local t = i*.20
                    local point = {x=fx.pos.x+(finish_point.x-fx.pos.x)*t,y=fx.pos.y+(finish_point.y-fx.pos.y)*t}
                    self:draw_effect(self.effects,"speck",point,5,color_at(q,rgb),0)
                end
            end
            self:draw_effect(self.effects,"surge",fx.pos,radius*(1.13-q*.36),color_at(q*.8,rgb),time*34)
            end
        end
    end
    if breakup_time and sim.boss_breakup.pos then
        local data=sim.boss_breakup
        local phase=math.min(1,breakup_time/1.55)
        self:draw_effect(self.effects,"surge",data.pos,data.radius*(.9+phase*2.1),color_at((1-phase)*.95,GOLD),phase*70)
        for i=1,18 do
            local angle=i*2.39996
            local distance=data.radius*(.1+i%4*.12+phase*(.88+i%5*.22))
            local fragment={x=data.pos.x+math.cos(angle)*distance,y=data.pos.y+math.sin(angle)*distance}
            self:draw_effect(self.effects,"speck",fragment,math.max(1,(16+i%4*5)*(1-phase)),
                color_at(1-phase,i%3==0 and ICE or GOLD),phase*155+angle)
        end
    end
    for _,group in ipairs({self.fluid,self.walls,self.landmarks,self.fields,self.organisms,self.objects,self.effects,self.labels}) do finish(group) end
end

function Scene:hide()
    gui.set_enabled(self.anatomy,false)
    for _,group in ipairs({self.fluid,self.walls,self.landmarks,self.fields,self.organisms,self.objects,self.effects,self.labels}) do finish(group) end
end

return Scene
