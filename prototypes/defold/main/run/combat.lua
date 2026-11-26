local Catalog = require("main.run.catalog")
local Stats = require("main.run.combat_stats")
local Size = require("main.run.size_rules")
local V = require("main.run.combat_math")
local Evolution = require("main.run.evolution_rules")
local Combat = {}

local min, max, exp = math.min, math.max, math.exp
local distance_squared, point, offset = V.distance_squared, V.point, V.offset
local contains = V.contains
local TAU = V.tau

local PATTERNS = {
    { name = "Игольчатый веер", hint = "Уйди вбок от лучей", organ = "spikes", count = 7, spread = 0.18, speed = 210, color = "ffb57c" },
    { name = "Споровое кольцо", hint = "Останься между лучами", organ = "infection", count = 12, spread = TAU / 12, speed = 165, color = "e492ec" },
    { name = "Кислотный поток", hint = "Уйди поперёк потока", organ = "acid", count = 3, spread = 0.10, speed = 250, color = "d8ef8b" },
}

function Combat:boss_attack(index, seed)
    seed = seed and seed >= 0 and seed or self.world.seed_value
    index = index and index > 0 and index or self.stage_index
    return PATTERNS[(seed + index) % #PATTERNS + 1]
end

function Combat:_enemy_label(enemy)
    if enemy.kind == "boss" then return enemy.title or "Архицит" end
    if enemy.kind == "miniboss" then return enemy.title or "Минибосс" end
    if enemy.kind == "spitter" then return "Плюющая амёба" end
    return enemy.r > self:body_radius() * 1.08 and "Крупная амёба" or "Враждебная амёба"
end

function Combat:hit_enemy(enemy, amount, source)
    if enemy.hp <= 0 or enemy.captured then return 0 end
    source = source or "unknown"
    local build = self.build
    local raw = max(0, amount) * (1 + build:passive("catalysis")) * build:power(source)
    local exposed = (enemy.boss_exposed or 0) > 0
    local ratio = enemy.r / self:body_radius()
    local giant = enemy.kind == "boss" or ratio >= 1.6
    local weak = exposed or (enemy.enzyme_time or 0) > 0
    local piercing = (source == "spikes" and (build.specializations.spikes == "spikes_piercer" or (not giant and build:rank("spikes") >= 3)))
        or (source == "devour" and build:rank("devour") >= 2 and self:mouth_contact(enemy))
    if giant and not (weak or piercing or enemy.fractured) then return 0 end
    if exposed then raw = raw * 1.6 end
    local budget = enemy.tissue_budget or enemy.max_hp * 0.01
    local dealt = min(enemy.hp, raw, budget)
    enemy.tissue_budget = max(0, budget - dealt)
    enemy.hp = enemy.hp - dealt
    if dealt <= 0 then return 0 end
    if enemy.hp > 0 and piercing and ratio >= 0.9 and not enemy.fractured and (weak or enemy.hp <= enemy.max_hp * 0.48) then
        self:_fracture_membrane(enemy)
    end
    enemy.last_damage_source = source
    Stats.record_damage(self.combat_stats, source, dealt)
    self:_feedback("hit", enemy.pos, dealt)
    enemy.popup_damage = (enemy.popup_damage or 0) + dealt
    if self.elapsed - (enemy.popup_at or -1) >= 0.24 and enemy.popup_damage >= 0.8 then
        self:_effect("damage", enemy.pos, 0, 0.75, { amount = enemy.popup_damage, player = false })
        enemy.popup_damage, enemy.popup_at = 0, self.elapsed
    end
    return dealt
end

function Combat:heal_player(amount)
    local actual = max(0, min(self.max_hp - self.hp, amount * (self:has_trait("folds") and 0.9 or 1)))
    if actual <= 0 then return end
    self.hp = self.hp + actual
    Stats.record_heal(self.combat_stats, actual)
    for _, effect in ipairs(self.effects) do
        if effect.type == "heal" and effect.life > 0.65 then
            effect.amount = effect.amount + actual
            return
        end
    end
    self:_effect("heal", self.player, 0, 1.15, { amount = actual })
end

function Combat:barrier_capacity()
    local rank = self.build:rank("barrier")
    return rank > 0 and Catalog.scaled_damage(8 + rank * 6, rank) * self.build:power("barrier") or 0
end

function Combat:hurt_player(amount, source)
    if self.hp <= 0 then return end
    source = source or {}
    local kind, origin = source.kind or "unknown", source.pos or self.player
    local label = source.name or "Неизвестный источник"
    local incoming = max(0, amount) * (kind == "collision" and self:has_trait("elastic") and 1.08 or 1)
    local damage = incoming * (1 - self.build:passive("armor"))
    if damage > 0 and self.build:rank("barrier") > 0 and self:_ready("barrier") then
        damage = max(0, damage - self:barrier_capacity())
        self.cooldowns.barrier = 8
        self:_effect("barrier_block", self.player, self:body_radius() * 1.2, 0.45)
        self:_feedback("synergy", self.player)
    end
    if incoming > 0 and kind == "collision" and self.build:evolved("acid") and self:_ready("mantle") then
        self.cooldowns.mantle = 2
        local p = self:_membrane_anchor(V.angle(origin.x - self.player.x, origin.y - self.player.y), 0.95)
        local rank = self.build:rank("acid")
        self:_field(p, self:body_radius() * 0.8, Catalog.scaled_damage(3 + rank * 1.5, rank), 1.2, "mantle")
        self:_effect("mantle", self.player, self:body_radius(), 0.65, { ["end"] = p })
    end
    local actual = min(self.hp, damage)
    local entry = Stats.record_taken(self.combat_stats, self.elapsed, actual, incoming - damage, kind, label, origin, source.id or 0)
    if actual <= 0 then return end
    self.hp, self.last_damage = self.hp - actual, entry
    self:_feedback("hurt", origin, actual, kind)
    local marked = false
    for _, marker in ipairs(self.damage_markers) do
        if marker.kind == kind and marker.name == label and distance_squared(marker.pos, origin) < 10000 then
            marker.amount, marker.life, marker.pos = marker.amount + actual, 1.5, origin
            marked = true
            break
        end
    end
    if not marked then
        if #self.damage_markers >= 6 then table.remove(self.damage_markers, 1) end
        self.damage_markers[#self.damage_markers + 1] = { pos = origin, kind = kind, name = label, amount = actual, life = 1.5, max = 1.5 }
    end
    for _, effect in ipairs(self.effects) do
        if effect.type == "damage" and effect.player and effect.life > 0.5 then
            effect.amount = effect.amount + actual
            return
        end
    end
    self:_effect("damage", self.player, 0, 0.75, { amount = actual, player = true })
end

function Combat:mouth_contact(enemy)
    if self.build:rank("devour") <= 0 then return false end
    local x, y, distance = V.normal(enemy.pos.x - self.player.x, enemy.pos.y - self.player.y)
    if distance > self:body_radius() * 1.18 + enemy.r then return false end
    return distance < 0.1 or x * math.cos(self.facing) + y * math.sin(self.facing) >= math.cos(0.7)
end

function Combat:interaction(enemy)
    local build = self.build
    return Size.profile(self:body_radius(), enemy.r, enemy.hp / max(1, enemy.max_hp),
        build:rank("magnet") + ((enemy.grasp or 0) > 0 and 1 or 0), build:rank("devour"), self:mouth_contact(enemy))
end

function Combat:_can_be_absorbed(enemy, radius)
    radius = radius or self:body_radius()
    if enemy.hp <= 0 or enemy.kind == "boss" or enemy.r >= radius * 1.6 then return false end
    if enemy.kind == "miniboss" and enemy.hp > enemy.max_hp * 0.15 then return false end
    return self:interaction(enemy).eligible
end

function Combat:_is_engulfing(enemy)
    if enemy.captured then return true end
    return self:_can_be_absorbed(enemy) and self:_touches(enemy.pos, enemy.r * 1.17)
end

function Combat:_blocks_body(enemy, radius)
    if enemy.hp <= 0 or enemy.captured then return false end
    if enemy.kind == "boss" or enemy.r >= radius * 1.6 then return true end
    if enemy.kind == "miniboss" and enemy.hp > enemy.max_hp * 0.15 then return true end
    return enemy.r > radius * 0.72 and not self:interaction(enemy).eligible
end

function Combat:_contact_radius(enemy, radius)
    return radius * 0.78 + enemy.r * (enemy.fractured and 0.68 or 0.78)
end

function Combat:_limit_body_motion(dx, dy, radius, slide)
    local distance = math.sqrt(dx * dx + dy * dy)
    for _, enemy in ipairs(self.enemies) do
        local contact = self:_contact_radius(enemy, radius)
        if distance_squared(self.player, enemy.pos) <= (contact + distance)^2 and self:_blocks_body(enemy, radius) then
            dx, dy = Size.slide_contact(self.player, dx, dy, enemy.pos, contact, slide)
        end
    end
    for _, resident in ipairs(self.residents) do
        if not (resident.active or resident.dead) then
            local contact = (radius + resident.r) * 0.78
            if distance_squared(self.player, resident.pos) <= (contact + distance)^2 then
                dx, dy = Size.slide_contact(self.player, dx, dy, resident.pos, contact, slide)
            end
        end
    end
    return dx, dy
end

function Combat:_move_player_against_bodies(dx, dy)
    local radius, p = self:body_radius(), self.player
    local terrain_radius = min(26, radius * 0.65)
    local x, y = self.world:move_body(p.x, p.y, dx, dy, terrain_radius)
    dx, dy = x - p.x, y - p.y
    if dx == 0 and dy == 0 then return p end
    local adjusted_x, adjusted_y = self:_limit_body_motion(dx, dy, radius, true)
    if adjusted_x == dx and adjusted_y == dy then return point(x, y) end
    x, y = self.world:move_body(p.x, p.y, adjusted_x, adjusted_y, terrain_radius)
    dx, dy = self:_limit_body_motion(x - p.x, y - p.y, radius, false)
    x, y = p.x + dx, p.y + dy
    return self.world:walkable(x, y, terrain_radius) and point(x, y) or p
end

function Combat:_boss_windup(enemy, dt)
    enemy.boss_exposed = max(0, (enemy.boss_exposed or 0) - dt)
    if (enemy.boss_windup or 0) > 0 then
        enemy.boss_windup = max(0, enemy.boss_windup - dt)
        if enemy.boss_windup == 0 then
            local attack = self:boss_attack()
            for ray = 0, attack.count - 1 do
                local heading = enemy.boss_angle + (ray - (attack.count - 1) * 0.5) * attack.spread
                self:_shot(enemy.pos, offset(point(), heading, attack.speed), 13, true, "enemy", self:_enemy_label(enemy) .. " · " .. attack.name, enemy.id)
            end
            enemy.boss_exposed = 1.5
            enemy.shot_cd = enemy.hp < enemy.max_hp * 0.35 and 1.8 or 3
        end
        return
    end
    enemy.shot_cd = max(0, enemy.shot_cd - dt)
    if enemy.shot_cd > 0 or distance_squared(enemy.pos, self.player) > 460^2 or self:_safe_zone(self.player) then return end
    enemy.boss_angle = V.angle(self.player.x - enemy.pos.x, self.player.y - enemy.pos.y)
    enemy.boss_windup = 1.1
    self:_feedback("danger", enemy.pos)
end

function Combat:_spitter_windup(enemy, dt, distance)
    if (enemy.spit_windup or 0) > 0 then
        enemy.spit_windup = max(0, enemy.spit_windup - dt)
        if enemy.spit_windup == 0 then
            self:_shot(enemy.pos, offset(point(), enemy.spit_angle, 155), 8, true,
                "enemy", self:_enemy_label(enemy), enemy.id)
            enemy.shot_cd = 2
        end
        return
    end
    enemy.shot_cd = max(0, (enemy.shot_cd or 0) - dt)
    if enemy.shot_cd > 0 or distance >= 850 then return end
    enemy.spit_angle = V.angle(self.player.x - enemy.pos.x, self.player.y - enemy.pos.y)
    enemy.spit_windup = 0.65
    self:_feedback("danger", enemy.pos)
end

function Combat:_update_enemy_status(enemy, dt, radius)
    local build = self.build
    local elite = enemy.kind == "boss" or enemy.kind == "miniboss"
    local rate = Size.damage_rate(enemy.r / radius, elite)
    if enemy.kind == "boss" and (enemy.boss_exposed or 0) > 0 then rate = rate * 1.6 end
    enemy.tissue_budget = min(enemy.max_hp * 0.06, (enemy.tissue_budget or 0) + enemy.max_hp * rate * dt)
    enemy.slow = max(0, enemy.slow - dt)
    enemy.grasp = max(0, (enemy.grasp or 0) - dt)
    enemy.crown_time = max(0, (enemy.crown_time or 0) - dt)
    if enemy.crown_time > 0 then
        local eligible = build:evolved("tentacle") and Evolution.crown_eligible(radius, enemy, build:rank("magnet"))
            and distance_squared(enemy.pos, self.player) <= (Evolution.crown_reach(radius, build:rank("tentacle")) + 15)^2
        if eligible then
            enemy.crown_age = (enemy.crown_age or 0) + dt
            if enemy.crown_age > 0.18 then
                local acid = build:rank("acid")
                if acid > 0 then self:hit_enemy(enemy, Catalog.scaled_damage(1 + acid, acid) * dt, "acid") end
                if build:rank("infection") > 0 then enemy.infect = max(enemy.infect, 1) end
            end
        else
            enemy.crown_time = 0
        end
    end
    if enemy.infect > 0 then
        enemy.infect = enemy.infect - dt
        local rank = build:rank("infection")
        self:hit_enemy(enemy, Catalog.scaled_damage(4 + rank * 3, rank) * dt, "infection")
    end
    if enemy.kind ~= "miniboss" and contains(enemy.traits, "regen") then
        enemy.hp = min(enemy.max_hp, enemy.hp + enemy.max_hp * 0.012 * dt)
    end
    if (enemy.enzyme_time or 0) > 0 then
        enemy.enzyme_time = max(0, enemy.enzyme_time - dt)
        local rank = build:rank("enzymes")
        self:hit_enemy(enemy, Catalog.scaled_damage(3 + rank * 2, rank) * dt, "enzymes")
    end
    if contains(enemy.traits, "toxic") then
        enemy.emission_cd = enemy.emission_cd - dt
        if enemy.emission_cd <= 0 then
            enemy.emission_cd = 2.5
            self:_field(enemy.pos, 48, 6, 2.8, "enemy_toxin", true, self:_enemy_label(enemy) .. " · токсин", enemy.id)
        end
    end
end

function Combat:_update_enemy(i, dt, radius, safe)
    local enemy = self.enemies[i]
    if enemy.hp > 0 then self:_update_enemy_status(enemy, dt, radius) end
    if enemy.hp <= 0 then self:_die(i, false); return end
    local x, y, distance = V.normal(self.player.x - enemy.pos.x, self.player.y - enemy.pos.y)
    local elite = enemy.kind == "boss" or enemy.kind == "miniboss"
    if distance > 1600 and not elite and not enemy.resident_id then
        table.remove(self.enemies, i)
        return
    end
    local rules = self:interaction(enemy)
    if self:_is_engulfing(enemy) then
        if not enemy.captured then
            enemy.entry_angle, enemy.entry_distance = V.angle(-x, -y), distance
            enemy.captured, enemy.via_mouth = true, self:mouth_contact(enemy)
            enemy.meal_infected, enemy.digest_duration = enemy.infect > 0, rules.duration
        end
        enemy.engulf = min(1, enemy.engulf + dt / enemy.digest_duration)
        local decay = exp(-dt / 0.18)
        enemy.vel = point(enemy.vel.x * decay, enemy.vel.y * decay)
        enemy.pos = offset(self.player, enemy.entry_angle, radius * 0.35)
        if enemy.engulf >= 1 then self:_die(i, true) end
        return
    end
    enemy.engulf = max(0, enemy.engulf - dt * 0.12)
    local dx, dy = x, y
    if enemy.r < radius * 0.82 then
        if distance < 180 + radius then dx, dy = -x, -y
        else
            local c, s = math.cos(enemy.phase), math.sin(enemy.phase)
            dx, dy = x * c - y * s, x * s + y * c
        end
    end
    if enemy.kind == "spitter" and distance < 300 then dx, dy = -dx * 0.3, -dy * 0.3 end
    if safe and enemy.kind ~= "prey" then dx, dy = -dx, -dy end
    local speed = enemy.speed * rules.speed * (enemy.slow > 0 and 0.35 or 1) * (contains(enemy.traits, "swift") and 1.2 or 1)
    dx, dy = dx * speed, dy * speed
    local pull_range = self:attraction_radius()
    if enemy.grasp > 0 then
        local build = self.build
        pull_range = max(pull_range, (165 + build:rank("tentacle") * 12) * build:specialization_value("tentacle", "reach_mult") * self:ability_scale())
    end
    if enemy.crown_time > 0 then
        local p = self:_crown_destination()
        local mx, my = V.normal(p.x - enemy.pos.x, p.y - enemy.pos.y)
        dx, dy = dx * 0.25 + mx * rules.pull * 1.35, dy * 0.25 + my * rules.pull * 1.35
    elseif distance < pull_range and rules.pull > 0 then
        dx, dy = dx + x * rules.pull, dy + y * rules.pull
    end
    if enemy.impulse then
        local decay = exp(-dt / 0.25)
        enemy.impulse = point(enemy.impulse.x * decay, enemy.impulse.y * decay)
        dx, dy = dx + enemy.impulse.x, dy + enemy.impulse.y
    end
    if enemy.kind == "boss" and (enemy.boss_windup or 0) > 0 then
        enemy.vel = point()
    else
        local response = exp(-dt / 0.28)
        local old_x, old_y = enemy.vel.x - dx, enemy.vel.y - dy
        enemy.vel = point(dx + old_x * response, dy + old_y * response)
        dx, dy = dx * dt + old_x * 0.28 * (1 - response), dy * dt + old_y * 0.28 * (1 - response)
        local contact = self:_contact_radius(enemy, radius)
        if distance <= contact + math.sqrt(dx * dx + dy * dy) and self:_blocks_body(enemy, radius) then
            dx, dy = Size.slide_contact(enemy.pos, dx, dy, self.player, contact)
        end
        enemy.pos = point(self.world:move_body(enemy.pos.x, enemy.pos.y, dx, dy, min(26, enemy.r * 0.6)))
    end
    if enemy.kind == "boss" then
        self.boss_marker = enemy.pos
        self:_boss_windup(enemy, dt)
    elseif enemy.kind == "spitter" then
        self:_spitter_windup(enemy, dt, distance)
    elseif enemy.kind == "miniboss" then
        enemy.shot_cd = enemy.shot_cd - dt
        if enemy.shot_cd <= 0 and distance < 850 then
            enemy.shot_cd = 1.5
            for n = 0, 4 do
                self:_shot(enemy.pos, offset(point(), n * TAU / 5 + self.elapsed, 100), 7,
                    true, "enemy", self:_enemy_label(enemy), enemy.id)
            end
        end
    end
    if distance < enemy.r + radius * 0.75 and rules.impact > 0 and self.invuln <= 0 and not safe
        and not self:_can_be_absorbed(enemy, radius) then
        self:hurt_player(rules.impact * (elite and 1.2 or 1), { kind = "collision", name = self:_enemy_label(enemy), pos = enemy.pos, id = enemy.id })
        self.invuln, enemy.impulse = 0.65, point(-x * 24, -y * 24)
        self:_effect("hurt", self.player, 45, 0.3)
    end
end

function Combat:_update_enemies(dt)
    local safe = self:_safe_zone(self.player)
    for i = #self.enemies, 1, -1 do
        self:_update_enemy(i, dt, self:body_radius(), safe)
        if self.stage_transition or self.hp <= 0 then return end
    end
end

local function damage(rank, base, scale)
    return Catalog.scaled_damage(base + rank * scale, rank)
end

function Combat:_attack_reach(enemy, reach)
    if enemy.kind == "boss" or enemy.r >= self:body_radius() * 1.6 then return reach + enemy.r * 0.78 end
    return reach
end

function Combat:_nearest(radius, accept)
    local nearest, best = nil, radius^2
    for _, enemy in ipairs(self.enemies) do
        local distance = distance_squared(self.player, enemy.pos)
        if enemy.hp > 0 and distance < best and (not accept and not self:_is_engulfing(enemy) or accept and accept(enemy)) then
            nearest, best = enemy, distance
        end
    end
    return nearest
end

function Combat:_bite(combos)
    local rank = self.build:rank("devour")
    if rank <= 0 or not self:_ready("bite") then return end
    local target = self:_nearest(math.huge, function(enemy) return not enemy.captured and self:mouth_contact(enemy) end)
    if not target then return end
    self.cooldowns.bite = 0.45 * self.build:specialization_value("devour", "bite_cooldown_mult")
    self.bite_flash = 1
    local bio = contains(combos, "enzyme_bite")
    self:hit_enemy(target, damage(rank, 7, 5) * (bio and 1.25 or 1), "devour")
    if bio then
        target.enzyme_time = 3
        self:_effect("enzyme_bite", self.player, self:body_radius(), 0.7, { ["end"] = target.pos })
    end
    self:_effect("bite", offset(self.player, self.facing, self:body_radius() * 0.8), self:body_radius() * 0.25, 0.3, { ["end"] = target.pos })
end

function Combat:_tentacle(rank, scale, metabolic, combos)
    local reach = (165 + rank * 12) * self.build:specialization_value("tentacle", "reach_mult") * scale
    local targets = {}
    for _, enemy in ipairs(self.enemies) do
        if enemy.hp > 0 and not enemy.captured and distance_squared(enemy.pos, self.player) < self:_attack_reach(enemy, reach)^2 then
            targets[#targets + 1] = enemy
        end
    end
    if #targets == 0 then return end
    table.sort(targets, function(a, b)
        local da, db = distance_squared(a.pos, self.player), distance_squared(b.pos, self.player)
        if da == db then return a.id < b.id end
        return da < db
    end)
    self.cooldowns.tentacle = 0.85 * metabolic
    local count = Catalog.tentacle_count(rank)
    for _, enemy in ipairs(self.enemies) do
        enemy.was_crown = (enemy.crown_time or 0) > 0
        enemy.crown_time = 0
    end
    local crown, ordinary = {}, {}
    local evolved, magnet = self.build:evolved("tentacle"), self.build:rank("magnet")
    for _, enemy in ipairs(targets) do
        if evolved and #crown < min(2, count) and Evolution.crown_eligible(self:body_radius(), enemy, magnet) then
            enemy.crown_time, enemy.crown_limbs = 1.1, {}
            if not enemy.was_crown then enemy.crown_age = 0 end
            crown[#crown + 1] = enemy
        else
            ordinary[#ordinary + 1] = enemy
        end
    end
    local crown_limbs = #crown > 0 and min(count, max(#crown, math.floor(count / 2))) or 0
    local portions, grasp = {}, contains(combos, "acid_grasp")
    for limb = 0, count - 1 do
        local target = targets[limb % #targets + 1]
        if limb < crown_limbs then target = crown[limb % #crown + 1]
        elseif #ordinary > 0 then target = ordinary[(limb - crown_limbs) % #ordinary + 1] end
        if target.crown_time > 0 then target.crown_limbs[#target.crown_limbs + 1] = limb end
        portions[target.id] = (portions[target.id] or 0) + 1
        self:_effect("lash", self.player, reach, 0.5, { ["end"] = target.pos, limb = limb, count = count })
        if grasp then target.slow, target.grasp = 1.3, 1.3 end
    end
    for _, target in ipairs(targets) do
        if portions[target.id] then self:hit_enemy(target, damage(rank, 9, 7) * portions[target.id] / count, "tentacle") end
    end
    if grasp then self:_effect("acid_grasp", self.player, 30, 0.65, { ["end"] = targets[1].pos }) end
end

function Combat:_electric(rank, scale, combos)
    local reach = 280 * scale
    if not self:_nearest(reach) then return end
    local previous, visited = self.player, {}
    local count = min(7, Catalog.electric_targets(rank) + self.build:specialization_bonus("electric", "target_bonus"))
    for _ = 1, count do
        local target, best = nil, reach^2
        for _, enemy in ipairs(self.enemies) do
            local distance = distance_squared(previous, enemy.pos)
            if not visited[enemy.id] and not enemy.captured and enemy.hp > 0 and distance < best then
                target, best = enemy, distance
            end
        end
        if not target then break end
        visited[target.id] = true
        self:hit_enemy(target, damage(rank, 12, 6), "electric")
        self:_effect("electric", previous, 20, 0.35, { ["end"] = target.pos })
        if contains(combos, "conductive_bath") then
            target.slow = 1.2
            self:_effect("conductive_bath", previous, target.r + 25, 0.7, { ["end"] = target.pos })
            self:_field(target.pos, 30, 3, 1, "acid_arc")
        end
        previous = target.pos
    end
    self.cooldowns.electric = 2.6
end

function Combat:_cilia(rank, scale, combos)
    local touched = false
    local reach = (100 + rank * 10) * self.build:specialization_value("cilia", "reach_mult") * scale
    for _, enemy in ipairs(self.enemies) do
        local x, y, distance = V.normal(enemy.pos.x - self.player.x, enemy.pos.y - self.player.y)
        if not enemy.captured and distance <= self:_attack_reach(enemy, reach) and x * math.cos(self.facing) + y * math.sin(self.facing) >= 0.5 then
            self:hit_enemy(enemy, damage(rank, 10, 6), "cilia")
            touched = true
        end
    end
    if not touched then return end
    self.cooldowns.cilia = 1.4
    local radius = self:body_radius() * 3
    local finish = offset(self.player, self.facing, radius)
    self:_effect("cilia", self.player, radius, 0.4, { ["end"] = finish })
    if contains(combos, "barbed_cilia") then
        self:_effect("barbed_cilia", self.player, radius, 0.8, { ["end"] = finish })
        local spike_rank = self.build:rank("spikes")
        for i = -1, 1 do self:_shot(self.player, offset(point(), self.facing + i * 0.35, 300), damage(spike_rank, 12, 5), false) end
    end
end

function Combat:_pulse(rank, scale, metabolic, combos)
    self.cooldowns.pulse = 3.2 * metabolic
    if contains(combos, "shield_pulse") then
        self.cooldowns.barrier = max(0, (self.cooldowns.barrier or 0) - 2)
        self:_effect("shield_pulse", self.player, self:body_radius() * 2.4, 1)
    end
    local radius = (130 + rank * 18) * self.build:specialization_value("pulse", "radius_mult") * scale
    for _, enemy in ipairs(self.enemies) do
        if not self:_is_engulfing(enemy) and distance_squared(self.player, enemy.pos) < self:_attack_reach(enemy, radius)^2 then
            self:hit_enemy(enemy, damage(rank, 12, 8), "pulse")
            local x, y = V.normal(enemy.pos.x - self.player.x, enemy.pos.y - self.player.y)
            local impulse = enemy.impulse or point()
            enemy.impulse = point(impulse.x + x * 100, impulse.y + y * 100)
        end
    end
    self:_effect("pulse", self.player, radius, 0.55)
    if contains(combos, "spike_pulse") then
        self:_effect("spike_pulse", self.player, radius, 0.8)
        local spike_rank = self.build:rank("spikes")
        for i = 0, 7 do self:_shot(self.player, offset(point(), i * TAU / 8, 370), damage(spike_rank, 18, 4), false) end
    end
end

function Combat:clone_positions()
    local result = {}
    local count = min(6, Catalog.clone_count(self.build:rank("division")) + self.build:specialization_bonus("division", "clone_bonus"))
    for i = 0, count - 1 do result[#result + 1] = offset(self.player, self.elapsed * 1.6 + i * TAU / count, 105) end
    return result
end

function Combat:_attack(dt)
    local build = self.build
    local combos, scale, metabolic = build:active_synergies(), self:ability_scale(), self:cooldown_factor()
    self:_bite(combos)
    local rank = build:rank("cilia")
    if rank > 0 and self:_ready("cilia") then self:_cilia(rank, scale, combos) end
    rank = build:rank("enzymes")
    if rank > 0 and self:_ready("enzymes") then
        local target = self:_nearest(230 * scale)
        if target then
            target.enzyme_time = 4 * build:specialization_value("enzymes", "duration_mult")
            self.cooldowns.enzymes = 2
            self:_effect("enzymes", self.player, target.r, 0.5, { ["end"] = target.pos })
        end
    end
    rank = build:rank("electric")
    if rank > 0 and self:_ready("electric") then self:_electric(rank, scale, combos) end
    if contains(combos, "metabolic_colony") and self:_ready("colony_visual") and self.hp < self.max_hp then
        self.cooldowns.colony_visual = 2
        self:_effect("metabolic_colony", self.player, self:body_radius() * 2.5, 1.4)
    end
    rank = build:rank("tentacle")
    if rank > 0 and self:_ready("tentacle") then self:_tentacle(rank, scale, metabolic, combos) end
    rank = build:rank("acid")
    if rank > 0 then
        local reach = (75 + rank * 9) * build:specialization_value("acid", "radius_mult") * scale
        for _, enemy in ipairs(self.enemies) do
            if not self:_is_engulfing(enemy) and distance_squared(self.player, enemy.pos) < self:_attack_reach(enemy, reach)^2 then
                self:hit_enemy(enemy, damage(rank, 4, 3) * dt, "acid")
            end
        end
    end
    rank = build:rank("spikes")
    if rank > 0 and self:_ready("spikes") then
        local target = self:_nearest(650)
        if target then
            self.cooldowns.spikes = 1.3 * metabolic
            local heading = V.angle(target.pos.x - self.player.x, target.pos.y - self.player.y)
            local count = min(7, Catalog.shot_count(rank) + build:specialization_bonus("spikes", "shot_bonus"))
            for i = 0, count - 1 do
                local angle = heading + (i - (count - 1) / 2) * 0.13
                self:_shot(self.player, offset(point(), angle, 450), damage(rank, 12, 5), false)
            end
        end
    end
    rank = build:rank("pulse")
    if rank > 0 and self:_ready("pulse") then self:_pulse(rank, scale, metabolic, combos) end
    rank = build:rank("infection")
    if rank > 0 and self:_ready("infection") then
        local target = self:_nearest(420 * scale)
        if target then
            target.infect = 4.5 * build:specialization_value("infection", "duration_mult")
            self:_effect("infection", self.player, target.r, 0.85, { ["end"] = target.pos })
            self.cooldowns.infection = 1.6 * metabolic
        end
    end
    rank = build:rank("trail")
    if rank > 0 and self:_ready("trail") then
        local duration = build:specialization_value("trail", "duration_mult")
        self.cooldowns.trail = 0.6
        self:_field(self.player, 50 + rank * 6, damage(rank, 5, 3), 3 * duration, "poison")
        if contains(combos, "toxic_colony") then
            for _, p in ipairs(self:clone_positions()) do self:_field(p, 40, damage(rank, 3, 1.5), 2 * duration, "poison") end
            self:_effect("toxic_colony", self.player, 105, 0.65)
        end
    end
    rank = build:rank("division")
    if rank > 0 then
        for _, p in ipairs(self:clone_positions()) do
            for _, enemy in ipairs(self.enemies) do
                if not self:_is_engulfing(enemy) and distance_squared(p, enemy.pos) < (enemy.r + 18)^2 then
                    self:hit_enemy(enemy, damage(rank, 8, 4) * dt, "division")
                end
            end
        end
    end
end

function Combat:_shot(pos, vel, amount, hostile, source, name, id)
    if #self.shots >= 200 then return end
    self.shots[#self.shots + 1] = {
        pos = pos, vel = vel, damage = amount, hostile = hostile, life = 2,
        source = source or "spikes", origin = pos, actor_name = name, actor_id = id,
    }
end

local function projectile_hit(shot, enemies)
    for _, enemy in ipairs(enemies) do
        if enemy.hp > 0 and not enemy.captured and distance_squared(shot.pos, enemy.pos) < (enemy.r + 8)^2 then return enemy end
    end
end

function Combat:_update_shots(dt)
    if #self.shots == 0 then return end
    local buckets, wide = {}, {}
    for _, shot in ipairs(self.shots) do
        if not shot.hostile then
            for _, enemy in ipairs(self.enemies) do
                if enemy.r + 8 > 100 then
                    wide[#wide + 1] = enemy
                else
                    local key = math.floor(enemy.pos.y / 100) * 1024 + math.floor(enemy.pos.x / 100)
                    if not buckets[key] then buckets[key] = {} end
                    buckets[key][#buckets[key] + 1] = enemy
                end
            end
            break
        end
    end
    local safe = self:_safe_zone(self.player)
    for i = #self.shots, 1, -1 do
        local shot = self.shots[i]
        shot.life = shot.life - dt
        shot.pos = point(shot.pos.x + shot.vel.x * dt, shot.pos.y + shot.vel.y * dt)
        local hit
        if shot.hostile then
            hit = distance_squared(shot.pos, self.player) < (self:body_radius() * 0.78 + 3)^2
            if hit and self.invuln <= 0 and not safe then
                self:hurt_player(shot.damage, { kind = "projectile", name = shot.actor_name or "Вражеский снаряд", pos = shot.origin, id = shot.actor_id })
                self.invuln = 0.4
            end
        else
            local enemy = projectile_hit(shot, wide)
            local key = math.floor(shot.pos.y / 100) * 1024 + math.floor(shot.pos.x / 100)
            for y = -1, 1 do
                if enemy then break end
                for x = -1, 1 do
                    if enemy then break end
                    local bucket = buckets[key + y * 1024 + x]
                    if bucket then enemy = projectile_hit(shot, bucket) end
                end
            end
            if enemy then
                self:hit_enemy(enemy, shot.damage, shot.source)
                hit = true
            end
        end
        if hit or shot.life <= 0 or not self.world:walkable(shot.pos.x, shot.pos.y) then table.remove(self.shots, i) end
    end
end

function Combat:_field(pos, radius, amount, life, kind, hostile, name, id)
    if not hostile and kind == "poison" and contains(self.build:active_synergies(), "ferment_cloud") then
        amount = amount * 1.25
        if self:_ready("ferment_visual") then
            self.cooldowns.ferment_visual = 1.2
            self:_effect("ferment_cloud", pos, radius * 1.25, 1.2)
        end
    end
    if kind == "spore" then self:_effect("spore_feast", pos, radius, 1.4) end
    if #self.fields >= 80 then table.remove(self.fields, 1) end
    self.fields[#self.fields + 1] = {
        pos = pos, r = radius, damage = amount, life = life, max = life, kind = kind, hostile = hostile,
        source = ({ spore = "infection", mantle = "acid", acid_arc = "electric" })[kind] or "trail",
        actor_name = name, actor_id = id,
    }
end

function Combat:_update_fields(dt)
    if #self.fields == 0 then return end
    local ferment = contains(self.build:active_synergies(), "ferment_cloud")
    local fields, pending = self.fields, {}
    local safe = self:_safe_zone(self.player)
    -- A mantle pulse may append a field while an enemy field hurts the player.
    -- Keep original references so a capacity eviction cannot shift loop indices.
    for i = 1, #fields do pending[i] = fields[i] end
    for i = #pending, 1, -1 do
        local field = pending[i]
        field.life = field.life - dt
        if field.hostile then
            if not safe and distance_squared(field.pos, self.player) < (field.r + self:body_radius() * 0.65)^2 then
                self:hurt_player(field.damage * dt, {
                    kind = "toxin", name = field.actor_name or (field.kind == "enemy_spore" and "Вражеские споры" or "Ядовитое облако"),
                    pos = field.pos, id = field.actor_id,
                })
            end
        else
            for _, enemy in ipairs(self.enemies) do
                if distance_squared(field.pos, enemy.pos) < (field.r + enemy.r * 0.5)^2 then
                    self:hit_enemy(enemy, field.damage * dt, field.source)
                    if ferment then enemy.enzyme_time = 2 end
                end
            end
        end
    end
    for i = #fields, 1, -1 do if fields[i].life <= 0 then table.remove(fields, i) end end
end

return Combat
