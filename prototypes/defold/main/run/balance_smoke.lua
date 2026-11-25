local Simulation = require "main.run.simulation"
local Catalog = require "main.run.catalog"

local M = {}
local STEP = 1 / 60
local HORIZON_SECONDS = 600
local SEEDS = {47, 71}
local BRANCHES = {"predator", "toxic", "colony"}
local DIRECTIONS = {
    {1, 0}, {0.70710678, 0.70710678}, {0, 1}, {-0.70710678, 0.70710678},
    {-1, 0}, {-0.70710678, -0.70710678}, {0, -1}, {0.70710678, -0.70710678},
}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function settle_levels(sim)
    while sim.pending_levels > 0 do
        local selected = false
        for _, id in ipairs(sim:prepare_offers()) do
            if sim:choose_mutation(id) then
                selected = true
                break
            end
        end
        if not selected then
            if not sim:take_level_biomass() then sim:commit_level_pick() end
        end
    end
end

local function settle_rewards(sim)
    local attempts = 0
    while #sim.reward_queue > 0 and attempts < 16 do
        attempts = attempts + 1
        local options = sim:prepare_reward()
        local claimed = false
        for index = 1, #options do
            if sim:claim_reward(index) then
                claimed = true
                break
            end
        end
        if not claimed then break end
    end
end

local function settle_stage(sim)
    if not sim.stage_transition then return end
    if sim.boss_reward and sim.boss_reward.organ then
        local claimed = sim:claim_boss_reward()
        if not claimed then
            for _, id in ipairs(Catalog.ORGAN_IDS) do
                if sim.build:rank(id) > 0 and sim:claim_boss_reward(id) then
                    claimed = true
                    break
                end
            end
        end
    end
    assert(sim:enter_next_stage(), "Balance run could not enter the next stage")
end

local function run(seed, branch)
    local sim = Simulation.new(seed, nil, nil, branch)
    local max_enemies, max_fields, max_remains = 0, 0, 0
    local steps = 0

    for tick = 1, HORIZON_SECONDS * 60 do
        if sim.outcome ~= "" then break end
        settle_stage(sim)
        settle_levels(sim)
        settle_rewards(sim)

        local direction = DIRECTIONS[math.floor(sim.elapsed / 20) % #DIRECTIONS + 1]
        sim:step(STEP, direction[1], direction[2])
        settle_levels(sim)
        settle_rewards(sim)
        settle_stage(sim)

        steps = tick
        max_enemies = math.max(max_enemies, #sim.enemies)
        max_fields = math.max(max_fields, #sim.fields)
        max_remains = math.max(max_remains, #sim.remains)

        assert(finite(sim.elapsed) and finite(sim.hp) and finite(sim.player.x) and finite(sim.player.y),
            "Balance run produced a non-finite simulation value")
        assert(#sim.enemies <= 28, "Balance run exceeded the enemy cap")
        assert(#sim.fields <= 80, "Balance run exceeded the field cap")
        assert(#sim.remains <= 96, "Balance run exceeded the remains cap")
    end

    assert(finite(sim.elapsed) and finite(sim.build.biomass) and finite(sim.kills),
        "Balance run ended with invalid summary values")
    print(string.format(
        "MICROGEN BALANCE RUN seed=%d branch=%s seconds=%.1f stage=%d level=%d kills=%d hp=%.1f outcome=%s steps=%d peak_enemies=%d peak_fields=%d peak_remains=%d",
        seed, branch, sim.elapsed, sim.stage_index, sim.level, sim.kills, sim.hp,
        sim.outcome == "" and "alive" or sim.outcome, steps, max_enemies, max_fields, max_remains))
    return sim.elapsed
end

function M.run()
    for index, branch in ipairs(BRANCHES) do
        for _, seed in ipairs(SEEDS) do
            run(seed + index * 100, branch)
        end
    end
    print("MICROGEN BALANCE SMOKE READY")
end

return M
