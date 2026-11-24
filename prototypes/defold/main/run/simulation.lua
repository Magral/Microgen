local World = require("main.run.world")
local Rng = require("main.run.rng")
local Build = require("main.run.build_model")
local Catalog = require("main.run.catalog")
local Genome = require("main.run.genome")
local Heredity = require("main.run.heredity")
local Rewards = require("main.run.rewards")
local Size = require("main.run.size_rules")
local V = require("main.run.combat_math")
local Combat = require("main.run.combat")
local Stats = require("main.run.combat_stats")

local Simulation = {}
Simulation.__index = function(_, key) return Simulation[key] or Combat[key] end
local point, offset, distance_squared, contains, copy = V.point, V.offset, V.distance_squared, V.contains, V.copy
local min, max, floor, ceil, sqrt, exp = math.min, math.max, math.floor, math.ceil, math.sqrt, math.exp
local clamp, smoothstep, TAU = Size.clamp, Size.smoothstep, V.tau
local ENEMY_CAP, REMAINS_CAP = 28, 96
local STAGE_NAMES = {"Соляная полость", "Кристаллический желоб", "Тихая лагуна", "Споровый разлом", "Глубинная взвесь", "Живой термоклин", "Мембранный каньон", "Янтарный провал"}
local BOSS_NAMES = {"Архицит", "Мембранный левиафан", "Поглотитель бездны", "Матка спор", "Кристаллический колосс"}
local MINIBOSS_NAMES = {"Матриарх", "Фагоцит", "Споровый страж", "Кристаллический хищник"}
local next_run = 0

function Simulation.new(seed, unlocked, upgrades, branch, loadout)
    seed = floor(tonumber(seed) or 1)
    next_run = next_run + 1
    local self = setmetatable({
        family_id = "", stock_capacity = 3, run_loadout = Heredity.normalize(loadout),
        world = World.generate(seed), rng = Rng.new(seed), build = Build.new(), upgrades = copy(upgrades or {}),
        hp = 100, max_hp = 100, elapsed = 0, xp = 0, level = 1, pending_levels = 0,
        enemies = {}, pickups = {}, remains = {}, fields = {}, shots = {}, effects = {}, residents = {},
        cysts = {}, events = {}, feedback = {}, explored = {}, cooldowns = {}, damage_markers = {}, last_damage = {},
        combat_stats = Stats.create(),
        reward_queue = {}, reward_options = {}, pending_inventory = {}, offer_quality = {}, claimed_rewards = {},
        current_offers = {}, boss_reward = {}, boss_breakup = {}, material_pending = {}, material_batch = 0,
        stage_index = 1, best_stage = 0, minibosses_spawned = 0, minibosses_defeated = 0, next_miniboss_at = 180,
        stage_transition = false, pending_stage_seed = 0, boss_spawned = false, boss_marker = point(),
        digesting_id = -1, paused = false, outcome = "", player_velocity = point(), bite_flash = 0,
        next_id = 0, kills = 0, cores_found = 0, rerolls = 0, spawn_timer = 0, invuln = 0, spore_charge = 0,
        run_id = string.format("%d-%d-%d-%d", seed, os.time(), floor(os.clock() * 1000000), next_run), _danger_at = -10,
    }, Simulation)
    self.player, self.previous_player = self.world.start, self.world.start
    self.inherited_traits = Heredity.traits(self.run_loadout)
    self.player_genome = next(self.run_loadout) and Heredity.recipe(self.run_loadout) or Genome.create(seed, 0, "player", 0)
    self.facing = self.player_genome.rotation
    self.tissue_pigment = V.pigment(Genome.colors(self.player_genome)[1])
    if self.run_loadout.ancestry_recipe then
        V.combine(self.tissue_pigment, V.pigment(Genome.colors(self.run_loadout.ancestry_recipe)[1], 6))
    end
    local build = self.build
    build.unlocked = copy(unlocked or Catalog.base_unlocked())
    build.branch = branch or "predator"
    if next(self.run_loadout) then
        build.branch = self.run_loadout.branch
        local starter = ({ predator = "devour", toxic = "acid", colony = "division" })[self.run_loadout.form]
        if not contains(build.unlocked, starter) then build.unlocked[#build.unlocked + 1] = starter end
        build:apply(starter)
        local imprint = self.run_loadout.imprint
        if Catalog.ORGANS[imprint] and contains(build.unlocked, imprint) and build:rank(imprint) == 0 then build:apply(imprint) end
    else
        build:apply("tentacle")
    end
    build.branch_weight = self:has_trait("receptive") and 1.75 or 1.35
    self.max_hp = 100 + (self.upgrades.health or 0) * 5
    self.hp = self.max_hp
    self:_populate_stage()
    self:_reveal()
    return self
end

function Simulation:has_trait(id)
    return contains(self.inherited_traits, id)
end

function Simulation:_ready(id)
    return (self.cooldowns[id] or 0) <= 0
end

function Simulation:xp_needed()
    return 12 + (self.level - 1) * 6
end

function Simulation:gain_xp(amount)
    self.xp = self.xp + amount * (1 + self.build:passive("metabolism")) * (self:has_trait("receptive") and 0.95 or 1)
    while self.xp >= self:xp_needed() do
        self.xp = self.xp - self:xp_needed()
        self.level, self.pending_levels = self.level + 1, self.pending_levels + 1
    end
end

function Simulation:body_radius()
    if self._radius_level ~= self.level or self._radius_xp ~= self.xp then
        self._radius_level, self._radius_xp = self.level, self.xp
        self._radius = clamp(22 + (max(1, self.level) - 1 + clamp(self.xp / self:xp_needed(), 0, 1)) * 4, 22, 96)
    end
    return self._radius
end

function Simulation:view_zoom()
    local radius = self:body_radius()
    return (68 + math.log(max(1, radius / 22)) * 12) / radius
end

function Simulation:body_color()
    return V.pigment_color(self.tissue_pigment)
end

function Simulation:ability_scale()
    return self:body_radius() / 34
end

function Simulation:cooldown_factor()
    return self.world.conditions[self.world:biome(self.player.x, self.player.y)] == 2 and 0.88 or 1
end

function Simulation:attraction_radius()
    return self:body_radius() + self.build:passive("magnet") + (self.upgrades.collect or 0) * 8
end

function Simulation:sensing_radius()
    return self:has_trait("sensory") and 400 or 240
end

function Simulation:_feedback(kind, pos, amount, source)
    if #self.feedback >= 48 then
        if kind == "hit" then return end
        local expendable = 1
        for i, entry in ipairs(self.feedback) do if entry.kind == "hit" then expendable = i; break end end
        table.remove(self.feedback, expendable)
    end
    self.feedback[#self.feedback + 1] = { kind = kind, pos = pos, amount = amount or 0, tier = floor(amount or 0), source = source or "" }
end

function Simulation:_effect(kind, pos, radius, life, extras)
    if Catalog.SYNERGIES[kind] or kind == "electric" or kind == "enzymes" or kind == "cilia" then
        self:_feedback("synergy", pos)
    end
    if #self.effects >= 160 then table.remove(self.effects, 1) end
    local effect = extras or {}
    effect.type, effect.pos, effect.r, effect.life, effect.max = kind, pos, radius, life, life
    self.effects[#self.effects + 1] = effect
end

function Simulation:_event(kind, entry)
    entry.type = kind
    self.events[#self.events + 1] = entry
end

function Simulation:_message(text)
    self:_event("message", { text = text })
end

function Simulation:_id()
    local id = self.next_id
    self.next_id = id + 1
    return id
end

function Simulation:stage_name(index, seed)
    seed = seed and seed >= 0 and seed or self.world.seed_value
    index = index and index > 0 and index or self.stage_index
    return STAGE_NAMES[(seed + index * 13) % #STAGE_NAMES + 1]
end

function Simulation:boss_title(index, seed)
    seed = seed and seed >= 0 and seed or self.world.seed_value
    index = index and index > 0 and index or self.stage_index
    return BOSS_NAMES[(seed + index * 7) % #BOSS_NAMES + 1]
end

function Simulation:stage_miniboss_target(index)
    return (index and index > 0 and index or self.stage_index) <= self.best_stage and 1 or 2
end

function Simulation:boss_reward_materials()
    return { organelle = 5 + min(15, self.stage_index), membrane = 4 + min(12, self.stage_index), plasma = 3 + min(10, self.stage_index) }
end

function Simulation:_safe_zone(pos)
    for _, colony in ipairs(self.world.colonies) do
        if distance_squared(pos, colony.pos) < 150^2 then return true end
    end
    return false
end

function Simulation:nearby_colony()
    for i, colony in ipairs(self.world.colonies) do
        if distance_squared(self.player, colony.pos) < 150^2 then return i end
    end
    return 0
end

function Simulation:_reveal()
    local world, p = self.world, self.player
    local tx, ty = floor(p.x / world.tile_size), floor(p.y / world.tile_size)
    local key = ty * world.w + tx + 1
    if self.last_tile == key then return end
    self.last_tile = key
    for y = max(0, ty - 4), min(world.h - 1, ty + 4) do
        for x = max(0, tx - 4), min(world.w - 1, tx + 4) do
            if (x - tx)^2 + (y - ty)^2 <= 4.5^2 then self.explored[y * world.w + x + 1] = true end
        end
    end
    for _, colony in ipairs(world.colonies) do
        if distance_squared(p, colony.pos) < 550^2 then colony.visited = true end
    end
end

function Simulation:_drop(pos, kind, amount)
    if #self.pickups >= 600 then
        local first, merge_a, merge_b = {}, nil, nil
        for i, item in ipairs(self.pickups) do
            if item.type == kind then item.amount = item.amount + amount; return end
            if first[item.type] and not merge_a then merge_a, merge_b = first[item.type], i end
            first[item.type] = first[item.type] or i
        end
        if merge_a then
            self.pickups[merge_a].amount = self.pickups[merge_a].amount + self.pickups[merge_b].amount
            table.remove(self.pickups, merge_b)
        end
    end
    local item = { pos = pos, type = kind, amount = amount, id = self:_id() }
    self.pickups[#self.pickups + 1] = item
    return item
end

function Simulation:_create_residents()
    local rng = Rng.new(self.world.seed_value + 991721)
    self.residents = {}
    for i = 0, 3 do
        local anchor = offset(self.player, 0.15 + i * 1.65, 215 + i * 320)
        local p, biome
        for _ = 1, 30 do
            local candidate = point(anchor.x + rng:randf_range(-60, 60), anchor.y + rng:randf_range(-60, 60))
            if self.world:walkable(candidate.x, candidate.y, 26) then
                p, biome = candidate, self.world:biome(candidate.x, candidate.y) - 1
                break
            end
        end
        p, biome = p or point(self.player.x + 195, self.player.y + i * 18 - 27), biome or 0
        self.residents[#self.residents + 1] = {
            id = -100 - i, pos = p, r = 72 + i * 2, hp = 360 + i * 60, max_hp = 360 + i * 60,
            genome = Genome.create(self.world.seed_value, -100 - i, "hunter", biome), active = false, dead = false,
        }
    end
end

function Simulation:_create_expansions()
    local placed
    for _, kind in ipairs({"body_extension", "stock_extension"}) do
        local best, best_score = nil, math.huge
        local desired = kind == "body_extension" and 750 or 1400
        for _, item in ipairs(self.pickups) do
            if item.type == "dna" then
                local distance = sqrt(distance_squared(item.pos, self.world.start))
                local score = math.abs(distance - desired)
                if distance >= 500 and score < best_score and (not placed or distance_squared(item.pos, placed) >= 220^2)
                    and self.world:walkable(item.pos.x, item.pos.y, 35) then
                    best, best_score = item, score
                end
            end
        end
        if best then best.type, best.amount, placed = kind, 1, best.pos end
    end
end

function Simulation:_spawn_cyst(pos, tier, identity)
    if #self.cysts >= 12 then return end
    local token = self.run_id .. ":stage:" .. self.stage_index .. ":cyst:" .. identity
    if contains(self.claimed_rewards, token) then return end
    for _, cyst in ipairs(self.cysts) do if cyst.token == token then return end end
    local id = -300
    for n = 1, #identity do id = (id * 33 - identity:byte(n)) % 1000000000 end
    self.cysts[#self.cysts + 1] = {
        id = -300 - id, pos = pos, tier = clamp(tier, 1, 3), r = 21 + tier * 4,
        token = token, captured = false, progress = 0, duration = 0.65,
    }
end

function Simulation:_create_cysts()
    local world, rng = self.world, Rng.new(self.world.seed_value + 811733)
    self.cysts = {}
    for i, tier in ipairs({1, 1, 2, 1, 2, 3}) do
        for _ = 1, 100 do
            local p
            if i == 1 then p = offset(world.start, rng:randf() * TAU, rng:randf_range(380, 650))
            else p = point(rng:randf_range(220, world.w * world.tile_size - 220), rng:randf_range(220, world.h * world.tile_size - 220)) end
            local available = distance_squared(p, world.start) >= 350^2 and world:walkable(p.x, p.y, 28) and not self:_safe_zone(p)
            if available then
                for _, cyst in ipairs(self.cysts) do
                    if distance_squared(cyst.pos, p) < 220^2 then available = false; break end
                end
            end
            if available then self:_spawn_cyst(p, tier, "map:" .. (i - 1)); break end
        end
    end
end

function Simulation:_populate_stage()
    self.pickups = {}
    local world, rng = self.world, self.rng
    for _, nutrient in ipairs(world.nutrients) do self:_drop(nutrient.pos, "dna", nutrient.rich and 8 or 3) end
    local quality_rng = Rng.new(world.seed_value + 889711)
    for _, colony in ipairs(world.colonies) do
        local organs = {}
        for _, id in ipairs(self.build.unlocked) do if Catalog.ORGANS[id] then organs[#organs + 1] = id end end
        colony.stock = {}
        local branch = world:biome(colony.pos.x, colony.pos.y) == 2 and "toxic" or "predator"
        for _ = 1, 2 do
            if #organs == 0 then break end
            local pool = {}
            for i, id in ipairs(organs) do if Catalog.item(id).branch == branch then pool[#pool + 1] = i end end
            local index = #pool > 0 and pool[rng:randi_range(1, #pool)] or rng:randi_range(1, #organs)
            colony.stock[#colony.stock + 1] = {
                id = table.remove(organs, index), price = 18 + rng:randi_range(0, 6), sold = false,
                quality = Rewards.roll_quality(quality_rng, 1),
            }
        end
        colony.stock[#colony.stock + 1] = { id = "heal", price = 12, sold = false }
    end
    self:_create_residents()
    for i = 0, 11 do
        local p = offset(self.player, i * 2.399, 85 + i * 27)
        if world:walkable(p.x, p.y, 7) then self:_drop(p, "heal", 6) end
    end
    self:_create_expansions()
    self:_create_cysts()
    for i = 0, 7 do self:_drop(offset(self.player, i * TAU / 8, rng:randf_range(70, 220)), "dna", 3) end
end

function Simulation:enter_next_stage(prepared_world)
    if not self.stage_transition then return false end
    self.stage_index = self.stage_index + 1
    self.pending_stage_seed = max(1, self.pending_stage_seed)
    self.world = prepared_world and prepared_world.seed_value == self.pending_stage_seed and prepared_world or World.generate(self.pending_stage_seed)
    self.rng = Rng.new(self.pending_stage_seed)
    self.player, self.previous_player, self.player_velocity = self.world.start, self.world.start, point()
    self.last_damage, self._danger_at = {}, -10
    self.enemies, self.remains, self.fields, self.shots, self.effects, self.damage_markers = {}, {}, {}, {}, {}, {}
    self.cooldowns, self.explored, self.events, self.current_offers, self.offer_quality = {}, {}, {}, {}, {}
    self.digesting_id, self.boss_spawned, self.boss_marker = -1, false, point()
    self.minibosses_spawned, self.minibosses_defeated = 0, 0
    self.stage_transition, self.boss_reward, self.boss_breakup = false, {}, {}
    self.spawn_timer, self.last_tile = 0, nil
    self:_populate_stage()
    self:_reveal()
    return true
end

function Simulation:spawn_enemy(pos, kind)
    if #self.enemies >= ENEMY_CAP then return end
    local boss, prey = kind == "boss", kind == "prey"
    local rng, seed = self.rng, self.world.seed_value
    local variant = rng:randi_range(0, 3)
    local id = self:_id()
    local traits = Genome.traits(seed, id, self.elapsed, kind)
    local health = (prey and 8 or 40 + self.elapsed * 0.17) * (variant == 1 and 1.4 or 1)
    if boss then health = 1600 * (1 + 0.14 * (self.stage_index - 1))
    elseif contains(traits, "shell") then health = health * 1.3 end
    local biome = self.world:biome(pos.x, pos.y) - 1
    local enemy = {
        pos = pos, kind = kind, hp = health, max_hp = health, r = prey and 12 or (boss and 140 or 23 + rng:randf() * 6),
        speed = prey and 42 or (boss and 48 or 44 + min(25, self.elapsed * 0.035) + (variant == 2 and 12 or 0)),
        vel = point(), engulf = 0, phase = rng:randf() * TAU, variant = variant, infect = 0, slow = 0,
        shot_cd = 2.5, id = id, biome = biome, genome = Genome.create(seed, id, kind, biome), traits = traits,
        emission_cd = rng:randf_range(1, 3),
    }
    if boss then enemy.title = self:boss_title()
    elseif not prey and (id * 31 + seed) % 7 == 0 then
        enemy.r, enemy.hp, enemy.max_hp = 44 + id % 5, health * 1.7, health * 1.7
    end
    self.enemies[#self.enemies + 1] = enemy
    return enemy
end

function Simulation:_spawn_wave()
    if #self.enemies >= ENEMY_CAP - 2 then return end
    for _ = 1, min(2, 1 + floor(self.elapsed / 180)) do
        for _ = 1, 12 do
            local rng, world = self.rng, self.world
            local p = offset(self.player, rng:randf() * TAU, rng:randf_range(650, 900))
            if world:walkable(p.x, p.y, 25) and not self:_safe_zone(p) then
                local kind = rng:randf() < 0.24 and "prey" or (world:biome(p.x, p.y) == 2 and rng:randf() < 0.3 and "spitter" or "hunter")
                self:spawn_enemy(p, kind)
                break
            end
        end
    end
end

function Simulation:_update_ecology()
    for _, resident in ipairs(self.residents) do
        if not resident.dead and not resident.active and #self.enemies < ENEMY_CAP and distance_squared(self.player, resident.pos) <= 650^2
            and (self.elapsed >= 8 or self:_touches(resident.pos, resident.r)) then
            local enemy = self:spawn_enemy(resident.pos, "hunter")
            enemy.id, enemy.resident_id, enemy.r = resident.id, resident.id, resident.r
            enemy.hp, enemy.max_hp, enemy.genome, enemy.speed = resident.hp, resident.max_hp, copy(resident.genome), 23
            resident.active = true
        end
    end
end

function Simulation:_check_nests()
    for _, nest in ipairs(self.world.nests) do
        if not nest.used and distance_squared(self.player, nest.pos) <= 100^2 then
            nest.used = true
            if nest.kind == 0 then
                self:gain_xp(20)
                self:_message("Найден древний геном: +20 ДНК")
            elseif nest.kind == 1 then
                self.build.biomass = self.build.biomass + 20
                self:_message("Питательный сгусток: +20 биомассы")
            else
                self:_drop(nest.pos, "core", 2)
                for i = 0, 4 do
                    local p = offset(nest.pos, i * TAU / 5, 200)
                    if self.world:walkable(p.x, p.y, 25) then self:spawn_enemy(p, "hunter") end
                end
                self:_message("Паразитический очаг! Защити найденное ядро.")
            end
        end
    end
end

function Simulation:_update_minibosses()
    if self.minibosses_spawned >= self:stage_miniboss_target() or #self.enemies >= ENEMY_CAP then return end
    local discovered = 0
    for _, nest in ipairs(self.world.nests) do if nest.used then discovered = discovered + 1 end end
    if discovered < (self.minibosses_spawned + 1) * 2 then return end
    local nest = self.world.nests[min(#self.world.nests, self.minibosses_spawned * 2 + 2)]
    local p = nest and nest.pos or offset(self.player, self.minibosses_spawned * math.pi + 0.3, 330)
    local enemy = self:spawn_enemy(p, "miniboss")
    enemy.r = clamp(self:body_radius() * 1.22, 48, 110)
    enemy.max_hp = (380 + self.elapsed * 0.2) * (1 + 0.14 * (self.stage_index - 1))
    enemy.hp, enemy.speed = enemy.max_hp, 28
    enemy.title = MINIBOSS_NAMES[(self.stage_index * 3 + self.minibosses_spawned) % #MINIBOSS_NAMES + 1]
    enemy.elite_token = self.run_id .. ":elite:" .. self.stage_index .. ":" .. self.minibosses_spawned
    enemy.traits = { "shell", self.minibosses_spawned == 0 and "toxic" or "spores" }
    self.minibosses_spawned, self.next_miniboss_at = self.minibosses_spawned + 1, self.elapsed
    self:_feedback("miniboss", p)
    self:_message("Минибосс: " .. enemy.title)
end

function Simulation:_contact_shape()
    local radius, health = self:body_radius(), self.hp / self.max_hp
    local build, recipe = self.build, self.player_genome
    local crown, mantle, womb = build:evolved("tentacle"), build:evolved("acid"), build:evolved("infection")
    local evolved = (crown and 1 or 0) + (mantle and 2 or 0) + (womb and 4 or 0)
    local moment = evolved == 0 and 0 or self.elapsed
    local cache = self._contact_cache
    if cache and cache.radius == radius and cache.health == health and cache.mask == evolved and cache.moment == moment
        and cache.contour == self.contact_contour and cache.recipe == recipe then return cache.polygon, cache end
    local source = self.contact_contour
    local polygon = {}
    if source and #source > 2 then
        for i, p in ipairs(source) do polygon[i] = point(p.x * radius, p.y * radius) end
    else
        source = Genome.contour(recipe, 48)
        local severity = smoothstep(0.04, 1, 1 - clamp(health, 0, 1))
        local sites = {}
        if severity > 0 then
            local phase = ((recipe.seed * 73 + recipe.identity * 151) % 997) / 997 * TAU
            for i = 0, 4 do
                sites[#sites + 1] = {
                    angle = phase + i * TAU / 5 + 0.16 * math.sin(i * 4.73 + phase) + recipe.rotation,
                    width = 0.30 + 0.055 * math.sin(i * 2.83 + phase),
                    depth = severity * (0.61 + 0.08 * math.sin(i * 3.17 + phase)), i = i,
                }
            end
        end
        for i, p in ipairs(source) do
            local angle = V.angle(p.x, p.y)
            local cut = 0
            for _, site in ipairs(sites) do
                local d = math.abs((angle - site.angle + math.pi) % TAU - math.pi)
                cut = max(cut, site.depth * (1 - smoothstep(0, site.width * 1.8, d)) * (0.80 + 0.20 * math.cos(d * 37 + site.i * 2.2)))
            end
            local a, swell = angle - recipe.phase, 0
            if crown then swell = swell + 0.08 + 0.045 * math.cos(a * 3) end
            if mantle then swell = swell + 0.035 + 0.065 * math.cos(a * 6 + math.sin(moment * 1.4) * 0.2) end
            if womb then swell = swell + 0.06 + 0.09 * math.cos(a * 3 - 1.8) + 0.025 * math.sin(moment * 2.2 + a * 3) end
            local scale = radius * (1 - clamp(cut, 0, 0.7)) * (1 + clamp(swell, -0.08, 0.22))
            polygon[i] = point(p.x * scale, p.y * scale)
        end
    end
    local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(polygon) do
        min_x, min_y = min(min_x, p.x), min(min_y, p.y)
        max_x, max_y = max(max_x, p.x), max(max_y, p.y)
    end
    cache = {
        radius = radius, health = health, mask = evolved, moment = moment, contour = self.contact_contour,
        recipe = recipe, polygon = polygon, min_x = min_x, min_y = min_y, max_x = max_x, max_y = max_y,
    }
    self._contact_cache = cache
    return polygon, cache
end

local function membrane_distance(polygon, x, y, radius)
    local nearest = math.huge
    for i, p in ipairs(polygon) do
        local q = polygon[i % #polygon + 1]
        local dx, dy = q.x - p.x, q.y - p.y
        local den = x * dy - y * dx
        if math.abs(den) >= 0.00001 * radius then
            local distance, along = (p.x * dy - p.y * dx) / den, (p.x * y - p.y * x) / den
            if distance > 0 and along >= -0.00001 and along <= 1.00001 then nearest = min(nearest, distance) end
        end
    end
    return nearest < math.huge and nearest or radius * 0.8
end

function Simulation:_membrane_anchor(angle, scale)
    local polygon = self:_contact_shape()
    local distance = membrane_distance(polygon, math.cos(angle), math.sin(angle), self:body_radius())
    return offset(self.player, angle, distance * (scale or 1))
end

function Simulation:_crown_destination()
    local contour, cache = self:_contact_shape()
    if cache.aim == self.facing and cache.bite == self.bite_flash and cache.player == self.player then return cache.throat end
    local radius = self:body_radius()
    local forward_x, forward_y = math.cos(self.facing), math.sin(self.facing)
    local anchor = membrane_distance(contour, forward_x, forward_y, radius)
    local activation = clamp(self.bite_flash, 0, 1)
    local gap = (0.016 + activation * 0.19) * radius
    local width = (0.23 + activation * 0.18) * radius
    local center = anchor - (0.105 + activation * 0.15) * radius
    local across_scale, fit = 1, 1
    local tan_cone = math.tan(0.67)
    for i = 0, 16 do
        local u = i / 16
        local arch = max(0, math.sin(u * math.pi))^0.85
        local across = (u - 0.5) * width * 2
        if math.abs(across) > 0.00001 * radius then
            across_scale = min(across_scale, max(0.03 * radius, center - gap * arch * 1.42) * tan_cone / math.abs(across))
        end
    end
    for i = 0, 16 do
        local u = i / 16
        local arch = max(0, math.sin(u * math.pi))^0.85
        local across = (u - 0.5) * width * 2 * across_scale
        for _, depth in ipairs({center + gap * arch * 0.38, center - gap * arch * 1.42}) do
            local x, y = depth * forward_x + across * forward_y, depth * forward_y - across * forward_x
            local nx, ny, distance = V.normal(x, y)
            fit = min(fit, membrane_distance(contour, nx, ny, radius) * 0.96 / max(0.00001 * radius, distance))
        end
    end
    cache.aim, cache.bite, cache.player = self.facing, self.bite_flash, self.player
    cache.throat = offset(self.player, self.facing, (center - gap * 0.61) * fit)
    return cache.throat
end

function Simulation:_touches(pos, object_radius)
    local a, b, radius = self.previous_player, self.player, self:body_radius()
    local broad = radius * 2.1 + object_radius
    if math.abs(pos.x - b.x) > broad + math.abs(b.x - a.x) or math.abs(pos.y - b.y) > broad + math.abs(b.y - a.y) then return false end
    if V.segment_distance_squared(pos.x, pos.y, a.x, a.y, b.x, b.y) > broad^2 then return false end
    local polygon, bounds = self:_contact_shape()
    local margin = object_radius + 3
    local low_x, low_y = bounds.min_x - margin, bounds.min_y - margin
    local high_x, high_y = bounds.max_x + margin, bounds.max_y + margin
    local from_x, from_y, to_x, to_y = pos.x - a.x, pos.y - a.y, pos.x - b.x, pos.y - b.y
    if max(from_x, to_x) < low_x or min(from_x, to_x) > high_x
        or max(from_y, to_y) < low_y or min(from_y, to_y) > high_y then return false end
    local steps = max(1, ceil(sqrt(distance_squared(a, b)) / max(4, radius * 0.3)))
    local edge_distance = margin^2
    for step = 0, steps do
        local x, y = pos.x - a.x - (b.x - a.x) * step / steps, pos.y - a.y - (b.y - a.y) * step / steps
        if x >= low_x and x <= high_x and y >= low_y and y <= high_y then
            local inside = false
            for i, p in ipairs(polygon) do
                local q = polygon[i % #polygon + 1]
                if V.segment_distance_squared(x, y, p.x, p.y, q.x, q.y) <= edge_distance then return true end
                if ((p.y > y) ~= (q.y > y)) and x < (q.x - p.x) * (y - p.y) / (q.y - p.y) + p.x then inside = not inside end
            end
            if inside then return true end
        end
    end
    return false
end

function Simulation:_capture(item)
    item.captured, item.internal, item.vel = true, true, point()
    local x, y = item.pos.x - self.player.x, item.pos.y - self.player.y
    item.entry_angle, item.entry_distance = V.angle(x, y), sqrt(x * x + y * y)
    item.progress, item.duration = clamp(item.progress or 0, 0, 0.7), min(0.65, item.duration or 0.55)
    if item.material and self:has_trait("folds") then item.duration = item.duration * 0.8 end
end

function Simulation:_assimilate(recipe, amount, pos, pigment)
    pigment = pigment or V.pigment(Genome.colors(recipe)[1], amount)
    V.combine(self.tissue_pigment, pigment)
    self.tissue_pigment.mass = min(80, self.tissue_pigment.mass)
    self:_feedback("absorb", self.player)
    self:_effect("assimilate", self.player, 36, 1.1, { ["end"] = pos, color = V.pigment_color(pigment) })
end

function Simulation:_infected_meal()
    if not self.build:evolved("infection") then return end
    self.spore_charge = self.spore_charge + 1
    self:_effect("womb_feed", self.player, self:body_radius(), 0.7)
    if self.spore_charge < 3 then return end
    self.spore_charge = 0
    local rank, radius = self.build:rank("infection"), self:body_radius() * 2.3
    self:_field(self.player, radius, Catalog.scaled_damage(4 + rank * 2, rank), 2.4, "spore")
    self:_effect("womb_burst", self.player, radius, 1)
end

function Simulation:_store_fragment(fragment)
    if #self.remains < REMAINS_CAP then
        self.remains[#self.remains + 1] = fragment
        return
    end
    local receiver = self.remains[#self.remains]
    receiver.dna, receiver.bio = receiver.dna + fragment.dna, receiver.bio + fragment.bio
    receiver.infected = receiver.infected or fragment.infected
    receiver.quality = max(receiver.quality or 0, fragment.quality)
    V.combine(receiver.pigment, fragment.pigment)
end

local function tissue_piece(enemy, start, finish, distance)
    local body_angle = enemy.genome.rotation or 0
    local anchor = offset(point(), body_angle + (start + finish) * 0.5, distance)
    return {
        body_id = enemy.id, body_kind = enemy.kind, body_radius = enemy.r,
        genome = copy(enemy.genome), body_infected = (enemy.infect or 0) > 0,
        cut_start = start, cut_end = finish,
        anchor = anchor, rotation = body_angle, turn = 0,
        pos = point(enemy.pos.x + anchor.x, enemy.pos.y + anchor.y),
    }
end

function Simulation:_fracture_membrane(enemy)
    enemy.fractured = true
    local x, y, length = V.normal(self.player.x - enemy.pos.x, self.player.y - enemy.pos.y)
    local angle = length > 0 and V.angle(x, y) or 0
    local edge = offset(enemy.pos, angle, enemy.r * 0.74)
    local radius = clamp(enemy.r * 0.17, 6, 15)
    local cut_width = 0.58
    local cut_start = (angle - (enemy.genome.rotation or 0) - cut_width * 0.5) % TAU
    local part = tissue_piece(enemy, cut_start, cut_start + cut_width, enemy.r * 0.74)
    part.id, part.vel, part.r = self:_id(), offset(point(), angle + 0.3, 19), radius
    part.part, part.quality, part.material = 1, 2, "membrane"
    part.dna, part.bio, part.progress, part.duration = 2, 1, 0, 0.65
    part.pigment = V.pigment(Genome.colors(enemy.genome)[1], max(0.5, radius * 0.12))
    self:_store_fragment(part)
    self:_effect("membrane_break", edge, radius * 1.8, 0.65, { ["end"] = offset(edge, angle, radius) })
end

function Simulation:_leave_remains(enemy)
    local scale = enemy.r > 40 and max(1, enemy.r / 26) or 1
    local prey, elite = enemy.kind == "prey", enemy.kind == "miniboss"
    local dna, bio = prey and 4 or floor(9 * scale), prey and 1 or floor(4 * scale)
    if elite then dna, bio = max(45, dna * 2), max(24, bio * 2) end
    local grade = elite and 3 or (enemy.r >= 60 and 2 or (enemy.r >= 40 and 1 or 0))
    local count = clamp(floor(enemy.r / 18) + 1, 2, 8)
    local angle_step = TAU / count
    local radius = max(5, enemy.r * 0.36 / sqrt(count / 3))
    local materials = {"organelle", "membrane", "plasma"}
    local body_angle = enemy.genome.rotation or 0
    local boundaries = {[0] = 0, [count] = TAU}
    for boundary = 1, count - 1 do
        boundaries[boundary] = boundary * angle_step + self.rng:randf_range(-angle_step * 0.20, angle_step * 0.20)
    end
    for i = 1, count do
        local sector = i - 1
        local cut_start, cut_end = boundaries[sector], boundaries[sector + 1]
        local cut_width = cut_end - cut_start
        local cut_center = (cut_start + cut_end) * 0.5
        local angle = body_angle + cut_center
        local dna_share = floor(dna / count) + (sector < dna % count and 1 or 0)
        local bio_share = floor(bio / count) + (sector < bio % count and 1 or 0)
        local piece_scale = self.rng:randf_range(0.78, 1.22)
        local radial_angle = angle + self.rng:randf_range(-cut_width * 0.10, cut_width * 0.10)
        local piece_grade = i == 1 and max(1, grade) or max(0, grade - 1)
        local part = tissue_piece(enemy, cut_start, cut_end, enemy.r * self.rng:randf_range(0.28, 0.46))
        part.id, part.r = self:_id(), radius * piece_scale
        part.vel = offset(point(), radial_angle, enemy.r * 0.95 + self.rng:randf_range(12, 25))
        part.part, part.quality = sector % #materials, piece_grade
        part.piece_count, part.piece_index = count, sector
        part.spin, part.release_delay = self.rng:randf_range(-0.65, 0.65), 0.10
        part.material = materials[sector % #materials + 1]
        part.dna, part.bio, part.progress = dna_share, bio_share, 0
        part.duration = self.rng:randf_range(1.2, 2)
        part.infected = enemy.infect > 0 and i == 1
        part.pigment = V.pigment(Genome.colors(enemy.genome)[1], max(0.5, radius * 0.12))
        self:_store_fragment(part)
    end
end

local function boss_pieces(enemy)
    local count, pieces = 7, {}
    for i = 0, count - 1 do
        local start, finish = TAU * i / count, TAU * (i + 1) / count
        local part = tissue_piece(enemy, start, finish, enemy.r * 0.42)
        part.id = i
        part.spin = math.sin(i * 2.1) * 0.36
        pieces[i + 1] = part
    end
    return pieces
end

function Simulation:flush_family_materials()
    if not next(self.material_pending) then return end
    self:_event("family_material", { token = self.run_id .. ":materials:" .. self.material_batch, materials = self.material_pending })
    self.material_batch, self.material_pending = self.material_batch + 1, {}
end

function Simulation:_die(index, absorbed)
    local enemy = table.remove(self.enemies, index)
    for _, resident in ipairs(self.residents) do
        if resident.id == enemy.resident_id then resident.dead, resident.active = true, false end
    end
    self.kills = self.kills + 1
    local source = absorbed and "devour" or (enemy.last_damage_source or "unknown")
    Stats.record_kill(self.combat_stats, source)
    if contains(enemy.traits, "spores") then self:_field(enemy.pos, 75, 8, 2.5, "enemy_spore", true, self:_enemy_label(enemy) .. " · споры", enemy.id) end
    if absorbed then
        local scale, prey = enemy.r > 40 and max(1, enemy.r / 26) or 1, enemy.kind == "prey"
        self:_assimilate(enemy.genome, max(1, enemy.r / 12), enemy.pos)
        self:gain_xp(prey and 4 or floor(6 * scale))
        self.build.biomass = self.build.biomass + (prey and 1 or floor(3 * scale))
        self:heal_player(self.build:rank("devour") * 0.8)
        if enemy.meal_infected then self:_infected_meal() end
        if enemy.infect > 0 and contains(self.build:active_synergies(), "spore_feast") then self:_field(enemy.pos, 100, 14, 2.5, "spore") end
    elseif enemy.kind ~= "boss" then
        self:_leave_remains(enemy)
        if self.kills % 3 == 0 then self:_drop(enemy.pos, "heal", 6) end
    end
    if enemy.kind == "boss" then
        local attack = self:boss_attack()
        self.stage_transition, self.pending_stage_seed = true, self.rng:randi()
        self.boss_reward = { name = self:_enemy_label(enemy), organ = attack.organ, genome = copy(enemy.genome), claimed = false }
        self.boss_breakup = { pos = enemy.pos, radius = enemy.r, pieces = boss_pieces(enemy) }
        self:flush_family_materials()
        self:_event("core", { token = self.run_id .. ":boss:" .. self.stage_index, amount = 12 + min(20, self.stage_index) })
        self:_event("stage_clear", { token = self.run_id .. ":stage-clear:" .. self.stage_index, stage = self.stage_index })
        self:_message("Главная угроза разрушена. Путь ведёт на следующую ступень.")
    elseif enemy.kind == "miniboss" then
        self.minibosses_defeated = self.minibosses_defeated + 1
        self:_spawn_cyst(enemy.pos, 3, "elite:" .. enemy.id)
        self:_event("core", { token = enemy.elite_token or self.run_id .. ":elite:" .. enemy.id, amount = 4 })
        self:_event("organium", { token = self.run_id .. ":organium:elite:" .. enemy.id, amount = 2 })
        self:_message(string.format("Минибосс повержен · +2 органиума · %d/%d", self.minibosses_defeated, self:stage_miniboss_target()))
    elseif self.kills % 18 == 0 then
        self:_drop(enemy.pos, "core", 1)
    end
    if absorbed then self:_effect("burst", enemy.pos, enemy.r + 20, 0.4) end
end

local function approach(item, p, distance)
    local x, y, length = V.normal(p.x - item.pos.x, p.y - item.pos.y)
    distance = min(length, distance)
    item.pos = point(item.pos.x + x * distance, item.pos.y + y * distance)
end

function Simulation:_update_remains(dt)
    self.digesting_id = -1
    local rank = self.build:rank("magnet")
    local attraction = self:attraction_radius()
    local pulling = rank > 0 or (self.upgrades.collect or 0) > 0
    for i = #self.remains, 1, -1 do
        local part = self.remains[i]
        if (part.release_delay or 0) > 0 then
            part.release_delay = max(0, part.release_delay - dt)
        elseif not part.captured then
            part.pos = point(self.world:move_body(part.pos.x, part.pos.y, part.vel.x * dt, part.vel.y * dt, part.r * 0.5))
            local decay = exp(-dt / 0.8)
            part.vel = point(part.vel.x * decay, part.vel.y * decay)
            if part.spin then
                part.rotation = (part.rotation or 0) + part.spin * dt
                if part.anchor then part.turn = (part.turn or 0) + part.spin * dt end
            end
            if self:_touches(part.pos, part.r) then self:_capture(part)
            elseif pulling and distance_squared(self.player, part.pos) < attraction^2 then approach(part, self.player, dt * (70 + rank * 25)) end
        end
        if part.captured then
            if self.digesting_id == -1 then self.digesting_id = part.id end
            part.pos = offset(self.player, part.entry_angle, self:body_radius() * 0.35)
            part.progress = min(1, part.progress + dt / part.duration)
            if part.progress >= 1 then
                self:_assimilate(part.genome, max(0.5, part.r * 0.12), part.pos, part.pigment)
                local tissue = part.material
                self.material_pending[tissue] = (self.material_pending[tissue] or 0) + 1 + floor((part.quality or 0) / 2)
                local total = 0
                for _, amount in pairs(self.material_pending) do total = total + amount end
                if total >= 3 then self:flush_family_materials() end
                if part.infected then
                    self:_infected_meal()
                    if contains(self.build:active_synergies(), "spore_feast") then self:_field(part.pos, 100, 14, 2.5, "spore") end
                end
                self:gain_xp(part.dna)
                self.build.biomass = self.build.biomass + part.bio
                table.remove(self.remains, i)
            end
        end
    end
    if #self.remains == 0 then self.digesting_id = -1 end
end

function Simulation:_collect(dt)
    local rank, radius = self.build:rank("magnet"), self:attraction_radius()
    local pulling = rank > 0 or (self.upgrades.collect or 0) > 0
    for i = #self.pickups, 1, -1 do
        local item = self.pickups[i]
        if not item.captured and (item.type ~= "heal" or self.hp < self.max_hp) then
            if self:_touches(item.pos, 7) then self:_capture(item)
            elseif pulling and distance_squared(self.player, item.pos) < radius^2 then approach(item, self.player, dt * (95 + 35 * rank)) end
        end
        if item.captured then
            item.pos = offset(self.player, item.entry_angle, self:body_radius() * 0.3)
            item.progress = min(1, item.progress + dt / item.duration)
            if item.progress >= 1 then
                if item.type == "heal" and self.hp >= self.max_hp then
                    item.captured, item.internal, item.progress = false, false, 0
                    item.pos = offset(self.player, item.entry_angle, self:body_radius() * 1.6 + 12)
                else
                    self:_feedback("absorb", self.player)
                    if item.type == "dna" then self:gain_xp(item.amount)
                    elseif item.type == "bio" then self.build.biomass = self.build.biomass + item.amount
                    elseif item.type == "body_extension" or item.type == "stock_extension" then
                        self:_event("expansion", { target = item.type == "body_extension" and "body" or "stock", amount = item.amount, token = self.run_id .. ":" .. item.id })
                    elseif item.type == "heal" then
                        self:heal_player(item.amount)
                        self:_effect("assimilate", self.player, self:body_radius(), 0.8, { ["end"] = item.pos, color = "7dfcd4" })
                    else
                        self.cores_found = self.cores_found + item.amount
                        self:_event("core", { token = self.run_id .. ":" .. item.id, amount = item.amount })
                    end
                    table.remove(self.pickups, i)
                end
            end
        end
    end
end

function Simulation:_update_cysts(dt)
    for i = #self.cysts, 1, -1 do
        local cyst = self.cysts[i]
        if not cyst.captured and self:_touches(cyst.pos, cyst.r) then self:_capture(cyst) end
        if cyst.captured then
            cyst.pos = offset(self.player, cyst.entry_angle, self:body_radius() * (0.75 - cyst.progress * 0.65))
            cyst.progress = min(1, cyst.progress + dt / cyst.duration)
            if cyst.progress >= 1 then
                local duplicate = contains(self.claimed_rewards, cyst.token)
                for _, queued in ipairs(self.reward_queue) do if queued.token == cyst.token then duplicate = true; break end end
                if not duplicate then self.reward_queue[#self.reward_queue + 1] = { token = cyst.token, tier = cyst.tier } end
                self:_feedback("reward", self.player, cyst.tier)
                self:_effect("assimilate", self.player, self:body_radius(), 1.1, { ["end"] = cyst.pos, color = Rewards.quality_color(cyst.tier) })
                table.remove(self.cysts, i)
            end
        end
    end
end

function Simulation:step(dt, x, y)
    if self.paused or self.stage_transition or self.outcome ~= "" then return end
    dt = clamp(dt, 0, 0.5)
    if dt == 0 then return end
    if type(x) == "table" then x, y = x.x, x.y end
    x, y = x or 0, y or 0
    local build, world = self.build, self.world
    self.elapsed, self.invuln = self.elapsed + dt, max(0, self.invuln - dt)
    self.previous_player = self.player
    local condition = world.conditions[world:biome(self.player.x, self.player.y)]
    local speed = (72 + self:body_radius() * 0.6) * (1 + build:passive("speed")) * (condition == 1 and 0.85 or 1)
    local inertia = self:has_trait("elastic") and 0.13 or 0.2
    if self:has_trait("sensory") then speed = speed * 0.95 end
    local magnitude = max(1, sqrt(x * x + y * y))
    x, y = x * speed / magnitude, y * speed / magnitude
    local response = exp(-dt / inertia)
    local vx, vy = self.player_velocity.x - x, self.player_velocity.y - y
    self.player_velocity = point(x + vx * response, y + vy * response)
    self.bite_flash = max(0, self.bite_flash - dt * 4.5)
    self.player = self:_move_player_against_bodies(x * dt + vx * inertia * (1 - response), y * dt + vy * inertia * (1 - response))
    local dx, dy = self.player.x - self.previous_player.x, self.player.y - self.previous_player.y
    if dx * dx + dy * dy > 4 * max(0.001, dt)^2 then
        local diff = (V.angle(dx, dy) - self.facing + math.pi) % TAU - math.pi
        self.facing = self.facing + diff * (1 - exp(-dt * 9))
    end
    if not build:evolved("infection") then self.spore_charge = 0 end
    local colony_regen = contains(build:active_synergies(), "metabolic_colony") and build:rank("division") * 0.15 or 0
    self:heal_player((build:passive("regen") + (self.upgrades.regen or 0) * 0.1 + colony_regen) * dt)
    if self.hp < self.max_hp * 0.25 and self.elapsed - self._danger_at > 2 then
        self:_feedback("danger", self.player)
        self._danger_at = self.elapsed
    end
    self:_reveal()
    for id, seconds in pairs(self.cooldowns) do self.cooldowns[id] = max(0, seconds - dt) end
    self.spawn_timer = self.spawn_timer - dt
    if self.spawn_timer <= 0 then
        self.spawn_timer = max(2, 2.6 - self.elapsed / 1000)
        self:_spawn_wave()
    end
    self:_check_nests()
    self:_update_ecology()
    self:_update_minibosses()
    self:_update_enemies(dt)
    if self.stage_transition or self:_check_run_death() then return end
    if not self.boss_spawned and self.minibosses_defeated >= self:stage_miniboss_target() and #self.enemies < ENEMY_CAP then
        self.boss_spawned, self.boss_marker = true, self.world.boss_pos
        self:spawn_enemy(self.world.boss_pos, "boss")
        self:_message("Открыт путь к главной угрозе: " .. self:boss_title() .. ". Найди её на карте.")
    end
    self:_attack(dt)
    self:_update_shots(dt)
    self:_update_fields(dt)
    self:_update_remains(dt)
    self:_collect(dt)
    self:_update_cysts(dt)
    for _, entries in ipairs({self.damage_markers, self.effects}) do
        for i = #entries, 1, -1 do
            entries[i].life = entries[i].life - dt
            if entries[i].life <= 0 then table.remove(entries, i) end
        end
    end
    self:_check_run_death()
end

function Simulation:_check_run_death()
    if self.hp > 0 then return false end
    if self.outcome == "" then
        self.outcome = "death"
        self:_event("end", { outcome = self.outcome })
    end
    return true
end

function Simulation:roll_offer_quality()
    local quality = {}
    for _, id in ipairs(self.current_offers) do
        quality[id] = self.offer_quality[id] or Rewards.roll_quality(self.rng, min(5, floor(self.elapsed / 120)))
    end
    self.offer_quality = quality
end

function Simulation:prepare_offers()
    if self.pending_levels <= 0 then return {} end
    if #self.current_offers == 0 then
        self.current_offers = self.build:offers(self.rng)
        self:roll_offer_quality()
    end
    local usable = {}
    for _, id in ipairs(self.current_offers) do
        if self.build:stored_rank(id) < Catalog.max_rank(id) or (self.offer_quality[id] or 0) > self.build:quality(id) then
            usable[#usable + 1] = id
        end
    end
    return usable
end

function Simulation:take_level_biomass()
    if self.pending_levels <= 0 or #self:prepare_offers() > 0 then return false end
    self.build.biomass = self.build.biomass + 15
    self:commit_level_pick()
    return true
end

local function same_offers(a, b)
    if #a ~= #b then return false end
    for _, id in ipairs(a) do if not contains(b, id) then return false end end
    return true
end

function Simulation:reroll_offers(focused)
    if self.pending_levels <= 0 or self.rerolls >= 3 then return false end
    local price = 5 + self.rerolls * 5 + (focused and 5 or 0)
    if self.build.biomass < price then return false end
    for _ = 1, 12 do
        local candidates = self.build:offers(self.rng, focused and self.build.branch or "")
        if #candidates == 0 then return false end
        if not same_offers(self.current_offers, candidates) then
            if not self.build:spend(price) then return false end
            self.rerolls, self.current_offers = self.rerolls + 1, candidates
            self:roll_offer_quality()
            return true
        end
    end
    return false
end

function Simulation:commit_level_pick()
    self.pending_levels = max(0, self.pending_levels - 1)
    self.current_offers, self.offer_quality, self.rerolls = {}, {}, 0
    self:_effect("mutation", self.player, self:body_radius() * 1.6, 1.2)
end

function Simulation:choose_mutation(id, replace_id, award)
    if self.pending_levels <= 0 or not contains(self.current_offers, id) then return false end
    if not self:_apply_award(id, replace_id, self.offer_quality[id] or 0, award) then return false end
    self:commit_level_pick()
    return true
end

function Simulation:_apply_award(id, replace_id, grade, award)
    if award and Catalog.ORGANS[id] then return award(id, replace_id or "", grade) end
    return self.build:apply(id, replace_id, grade)
end

function Simulation:buy_colony(index, stock_index, replace_id, award)
    local colony = self.world.colonies[index]
    local item = colony and colony.stock[stock_index]
    if self:nearby_colony() ~= index or not item or item.sold or self.build.biomass < item.price then return false end
    if item.id == "heal" then
        if self.hp >= self.max_hp then return false end
        self:heal_player(40)
    elseif not self:_apply_award(item.id, replace_id, item.quality or 0, award) then
        return false
    end
    self.build.biomass, item.sold = self.build.biomass - item.price, true
    return true
end

function Simulation:claim_boss_reward(replace_id, award)
    local reward = self.boss_reward
    if not self.stage_transition or not reward.organ or reward.claimed then return false end
    if not self:_apply_award(reward.organ, replace_id, 3, award) then return false end
    reward.claimed = true
    return true
end

function Simulation:prepare_reward()
    while self.reward_queue[1] and contains(self.claimed_rewards, self.reward_queue[1].token) do
        table.remove(self.reward_queue, 1)
        self.reward_options = {}
    end
    if #self.reward_queue == 0 then self.reward_options = {}; return self.reward_options end
    if #self.reward_options > 0 then self:_refresh_reward_options(); return self.reward_options end
    local tier = clamp(self.reward_queue[1].tier, 1, 3)
    local options, build, rng = self.reward_options, self.build, self.rng
    if tier >= 2 then
        local id = build:evolution_candidates()[1]
        if id then options[#options + 1] = { kind = "evolution", id = id, quality = build:quality(id) } end
    end
    local temporary = {}
    for _, id in ipairs(Catalog.TEMP_MUTATION_IDS) do
        if build:can_apply_temporary_mutation(id, tier) then temporary[#temporary + 1] = id end
    end
    if #temporary > 0 then
        options[#options + 1] = {
            kind = "temporary", id = temporary[rng:randi_range(1, #temporary)],
            quality = max(tier, Rewards.roll_quality(rng, tier + 2)),
        }
    end
    local pool = build:offers(rng)
    for _, installed in ipairs({Catalog.ORGAN_IDS, Catalog.ADAPTATION_IDS}) do
        for _, id in ipairs(installed) do
            if build:stored_rank(id) >= Catalog.max_rank(id) and build:quality(id) < tier and not contains(pool, id) then pool[#pool + 1] = id end
        end
    end
    for _, id in ipairs(pool) do
        if #options >= 3 then break end
        options[#options + 1] = { kind = "mutation", id = id, quality = max(tier, Rewards.roll_quality(rng, tier + 2)) }
    end
    if #options == 0 then options[1] = { kind = "biomass", id = "biomass", quality = tier, amount = 20 + tier * 20 } end
    return options
end

function Simulation:_refresh_reward_options()
    local build = self.build
    for i, option in ipairs(self.reward_options) do
        local kind, id, quality = option.kind, option.id, option.quality
        local obsolete = kind == "mutation" and build:stored_rank(id) >= Catalog.max_rank(id) and build:quality(id) >= quality
            or kind == "temporary" and not build:can_apply_temporary_mutation(id, quality)
            or kind == "evolution" and not contains(build:evolution_candidates(), id)
        if obsolete then self.reward_options[i] = { kind = "biomass", id = "biomass", quality = quality, amount = 20 + 20 * max(1, quality) } end
    end
end

function Simulation:claim_reward(index, replace_id, award)
    self:_refresh_reward_options()
    local reward, option = self.reward_queue[1], self.reward_options[index]
    if not reward or not option or contains(self.claimed_rewards, reward.token) then return false end
    replace_id = replace_id or ""
    local accepted
    if option.kind == "mutation" then
        accepted = self:_apply_award(option.id, replace_id, option.quality, award)
    elseif option.kind == "temporary" then
        accepted = self.build:apply_temporary_mutation(option.id, option.quality)
    elseif option.kind == "evolution" and replace_id == "" then
        accepted = self.build:evolve(option.id)
    elseif option.kind == "biomass" and replace_id == "" then
        self.build.biomass = self.build.biomass + option.amount
        accepted = true
    end
    if not accepted then return false end
    self.claimed_rewards[#self.claimed_rewards + 1] = reward.token
    table.remove(self.reward_queue, 1)
    self.reward_options = {}
    self:_feedback("reward", self.player, option.kind == "evolution" and 3 or option.quality)
    self:_effect("mutation", self.player, self:body_radius() * 1.6, 1.2)
    return true
end

local SAVED_KEYS = {
    "family_id", "stock_capacity", "run_loadout", "spore_charge", "combat_stats", "last_damage",
    "cysts", "reward_queue", "reward_options", "pending_inventory", "offer_quality", "claimed_rewards", "player_genome",
    "minibosses_spawned", "minibosses_defeated", "stage_index", "best_stage", "stage_transition", "boss_reward", "boss_breakup",
    "pending_stage_seed", "next_miniboss_at", "facing", "tissue_pigment", "residents", "outcome", "events", "material_pending",
    "material_batch", "run_id", "player", "player_velocity", "remains", "digesting_id", "hp", "max_hp", "elapsed", "xp",
    "level", "pending_levels", "enemies", "pickups", "boss_spawned", "boss_marker", "kills", "cores_found",
    "next_id", "upgrades", "cooldowns", "current_offers", "rerolls", "fields", "shots", "spawn_timer", "invuln",
}

function Simulation:snapshot()
    local saved = { version = 1, seed = self.world.seed_value, rng_state = copy(self.rng.state), build = self.build:to_dict() }
    saved.colonies, saved.nests = copy(self.world.colonies), copy(self.world.nests)
    saved.explored = {}
    for key in pairs(self.explored) do saved.explored[#saved.explored + 1] = key end
    table.sort(saved.explored)
    for _, key in ipairs(SAVED_KEYS) do saved[key] = copy(self[key]) end
    return saved
end

local function finite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

function Simulation.restore(saved)
    if type(saved) ~= "table" or saved.version ~= 1 or not finite(saved.seed) or not Genome.validate(saved.player_genome)
        or type(saved.build) ~= "table" or type(saved.rng_state) ~= "table" or #saved.rng_state ~= 4
        or type(saved.player) ~= "table" or not finite(saved.player.x) or not finite(saved.player.y) then return nil end
    for _, limb in ipairs(saved.rng_state) do
        if not finite(limb) or limb < 0 or limb > 65535 or limb % 1 ~= 0 then return nil end
    end
    local self = Simulation.new(saved.seed, nil, saved.upgrades, saved.build.branch, saved.run_loadout)
    self.build:from_dict(saved.build)
    for _, key in ipairs(SAVED_KEYS) do if saved[key] ~= nil then self[key] = copy(saved[key]) end end
    self.rng.state = copy(saved.rng_state)
    self.combat_stats = Stats.restore(saved.combat_stats)
    self.run_loadout = Heredity.normalize(saved.run_loadout)
    self.world.colonies, self.world.nests = copy(saved.colonies or self.world.colonies), copy(saved.nests or self.world.nests)
    self.previous_player = self.player
    self.explored = {}
    for _, key in ipairs(saved.explored or {}) do self.explored[key] = true end
    self.last_tile = nil
    self:_reveal()
    return self
end

return Simulation
