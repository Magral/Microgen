local Catalog = require "main.run.catalog"
local Evolution = require "main.run.evolution_rules"
local Rewards = require "main.run.rewards"
local Tissue = require "main.tissue_motion"

local Anatomy = {}
local TAU = 2 * math.pi
local OVERLAY_DIAMETER = 4.2
local properties = {}
for _, name in ipairs({"ranks", "glands", "action", "barrier", "mouth", "body", "edge", "lip", "growth", "appendages",
    "shape_12", "shape_34", "shape_56", "shape_78", "shape_rest"}) do
    properties[name] = hash("anatomy_" .. name)
end
local shape_properties = {properties.shape_12, properties.shape_34, properties.shape_56,
    properties.shape_78, properties.shape_rest}

-- Each frame uses eight Fourier pairs fitted to the alpha-64 silhouette of
-- its original 108px Godot portrait. The outer charge arc lies beyond the
-- sampled membrane. The final vector holds the mean and true frontal radius.
local SHAPES = {
    {
        vmath.vector4(0.0051, -0.0171, 0.0284, -0.0260),
        vmath.vector4(-0.0014, -0.0055, 0.1422, -0.0117),
        vmath.vector4(0.0017, -0.0061, -0.0116, -0.0152),
        vmath.vector4(-0.0004, 0.0011, -0.0014, 0.0003),
        vmath.vector4(0.8226, 0.9954, 0.0000, 0.0000),
    },
    {
        vmath.vector4(0.0058, -0.0204, 0.3186, 0.1726),
        vmath.vector4(0.0065, -0.0060, 0.0375, 0.0301),
        vmath.vector4(0.0010, -0.0007, 0.0108, -0.0231),
        vmath.vector4(-0.0013, -0.0007, 0.0165, -0.0190),
        vmath.vector4(0.7907, 1.2060, 0.0000, 0.0000),
    },
    {
        vmath.vector4(0.2109, -0.1353, -0.0361, -0.0503),
        vmath.vector4(-0.1186, -0.0395, -0.0051, 0.0062),
        vmath.vector4(-0.0086, 0.0148, 0.0004, 0.0004),
        vmath.vector4(0.0007, 0.0027, -0.0002, 0.0001),
        vmath.vector4(0.6803, 0.7245, 0.0000, 0.0000),
    },
    {
        vmath.vector4(0.0034, -0.0114, 0.0781, -0.0258),
        vmath.vector4(0.0001, -0.0006, -0.0077, -0.0316),
        vmath.vector4(-0.0145, -0.0045, 0.1363, -0.2455),
        vmath.vector4(-0.0080, -0.0076, -0.0265, 0.0156),
        vmath.vector4(0.6977, 0.8171, 0.0000, 0.0000),
    },
    {
        vmath.vector4(-0.0154, -0.0374, -0.1230, -0.0152),
        vmath.vector4(0.0518, -0.1801, -0.0072, 0.0088),
        vmath.vector4(-0.0536, 0.0175, -0.0235, -0.0415),
        vmath.vector4(0.0061, 0.0067, -0.0111, 0.0216),
        vmath.vector4(0.8187, 0.6505, 0.0000, 0.0000),
    },
    {
        vmath.vector4(0.0055, -0.0108, -0.0668, -0.0460),
        vmath.vector4(0.0040, 0.0005, 0.0038, 0.0060),
        vmath.vector4(0.0025, -0.0024, 0.0088, 0.0022),
        vmath.vector4(0.0016, 0.0046, -0.0128, 0.0082),
        vmath.vector4(0.8395, 0.7917, 0.0000, 0.0000),
    },
}

local function unit(value)
    return math.max(0, math.min(1, value))
end

local function smoothstep(lo, hi, value)
    local t = unit((value - lo) / (hi - lo))
    return t * t * (3 - 2 * t)
end

local function stage(rank)
    if rank >= 10 then return 3 end
    if rank >= 6 then return 2 end
    if rank >= 3 then return 1 end
    return 0
end

local function set(node, name, x, y, z, w)
    gui.set(node, properties[name], vmath.vector4(x, y, z, w))
end

local function new_box(layer)
    local node = gui.new_box_node(vmath.vector3(), vmath.vector3())
    if layer then gui.set_layer(node, layer) end
    gui.set_material(node, "anatomy")
    return node
end

function Anatomy.new(layer)
    return {node = new_box(layer), layer = layer, ribbons = {}, lashes = {}, points = {}}
end

local function silhouette(shape, angle)
    if math.abs(angle) < 0.00001 then return shape[5].y end
    local radius = shape[5].x
    for i = 1, 4 do
        local v, harmonic = shape[i], i * 2 - 1
        radius = radius + v.x * math.cos(angle * harmonic) + v.y * math.sin(angle * harmonic)
            + v.z * math.cos(angle * (harmonic + 1)) + v.w * math.sin(angle * (harmonic + 1))
    end
    return radius
end

local ARCH = {}
for i = 0, 16 do ARCH[i] = math.max(0, math.sin(i / 16 * math.pi)) ^ 0.85 end

local function jaw(shape, activation)
    local gap = 0.016 + activation * 0.19
    local width = 0.23 + activation * 0.18
    local center = silhouette(shape, 0) - (0.105 + activation * 0.15)
    local across_scale, fit = 1, 1
    local cone = math.tan(0.67)
    for i = 0, 16 do
        local across = math.abs((i / 16 - 0.5) * width * 2)
        if across > 0.00001 then
            across_scale = math.min(across_scale, math.max(0.03, center - gap * ARCH[i] * 1.42) * cone / across)
        end
    end
    width = width * across_scale
    for i = 0, 16 do
        local across = (i / 16 - 0.5) * width * 2
        for j = 1, 2 do
            local depth = center + (j == 1 and 0.38 or -1.42) * gap * ARCH[i]
            local length = math.sqrt(depth * depth + across * across)
            fit = math.min(fit, silhouette(shape, math.atan2(across, depth)) * 0.96 / math.max(0.00001, length))
        end
    end
    return center * fit, width * fit, gap * fit
end

local function front_feeding(entries, facing, progress_field)
    local activation = 0
    for _, entry in ipairs(entries) do
        if entry.captured and entry.entry_angle and math.cos(entry.entry_angle - facing) > math.cos(0.7) then
            activation = math.max(activation, math.sin(math.pi * unit(entry[progress_field] or 0)))
        end
    end
    return activation
end

local function hex_color(hex)
    local rgb = tonumber(hex, 16)
    return {math.floor(rgb / 65536) / 255, math.floor(rgb / 256) % 256 / 255, rgb % 256 / 255}
end

local function blend(a, b, weight)
    return {a[1] + (b[1] - a[1]) * weight, a[2] + (b[2] - a[2]) * weight, a[3] + (b[3] - a[3]) * weight}
end

local ACID, INFECTION = hex_color("bbec76"), hex_color("ec9bd5")
local WHITE = {1, 1, 1}

local function organ_color(build, name, base)
    local grade = build:quality(name)
    return grade > 0 and blend(base, hex_color(Rewards.quality_color(grade)), 0.63) or base
end

local function deform(pose, x, y)
    if pose and Tissue.deform_point then return Tissue.deform_point(pose, x, y) end
    return x, y
end

local function tendril(state, draw, angle, phase, length, width, pigment, strike)
    local index = draw.count + 1
    draw.count = index
    local node = state.ribbons[index]
    if not node then
        node = new_box(state.layer)
        state.ribbons[index] = node
        gui.set(node, properties.growth, vmath.vector4(0, 0, 0, 1))
    end
    gui.set_enabled(node, true)
    local dir_x, dir_y = math.cos(angle), math.sin(angle)
    local anchor = silhouette(draw.shape, angle)
    local root_x, root_y = dir_x * 0.76 * anchor, dir_y * 0.76 * anchor
    local deform_x, deform_y = deform(draw.pose, root_x, root_y)
    local left, right, bottom, top = math.huge, -math.huge, math.huge, -math.huge
    local points = state.points
    for i = 0, 9 do
        local t = i / 9
        local swell = math.sin(t * 4 + phase * 1.5) * t * 0.24
        local extension = 0.76 + t * length
        local x = dir_x * anchor * extension + dir_y * swell + deform_x - root_x
        local y = dir_y * anchor * extension - dir_x * swell + deform_y - root_y
        if strike then
            local arc = math.sin(t * math.pi) * 0.25
            local sx = deform_x + (strike.x - deform_x) * t + dir_y * arc
            local sy = deform_y + (strike.y - deform_y) * t - dir_x * arc
            x = x + (sx - x) * strike.extension
            y = y + (sy - y) * strike.extension
        end
        points[2 * i + 1], points[2 * i + 2] = x, y
        left, right, bottom, top = math.min(left, x), math.max(right, x), math.min(bottom, y), math.max(top, y)
    end
    local pad = width + 2 / math.max(1, draw.radius)
    local x, y = (left + right) * 0.5, (bottom + top) * 0.5
    local w, h = right - left + 2 * pad, top - bottom + 2 * pad
    gui.set_position(node, vmath.vector3(draw.x + draw.radius * (x * draw.cos + y * draw.sin),
        draw.y + draw.radius * (y * draw.cos - x * draw.sin), 0))
    gui.set_size(node, vmath.vector3(w * draw.radius, h * draw.radius, 0))
    gui.set_rotation(node, draw.angle)
    for i = 1, 5 do
        local j = (i - 1) * 4 + 1
        gui.set(node, shape_properties[i], vmath.vector4(points[j] - x, points[j + 1] - y,
            points[j + 2] - x, points[j + 3] - y))
    end
    set(node, "mouth", w, h, width, draw.radius)
    set(node, "edge", pigment[1], pigment[2], pigment[3], strike and strike.extension or 0)
end

local function strike_tip(state, sim, limb, target, extension, radius, cosine, sine)
    local tip = state.lashes[limb] or {}
    local x, y = target.x - sim.player.x, target.y - sim.player.y
    tip.x, tip.y = (x * cosine + y * sine) / radius, (x * sine - y * cosine) / radius
    tip.extension = extension
    state.lashes[limb] = tip
end

function Anatomy.update(state, sim, x, y, radius, _, pose, visual_time)
    local node, build = state.node, sim.build
    gui.set_enabled(node,true)
    local genome = sim.player_genome
    local shape = SHAPES[genome.family + 1] or SHAPES[1]
    local time = visual_time or sim.elapsed
    if state.sim~=sim then
        state.sim,state.growth,state.time=sim,{},time
        for _,kind in ipairs({"tentacle","acid","infection"}) do
            state.growth[kind]=sim.build:evolved(kind) and 1 or 0
        end
    end
    local step=math.max(0,math.min(.1,time-state.time))
    state.time=time
    for _,kind in ipairs({"tentacle","acid","infection"}) do
        state.growth[kind]=sim.build:evolved(kind) and math.min(1,state.growth[kind]+step/2.2) or 0
    end
    local facing, phase = sim.facing, genome.phase - genome.rotation
    local cosine, sine = math.cos(facing), math.sin(facing)
    local angle = vmath.vector3(0, 0, -math.deg(facing))
    local world_radius = sim:body_radius()
    local acid, enzymes, infection = build:rank("acid"), build:rank("enzymes"), build:rank("infection")
    local barrier, tentacle, cilia = build:rank("barrier"), build:rank("tentacle"), build:rank("cilia")
    local evolved_tentacle=build:evolved("tentacle")
    local body = hex_color(sim:body_color())
    local edge = blend(body, WHITE, 0.38)
    local bite = math.max(unit(sim.bite_flash or 0), front_feeding(sim.enemies, facing, "engulf"),
        front_feeding(sim.pickups, facing, "progress"), front_feeding(sim.remains, facing, "progress"))
    local mantle, block = 0, 0
    for limb in pairs(state.lashes) do state.lashes[limb] = nil end
    for _, effect in ipairs(sim.effects) do
        local life = unit(effect.life / math.max(effect.max, 0.001))
        if effect.type == "lash" and effect["end"] then
            local extension = math.sin(math.pi * smoothstep(0, 1, 1 - life))
            strike_tip(state, sim, effect.limb or 0, effect["end"], extension, world_radius, cosine, sine)
        elseif effect.type == "mantle" then
            mantle = math.sin(math.pi * life)
        elseif effect.type == "barrier_block" then
            block = math.max(block, life)
        end
    end
    if evolved_tentacle then
        for _, enemy in ipairs(sim.enemies) do
            if (enemy.crown_time or 0) > 0 and Evolution.crown_eligible(world_radius, enemy, build:rank("magnet")) then
                local extension = smoothstep(0, 0.18, enemy.crown_age or 0) * smoothstep(0, 0.18, enemy.crown_time)
                for _, limb in ipairs(enemy.crown_limbs or {}) do
                    local side = limb % 2 == 0 and -1 or 1
                    local offset = {x = enemy.pos.x - sim.player.x, y = enemy.pos.y - sim.player.y}
                    local tip = Evolution.crown_tip(offset, enemy.r, side, time + limb)
                    tip.x, tip.y = tip.x + sim.player.x, tip.y + sim.player.y
                    strike_tip(state, sim, limb, tip, extension, world_radius, cosine, sine)
                end
            end
        end
    end

    local draw = state.draw or {}
    state.draw = draw
    draw.x, draw.y, draw.radius, draw.angle, draw.cos, draw.sin, draw.shape, draw.pose, draw.count =
        x, y, radius, angle, cosine, sine, shape, pose, 0
    local count = Catalog.tentacle_count(tentacle)
    local tentacle_color = organ_color(build, "tentacle", edge)
    if evolved_tentacle and acid > 0 then tentacle_color = blend(tentacle_color, ACID, 0.35) end
    if evolved_tentacle and infection > 0 then tentacle_color = blend(tentacle_color, INFECTION, 0.25) end
    local lash_mask=0
    for i=0,count-1 do
        local strike=state.lashes[i]
        if strike and strike.extension>.04 then
            lash_mask=lash_mask+2^i
            tendril(state,draw,-phase-i*TAU/count,time+phase+i,
                .9+stage(tentacle)*.2+state.growth.tentacle*.17,
                .105+stage(tentacle)*.006,tentacle_color,strike)
        end
    end
    local speed=build:rank("speed")
    local sensory=genome.family==5 or build:rank("magnet")>0
    set(node,"appendages",count,cilia,speed,sensory and 1 or 0)
    for i = draw.count + 1, #state.ribbons do gui.set_enabled(state.ribbons[i], false) end

    if state.shape ~= shape then
        for i, property in ipairs(shape_properties) do gui.set(node, property, shape[i]) end
        state.shape = shape
    end
    if state.jaw_shape ~= shape or state.bite ~= bite then
        state.center, state.width, state.gap = jaw(shape, bite)
        state.jaw_shape, state.bite = shape, bite
    end
    set(node, "mouth", state.center, state.width, state.gap, 1 / radius)
    local diameter = radius * OVERLAY_DIAMETER
    gui.set_position(node, vmath.vector3(x, y, 0))
    gui.set_size(node, vmath.vector3(diameter, diameter, 0))
    gui.set_rotation(node, angle)
    local devour, spikes = build:rank("devour"), build:rank("spikes")
    local lip = organ_color(build, "devour", edge)
    local wound_seed = ((genome.seed * 73 + genome.identity * 151) % 997) / 997 * TAU
    local distress = smoothstep(0.04, 1, 1 - unit(sim.hp / math.max(1, sim.max_hp)))
    set(node, "ranks", build:rank("armor"), spikes, devour, build:rank("pulse"))
    set(node, "glands", acid, enzymes, infection, barrier)
    set(node, "action", time, bite, -phase, mantle)
    set(node, "barrier", block, build:rank("trail"), build:rank("division"), sim.spore_charge or 0)
    set(node, "body", body[1], body[2], body[3], distress)
    set(node, "edge", edge[1], edge[2], edge[3], -wound_seed)
    set(node, "lip", lip[1], lip[2], lip[3], lash_mask)
    set(node, "growth", state.growth.tentacle, state.growth.acid, state.growth.infection, 0)
    if pose and Tissue.apply_deformation then Tissue.apply_deformation(node, pose) end
end

function Anatomy.hide(state)
    gui.set_enabled(state.node,false)
    for _,node in ipairs(state.ribbons) do gui.set_enabled(node,false) end
end

return Anatomy
