local Jelly = require "main.jelly_motion"

-- Keep the draw bounds in sync with the padded local coordinates in tissue.fp.
local tissue = {OVERSCAN = 1.24}
local atlas_property = hash("tissue_atlas")
local size_property = hash("tissue_size")
local strain_property = hash("tissue_strain")
local waves_property = hash("tissue_waves")
local flow_property = hash("tissue_flow")
local contact_property = hash("tissue_contact")
local wounds_property = hash("tissue_wounds")
local pigment_property = hash("tissue_pigment")
local fragment_property = hash("tissue_fragment")
local TAU = 2 * math.pi
local atan2 = math.atan2 or math.atan
local zero = vmath.vector4()
local rest_flow = vmath.vector4(0, 0, 1, 0)

local function region(geometry, texture)
    -- The resource API gives pixel coordinates measured from the top left.
    -- Defold shaders sample normalized UVs measured from the bottom left.
    local uvs = geometry.uvs
    if #uvs < 6 then return nil end
    local left, right, top, bottom = uvs[1], uvs[1], uvs[2], uvs[2]
    for i = 3, #uvs, 2 do
        left = math.min(left, uvs[i])
        right = math.max(right, uvs[i])
        top = math.min(top, uvs[i + 1])
        bottom = math.max(bottom, uvs[i + 1])
    end
    local half_width = (right - left) / (2 * texture.width)
    local half_height = (bottom - top) / (2 * texture.height)
    if half_width == 0 or half_height == 0 then return nil end
    return vmath.vector4(
        (left + right) / (2 * texture.width),
        1 - (top + bottom) / (2 * texture.height),
        geometry.rotated and -half_width or half_width,
        half_height)
end

function tissue.load_atlas()
    local atlas = resource.get_atlas("/main/cells.a.texturesetc")
    local texture = resource.get_texture_info(atlas.texture)
    local regions = {}
    for _, animation in ipairs(atlas.animations) do
        local geometry = atlas.geometries[animation.frames[1]]
        if geometry then regions[animation.id] = region(geometry, texture) end
    end
    return regions
end

function tissue.attach(atlas, node, frame)
    local bounds = atlas[frame]
    if not bounds then return nil end

    gui.set_material(node, "tissue")
    gui.set(node, atlas_property, bounds)
    return {node = node}
end

function tissue.attach_fragment(atlas, node, look, first, last, phase)
    local state = tissue.attach(atlas, node, look.frame)
    if not state then return nil end
    local diameter = 2 * look.source_radius
    gui.set(node, size_property, vmath.vector4(look.dimensions[1] / diameter, look.dimensions[2] / diameter,
        look.pose and look.pose.compact and 1 or 0, 0))
    tissue.apply_deformation(node, look.pose)
    gui.set(node, pigment_property, look.pose and look.pose.stain or look.stain)
    gui.set(node, fragment_property, vmath.vector4(1, first, last, phase))
    return state
end

function tissue.motion(previous, dt, x, y, genome, player_facing)
    local state = previous
    if not state or state.genome ~= genome then
        local angle = genome and genome.rotation or 0
        state = Jelly.new(angle)
        state.genome = genome
        state.phase = genome and genome.phase or 0
        local seed, identity = genome and genome.seed or 0, genome and genome.identity or 0
        state.wound_phase = ((seed * 73 + identity * 151) % 997) / 997 * TAU
        state.x, state.y = x, y
    end

    local dx, dy = x - state.x, y - state.y
    state.x, state.y = x, y
    if dt and dt > 0 then
        if dx * dx + dy * dy >= 100 * 100 then dx, dy = 0, 0 end
        local interval = math.max(dt, 0.001)
        state:step(dt, dx / interval, dy / interval)
    end
    if player_facing then state.angle = player_facing end
    return state
end

function tissue.turn(motion)
    return motion and motion:turn() or 0
end

local function bounded_direction(x, y)
    local length_squared = x * x + y * y
    if length_squared > 1 then
        local length = math.sqrt(length_squared)
        return x / length, y / length
    end
    return x, y
end

local function unit(value)
    return math.min(math.max(value or 0, 0), 1)
end

local function damage_flow(strength, hit_x, hit_y)
    local x, y = bounded_direction(hit_x or 0, hit_y or 0)
    local pulse = unit(strength) * 0.10
    return -x * pulse, -y * pulse
end

tissue.damage_flow = damage_flow

local function smoothstep(lo, hi, value)
    local t = unit((value - lo) / (hi - lo))
    return t * t * (3 - 2 * t)
end

function tissue.apply_deformation(node, state)
    gui.set(node, strain_property, state and state.strain or zero)
    gui.set(node, waves_property, state and state.waves or zero)
    gui.set(node, flow_property, state and state.flow or rest_flow)
    gui.set(node, contact_property, state and state.contact or zero)
    gui.set(node, wounds_property, state and state.wounds or zero)
end

function tissue.update(state, motion, time, angle, half_width, half_height, contact_x, contact_y, bite, pigment, pigment_hex,
        health_ratio, reaction, impact_x, impact_y, impact_strength, compact)
    if not state then return end
    local node = state.node
    contact_x, contact_y = bounded_direction(contact_x or 0, contact_y or 0)
    bite = unit(bite)
    if contact_x == 0 and contact_y == 0 then bite = 0 end

    compact=not not compact
    if state.half_width ~= half_width or state.half_height ~= half_height or state.compact ~= compact then
        gui.set(node, size_property, vmath.vector4(half_width, half_height, compact and 1 or 0, 0))
        state.half_width, state.half_height, state.compact = half_width, half_height, compact
    end

    local phase, clock = motion.phase, motion.clock
    local cos_angle, sin_angle = math.cos(angle), math.sin(angle)
    local cos_double = cos_angle * cos_angle - sin_angle * sin_angle
    local sin_double = 2 * cos_angle * sin_angle
    -- Convert the world spring from Godot's Y-down coordinates to the rotated GUI node's Y-up basis.
    state.strain = vmath.vector4(
        cos_double * motion.strain_x + sin_double * motion.strain_y,
        sin_double * motion.strain_x - cos_double * motion.strain_y,
        cos_angle * motion.lag_x + sin_angle * motion.lag_y,
        sin_angle * motion.lag_x - cos_angle * motion.lag_y)

    local third = 3 * motion.rest_angle - clock * 2.7 + phase
    local fifth = 5 * motion.rest_angle + clock * 1.8 - phase
    local amplitude = 0.055 + 0.025 * motion.speed
    state.waves = vmath.vector4(amplitude * math.sin(third), -amplitude * math.cos(third),
        0.018 * math.sin(fifth), -0.018 * math.cos(fifth))

    local breathing = 1 + 0.025 * math.sin(time * 1.7 + phase + motion:turn()) + unit(reaction) * 0.055
    local recoil_x, recoil_y = damage_flow(impact_strength, impact_x, impact_y)
    state.flow = vmath.vector4(0.064 * math.sin(clock * 1.91 + phase) + recoil_x,
        0.053 * math.sin(clock * 1.47 - phase) + recoil_y, breathing, math.cos(clock * 3.45 + phase))
    state.contact = vmath.vector4(contact_x, contact_y, bite, bite > 0 and math.sin(time * 10.2) or 0)

    local distress = smoothstep(0.04, 1, 1 - (health_ratio == nil and 1 or unit(health_ratio)))
    state.wounds = distress > 0 and vmath.vector4(motion.wound_phase, distress, math.sin(time * 7 + phase), 0) or zero
    tissue.apply_deformation(node, state)

    pigment = unit(pigment)
    if state.pigment ~= pigment or state.pigment_hex ~= pigment_hex then
        local r, g, b = 0.76, 0.58, 0.83
        local hex = type(pigment_hex) == "string" and pigment_hex:match("^#(%x%x%x%x%x%x)$")
        local rgb = hex and tonumber(hex, 16)
        if rgb then
            r = math.floor(rgb / 65536) / 255
            g = (math.floor(rgb / 256) % 256) / 255
            b = (rgb % 256) / 255
        end
        state.stain = vmath.vector4(r, g, b, pigment)
        gui.set(node, pigment_property, state.stain)
        state.pigment, state.pigment_hex = pigment, pigment_hex
    end
end

-- Forward map for roots of CPU-drawn organs using the same deformation as the membrane.
function tissue.deform_point(state, x, y)
    if not state or not state.flow then return x, y end
    local strain, waves, flow, wounds, contact = state.strain, state.waves, state.flow, state.wounds, state.contact
    local length = math.sqrt(x * x + y * y)
    if length > 0.0001 then
        local nx, ny = x / length, y / length
        if wounds.y > 0 then
            local theta = -atan2(y, x) - wounds.x
            local sector = math.floor(theta * (5 / TAU) + 0.5)
            local index = sector % 5
            local offset = math.abs(theta - sector * (TAU / 5) - 0.16 * math.sin(index * 4.73 + wounds.x))
            local width = (0.30 + 0.055 * math.sin(index * 2.83 + wounds.x)) * 1.8
            local cut = wounds.y * (0.61 + 0.08 * math.sin(index * 3.17 + wounds.x))
                * (1 - smoothstep(0, width, offset)) * (0.80 + 0.20 * math.cos(offset * 37 + index * 2.2))
            length = length * (1 - cut)
        end
        local depth = math.min(length, 1.2)
        local x2, y2 = nx * nx - ny * ny, 2 * nx * ny
        local x3, y3 = x2 * nx - y2 * ny, x2 * ny + y2 * nx
        local x5, y5 = x3 * x2 - y3 * y2, x3 * y2 + y3 * x2
        local swell = flow.x * nx + flow.y * ny
        local scale = 1 + depth * (waves.x * x3 + waves.y * y3 + waves.z * x5 + waves.w * y5 + swell)
        local curl = depth * (0.035 * flow.w * y2 + 0.42 * (flow.y * nx - flow.x * ny))
        x, y = length * (nx * scale - ny * curl), length * (ny * scale + nx * curl)
    end
    local depth = math.min(length, 1.2)
    local interior = 1 - smoothstep(0.12, 0.85, depth)
    x, y = (1 + strain.x) * x + strain.y * y + strain.z * (1 - depth * 0.55) + flow.x * interior,
        strain.y * x + (1 - strain.x) * y + strain.w * (1 - depth * 0.55) + flow.y * interior
    if contact.z > 0 then
        local forward = x * contact.x + y * contact.y
        local across = math.abs(y * contact.x - x * contact.y)
        local bite = contact.z * smoothstep(0.10, 0.78, forward) * (1 - smoothstep(0.16, 0.78, across))
        local reach = bite * (0.20 + 0.072 * contact.w)
        x, y = x + contact.x * reach + x * bite * 0.038, y + contact.y * reach + y * bite * 0.038
    end
    return x * flow.z, y * flow.z
end

return tissue
