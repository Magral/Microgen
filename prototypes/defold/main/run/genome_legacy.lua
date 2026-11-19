local util = require "main.run.meta_util"
local genome = require "main.run.genome"
local catalog = require "main.run.catalog"
local M = {}

M.FORMS = {
    predator = {name = "Хищная", organ = "devour", branch = "predator", research = "", desc = "Выраженная передняя часть и пасть: сближение и укусы."},
    toxic = {name = "Железистая", organ = "acid", branch = "toxic", research = "toxic", desc = "Складчатая мембрана растворяет добычу рядом с телом."},
    colony = {name = "Колониальная", organ = "division", branch = "colony", research = "colony", desc = "Живые перемычки связывают доли; почки отделяются в помощников."},
}
M.TRAITS = {
    elastic = {name = "Эластичная ткань", research = "elastic", desc = "Разгон и торможение: 0,13 с вместо 0,20 с.", tradeoff = "Контактный урон +8%.", visual = "Вытянутые мягкие доли."},
    sensory = {name = "Чувствительная мембрана", research = "sensory", desc = "Обнаружение ценных ресурсов +160.", tradeoff = "Скорость −5%.", visual = "Рецепторные выступы по краю тела."},
    folds = {name = "Пищеварительные складки", research = "folds", desc = "Переваривание отделённых фрагментов быстрее на 20%.", tradeoff = "Получаемое лечение −10%.", visual = "Глубокие складки пищеварительной ткани."},
    receptive = {name = "Генетическая восприимчивость", research = "receptive", desc = "Вес выбранной ветви мутаций: 1,75 вместо 1,35.", tradeoff = "Получаемая ДНК −5%.", visual = "Светящиеся рецепторные камеры."},
}
M.RESEARCH = {
    toxic = {name = "Железистая форма", branch = "structure", cost = 4, requires = {}, effect = "Открывает железистый старт с кислотой.", visual = "Мягкое складчатое тело и железы."},
    colony = {name = "Колониальная форма", branch = "structure", cost = 8, requires = {}, effect = "Открывает деление и колониальный старт одной покупкой.", visual = "Доли и живые перемычки."},
    elastic = {name = "Эластичная ткань", branch = "adaptation", cost = 4, requires = {}, effect = "Открывает наследственный признак скорости.", visual = "Мягкие вытянутые доли."},
    sensory = {name = "Чувствительная мембрана", branch = "adaptation", cost = 4, requires = {}, effect = "Открывает наследственные рецепторы.", visual = "Рецепторные выступы."},
    folds = {name = "Пищеварительные складки", branch = "adaptation", cost = 6, requires = {"sensory"}, effect = "Открывает наследственный признак усвоения.", visual = "Складки пищеварительной ткани."},
    receptive = {name = "Генетическая восприимчивость", branch = "memory", cost = 8, requires = {"memory"}, effect = "Открывает предпочтение выбранной ветви мутаций.", visual = "Светящиеся рецепторные камеры."},
    memory = {name = "Закрепление памяти", branch = "memory", cost = 4, requires = {}, effect = "Повторные отпечатки дают до 3 знаний на ветвь; каждое заменяет одно ядро исследования.", visual = "Яркое наследственное ядро."},
}
M.BRANCHES = {
    structure = "Строение",
    adaptation = "Приспособление",
    memory = "Генетическая память",
}
M.FORM_IDS = {"predator", "toxic", "colony"}
M.TRAIT_IDS = {"elastic", "sensory", "folds", "receptive"}
M.RESEARCH_IDS = {"toxic", "colony", "elastic", "sensory", "folds", "receptive", "memory"}
M.MAX_PENDING_QUEUE = 8

function M.defaults()
    return {
        version = 1, generation = 0, research = {}, forms = {"predator"}, traits = {}, equipped_traits = {},
        selected_form = "predator", selected_imprint = "", morphology_seed = 1, focus = "",
        knowledge = {structure = 0, adaptation = 0, memory = 0}, imprints = {}, pending = {},
        pending_queue = {}, presets = {}, history = {},
    }
end

local function ids(raw, allowed, limit)
    local result = {}
    for _, id in ipairs(util.array_or_empty(raw)) do
        if #result >= (limit or 32) then break end
        if type(id) == "string" and allowed[id] and not util.index(result, id) then
            result[#result + 1] = id
        end
    end
    return result
end

function M.valid_imprint(id)
    if type(id) ~= "string" then return false end
    return catalog.ORGANS[id] ~= nil or M.TRAITS[id:match("^trait:(.+)$")] ~= nil
end

function M.imprint_name(id)
    local trait = M.TRAITS[id:match("^trait:(.+)$")]
    return trait and trait.name or util.table(catalog.item(id)).name or id
end

local function research_branch(id)
    if id:sub(1, 6) == "trait:" then return id == "trait:receptive" and "memory" or "adaptation" end
    return ({predator = "structure", toxic = "adaptation", colony = "memory"})[util.table(catalog.item(id)).branch] or "structure"
end

local function imprints(raw)
    local result, seen = {}, {}
    for _, imprint in ipairs(util.array_or_empty(raw)) do
        local record = util.table(imprint)
        local id = record.id
        if M.valid_imprint(id) and not seen[id] and genome.validate(record.recipe) then
            local origin = util.table(record.origin)
            result[#result + 1] = {
                id = id, name = M.imprint_name(id), branch = research_branch(id),
                origin = {
                    generation = math.max(0, util.integer(origin.generation)),
                    biome = util.clamp(util.integer(origin.biome), 0, 32),
                    elapsed = math.max(0, util.integer(origin.elapsed)),
                },
                recipe = genome.canonical(record.recipe), rank = 1, quality = 0,
            }
            seen[id] = true
        end
    end
    return result
end

local function selection(legacy, form, traits, imprint, seed)
    if form == "division" then form = "colony" end
    form = util.index(legacy.forms, form) and form or "predator"
    local equipped = {}
    for _, trait in ipairs(ids(traits, M.TRAITS, 2)) do
        if util.index(legacy.traits, trait) then equipped[#equipped + 1] = trait end
    end
    local inherited = util.find(legacy.imprints, imprint)
    return {
        form = form, traits = equipped, imprint = inherited and imprint or "",
        seed = util.clamp(util.integer(seed, 1), 1, 2147483646),
        branch = M.FORMS[form].branch, ancestry_recipe = inherited and util.copy(inherited.recipe) or {},
    }
end

function M.normalize(profile)
    profile = util.table(profile)
    local clean, raw = M.defaults(), util.table(profile.legacy)
    clean.generation = math.max(0, util.integer(raw.generation))
    clean.research = ids(raw.research, M.RESEARCH)
    if util.index(util.array_or_empty(profile.unlocked), "division") and not util.index(clean.research, "colony") then
        clean.research[#clean.research + 1] = "colony"
    end
    for _, id in ipairs(M.FORM_IDS) do
        if util.index(clean.research, M.FORMS[id].research) then clean.forms[#clean.forms + 1] = id end
    end
    for _, id in ipairs(M.TRAIT_IDS) do
        if util.index(clean.research, id) then clean.traits[#clean.traits + 1] = id end
    end
    clean.imprints, clean.pending = imprints(raw.imprints), imprints(raw.pending)
    for _, life in ipairs(util.array_or_empty(raw.pending_queue)) do
        if #clean.pending_queue == M.MAX_PENDING_QUEUE then break end
        local candidates = imprints(life)
        if #candidates > 0 then clean.pending_queue[#clean.pending_queue + 1] = candidates end
    end
    if #clean.pending == 0 and #clean.pending_queue > 0 then clean.pending = table.remove(clean.pending_queue, 1) end
    local active = selection(clean, raw.selected_form, raw.equipped_traits, raw.selected_imprint, raw.morphology_seed)
    clean.selected_form, clean.equipped_traits = active.form, active.traits
    clean.selected_imprint, clean.morphology_seed = active.imprint, active.seed
    if M.RESEARCH[raw.focus] and not util.index(clean.research, raw.focus) then clean.focus = raw.focus end
    local knowledge = util.table(raw.knowledge)
    for branch in pairs(M.BRANCHES) do clean.knowledge[branch] = util.clamp(util.integer(knowledge[branch]), 0, 3) end
    for _, preset in ipairs(util.array_or_empty(raw.presets)) do
        if #clean.presets == 6 then break end
        if type(preset) == "table" then
            local entry = selection(clean, preset.form, preset.traits, preset.imprint, preset.seed)
            entry.name = util.limit_text(util.string(preset.name, "Набор"), 32)
            clean.presets[#clean.presets + 1] = entry
        end
    end
    local history = util.array_or_empty(raw.history)
    for index = math.max(1, #history - 11), #history do
        local entry = history[index]
        if type(entry) == "table" then
            local candidates = {}
            for _, id in ipairs(util.array_or_empty(entry.candidates)) do
                if M.valid_imprint(id) and not util.index(candidates, id) then candidates[#candidates + 1] = id end
            end
            clean.history[#clean.history + 1] = {
                generation = math.max(0, util.integer(entry.generation)), elapsed = math.max(0, util.integer(entry.elapsed)),
                outcome = util.limit_text(util.string(entry.outcome), 32), form = util.string(entry.form, "predator"),
                candidates = candidates,
            }
        end
    end
    return clean
end

function M.loadout(profile)
    local legacy = M.normalize(profile)
    return selection(legacy, legacy.selected_form, legacy.equipped_traits, legacy.selected_imprint, legacy.morphology_seed)
end

function M.focus_progress_in(profile, legacy, id)
    if not id or id == "" then id = legacy.focus end
    local node = M.RESEARCH[id]
    if not node then return {} end
    local missing = {}
    for _, requirement in ipairs(node.requires) do
        if not util.index(legacy.research, requirement) then missing[#missing + 1] = requirement end
    end
    local knowledge = util.index(legacy.research, "memory") and legacy.knowledge[node.branch] or 0
    local price = math.max(0, node.cost - knowledge)
    local cores = util.integer(profile.cores)
    return {
        id = id, cost = price, cores = math.max(0, cores), knowledge = knowledge,
        remaining = math.max(0, price - cores), ready = not util.index(legacy.research, id) and #missing == 0 and cores >= price,
        requires = missing,
    }
end

function M.focus_progress(profile, id)
    return M.focus_progress_in(profile, M.normalize(profile), id)
end

function M.can_start(profile)
    return #M.normalize(profile).pending_queue < M.MAX_PENDING_QUEUE
end

function M.complete(profile, sim)
    local outcome = util.string(sim.outcome)
    if outcome == "" then return false end
    local legacy = M.normalize(profile)
    legacy.generation = legacy.generation + 1
    local candidates, elapsed = {}, util.integer(sim.elapsed)
    local loadout = util.table(sim.run_loadout)
    if elapsed >= 60 and genome.validate(sim.player_genome) then
        local combat, build = util.table(sim.combat_stats), util.table(sim.build)
        local biome = 0
        if sim.world and sim.world.biome and sim.player then biome = sim.world:biome(sim.player.x, sim.player.y) end
        local origin = {generation = legacy.generation, biome = biome, elapsed = elapsed}
        local function candidate(id)
            candidates[#candidates + 1] = {
                id = id, name = M.imprint_name(id), branch = research_branch(id), origin = util.copy(origin),
                recipe = genome.canonical(sim.player_genome), rank = 1, quality = 0,
            }
        end
        for _, id in ipairs(util.sorted_keys(util.table(build.organs))) do
            local organ = util.table(util.table(combat.organs)[id])
            local rank = build.rank and build:rank(id) or build.organs[id]
            if catalog.ORGANS[id] and rank >= 3 and (organ.damage or 0) > 0 then candidate(id) end
        end
        if (combat.damage_dealt or 0) > 0 then
            for _, id in ipairs(ids(loadout.traits, M.TRAITS, 2)) do candidate("trait:" .. id) end
        end
    end
    if #candidates > 0 then
        if #legacy.pending == 0 then
            legacy.pending = candidates
        elseif #legacy.pending_queue < M.MAX_PENDING_QUEUE then
            legacy.pending_queue[#legacy.pending_queue + 1] = candidates
        else
            return false
        end
    end
    local candidate_ids = {}
    for index, entry in ipairs(candidates) do candidate_ids[index] = entry.id end
    legacy.history[#legacy.history + 1] = {
        generation = legacy.generation, elapsed = elapsed, outcome = outcome,
        form = loadout.form or "ancestral", candidates = candidate_ids,
    }
    if #legacy.history > 12 then table.remove(legacy.history, 1) end
    profile.legacy = legacy
    return true
end

return M
