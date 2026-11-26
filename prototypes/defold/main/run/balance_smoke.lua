local Simulation = require "main.run.simulation"
local Catalog = require "main.run.catalog"
local Build = require "main.run.build_model"
local Legacy = require "main.run.genome_legacy"
local Size = require "main.run.size_rules"
local SaveStore = require "main.run.save_store"
local Util = require "main.run.meta_util"
local Effects = require "main.run.effects_view"

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

local function validate_contact_balance()
    local sim = Simulation.new(147, nil, nil, "colony")
    local function impact(ratio, elite)
        local rules = Size.profile(100, 100 * ratio, 1, 0, 0, false)
        return sim:contact_impact(rules, elite), rules.impact
    end
    local small, original_small = impact(1.2, false)
    local medium, original_medium = impact(1.8, false)
    local large, original_large = impact(2.4, false)
    local elite, original_elite = impact(2.4, true)
    assert(small == original_small, "Small contact damage must remain unchanged")
    assert(medium < original_medium and medium > small, "Large contact damage must scale smoothly")
    assert(math.abs(large - original_large * 0.75) < 0.00001 and large > medium,
        "Largest ordinary amoebas must deal 25 percent less contact damage")
    assert(math.abs(elite - original_elite * 1.2) < 0.00001, "Elite contact damage must remain unchanged")
    print("MICROGEN CONTACT BALANCE READY")
end

local function validate_colony_coverage()
    local sim = Simulation.new(147, nil, nil, "colony", {form = "colony", branch = "colony", seed = 147})
    assert(sim.build:rank("division") == 1, "Colony must start with division")
    assert(Catalog.clone_count(1) == 2 and Catalog.clone_count(2) == 3
        and Catalog.clone_count(3) == 4 and Catalog.clone_count(4) == 5 and Catalog.clone_count(10) == 5,
        "Early clone count and late clone cap must match the balance rules")
    local clones = sim:clone_positions()
    assert(#clones == 2, "Colony must start with two actual clones")
    for index, p in ipairs(clones) do
        local q = clones[index % #clones + 1]
        local dx, dy = p.x - q.x, p.y - q.y
        assert(math.abs(dx * dx + dy * dy - 4 * 105 * 105) < 0.01,
            "Two clones must be opposite each other")
    end
    local restored = assert(Simulation.restore(sim:snapshot()))
    assert(#restored:clone_positions() == 2, "Reload must preserve colony coverage")
    print("MICROGEN COLONY COVERAGE READY")
end

local function validate_toxin_overlap()
    local sim = Simulation.new(147, nil, nil, "colony")
    sim.world.colonies = {}
    local p = sim.player
    local hits = {}
    sim.hurt_player = function(_, amount, source)
        hits[#hits + 1] = { amount = amount, id = source.id }
    end
    sim:_field(p, 48, 6, 2.8, "enemy_toxin", true, "Токсин", 101)
    sim:_field(p, 48, 8, 2.8, "enemy_toxin", true, "Токсин", 101)
    sim:_field({ x = p.x + 1000, y = p.y }, 48, 100, 2.8, "enemy_toxin", true, "Дальний токсин", 101)
    sim:_field(p, 48, 6, 2.8, "enemy_toxin", true, "Другой токсин", 102)
    sim:_field(p, 48, 4, 2.8, "enemy_toxin", true, "Старое поле")
    sim:_field(p, 48, 4, 2.8, "enemy_toxin", true, "Старое поле")
    sim:_update_fields(0.25)
    local totals, counts = {}, {}
    for _, hit in ipairs(hits) do
        local id = hit.id or 0
        totals[id] = (totals[id] or 0) + hit.amount
        counts[id] = (counts[id] or 0) + 1
    end
    assert(counts[101] == 1 and totals[101] == 2, "Same-source overlap must use only the strongest local field")
    assert(counts[102] == 1 and totals[102] == 1.5, "Independent hostile sources must retain their damage")
    assert(counts[0] == 2 and totals[0] == 2, "Legacy unidentified fields must remain independent")
    sim.world.colonies = {{ pos = p }}
    hits = {}
    sim:_update_fields(0.25)
    assert(#hits == 0, "Safe zones must still protect against hostile fields")
    print("MICROGEN TOXIN OVERLAP READY")
end

local function validate_save_recovery()
    -- Изолированный backend: настоящие файлы профиля игрока не затрагиваются.
    local records, fail_write = {}, false
    local backend = {
        get_save_file = function(_, filename) return filename end,
        load = function(path) return Util.copy(records[path]) end,
        save = function(path, record)
            if fail_write then return false end
            records[path] = Util.copy(record)
            return true
        end,
    }
    local store = SaveStore.new("balance_recovery", backend)
    assert(store:create_family("Первая", "predator"), "Initial family must be saved")
    local family = store:family_id()
    local sim = Simulation.new(147, nil, nil, "predator", {form = "predator", branch = "predator", seed = 147})
    sim.family_id, sim.hp, sim.elapsed = family, 62, 45
    assert(store:save_checkpoint(sim:snapshot(), family), "Checkpoint must be committed")
    assert(store:credit_once("test-reward", 7), "Reward must be credited once")
    local committed = store.revision
    fail_write = true
    assert(not store:bank(9) and store.revision == committed and store.profile.cores == 7,
        "Failed write must not change the committed in-memory profile")
    fail_write = false
    local reopened = SaveStore.new("balance_recovery", backend)
    reopened:load_profile()
    assert(reopened.revision == committed and reopened.profile.cores == 7,
        "Failed write must leave the last committed profile readable")
    assert(not reopened:credit_once("test-reward", 7) and reopened.profile.cores == 7,
        "Reload must not duplicate a previously credited reward")
    local restored = assert(Simulation.restore(reopened.profile.checkpoint))
    assert(restored.family_id == family and restored.hp == 62 and restored.elapsed == 45,
        "Reload must preserve the checkpoint and family identity")
    -- Повреждаем только самый свежий слот и проверяем предыдущую ревизию.
    records[reopened.paths[reopened.active_file]] = { revision = committed, profile = { version = -1 } }
    local fallback = SaveStore.new("balance_recovery", backend)
    fallback:load_profile()
    assert(fallback.revision == committed - 1 and fallback:family_id() == family,
        "Corrupted newest slot must fall back to the previous valid revision")
    local previous = assert(Simulation.restore(fallback.profile.checkpoint))
    assert(previous.hp == 62 and previous.elapsed == 45, "Fallback must retain the last valid checkpoint")
    assert(fallback:create_family("Вторая", "colony"), "Second family must be saved")
    assert(not fallback:save_checkpoint(sim:snapshot(), family), "Stale checkpoint must not overwrite another family")
    assert(fallback:select_family(family), "Original family must remain selectable")
    assert(fallback.profile.checkpoint.family_id == family, "Family switching must retain its own checkpoint")
    print("MICROGEN SAVE RECOVERY READY")
end

local function validate_form_specialization_data()
    local expected = {
        predator = {organ = "chemoreceptor_ridge", cells = 1},
        toxic = {organ = "osmotic_vacuole", cells = 2},
        colony = {organ = "synaptic_node", cells = 2},
    }
    for _, form_id in ipairs(Catalog.FORM_IDS) do
        local data, expected_form = Catalog.form_specialization(form_id), expected[form_id]
        assert(data and data.ability and data.passive and data.evolution, "Every form must define its ability, passive and evolution")
        assert(data.signature_organ == expected_form.organ, "Form signature organ must be stable")
        local organ = Catalog.ORGANS[data.signature_organ]
        assert(organ and organ.signature and organ.form == form_id, "Signature organ must belong to its form")
        assert(Catalog.cell_cost(data.signature_organ) == expected_form.cells, "Signature organ cell cost changed")
        assert(Catalog.SIGNATURE_ORGANS[data.signature_organ].form == form_id, "Signature organ parameters must match their form")
        assert(data.evolution.passive and data.evolution.passive_rank == 3, "Form evolution must use the shared passive-rank contract")
        assert(#(Catalog.SPECIALIZATIONS[data.signature_organ] or {}) == 2, "Every signature organ must have two specializations")
        local legacy_form = Legacy.FORMS[form_id]
        assert(legacy_form.signature_organ == data.signature_organ and legacy_form.ability == data.ability
            and legacy_form.passive == data.passive, "Legacy form metadata must point to the shared form model")
    end

    local baseline = Catalog.base_unlocked()
    assert(Util.index(baseline, "chemoreceptor_ridge"), "Predator signature organ must be available by default")
    assert(not Util.index(baseline, "osmotic_vacuole") and not Util.index(baseline, "synaptic_node")
        and not Util.index(baseline, "division"), "Research-gated organs must not be available by default")

    local staged = Build.new()
    staged.unlocked = {"chemoreceptor_ridge", "osmotic_vacuole", "synaptic_node"}
    local offers = staged:offers({randf = function() return 0 end})
    assert(#offers == 0, "Signature organs must not enter level-up offers before their combat effects are implemented")

    local old_unlocked = {
        "tentacle", "acid", "spikes", "pulse", "trail", "infection", "cilia", "enzymes",
        "electric", "barrier", "devour", "metabolism", "catalysis", "armor", "regen", "speed", "magnet",
    }
    local old_profile = SaveStore.defaults()
    old_profile.unlocked = Util.copy(old_unlocked)
    old_profile.legacy = Legacy.defaults()
    old_profile.legacy.research = {"toxic", "colony"}
    old_profile.legacy.selected_form = "toxic"
    old_profile.checkpoint = Simulation.new(147, nil, nil, "predator",
        {form = "predator", branch = "predator", seed = 147}):snapshot()
    old_profile.checkpoint.build.unlocked = Util.copy(old_unlocked)

    local migrated = SaveStore.normalize_profile(old_profile)
    assert(migrated, "An older profile with both form researches must remain valid")
    assert(Util.index(migrated.unlocked, "chemoreceptor_ridge")
        and Util.index(migrated.unlocked, "osmotic_vacuole")
        and Util.index(migrated.unlocked, "synaptic_node")
        and Util.index(migrated.unlocked, "division"), "Migration must restore all organs granted by existing research")
    assert(Util.index(migrated.checkpoint.build.unlocked, "chemoreceptor_ridge")
        and Util.index(migrated.checkpoint.build.unlocked, "osmotic_vacuole")
        and Util.index(migrated.checkpoint.build.unlocked, "synaptic_node"),
        "Migration must update the unlocked list inside an old checkpoint")
    local restored = Simulation.restore(migrated.checkpoint)
    assert(restored and Util.index(restored.build.unlocked, "osmotic_vacuole")
        and Util.index(restored.build.unlocked, "synaptic_node"), "Migrated checkpoint must restore with researched organs")

    local old_colony = SaveStore.defaults()
    old_colony.unlocked = Util.copy(old_unlocked)
    old_colony.unlocked[#old_colony.unlocked + 1] = "division"
    old_colony.legacy = Legacy.defaults()
    local migrated_colony = SaveStore.normalize_profile(old_colony)
    assert(migrated_colony and Util.index(migrated_colony.legacy.research, "colony")
        and Util.index(migrated_colony.unlocked, "synaptic_node"),
        "Legacy division unlock must imply colony research and its new signature organ")

    local archived_state = SaveStore.defaults()
    archived_state.families = nil
    archived_state.unlocked = Util.copy(old_unlocked)
    archived_state.legacy = Legacy.defaults()
    archived_state.legacy.research = {"toxic"}
    archived_state.legacy.selected_form = "toxic"
    local old_with_archive = Util.copy(old_profile)
    old_with_archive.checkpoint.family_id = "family-2"
    old_with_archive.families = {
        version = 1, active = "family-2", next_id = 3,
        items = {
            {id = "family-1", name = "Архивная железистая", form = "toxic", slot = 1, state = archived_state},
            {id = "family-2", name = "Активная хищная", form = "predator", slot = 2, state = {}},
        },
    }
    local migrated_archive = SaveStore.normalize_profile(old_with_archive)
    assert(migrated_archive, "Archived family profile must remain valid after migration")
    assert(Util.index(migrated_archive.families.items[1].state.unlocked, "osmotic_vacuole"),
        "Archived family migration must restore the signature organ from its saved research")

    local fresh = SaveStore.defaults()
    fresh.unlocked = Util.copy(old_unlocked)
    fresh.legacy = Legacy.defaults()
    local fresh_clean = SaveStore.normalize_profile(fresh)
    assert(fresh_clean and not Util.index(fresh_clean.unlocked, "osmotic_vacuole")
        and not Util.index(fresh_clean.unlocked, "synaptic_node"),
        "Migration must not grant forms that have not been researched")

    local records = {}
    local backend = {
        get_save_file = function(_, filename) return filename end,
        load = function(path) return Util.copy(records[path]) end,
        save = function(path, record) records[path] = Util.copy(record); return true end,
    }
    local store = SaveStore.new("signature_research", backend)
    store.profile.cores = 12
    assert(not store:unlock("osmotic_vacuole"), "Research-gated organ must not be purchased outside its research")
    assert(store:research("toxic") and Util.index(store.profile.unlocked, "osmotic_vacuole"),
        "Toxic research must unlock the osmotic vacuole")
    assert(store:research("colony") and Util.index(store.profile.unlocked, "synaptic_node")
        and Util.index(store.profile.unlocked, "division"), "Colony research must unlock division and the synaptic node")

    local family_records = {}
    local family_backend = {
        get_save_file = function(_, filename) return filename end,
        load = function(path) return Util.copy(family_records[path]) end,
        save = function(path, record) family_records[path] = Util.copy(record); return true end,
    }
    local family_store = SaveStore.new("signature_families", family_backend)
    assert(family_store:create_family("Железистая", "toxic")
        and Util.index(family_store.profile.unlocked, "osmotic_vacuole"),
        "Creating a researched toxic family must unlock its signature organ")
    assert(family_store:create_family("Колониальная", "colony")
        and Util.index(family_store.profile.unlocked, "synaptic_node")
        and Util.index(family_store.profile.unlocked, "division"),
        "Creating a colony family must unlock its signature organ and division")

    local old_build = Build.new()
    old_build:from_dict({unlocked = old_unlocked, organs = {devour = 1}})
    assert(Util.index(old_build.unlocked, "chemoreceptor_ridge"),
        "Loading a legacy build must append the new baseline signature organ")
    print("MICROGEN FORM SPECIALIZATION DATA READY")
end

local function validate_enemy_markers()
    local sim = Simulation.new(147, nil, nil, "toxic", {form = "toxic", seed = 147})
    local radius = sim:body_radius()
    local frames, labels = {}, {}
    local scene = {
        scale = 3, effects = {},
        draw_combat = function(_, _, frame, _, _, _, color)
            frames[#frames + 1] = {frame = frame, color = color}
        end,
        draw_number = function(_, _, label) labels[#labels + 1] = label end,
    }
    local function inspect(kind, ratio, hp, captured)
        frames, labels = {}, {}
        local actor = {kind = kind, pos = {x = sim.player.x + 100, y = sim.player.y},
            r = radius * ratio, hp = hp, max_hp = 100, captured = captured}
        Effects.draw_enemy_marker(scene, sim, actor, 0.2)
        local green = false
        for _, item in ipairs(frames) do
            assert(item.frame ~= "barb", "Hunter must never show the old orange icon")
            if item.frame == "ring" and item.color.y > 0.9 and item.color.x < 0.6 then green = true end
        end
        local marked = #labels > 0 and labels[#labels] == "ПОГЛОТИТЬ"
        assert(green == marked, "Absorption label and green ring must agree")
        return marked, actor
    end
    assert(inspect("prey", 0.5, 100), "Small prey must be clearly marked")
    assert(inspect("hunter", 1.0, 10), "Weakened edible hunter must be marked")
    assert(not inspect("hunter", 1.0, 100), "Healthy non-edible hunter must not be marked")
    assert(not inspect("hunter", 2.0, 1) and #frames == 1 and frames[1].frame == "ring",
        "Oversized hunter must show threat ring, not an absorption marker")
    assert(not inspect("miniboss", 0.5, 20), "Miniboss above 15 percent health must not be marked")
    assert(inspect("miniboss", 0.5, 15), "Eligible weakened miniboss must be marked")
    assert(not inspect("boss", 0.5, 1), "Boss must never have an absorption marker")
    assert(not inspect("prey", 0.5, 0) and #frames == 0, "Dead actor must not be marked")
    assert(not inspect("prey", 0.5, 100, true) and #frames == 0, "Captured actor must not be marked")
    assert(not inspect("clone", 0.5, 100) and #frames == 0, "Friendly clone must not be marked")
    assert(not inspect(nil, 0.5, 100) and #frames == 0, "Inactive resident must not be marked")
    assert(not inspect("spitter", 1.0, 100) and #frames == 1 and frames[1].frame == "plume",
        "Non-edible spitter must retain its distinct marker")
    print("MICROGEN ENEMY MARKERS READY")
end

function M.run()
    validate_form_specialization_data()
    validate_enemy_markers()
    validate_save_recovery()
    validate_toxin_overlap()
    validate_colony_coverage()
    validate_contact_balance()
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
