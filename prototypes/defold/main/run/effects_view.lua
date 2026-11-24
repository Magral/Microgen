local V = require "main.run.combat_math"
local Effects = {}

local min, max, sin = math.min, math.max, math.sin
local pi, tau = math.pi, V.tau
local point, offset, heading = V.point, V.offset, V.angle
local thread_frames = {"thread_0", "thread_1", "thread_2"}
local bolt_frames = {"bolt_0", "bolt_1", "bolt_2"}

local function clamp(value)
    return max(0, min(1, value))
end

local function mix(a, b, u)
    return point(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u)
end

local function rgb(hex, alpha)
    hex = hex:gsub("^#", "")
    local value = tonumber(hex, 16)
    if not value then value = 0xd3b7f0 end
    return vmath.vector4(
        math.floor(value / 65536) / 255,
        math.floor(value / 256) % 256 / 255,
        value % 256 / 255,
        clamp(alpha)
    )
end

local function wave(scene, frame, p, radius, color, alpha, angle, squash, group)
    if alpha <= 0 or radius <= 0 then return end
    -- Atlas contours are inset to leave room for the soft outer stroke.
    local size = radius / 0.44
    scene:draw_combat(group or scene.effects, frame, p, size, size * (squash or 1), rgb(color, alpha), angle or 0)
end

local function filament(scene, frame, a, b, width, color, alpha)
    if alpha <= 0 then return end
    local dx, dy = b.x - a.x, b.y - a.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.8 then return end
    scene:draw_combat(scene.effects, frame, mix(a, b, 0.5), length / 0.85, width,
        rgb(color, alpha), heading(dx, dy))
end

local function thread(scene, a, b, width, color, alpha, phase)
    local frame = thread_frames[math.floor(phase * 9) % #thread_frames + 1]
    filament(scene, frame, a, b, width, color, alpha)
end

local function speck(scene, p, radius, color, alpha)
    if alpha <= 0 then return end
    scene:draw_effect(scene.effects, "speck", p, radius, rgb(color, alpha), 0)
end

local function feedback(scene, fx, t, q)
    local heal = fx.type == "heal"
    local amount = fx.amount or 0
    local scale = max(0.01, scene.scale)
    local p = point(fx.pos.x + (heal and -38 or 7) / scale, fx.pos.y - (18 + t * 24 + (heal and 20 or 0)) / scale)
    local text = heal and string.format(amount < 0.1 and "+%.2f" or "+%.1f", amount)
        or tostring(max(1, math.floor(amount + 0.5)))
    local tint = heal and "69ffaf" or fx.player and "ff7185" or "ef9199"
    scene:draw_number(point(p.x + 1 / scale, p.y + 1 / scale), text, rgb("170c12", q * 0.9), 0.8)
    scene:draw_number(p, text, rgb(tint, min(1, fx.life * 2)), 0.8)
end

local function cloud(scene, p, r, t, alpha, angle, time)
    local color = "e4bd77"
    for i = -1, 1 do
        local a = angle + pi + i * 0.58
        local tip = offset(p, a, r * (0.3 + 0.48 * t))
        local spread = r * (0.24 + 0.20 * t)
        wave(scene, "plume", tip, spread, color, alpha * 0.8, a - time * 0.13 + i * 0.16)
        filament(scene, "petal", offset(p, a, r * 0.12), tip, spread * 1.3, color, alpha * 0.46)
    end
end

local function colony(scene, sim, p, r, t, alpha, time, toxic)
    local clones = sim:clone_positions()
    local color = toxic and "a9db69" or "f4b992"
    for i = 1, max(1, min(3, #clones)) do
        local q = clones[i] or p
        if V.distance_squared(p, q) > 4 then
            thread(scene, p, q, 32, color, alpha * 0.64, time + i)
        end
        if toxic then
            wave(scene, "membrane", q, r * (0.33 + t * 0.38), color, alpha, time * 0.25 + i)
            wave(scene, "plume", q, r * (0.4 + t * 0.4), color, alpha * 0.44, -time * 0.4 + i)
        else
            local beat = sin(t * pi * 3 + i) * 0.10
            wave(scene, "ring", q, r * (0.35 + beat), color, alpha, time * 0.25 + i)
            filament(scene, "petal", offset(q, pi, r * 0.33), offset(q, 0, r * 0.33),
                r * (0.6 + beat), color, alpha * 0.72)
        end
    end
end

-- A compound effect is built from a few tinted paths, so every synergy has its
-- own silhouette while sharing texture state and the scene's existing GUI pool.
function Effects.draw(scene, sim, fx)
    local kind, p = fx.type, fx.pos
    if not p or kind == "lash" then return end
    local q = clamp((fx.life or 0) / max(0.01, fx.max or 1))
    local t = 1 - q
    if kind == "damage" or kind == "heal" then
        feedback(scene, fx, t, q)
        return
    end

    local time = sim.elapsed or 0
    local tip = fx["end"] or p
    local delta = V.distance_squared(tip, p)
    local angle = delta > 1 and heading(tip.x - p.x, tip.y - p.y) or time * 0.12
    local alpha = sin(pi * t)^0.65
    local r = fx.r or 22

    if kind == "electric" or kind == "enzymes" or kind == "cilia" then
        local color = kind == "electric" and "a6e5ef" or kind == "enzymes" and "ebc787" or "b1e8c9"
        if kind == "electric" then
            local frame = bolt_frames[math.floor(t * 20) % #bolt_frames + 1]
            filament(scene, frame, p, tip, 23, color, alpha * 0.9)
        else
            thread(scene, p, tip, 22, color, alpha * 0.83, time)
        end
        if kind == "cilia" then
            for side = -1, 1, 2 do
                thread(scene, p, offset(p, angle + side * 0.5, r), 15, color, alpha * 0.43, time + side)
            end
        end
    elseif kind == "infection" then
        local advance = clamp(t / 0.55)
        local reached = mix(p, tip, advance * advance * (3 - 2 * advance))
        for i = -1, 1 do
            local side = angle + pi / 2
            local root, finish = offset(p, side, i * 5), offset(reached, side, i * 5)
            thread(scene, root, finish, 21, "eba6da", alpha * 0.78, time + i)
            for j = 0, 2 do
                local u = (t * 1.6 + j / 3 + i * 0.1) % 1
                speck(scene, offset(mix(root, finish, u), side, sin(u * pi * 3 + time * 4) * 3),
                    2.1, "ffc9f2", alpha * 0.85)
            end
        end
    elseif kind == "bite" then
        local center = mix(p, tip, 0.3)
        for i = 0, 4 do
            speck(scene, offset(center, i * 2.399, r * t), 2.4 * q + 0.5, "d7dfbb", alpha * 0.75)
        end
    elseif kind == "acid_grasp" then
        local color = "b9f27b"
        r = max(22, r)
        for side = -1, 1, 2 do
            local normal = angle + side * pi / 2
            local root = offset(p, normal, r * 0.15)
            local finish = offset(tip, normal, r * 0.19 * q)
            thread(scene, root, finish, 18 + r * 0.32, color, alpha * 0.9, time + side)
            filament(scene, "petal", finish, offset(tip, angle, r * 0.17), r * 0.85, color, alpha * 0.88)
        end
        wave(scene, "membrane", tip, r * (0.23 + 0.30 * t), color, alpha * 0.58, time)
    elseif kind == "spike_pulse" then
        wave(scene, "thorn", p, r * (0.35 + t * 0.90), "90d4f2", alpha, -time * 0.29)
    elseif kind == "toxic_colony" or kind == "metabolic_colony" then
        colony(scene, sim, p, max(22, r), t, alpha, time, kind == "toxic_colony")
    elseif kind == "spore_feast" then
        local color = "e1a1ee"
        r = max(22, r)
        for i = 0, 5 do
            local a = i * tau / 6 + time * 0.18
            local root = offset(p, a, r * (0.95 - 0.56 * t))
            local finish = offset(p, a + 0.48, r * (0.35 - 0.20 * t))
            filament(scene, "petal", root, finish, r * 0.45, color, alpha)
            wave(scene, "membrane", root, r * 0.09 * (1 - t * 0.6), color, alpha * 0.75, a + time)
        end
    elseif kind == "enzyme_bite" then
        local color = "ffcf84"
        r = max(22, r)
        for side = -1, 1, 2 do
            local a = angle + side * (1.45 + 0.50 * q)
            wave(scene, "jaw", tip, r * (0.35 + 0.10 * sin(t * pi)), color, alpha, a)
        end
        wave(scene, "arc", tip, r * (0.22 + t * 0.35), color, alpha * 0.48, angle + pi)
    elseif kind == "conductive_bath" then
        local color = "8ef4ef"
        r = max(22, r)
        if delta <= 4 then tip = offset(p, angle, r * 0.8) end
        local frame = bolt_frames[math.floor(t * 22) % #bolt_frames + 1]
        filament(scene, frame, p, tip, 32, color, alpha)
        for i = 0, 3 do
            local root = mix(p, tip, 0.2 + i * 0.18)
            local branch = angle + (i % 2 == 0 and -1 or 1)
            filament(scene, bolt_frames[i % #bolt_frames + 1], root, offset(root, branch, r * 0.36), 18,
                color, alpha * 0.72)
        end
        wave(scene, "membrane", tip, r * (0.28 + 0.42 * t), color, alpha * 0.67, time * 3.0)
    elseif kind == "barbed_cilia" then
        r = max(22, r)
        for i = -2, 2 do
            local root = offset(p, angle + pi / 2, i * r * 0.18)
            local finish = offset(offset(root, angle, r * (0.45 + 0.3 * sin(t * pi))),
                angle + pi / 2, r * 0.13 * sin(t * pi + i * 0.4))
            filament(scene, "barb", root, finish, 25, "a7efbf", alpha)
        end
    elseif kind == "shield_pulse" then
        local color = "a4bfff"
        for i = 0, 2 do
            wave(scene, "membrane", p, r * (0.58 + i * 0.13 + t * 0.35), color, alpha * (0.88 - i * 0.2),
                time * 0.7 + i)
        end
        wave(scene, "corona", p, r * (0.86 + t * 0.34), color, alpha * 0.82, time * 0.08)
    elseif kind == "ferment_cloud" then
        cloud(scene, p, max(22, r), t, alpha, angle, time)
    elseif kind == "barrier_block" then
        wave(scene, "skin", sim.player, r, "78bfff", q * 0.39, time * 0.11)
        wave(scene, "membrane", sim.player, r * (1 + t * 0.13), "a3d6ff", q, time * 0.11)
    elseif kind == "membrane_break" then
        for i = -2, 2 do
            local a = angle + i * 0.46
            filament(scene, "beam", offset(p, a, r * t * 0.65), offset(p, a, r * (0.38 + t)), 8, "ffcf83", q)
        end
    elseif kind == "mantle" then
        wave(scene, "arc", p, r * (0.9 + t * 0.6), "c7f27f", alpha * 0.9, angle)
    elseif kind == "womb_feed" or kind == "womb_burst" then
        local radius = r * (0.35 + t * 0.65)
        wave(scene, "membrane", sim.player, radius, "eea1d8", alpha * 0.77, time * 0.6)
        if kind == "womb_burst" then
            wave(scene, "corona", sim.player, radius * 0.86, "ffcfec", alpha * 0.67, -time * 0.2)
        end
    elseif kind == "assimilate" or kind == "mutation" then
        local color = fx.color or (kind == "mutation" and "98eecb" or "d3b7f0")
        local center = sim.player
        if kind == "mutation" then
            wave(scene, "ring", center, r * (0.45 + t * 0.5), color, alpha * 0.87, time * 0.3)
        end
        for i = 0, 7 do
            local a = i * 2.399 + time * 0.15
            local particle = offset(center, a, r * (0.15 + 0.55 * t))
            speck(scene, particle, 3 * q + 0.5, color, alpha * 0.75)
        end
        if fx.text then
            local text_y = min(170 / scene.scale, sim:body_radius() * 1.5 + 35 / scene.scale)
            scene:draw_number(offset(center, pi / 2, text_y), fx.text, rgb(color, min(1, fx.life * 1.5)), 1)
        end
    else
        local color = kind == "hurt" and "f5989e" or "9be8db"
        wave(scene, "ring", p, r * (1 - q * 0.6), color, q * 0.60, time * 0.18)
    end
end

function Effects.draw_field(scene, field, time, compact)
    local p, r = field.pos, field.r
    local color = field.hostile and "e499b6" or field.kind == "spore" and "dfa3ec" or "b2dd75"
    local alpha = clamp(field.life / 0.5) * 0.55
    local age = field.max - field.life
    if not compact then
        wave(scene, "skin", p, r, color, 0.45 * field.life / field.max, field.pos.x * 0.2,
            nil, scene.fields)
    elseif field.hostile then
        wave(scene, "ring", p, r, color, min(0.88, field.life * 1.6), time * 0.08, nil, scene.fields)
    end
    for i = 0, (compact and 0 or 1) do
        local radius = r * (0.64 + i * 0.23 + sin(time * 1.2 + i + age) * 0.035)
        wave(scene, "membrane", p, radius, color, alpha * (0.72 - i * 0.2), time * 0.08 + i * 1.7,
            0.84 + i * 0.08, scene.fields)
    end
end

function Effects.draw_infection(scene, actor, time, enzyme)
    local color = enzyme and "ffc16d" or "fa69c5"
    local phase = actor.genome and actor.genome.phase or actor.phase or 0
    local radius = actor.r * (1.15 + sin(time * 3 + phase) * 0.032)
    local remaining = enzyme and actor.enzyme_time or actor.infect
    local growth = min(1, max(0.55, (4.5 - (remaining or 2)) * 1.8))
    wave(scene, "skin", actor.pos, radius, color, 0.42 + sin(time * 4) * 0.08, phase)
    wave(scene, "vessel", actor.pos, radius * growth * 0.83, color, 0.8 + sin(time * 3 + phase) * 0.1,
        phase + sin(time * 1.4) * 0.15)
end

function Effects.draw_shot(scene, shot)
    local angle = heading(shot.vel.x, shot.vel.y)
    local color = shot.hostile and "e27e9d" or "e7d1a7"
    scene:draw_combat(scene.effects, "projectile", offset(shot.pos, angle, -5.1), 17, 7, rgb(color, 0.95), angle)
end

function Effects.draw_boss(scene, sim, boss, time)
    if (boss.boss_windup or 0) > 0 then
        local attack = sim:boss_attack()
        local charge = 1 - clamp(boss.boss_windup / 1.1)
        for ray = 0, attack.count - 1 do
            local angle = boss.boss_angle + (ray - (attack.count - 1) * 0.5) * attack.spread
            local root = offset(boss.pos, angle, boss.r * 0.85)
            local tip = offset(boss.pos, angle, attack.speed * 2)
            filament(scene, "beam", root, tip, 18 + 4 * charge, attack.color, 0.55 + charge * 0.4)
        end
    end
    if (boss.boss_exposed or 0) > 0 then
        local pulse = 0.5 + 0.5 * sin(time * 12)
        wave(scene, "skin", boss.pos, boss.r * 0.28, "80ffe6", 0.65 + pulse * 0.35, time)
        wave(scene, "membrane", boss.pos, boss.r * 0.29, "a2ffe1", 0.96, -time)
    end
end

function Effects.draw_breakup(scene, data, elapsed, time)
    if not data or not data.pos then return end
    local t = clamp((elapsed or data.time or 0) / 1.35)
    wave(scene, "reward", data.pos, 25 + sin((time or 0) * 2.5) * 1.6, "ffdb9b", 0.96, t * 0.45)
end

function Effects.draw_player(scene, sim, time)
    local radius = sim:body_radius()
    local rank = sim.build:rank("acid")
    if rank > 0 then
        local reach = (75 + rank * 9) * sim.build:specialization_value("acid", "radius_mult") * sim:ability_scale()
        wave(scene, "skin", sim.player, reach, "8cd34d", 0.16, 0)
        wave(scene, "ring", sim.player, reach, "99d966", 0.19, time * 0.07)
    end
    if (sim.invuln or 0) > 0 then
        wave(scene, "ring", sim.player, radius * 1.4, "f2c3d1", 0.2 + 0.2 * sin(time * 24), time * 0.4)
    end
    local last = sim.last_damage or {}
    if last.kind == "toxin" and time - (last.time or -10) < 1.5 then
        Effects.draw_infection(scene, {pos = sim.player, r = radius, genome = sim.player_genome}, time)
    end
end

local toxin_kinds = {toxin = true, acid = true, spore = true, toxic = true, pool = true}

function Effects.draw_damage_sources(scene, sim, time)
    for _, marker in ipairs(sim.damage_markers or {}) do
        local color = toxin_kinds[marker.kind] and "f1b76c" or "ff8398"
        local radius = 19
        for _, enemy in ipairs(sim.enemies) do
            if V.distance_squared(enemy.pos, marker.pos) < 16 then
                radius = enemy.r * 1.3
                break
            end
        end
        wave(scene, "ring", marker.pos, radius, color, clamp(marker.life / max(0.01, marker.max)) * 0.69, time * 0.25)
    end
    local source = sim.last_damage or {}
    local age = time - (source.time or -10)
    if age < 0 or age > 3 then return end
    local origin = source.pos or sim.player
    if not origin.x then origin = point(origin[1], origin[2]) end
    local dx, dy = origin.x - sim.player.x, origin.y - sim.player.y
    local radius, scale = sim:body_radius(), max(0.01, scene.scale)
    local toxin = toxin_kinds[source.kind]
    local color = toxin and "efbf77" or "ff879b"
    local alpha = clamp((3 - age) * 1.3)
    local label_pos
    if dx * dx + dy * dy < (radius * 1.6)^2 then
        local reach = radius * 1.35 + 8 / scale
        wave(scene, "ring", sim.player, reach, color, alpha * 0.47, time * 0.2)
        if toxin then
            wave(scene, "membrane", sim.player, reach + (8 + sin(time * 4) * 2) / scale, color, alpha * 0.27,
                -time * 0.25)
        end
        label_pos = offset(sim.player, pi / 2, reach + 25 / scale)
    else
        local angle = heading(dx, dy)
        local reach = 170 / scale
        local p = offset(sim.player, angle, reach)
        local rear = offset(p, angle + pi, 11 / scale)
        for side = -1, 1, 2 do
            local q = offset(rear, angle + side * pi / 2, 7 / scale)
            filament(scene, "beam", q, p, 10 / scale, color, alpha * 0.9)
        end
        label_pos = offset(p, angle + pi, 35 / scale)
    end
    scene:draw_number(label_pos, source.name or "Источник урона", rgb(color, alpha * 0.85), 0.9)
    if age < 0.4 then
        wave(scene, "ring", sim.player, radius * 1.18, "ff9aab", (1 - age / 0.4) * 0.22, time * 0.2)
    end
end

return Effects
