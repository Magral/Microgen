local Simulation = require "main.run.simulation"
local Catalog = require "main.run.catalog"

local M = {}
local STEP = 1 / 60
local HORIZON_SECONDS = 600
-- Одинаковые карты для всех форм: сравнение без подмены географии.
local SEEDS = {147, 171, 247, 271, 347, 371}
local BRANCHES = {
    {form = "predator", starter = "devour"},
    {form = "toxic", starter = "acid"},
    {form = "colony", starter = "division"},
}
local DIRECTIONS = {
    {1, 0}, {0.70710678, 0.70710678}, {0, 1}, {-0.70710678, 0.70710678},
    {-1, 0}, {-0.70710678, -0.70710678}, {0, -1}, {0.70710678, -0.70710678},
}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local PILOT_PRIORITY = {
    predator = { devour = 120, tentacle = 115, spikes = 110, cilia = 100, pulse = 95, acid = 60 },
    toxic = { acid = 120, infection = 115, enzymes = 110, trail = 100, electric = 70, barrier = 80 },
    colony = { division = 120, electric = 115, barrier = 110, pulse = 95, spikes = 80 },
}

local function mutation_priority(sim, id)
    local branch = PILOT_PRIORITY[sim.build.branch] or {}
    local priority = branch[id] or 35
    if sim.build:rank(id) > 0 then priority = priority + 12 end
    if id == "regen" then return 105 end
    if id == "armor" then return 90 end
    if id == "speed" then return 78 end
    if id == "catalysis" and sim.build:used_organ_cells() > 0 then return 88 end
    if id == "magnet" then return 18 end
    return priority
end

local function settle_levels(sim)
    while sim.pending_levels > 0 do
        local offers = sim:prepare_offers()
        table.sort(offers, function(a, b)
            local score_a, score_b = mutation_priority(sim, a), mutation_priority(sim, b)
            if score_a == score_b then return a < b end
            return score_a > score_b
        end)
        local selected = false
        for _, id in ipairs(offers) do
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

local function direction(sim, tick)
    local player, radius = sim.player, sim:body_radius()
    local away_x, away_y, nearest_target, target_score = 0, 0, nil, math.huge
    for _, enemy in ipairs(sim.enemies) do
        if enemy.hp > 0 and not enemy.captured then
            local dx, dy = player.x - enemy.pos.x, player.y - enemy.pos.y
            local distance = math.sqrt(dx * dx + dy * dy)
            local edible = enemy.kind == "prey" or
                (enemy.r <= radius * 1.2 and sim:interaction(enemy).eligible)
            if edible then
                local cost = distance + (enemy.kind == "prey" and 0 or 80)
                if cost < target_score then nearest_target, target_score = enemy, cost end
            elseif distance < 380 then
                local weight = (380 - distance) / 380 / math.max(40, distance)
                away_x, away_y = away_x + dx * weight, away_y + dy * weight
            end
        end
    end
    if sim.elapsed >= 8 then
        for _, resident in ipairs(sim.residents) do
            if not resident.dead and not resident.active then
                local dx, dy = player.x - resident.pos.x, player.y - resident.pos.y
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance < 380 then
                    local weight = (380 - distance) / 380 / math.max(40, distance)
                    away_x, away_y = away_x + dx * weight, away_y + dy * weight
                end
            end
        end
    end

    local away_length = math.sqrt(away_x * away_x + away_y * away_y)
    local desired_x, desired_y
    if away_length > 0.0001 then
        desired_x, desired_y = away_x / away_length, away_y / away_length
    elseif nearest_target then
        local dx, dy = nearest_target.pos.x - player.x, nearest_target.pos.y - player.y
        local distance = math.max(0.0001, math.sqrt(dx * dx + dy * dy))
        desired_x, desired_y = dx / distance, dy / distance
    else
        local roam = DIRECTIONS[math.floor(sim.elapsed / 12) % #DIRECTIONS + 1]
        desired_x, desired_y = roam[1], roam[2]
    end

    local best_x, best_y, best_score = desired_x, desired_y, -math.huge
    local step_distance = math.max(16, 85 * STEP * 2)
    for _, candidate in ipairs(DIRECTIONS) do
        local nx, ny = player.x + candidate[1] * step_distance, player.y + candidate[2] * step_distance
        local score = candidate[1] * desired_x + candidate[2] * desired_y
        if not sim.world:walkable(nx, ny, math.min(26, radius * 0.65)) then
            score = score - 100
        end
        for _, enemy in ipairs(sim.enemies) do
            if enemy.hp > 0 and not enemy.captured and enemy.kind ~= "prey" then
                local current_x, current_y = player.x - enemy.pos.x, player.y - enemy.pos.y
                local next_x, next_y = nx - enemy.pos.x, ny - enemy.pos.y
                local current_distance = math.sqrt(current_x * current_x + current_y * current_y)
                local next_distance = math.sqrt(next_x * next_x + next_y * next_y)
                if current_distance < 520 or next_distance < 520 then
                    local clearance = enemy.r + radius * 0.75 + 65
                    score = score + (next_distance - current_distance) * 0.025
                        - math.max(0, clearance - next_distance) * 0.03
                end
            end
        end
        for _, field in ipairs(sim.fields) do
            if field.hostile then
                local fx, fy = nx - field.pos.x, ny - field.pos.y
                local distance = math.sqrt(fx * fx + fy * fy)
                local clearance = field.r + radius * 0.65 + 60
                score = score - math.max(0, clearance - distance) * 0.025
            end
        end
        for _, colony in ipairs(sim.world.colonies) do
            local cx, cy = nx - colony.pos.x, ny - colony.pos.y
            if cx * cx + cy * cy < 150 * 150 then score = score + 0.08 end
        end
        if score > best_score then best_x, best_y, best_score = candidate[1], candidate[2], score end
    end
    return best_x, best_y
end

local function run(seed, scenario, horizon_seconds)
    horizon_seconds = horizon_seconds or HORIZON_SECONDS
    local branch, starter = scenario.form, scenario.starter
    local sim = Simulation.new(seed, nil, nil, branch, {form = branch, branch = branch, seed = seed})
    assert(sim.build:rank(starter) == 1, "Balance run must start with its form's organ")
    local max_enemies, max_fields, max_remains = 0, 0, 0
    local steps, first_hit = 0, nil
    local toxin_sources = {}
    local original_hurt = sim.hurt_player
    sim.hurt_player = function(self, amount, source)
        local health_before = self.hp
        original_hurt(self, amount, source)
        local dealt = health_before - self.hp
        if dealt > 0 and source and source.kind == "toxin" then
            local id = tostring(source.id or 0)
            local entry = toxin_sources[id]
            if not entry then
                entry = { id = id, name = source.name or "Источник неизвестен", damage = 0, hits = 0, first = self.elapsed }
                toxin_sources[id] = entry
            end
            entry.damage, entry.hits, entry.last = entry.damage + dealt, entry.hits + 1, self.elapsed
        end
    end

    for tick = 1, horizon_seconds * 60 do
        if sim.outcome ~= "" then break end
        settle_stage(sim)
        settle_levels(sim)
        settle_rewards(sim)

        local move_x, move_y = direction(sim, tick)
        local health_before = sim.hp
        sim:step(STEP, move_x, move_y)
        if not first_hit and sim.hp < health_before then
            local hit = sim.last_damage
            if hit then first_hit = string.format("%.1f/%s/%s", hit.time, hit.kind, hit.name) end
        end
        settle_levels(sim)
        settle_rewards(sim)
        settle_stage(sim)
        sim.feedback = {}

        steps = tick
        max_enemies = math.max(max_enemies, #sim.enemies)
        max_fields = math.max(max_fields, #sim.fields)
        max_remains = math.max(max_remains, #sim.remains)

        assert(finite(sim.elapsed) and finite(sim.hp) and finite(sim.player.x) and finite(sim.player.y),
            "Balance run produced a non-finite simulation value")
        assert(#sim.enemies <= Simulation.ENEMY_CAP, "Balance run exceeded the enemy cap")
        assert(#sim.fields <= 80, "Balance run exceeded the field cap")
        assert(#sim.remains <= 96, "Balance run exceeded the remains cap")
    end

    assert(finite(sim.elapsed) and finite(sim.build.biomass) and finite(sim.kills),
        "Balance run ended with invalid summary values")
    local history = sim.combat_stats.history
    local last_hit = history[#history]
    local cause = last_hit and string.format("%s/%s/%.1f", last_hit.kind, last_hit.name, last_hit.amount) or "none"
    local sources = {}
    for _, entry in pairs(sim.combat_stats.sources) do
        if entry.damage > 0 then sources[#sources + 1] = entry end
    end
    table.sort(sources, function(a, b)
        if a.damage == b.damage then return a.name < b.name end
        return a.damage > b.damage
    end)
    local source_labels = {}
    for index = 1, math.min(3, #sources) do
        local entry = sources[index]
        source_labels[index] = string.format("%s/%s=%.1f(%d)", entry.kind, entry.name, entry.damage, entry.hits)
    end
    local source_summary = #source_labels > 0 and table.concat(source_labels, ";") or "none"
    local toxin_labels = {}
    for _, entry in pairs(toxin_sources) do toxin_labels[#toxin_labels + 1] = entry end
    table.sort(toxin_labels, function(a, b)
        if a.damage == b.damage then return a.id < b.id end
        return a.damage > b.damage
    end)
    local toxin_summary = {}
    for index = 1, math.min(4, #toxin_labels) do
        local entry = toxin_labels[index]
        toxin_summary[index] = string.format("%s/%s=%.1f(%d)@%.1f-%.1f", entry.id, entry.name,
            entry.damage, entry.hits, entry.first, entry.last or entry.first)
    end
    local toxin_source_summary = #toxin_summary > 0 and table.concat(toxin_summary, ";") or "none"
    print(string.format(
        "MICROGEN BALANCE RUN seed=%d branch=%s starter=%s pilot=kite seconds=%.1f stage=%d level=%d kills=%d hp=%.1f damage_taken=%.1f first_hit=%s last_hit=%s damage_sources=%s toxin_sources=%s outcome=%s steps=%d peak_enemies=%d peak_fields=%d peak_remains=%d",
        seed, branch, starter, sim.elapsed, sim.stage_index, sim.level, sim.kills, sim.hp,
        sim.combat_stats.damage_taken, first_hit or "none", cause, source_summary, toxin_source_summary,
        sim.outcome == "" and "alive" or sim.outcome, steps, max_enemies, max_fields, max_remains))
    return { alive = sim.outcome == "", seconds = sim.elapsed, hp = sim.hp, level = sim.level, kills = sim.kills }
end

local function validate_resident_start_safety()
    local sim = Simulation.new(347, nil, nil, "colony")
    local resident = sim.residents[1]
    resident.pos = { x = sim.player.x, y = sim.player.y }
    for index = 2, #sim.residents do
        sim.residents[index].pos = { x = sim.player.x + 1200 + index * 100, y = sim.player.y }
    end

    sim.elapsed = 0
    sim:_update_ecology()
    assert(not resident.active and #sim.enemies == 0,
        "Resident amoeba became hostile during the initial safety window")

    sim.elapsed = 7.99
    sim:_update_ecology()
    assert(not resident.active and #sim.enemies == 0,
        "Resident amoeba became hostile before the eight-second safety window ended")

    sim.elapsed = 8
    sim:_update_ecology()
    assert(resident.active and #sim.enemies == 1,
        "Resident amoeba did not activate after the initial safety window")
    print("MICROGEN RESIDENT START SAFETY READY")
end

local function validate_combat_checkpoint()
    local sim = Simulation.new(347, nil, nil, "predator", {form = "predator", seed = 347})
    sim.elapsed, sim.hp, sim.bite_flash, sim._danger_at = 120, 20, 0.8, 119.5
    sim.cooldowns.devour = 0.25
    local spitter = assert(sim:spawn_enemy({x = sim.player.x + 300, y = sim.player.y}, "spitter"))
    spitter.shot_cd = 0
    sim:_spitter_windup(spitter, STEP, 300)
    local saved = sim:snapshot()
    local restored = assert(Simulation.restore(saved))
    assert(restored.bite_flash == sim.bite_flash and restored._danger_at == sim._danger_at
        and restored.cooldowns.devour == sim.cooldowns.devour,
        "Reload must preserve bite state and cooldowns")

    local resumed_spitter = restored.enemies[1]
    assert(resumed_spitter.spit_windup == spitter.spit_windup
        and resumed_spitter.spit_angle == spitter.spit_angle,
        "Reload must preserve an ongoing enemy windup")
    local delay = spitter.spit_windup
    sim:_spitter_windup(spitter, delay, 300)
    restored:_spitter_windup(resumed_spitter, delay, 300)
    local shot, resumed_shot = sim.shots[1], restored.shots[1]
    assert(shot and resumed_shot and shot.vel.x == resumed_shot.vel.x and shot.vel.y == resumed_shot.vel.y,
        "Resumed enemy attack must follow the original direction")

    saved.bite_flash, saved._danger_at = nil, nil
    local legacy = assert(Simulation.restore(saved))
    assert(legacy.bite_flash == 0 and legacy._danger_at == -10, "Older saves must remain readable")
    print("MICROGEN COMBAT CHECKPOINT READY")
end

function M.run()
    validate_resident_start_safety()
    validate_combat_checkpoint()
    for _, scenario in ipairs(BRANCHES) do
        local seconds, levels, kills, survivors = 0, 0, 0, 0
        for _, seed in ipairs(SEEDS) do
            local result = run(seed, scenario)
            seconds = seconds + result.seconds
            levels = levels + result.level
            kills = kills + result.kills
            if result.alive then survivors = survivors + 1 end
            collectgarbage("collect")
        end
        print(string.format("MICROGEN BALANCE SUMMARY branch=%s maps=%d mean_seconds=%.1f mean_level=%.2f mean_kills=%.2f survivors=%d",
            scenario.form, #SEEDS, seconds / #SEEDS, levels / #SEEDS, kills / #SEEDS, survivors))
    end
    print("MICROGEN BALANCE SMOKE READY")
end

return M
