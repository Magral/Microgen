local catalog = require "main.run.catalog"
local equipment = require "main.run.organism_equipment"
local rng = require "main.run.rng"
local slots = require "main.run.organism_slots"
local util = require "main.run.meta_util"

local M = {BOSS_REROLL_COST = 5}
local BOSS_ORGANS = {"spikes", "infection", "acid"}
local RECEIPTS = {
    body = "Орган сохранён в теле",
    stock = "Орган сохранён в запасе",
    reserve = "Орган сохранён в архиве семейства",
}

local function matches_family(store, sim)
    return sim and sim.family_id and sim.family_id ~= "" and sim.family_id == store:family_id()
end

local function unclaimed_reward(sim)
    local reward = sim.boss_reward
    return sim.stage_transition and reward and reward.organ and not reward.claimed and reward
end

local function save(store, profile)
    if store:write_profile(profile) then return true, "" end
    local error_text = store.last_error
    if not error_text or error_text == "" then error_text = "Не удалось сохранить. Попробуй ещё раз." end
    return false, error_text
end

function M.stage_reroll_cost(stage_index)
    return 8 + math.min(40, stage_index * 4)
end

function M.capture_equipment(profile, build)
    local state = equipment.from_profile(profile)
    local result = equipment.refresh(state, build)
    if not result.ok then return nil, result.error end
    local evolutions = util.table(util.table(build.stats).evolutions)
    for kind, evolved in pairs(evolutions) do
        if evolved then
            local first, is_evolved
            for _, part in ipairs(result.state.equipped) do
                if part.kind == kind then
                    first = first or part
                    if part.evolved then
                        is_evolved = true
                        break
                    end
                end
            end
            if first and not is_evolved then first.evolved = true end
        end
    end
    return result.state
end

function M.apply_equipment(state, build)
    local aggregate = equipment.aggregate(state)
    build.organs = aggregate.organs
    build.specializations = aggregate.specializations
    for _, kind in ipairs(catalog.ORGAN_IDS) do
        build.qualities[kind] = aggregate.qualities[kind]
        build.stats.evolutions[kind] = nil
    end
    for _, part in ipairs(state.equipped) do
        if part.evolved and catalog.EVOLUTIONS[part.kind] then build.stats.evolutions[part.kind] = true end
    end
    local unique_cells = 0
    for _, kind in ipairs(util.sorted_keys(build.organs)) do
        if not util.index(build.unlocked, kind) then build.unlocked[#build.unlocked + 1] = kind end
        unique_cells = unique_cells + equipment.cell_cost(kind)
    end
    build.organ_capacity = state.body_capacity
    build.extra_organ_cells = math.max(0, slots.used_cells(state) - unique_cells)
end

local function discover(profile, build)
    for _, group in ipairs({build.organs, build.adaptations}) do
        for _, id in ipairs(util.sorted_keys(group)) do
            if not util.index(profile.discovered, id) then profile.discovered[#profile.discovered + 1] = id end
        end
    end
    for _, id in ipairs(catalog.SYNERGY_IDS) do
        local needs = catalog.SYNERGIES[id].needs
        if not util.index(profile.synergies, id)
            and (build.organs[needs[1]] or build.adaptations[needs[1]])
            and (build.organs[needs[2]] or build.adaptations[needs[2]]) then
            profile.synergies[#profile.synergies + 1] = id
        end
    end
end

function M.reroll_boss_reward(store, sim)
    if not matches_family(store, sim) then return false, "Эта жизнь принадлежит другому семейству" end
    local previous = unclaimed_reward(sim)
    if not previous or previous.rerolled then return false, "Переброс недоступен" end
    local balance = store.profile.organium
    if balance < M.BOSS_REROLL_COST then return false, "Недостаточно органиума" end
    local alternatives = {}
    for _, kind in ipairs(BOSS_ORGANS) do
        if kind ~= previous.organ then alternatives[#alternatives + 1] = kind end
    end
    local reward = util.copy(previous)
    reward.organ = alternatives[sim.pending_stage_seed % #alternatives + 1]
    reward.rerolled = true
    local profile = util.copy(store.profile)
    profile.organium = balance - M.BOSS_REROLL_COST
    profile.checkpoint = sim:snapshot()
    profile.checkpoint.boss_reward = reward
    local ok, error_text = save(store, profile)
    if ok then sim.boss_reward = reward end
    return ok, error_text
end

function M.claim_boss_reward(store, sim, take_organ)
    if not matches_family(store, sim) then return false, "Эта жизнь принадлежит другому семейству" end
    local reward = unclaimed_reward(sim)
    if not reward then return false, "Награда уже недоступна" end
    local profile = util.copy(store.profile)
    local checkpoint = sim:snapshot()
    local state, error_text = M.capture_equipment(profile, checkpoint.build)
    if not state then return false, error_text end
    local receipt = "Материалы сохранены у семейства"
    if take_organ then
        local result = equipment.award(state, reward.organ, 3)
        if not result.ok then return false, result.error end
        state, receipt = result.state, RECEIPTS[result.location]
    else
        for material, amount in pairs(sim:boss_reward_materials()) do
            profile.organ_materials[material] = math.min(util.MAX_INTEGER, (profile.organ_materials[material] or 0) + amount)
        end
    end
    checkpoint.boss_reward.claimed = true
    checkpoint.boss_reward.receipt = receipt
    checkpoint.stock_capacity = state.stock_capacity
    M.apply_equipment(state, checkpoint.build)
    discover(profile, checkpoint.build)
    profile.organism, profile.checkpoint = state, checkpoint
    local ok, error_text = save(store, profile)
    if not ok then return false, error_text end
    local before = util.copy(sim.build:active_synergies())
    M.apply_equipment(state, sim.build)
    sim.stock_capacity = state.stock_capacity
    sim.boss_reward = checkpoint.boss_reward
    local activated = {}
    for _, id in ipairs(sim.build:active_synergies()) do
        if not util.index(before, id) then activated[#activated + 1] = id end
    end
    return true, "", activated
end

local function current_ticks()
    local seconds = socket and socket.gettime and socket.gettime() or os.time() + os.clock() % 1
    return math.floor(seconds * 1000000)
end

function M.reroll_stage_area(store, sim, ticks_usec)
    if not matches_family(store, sim) then return false, "Эта жизнь принадлежит другому семейству" end
    if not sim.stage_transition or unclaimed_reward(sim) then return false, "Сначала забери награду" end
    local cost = M.stage_reroll_cost(sim.stage_index)
    if store.profile.organium < cost then return false, "Недостаточно органиума" end
    local previous = sim.pending_stage_seed
    local modulus = 2147483647
    local ticks = util.finite(ticks_usec) and util.integer(ticks_usec) or current_ticks()
    local random = rng.new((previous + ticks + sim.stage_index * 7919) % modulus)
    local replacement = random:randi_range(1, modulus - 1)
    if replacement == previous then replacement = replacement % (modulus - 1) + 1 end
    local profile = util.copy(store.profile)
    profile.organium = profile.organium - cost
    profile.checkpoint = sim:snapshot()
    profile.checkpoint.pending_stage_seed = replacement
    local ok, error_text = save(store, profile)
    if ok then sim.pending_stage_seed = replacement end
    return ok, error_text
end

function M.enter_next_stage(store, sim, prepared_world)
    if not matches_family(store, sim) then return false, "Эта жизнь принадлежит другому семейству" end
    if not sim.stage_transition or unclaimed_reward(sim) then return false, "Сначала забери награду" end
    local previous = sim:snapshot()
    local state, error_text = M.capture_equipment(store.profile, previous.build)
    if not state then return false, error_text end
    if not sim:enter_next_stage(prepared_world) then return false, "Переход недоступен" end
    local checkpoint = sim:snapshot()
    local profile = util.copy(store.profile)
    profile.organism, profile.checkpoint = state, checkpoint
    discover(profile, checkpoint.build)
    local ok, error_text = save(store, profile)
    if not ok then
        local restored = sim.restore(previous)
        if restored then
            for key in pairs(sim) do sim[key] = nil end
            for key, value in pairs(restored) do sim[key] = value end
        end
        sim.paused = true
    end
    return ok, error_text
end

return M
