local util = require "main.run.meta_util"
local genome = require "main.run.genome"
local catalog = require "main.run.catalog"
local M = {}

M.TRAITS = {"elastic", "sensory", "folds", "receptive"}
local FORM_FAMILIES = {predator = 1, toxic = 0, colony = 4}

function M.normalize(source)
    if type(source) ~= "table" or not next(source) then return {} end
    local form = util.string(source.form, "predator")
    local branch = util.string(source.branch, "predator")
    local imprint = util.string(source.imprint)
    local result = {
        form = FORM_FAMILIES[form] and form or "predator",
        traits = {}, imprint = imprint,
        seed = util.clamp(util.integer(source.seed, 1), 0, 2147483647),
        branch = FORM_FAMILIES[branch] and branch or "predator",
    }
    for index, trait in ipairs(util.array_or_empty(source.traits)) do
        if index > 8 or #result.traits == 2 then break end
        if util.index(M.TRAITS, trait) and not util.index(result.traits, trait) then
            result.traits[#result.traits + 1] = trait
        end
    end
    local trait = imprint:match("^trait:(.+)$")
    if not catalog.ORGANS[imprint] and not util.index(M.TRAITS, trait) then result.imprint = "" end
    if result.imprint ~= "" and genome.validate(source.ancestry_recipe) then
        result.ancestry_recipe = util.copy(source.ancestry_recipe)
        for _, key in ipairs(genome.INTEGER_FIELDS) do
            result.ancestry_recipe[key] = util.integer(source.ancestry_recipe[key])
        end
    end
    return result
end

function M.traits(loadout)
    loadout = loadout or {}
    local traits = util.copy(util.array_or_empty(loadout.traits))
    local inherited = util.string(loadout.imprint):match("^trait:(.+)$")
    if util.index(M.TRAITS, inherited) and not util.index(traits, inherited) then traits[#traits + 1] = inherited end
    return traits
end

function M.recipe(loadout)
    loadout = loadout or {}
    local recipe = genome.create(util.integer(loadout.seed, 1), 0, "player", 0)
    local ancestor = loadout.ancestry_recipe
    if genome.validate(ancestor) then
        recipe.membrane, recipe.tissue = util.integer(ancestor.membrane), util.integer(ancestor.tissue)
    end
    recipe.family = FORM_FAMILIES[loadout.form] or 1
    local traits = M.traits(loadout)
    if util.index(traits, "elastic") then recipe.stretch, recipe.asymmetry = 1.12, 0.13 end
    if util.index(traits, "sensory") then recipe.membrane = 1 end
    if util.index(traits, "folds") then recipe.membrane = 2 end
    return recipe
end

return M
