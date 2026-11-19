local Catalog = require "main.run.catalog"

local Anatomy = {}
local OVERLAY_DIAMETER = 4.20
local ranks_property = hash("anatomy_ranks")
local glands_property = hash("anatomy_glands")
local action_property = hash("anatomy_action")
local barrier_property = hash("anatomy_barrier")
local shape_properties = {hash("anatomy_shape_12"), hash("anatomy_shape_34"), hash("anatomy_shape_56"),
    hash("anatomy_shape_78"), hash("anatomy_shape_rest")}
local shape_by_node = setmetatable({}, {__mode = "k"})

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

function Anatomy.new(layer)
    local node = gui.new_box_node(vmath.vector3(), vmath.vector3())
    if layer then gui.set_layer(node, layer) end
    gui.set_material(node, "anatomy")
    return node
end

function Anatomy.update(node, sim, x, y, radius)
    local family = sim.player_genome and sim.player_genome.family or 0
    local shape = SHAPES[family + 1] or SHAPES[1]
    if shape_by_node[node] ~= shape then
        for i, property in ipairs(shape_properties) do gui.set(node, property, shape[i]) end
        shape_by_node[node] = shape
    end

    local build = sim.build
    local acid, enzymes, infection = build:rank("acid"), build:rank("enzymes"), build:rank("infection")
    local barrier = build:rank("barrier")
    local barrier_charge = barrier > 0 and 1 - math.min(1, (sim.cooldowns.barrier or 0) / 8) or 0
    local bite, lash, fan, block = 0, 0, 0, 0
    for _, effect in ipairs(sim.effects) do
        local intensity = math.min(1, effect.life / math.max(effect.max, 0.001))
        if effect.type == "bite" then
            bite = math.max(bite, intensity)
        elseif effect.type == "lash" then
            lash = math.max(lash, intensity)
        elseif effect.type == "cilia" then
            fan = math.max(fan, intensity)
        elseif effect.type == "barrier_block" then
            block = math.max(block, intensity)
        end
    end
    for _, enemy in ipairs(sim.enemies) do
        if enemy.captured and enemy.via_mouth then
            bite = math.max(bite, 0.42 + 0.58 * math.sin(math.pi * math.min(1, enemy.engulf or 0)))
        end
    end

    local diameter = radius * OVERLAY_DIAMETER
    gui.set_position(node, vmath.vector3(x, y, 0))
    gui.set_size(node, vmath.vector3(diameter, diameter, 0))
    gui.set_rotation(node, vmath.vector3(0, 0, -math.deg(sim.facing)))
    gui.set(node, ranks_property, vmath.vector4(Catalog.tentacle_count(build:rank("tentacle")),
        build:rank("cilia"), build:rank("spikes"), build:rank("devour")))
    gui.set(node, glands_property, vmath.vector4(acid > 0 and math.min(5, 2 + acid) or 0,
        enzymes > 0 and 2 or 0, infection > 0 and 3 or 0, barrier))
    gui.set(node, action_property, vmath.vector4(sim.elapsed % 180, bite, lash, fan))
    gui.set(node, barrier_property, vmath.vector4(block,
        math.max(0, 1 - sim.hp / (math.max(1, sim.max_hp) * 0.45)), barrier_charge, 0))
end

return Anatomy
