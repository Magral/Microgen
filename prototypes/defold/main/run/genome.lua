local util = require "main.run.meta_util"
local rng = require "main.run.rng"
local M = {}

M.FAMILIES = {"lobed", "elongated", "crescent", "branched", "cluster", "radial"}
M.PALETTES = {
    {"249eaa", "95f2df", "9d6dcc", "c8dc67", "153844"},
    {"7150ad", "ccaff3", "e184c5", "a8d66c", "282544"},
    {"859f30", "e1ef91", "9872c9", "e9938f", "2d3a22"},
    {"377bb9", "b2d7f2", "bd85d9", "e1b869", "172f49"},
    {"ba5a75", "f6b3c3", "b77cd2", "e1ce89", "49263b"},
    {"b78b3b", "f4daa0", "9b74bb", "78c9b8", "443526"},
    {"427d83", "a7dcd9", "9c89de", "b7d975", "183c43"},
    {"4a9b76", "b1e6a2", "c183ca", "e5d383", "1b3b35"},
}
M.INTEGER_FIELDS = {"version", "seed", "identity", "family", "palette", "lobes", "membrane", "nuclei", "tissue", "biome"}
M.FLOAT_FIELDS = {"phase", "rotation", "stretch", "asymmetry"}

local TAU = 2 * math.pi
local UINT32 = 4294967296

local function role_hash(role)
    local hash = 5381
    for index = 1, #role do hash = (hash * 33 + role:byte(index)) % UINT32 end
    return hash
end

function M.create(seed, identity, role, biome)
    seed = util.integer(seed, 1)
    identity = util.integer(identity)
    role = role or "player"
    local random = rng.new(seed * 1664525 + identity * 1013904223 + role_hash(role))
    local family = random:randi_range(0, 5)
    if role == "prey" then family = ({0, 1, 4})[random:randi_range(1, 3)] end
    return {
        version = 1, seed = seed, identity = identity, family = family, palette = random:randi_range(0, 7),
        lobes = random:randi_range(3, 7), membrane = random:randi_range(0, 2), nuclei = random:randi_range(1, 3),
        phase = random:randf() * TAU, rotation = random:randf() * TAU, stretch = random:randf_range(0.91, 1.08),
        asymmetry = random:randf_range(0.04, 0.12), tissue = random:randi_range(0, 2), biome = biome or 0,
    }
end

function M.validate(recipe)
    if type(recipe) ~= "table" then return false end
    for _, key in ipairs(M.INTEGER_FIELDS) do
        if key ~= "biome" and not util.finite(recipe[key]) then return false end
    end
    for _, key in ipairs(M.FLOAT_FIELDS) do
        if not util.finite(recipe[key]) then return false end
    end
    local family, palette = util.integer(recipe.family), util.integer(recipe.palette)
    local nuclei, lobes = util.integer(recipe.nuclei), util.integer(recipe.lobes)
    return util.integer(recipe.version) == 1 and family >= 0 and family <= 5 and palette >= 0 and palette <= 7
        and nuclei >= 1 and nuclei <= 3 and lobes >= 3 and lobes <= 7
        and recipe.stretch >= 0.85 and recipe.stretch <= 1.15 and math.abs(recipe.asymmetry) <= 0.15
end

function M.canonical(recipe)
    local clean = {}
    for _, key in ipairs(M.INTEGER_FIELDS) do clean[key] = util.integer(recipe[key]) end
    for _, key in ipairs(M.FLOAT_FIELDS) do clean[key] = recipe[key] end
    return clean
end

function M.contour(recipe, detail)
    local points = {}
    detail = detail or 48
    local family, phase = recipe.family, recipe.phase
    local rotation_sine, rotation_cosine = math.sin(recipe.rotation), math.cos(recipe.rotation)
    for index = 0, detail - 1 do
        local angle = index * TAU / detail
        local wave = math.sin(angle * recipe.lobes + phase)
        local radius = 0.81 + 0.15 * wave
        if family == 1 then
            radius = 0.85 + 0.10 * math.sin(angle * 4 + phase)
        elseif family == 2 then
            radius = 0.67 + 0.25 * math.cos(angle) + 0.12 * math.sin(angle * 3 + phase)
        elseif family == 3 then
            radius = 0.46 + 0.61 * ((wave + 1) * 0.5)^2.6
        elseif family == 4 then
            radius = 0.79 + 0.20 * math.sin(angle * 3 + phase) + 0.06 * math.sin(angle * 6 - phase)
        elseif family == 5 then
            radius = 0.85 + 0.08 * math.sin(angle * 10 + phase)
        end
        radius = radius + recipe.asymmetry * math.sin(angle * 2 - phase)
        local x, y = math.cos(angle) * radius * recipe.stretch, math.sin(angle) * radius
        if family == 1 then x, y = x * 1.32, y * 0.63
        elseif family == 2 then x, y = x * 1.10, y * 0.90
        elseif family == 4 then x, y = x * 1.10, y * 0.86 end
        points[#points + 1] = {x = x * rotation_cosine - y * rotation_sine, y = x * rotation_sine + y * rotation_cosine}
    end
    return points
end

function M.colors(recipe)
    return util.copy(M.PALETTES[util.integer(recipe.palette) + 1] or M.PALETTES[1])
end

function M.traits(seed, identity, elapsed, kind)
    if kind == "prey" then return {} end
    local random = rng.new(seed * 69069 + identity * 362437 + 8291)
    local count = math.min(3, math.floor(elapsed / 150))
    if kind == "boss" then count = 3
    elseif elapsed < 150 and random:randf() < 0.35 then count = 1 end
    local pool = {"shell", "swift", "regen", "toxic", "spores"}
    local traits = {}
    for index = 1, count do traits[index] = table.remove(pool, random:randi_range(1, #pool)) end
    return traits
end

return M
