local Art = require "main.arena_art"
local BodyArt = require "main.body_art"
local Tissue = require "main.tissue_motion"
local Anatomy = require "main.anatomy"
local Fixture = require "main.arena_data"
local Genome = require "main.run.genome"
local Ocean = require "main.run.ocean"
local Effects = require "main.run.effects_view"

local Scene = {}
Scene.__index = Scene
local WIDTH, HEIGHT = Fixture.size[1], Fixture.size[2]
local CX, CY = WIDTH / 2, HEIGHT * .49
local PINK = vmath.vector4(1,.46,.52,1)
local WHITE = vmath.vector4(1,1,1,1)
local WORLD_GRAIN = 2147483647
local TAU = 2*math.pi

local FRAMES = {
    prey = {"actor_00", "actor_03", "actor_10"},
    hunter = {"actor_01", "actor_07", "actor_14"},
    spitter = {"actor_02", "actor_06", "actor_12"},
    miniboss = {"actor_18"},
    boss = {"actor_18"},
}

local function grain(x,y,seed,salt)
    local high=math.floor(seed/65536)
    local seed_term=(seed%65536*83492791+((high*83492791)%WORLD_GRAIN)*65536)%WORLD_GRAIN
    local n=(x*73856093+y*19349663+seed_term+salt*15485863)%WORLD_GRAIN
    return ((n*48271+12820163)%WORLD_GRAIN)/WORLD_GRAIN
end

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
        atlas=tissue_atlas, anatomy=Anatomy.new("anatomy"), ocean=Ocean.new(WIDTH,HEIGHT,CX,CY),
        walls=pool("substrate"), bed=pool("bed"), landmarks=pool("substrate"),
        fields=pool("fields"), organisms=pool("organisms"), fragments=pool("organisms"), objects=pool("objects"),
        effects=pool("effects"), labels=pool("world_labels",true),
        motions=setmetatable({},{__mode="k"}), scale=1,
    },Scene)
end

function Scene:project(p)
    return CX+(p.x-self.x)*self.scale, CY-(p.y-self.y)*self.scale
end

function Scene:terrain_frame(world,col,row)
    if self.terrain_source~=world then
        self.terrain_source,self.frames=world,{}
    end
    local id=row*world.w+col+1
    local entry=self.frames[id]
    if entry~=nil then return entry end
    local solid=world.cells[id]==1
    local kind
    if solid then kind="wall"
    else
        local growth=grain(math.floor(col/3),math.floor(row/3),world.seed_value,1)<.43
        local fibril=grain(col,row,world.seed_value,2)<.095
        kind=growth and (fibril and "bed_fibril" or "bed") or (fibril and "fibril" or false)
    end
    if kind then
        local x,y=(col+.5)*world.tile_size,(row+.5)*world.tile_size
        local biome=world:biome(x,y)
        local phase=math.floor(grain(col,row,world.seed_value,0)*4+.5)%4
        entry={frame=kind.."_"..(biome-1).."_"..phase,x=x,y=y,solid=solid}
    else entry=false end
    self.frames[id]=entry
    return entry
end

function Scene:render_ground(sim)
    local world, scale = sim.world, self.scale
    local tile = world.tile_size
    local x0 = math.max(0, math.floor((self.x-CX/scale-110)/tile))
    local x1 = math.min(world.w-1, math.floor((self.x+(WIDTH-CX)/scale+110)/tile))
    local y0 = math.max(0, math.floor((self.y-(HEIGHT-CY)/scale-110)/tile))
    local y1 = math.min(world.h-1, math.floor((self.y+CY/scale+110)/tile))
    for row=y0,y1 do
        for col=x0,x1 do
            local entry=self:terrain_frame(world,col,row)
            if entry then
                local slot=take(entry.solid and self.walls or self.bed)
                sprite(slot,"terrain",entry.frame)
                local x,y=CX+(entry.x-self.x)*scale,CY-(entry.y-self.y)*scale
                if slot.x~=x or slot.y~=y then
                    position(slot.node,x,y)
                    slot.x,slot.y=x,y
                end
                if slot.scale~=scale then
                    size(slot.node,208*scale,208*scale)
                    slot.scale=scale
                end
            end
        end
    end
    local time=self.visual_time
    for _,nest in ipairs(world.nests) do
        local x,y=self:project(nest.pos)
        if not nest.used and visibly_inside(x,y,60*scale) then
            self:draw_combat(self.landmarks,"ring",nest.pos,113,113,vmath.vector4(.70,.49,.91,.35),0)
            for index=0,4 do
                local a=index*TAU/5+time*.15
                local p={x=nest.pos.x+math.cos(a)*22,y=nest.pos.y+math.sin(a)*22}
                self:draw_combat(self.landmarks,"skin",p,29,29,vmath.vector4(.66,.47,.85,.62),a)
            end
        end
    end
    for _,colony in ipairs(world.colonies) do
        local x,y=self:project(colony.pos)
        if visibly_inside(x,y,152*scale) then
            self:draw_combat(self.landmarks,"ring",colony.pos,339,339,vmath.vector4(.35,.8,.7,.13),0)
            for index=0,7 do
                local a=index*TAU/8+math.sin(time*.4)*.05
                local p={x=colony.pos.x+math.cos(a)*35,y=colony.pos.y+math.sin(a)*35}
                self:draw_combat(self.landmarks,"skin",p,64,64,vmath.vector4(.27,.55,.52,.56),a)
            end
            self:draw_combat(self.landmarks,"skin",colony.pos,72,72,vmath.vector4(.51,.86,.71,.58),time*.24)
            self:draw_number({x=colony.pos.x,y=colony.pos.y+80},"КОЛОНИЯ",vmath.vector4(.51,.80,.74,.80),.62)
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

function Scene:set_labels_visible(visible)
    self.hide_labels = not visible
    if self.hide_labels then
        self.labels.count = 0
        finish(self.labels)
    end
end

function Scene:draw_number(p, message, color, scale)
    if self.hide_labels then return end
    local x,y = self:project(p)
    if not visibly_inside(x,y,50) then return end
    local slot = take(self.labels)
    gui.set_text(slot.node,message)
    gui.set_color(slot.node,color)
    gui.set_scale(slot.node,vmath.vector3(scale,scale,1))
    position(slot.node,x,y)
end

function Scene:draw_atlas(group,texture,frame,p,width,height,color,angle)
    local x,y=self:project(p)
    width,height=width*self.scale,height*self.scale
    if not visibly_inside(x,y,(width+height)*.5) then return end
    local slot=take(group)
    sprite(slot,texture,frame)
    position(slot.node,x,y)
    size(slot.node,width,height)
    gui.set_color(slot.node,color)
    gui.set_rotation(slot.node,vmath.vector3(0,0,-math.deg(angle or 0)))
end

function Scene:draw_combat(group,frame,p,width,height,color,angle)
    self:draw_atlas(group,"combat",frame,p,width,height,color,angle)
end

local function feeding_contact(sim)
    local x,y,total=0,0,0
    for _,group in ipairs({sim.remains,sim.pickups,sim.enemies}) do
        for _,item in ipairs(group) do
            if item.captured and item.entry_angle then
                local progress=item.engulf or item.progress or 0
                local weight=math.sin(math.pi*math.min(1,progress/.76))
                local angle=item.entry_angle-sim.facing
                x,y=x+math.cos(angle)*weight,y-math.sin(angle)*weight
                total=total+1
            end
        end
    end
    local bite=sim.bite_flash or 0
    if bite>0 then x=x+bite;total=total+1 end
    if total==0 then return 0,0,0 end
    local length=math.sqrt(x*x+y*y)
    if length<.0001 then return 0,0,0 end
    return x/length,y/length,math.min(1,length/total)
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
    local phase = self.visual_time
    local motion=Tissue.motion(self.motions[actor],self.dt,actor.pos.x,actor.pos.y,genome,is_player and sim.facing or nil)
    self.motions[actor]=motion
    self.ocean:track(actor,actor.pos,radius)
    local angle = is_player and sim.facing or ((genome and genome.rotation or 0)+Tissue.turn(motion))
    local overscan = slot.pose and Tissue.OVERSCAN or 1
    position(slot.node,x,y)
    size(slot.node,dimensions[1]*stretch*overscan,dimensions[2]*stretch*overscan)
    gui.set_rotation(slot.node,vmath.vector3(0,0,-math.deg(angle)))
    local cx,cy,bite=0,0,0
    if is_player then cx,cy,bite=feeding_contact(sim) end
    local infected = (actor.infection_time or actor.infect or 0)>0
    if is_player then
        local state=sim.tissue_pigment
        local stamp=state.mass
        if self.pigment_state~=state or self.pigment_stamp~=stamp then
            self.pigment_state,self.pigment_stamp=state,stamp
            self.player_pigment="#"..sim:body_color()
        end
    elseif slot.pigment_genome~=genome then
        slot.pigment_genome=genome
        slot.pigment_hex=genome and ("#"..Genome.colors(genome)[1])
    end
    local hp=is_player and sim.hp or actor.hp
    local maxhp=is_player and sim.max_hp or actor.max_hp
    local health=hp and hp/math.max(1,maxhp) or 1
    local pigment=infected and "#bfdb6b" or (is_player and self.player_pigment or slot.pigment_hex)
    local relative=math.sqrt((actor.pos.x-self.x)^2+(actor.pos.y-self.y)^2)
    if not is_player and not actor.captured and radius>sim:body_radius()*2
            and (actor.boss_windup or 0)<=0 and (actor.boss_exposed or 0)<=0 then
        local threshold=sim:body_radius()*6+radius
        local haze=smoothstep(threshold*.9,threshold*1.45,relative)
        gui.set_color(slot.node,vmath.vector4(1-haze*.72,1-haze*.62,1-haze*.53,opacity*(1-haze*.30)))
    else gui.set_color(slot.node,opacity==1 and WHITE or color_at(opacity,WHITE)) end
    Tissue.update(slot.pose,motion,phase,angle,dimensions[1]/(2*source_radius),dimensions[2]/(2*source_radius),
        cx,cy,bite,infected and .55 or (is_player and .67 or .4),pigment,health,is_player and self.reaction or 0,
        not is_player and radius*self.scale<32)
    if not is_player and not actor.captured and actor.max_hp and actor.hp < actor.max_hp then
        local bar = take(self.effects)
        sprite(bar,"cells","speck")
        local bx, by = x, y+radius*self.scale+20
        position(bar.node,bx,by)
        size(bar.node,math.max(2, actor.hp/actor.max_hp * radius*self.scale),5)
        gui.set_color(bar.node,PINK)
        gui.set_rotation(bar.node,vmath.vector3())
    end
    if not is_player and not actor.captured then
        if actor.kind=="boss" then Effects.draw_boss(self,sim,actor,phase) end
        if infected then Effects.draw_infection(self,actor,phase) end
        if (actor.enzyme_time or 0)>0 then Effects.draw_infection(self,actor,phase,true) end
        if actor.max_hp and actor.hp>0 and actor.kind and actor.kind~="boss" then
            local interaction=sim:interaction(actor)
            if interaction.eligible then
                self:draw_effect(self.effects,"shield",actor.pos,radius*1.25,vmath.vector4(.47,1,.68,.52),phase*22)
            end
        end
    end
    return slot.pose
end

function Scene:render(sim, breakup_time)
    self.x,self.y=sim.player.x,sim.player.y
    local target=math.min(WIDTH/1280,HEIGHT/720)*sim:view_zoom()
    if self.sim~=sim or self.world~=sim.world then
        self.sim,self.world=sim,sim.world
        self.scale,self.visual_time,self.elapsed,self.reaction=target,0,sim.elapsed,0
        self.motions=setmetatable({},{__mode="k"})
        self.clones={}
    end
    local dt=math.min(.1,math.max(0,sim.elapsed-self.elapsed))
    self.elapsed,self.dt=sim.elapsed,dt
    self.visual_time=self.visual_time+dt
    if math.abs(target-self.scale)>0.0001 then
        self.scale=self.scale+(target-self.scale)*(1-math.exp(-dt*2))
    end
    self.ocean:begin(sim,self.x,self.y,self.scale)
    self:render_ground(sim)
    local time=self.visual_time
    self.reaction=math.max(0,self.reaction-dt*1.4)
    local rich=0
    for _,field in ipairs(sim.fields) do
        local x,y=self:project(field.pos)
        if visibly_inside(x,y,field.r*self.scale*1.2) then
            local detailed=rich<8 and (field.pos.x-self.x)^2+(field.pos.y-self.y)^2<440^2
            if detailed then rich=rich+1 end
            Effects.draw_field(self,field,time,not detailed)
        end
    end
    for _,pickup in ipairs(sim.pickups) do
        local p,shrink,opacity=pickup.pos,1,1
        if pickup.captured then p,shrink,opacity=feeding_pose(sim,pickup,pickup.progress)
        else p={x=p.x,y=p.y+math.sin(time*2+pickup.id)*2} end
        local value=pickup.type
        local diameter=(value=="core" and 25 or value=="heal" and 20 or value:find("extension") and 29 or 17)*shrink
        self:draw_atlas(pickup.captured and self.effects or self.objects,"collectibles",value,p,
            diameter,diameter,opacity==1 and WHITE or color_at(opacity,WHITE),0)
    end
    for _,fragment in ipairs(sim.remains) do
        local p,shrink,opacity=fragment.pos,1,1
        if fragment.captured then p,shrink,opacity=feeding_pose(sim,fragment,fragment.progress) end
        local quality=fragment.quality or 0
        if fragment.piece_count and fragment.genome then
            local family=math.max(0,math.min(#BodyArt-1,fragment.genome.family or 0))
            local frame="body_"..family
            local dimensions=BodyArt[family+1]
            local x,y=self:project(p)
            local source_radius=fragment.body_radius or 108
            local stretch=self.scale*source_radius/108*(fragment.visual_scale or 1)*shrink
            local padding=math.max(dimensions[1],dimensions[2])*stretch*.7
            if visibly_inside(x,y,padding) then
                local slot=take(self.fragments)
                if slot.frame~=frame or not slot.pose or not slot.is_fragment or slot.fragment_id~=fragment.id then
                    slot.pose=Tissue.attach_fragment(self.atlas,slot.node,frame,
                        dimensions[1]/(2*108),dimensions[2]/(2*108),fragment.cut_angle or 0,
                        fragment.cut_half_angle or math.pi/3,quality,
                        ((fragment.id or 1)*.61803398875)%TAU,
                        "#"..Genome.colors(fragment.genome)[1])
                    slot.frame,slot.is_fragment,slot.fragment_id=frame,true,fragment.id
                end
                position(slot.node,x,y)
                size(slot.node,dimensions[1]*stretch,dimensions[2]*stretch)
                gui.set_color(slot.node,color_at(opacity,WHITE))
                gui.set_rotation(slot.node,vmath.vector3(0,0,-math.deg(fragment.rotation or 0)))
            end
        else
            local tint=quality>=3 and vmath.vector4(1,.78,.45,opacity) or quality==2 and vmath.vector4(.84,.56,.99,opacity)
                or quality==1 and vmath.vector4(.65,.79,1,opacity) or vmath.vector4(.89,.55,.64,opacity)
            local side=(fragment.r or 9)*2.8*shrink
            local shard=(fragment.part or fragment.id)%3
            self:draw_combat(fragment.captured and self.effects or self.objects,"shard_"..shard,p,
                side,side,tint,time*.24+(fragment.progress or 0)*1.4)
        end
    end
    for _,cyst in ipairs(sim.cysts) do
        if not cyst.used then
            local tier=math.max(1,math.min(3,cyst.tier or 1))
            local p,shrink,opacity=cyst.pos,1,1
            if cyst.captured then p,shrink,opacity=feeding_pose(sim,cyst,cyst.progress or 0) end
            local radius=(12+tier*3)*(1+math.sin(time*2.3+cyst.id)*.045)
            self:draw_atlas(cyst.captured and self.effects or self.objects,"collectibles","cyst_"..tier,p,
                radius*3.1*shrink,radius*3.1*shrink,color_at(opacity,WHITE),math.sin(time*.48+cyst.id)*.20)
        end
    end
    for index,resident in ipairs(sim.residents) do
        if not resident.dead and not resident.active then
            self:draw_body(sim,resident,false,index)
        end
    end
    for index,actor in ipairs(sim.enemies) do self:draw_body(sim,actor,false,index) end
    if sim.build:rank("division")>0 then
        for index,p in ipairs(sim:clone_positions()) do
            local clone=self.clones[index] or {kind="clone",id=-10000-index,r=17}
            self.clones[index]=clone
            clone.pos,clone.genome=p,sim.player_genome
            self:draw_body(sim,clone,false,index)
        end
    end
    local player = self.player or {}
    self.player = player
    player.pos, player.vel, player.facing = sim.player,sim.player_velocity,sim.facing
    player.kind = "prey"
    for _,fx in ipairs(sim.effects) do
        if fx.type=="mutation" and fx.life>fx.max-.12 then self.reaction=1 end
    end
    local pose=self:draw_body(sim,player,true)
    Anatomy.update(self.anatomy,sim,CX,CY,sim:body_radius()*self.scale,self.scale,pose,time)
    for _,shot in ipairs(sim.shots) do Effects.draw_shot(self,shot) end
    for _,fx in ipairs(sim.effects) do Effects.draw(self,sim,fx) end
    Effects.draw_player(self,sim,sim.elapsed)
    Effects.draw_damage_sources(self,sim,sim.elapsed)
    if breakup_time then Effects.draw_breakup(self,sim.boss_breakup,breakup_time,time) end
    self.ocean:draw(self.x,self.y,self.scale)
    for _,group in ipairs({self.bed,self.walls,self.landmarks,self.fields,self.organisms,self.fragments,self.objects,self.effects,self.labels}) do finish(group) end
end

function Scene:hide()
    Anatomy.hide(self.anatomy)
    self.ocean:hide()
    for _,group in ipairs({self.bed,self.walls,self.landmarks,self.fields,self.organisms,self.fragments,self.objects,self.effects,self.labels}) do finish(group) end
end

return Scene
