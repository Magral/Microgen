local Catalog = require("main.run.catalog")
local Build = require("main.run.build_model")

local M = {}
local format = string.format
local min, max = math.min, math.max

local function contains(list, value)
    for _, entry in ipairs(list) do
        if entry == value then
            return true
        end
    end
    return false
end

-- Match Godot's fixed-point formatting at binary-exact halfway values.
local function one(value)
    return value % 1 == 0.25 and value - 0.05 or value
end

local function two(value)
    local fraction = value % 1
    return (fraction == 0.125 or fraction == 0.625) and value - 0.005 or value
end

local attacks = {
    tentacle = { base = 9, growth = 7, interval = 0.85, tempo = true },
    acid = { base = 4, growth = 3 },
    spikes = { base = 12, growth = 5, interval = 1.3, tempo = true },
    pulse = { base = 12, growth = 8, interval = 3.2, tempo = true },
    division = { base = 8, growth = 4 },
    trail = { base = 5, growth = 3 },
    infection = { base = 4, growth = 3 },
    devour = { base = 7, growth = 5, interval = 0.45 },
    cilia = { base = 10, growth = 6, interval = 1.4 },
    enzymes = { base = 3, growth = 2 },
    electric = { base = 12, growth = 6, interval = 2.6 },
}

local function attack_details(build, id, rank, scale, tempo)
    if id == "tentacle" then
        local reach = (165 + rank * 12) * build:specialization_value(id, "reach_mult") * scale
        return format("; щупалец %d; суммарный залп делится между ними; дальность %.1f", Catalog.tentacle_count(rank), one(reach))
    elseif id == "acid" then
        local radius = (75 + rank * 9) * build:specialization_value(id, "radius_mult") * scale
        return format("; радиус %.1f", one(radius))
    elseif id == "spikes" then
        local shots = min(7, Catalog.shot_count(rank) + build:specialization_bonus(id, "shot_bonus"))
        return format("; шипов %d (DPS на один шип)", shots)
    elseif id == "pulse" then
        local radius = (130 + rank * 18) * build:specialization_value(id, "radius_mult") * scale
        return format("; радиус %.1f", one(radius))
    elseif id == "division" then
        local clones = min(6, Catalog.clone_count(rank) + build:specialization_bonus(id, "clone_bonus"))
        return format("; копий %d (урон одной копии)", clones)
    elseif id == "trail" then
        local duration = 3 * build:specialization_value(id, "duration_mult")
        return format("; радиус %.1f; поле %.1f с; интервал 0,6 с", 50 + rank * 6, one(duration))
    elseif id == "infection" then
        local duration = 4.5 * build:specialization_value(id, "duration_mult")
        return format("; заражение %.1f с; интервал %.2f с", one(duration), two(1.6 * tempo))
    elseif id == "devour" then
        return format("; сектор 80°; время переваривания −35%%; лечение %.1f HP за поглощение", one(rank * 0.8))
    elseif id == "cilia" then
        local reach = (100 + rank * 10) * build:specialization_value(id, "reach_mult") * scale
        return format("; дальность %.1f; сектор 120°", one(reach))
    elseif id == "enzymes" then
        local duration = 4 * build:specialization_value(id, "duration_mult")
        return format("; ферменты %.1f с; интервал 2 с", one(duration))
    elseif id == "electric" then
        local targets = min(7, Catalog.electric_targets(rank) + build:specialization_bonus(id, "target_bonus"))
        return format("; целей %d", targets)
    end
    return ""
end

local passive_formats = {
    armor = "Снижение урона %.1f%% (предел 60%%)",
    speed = "Скорость +%.1f%% (предел 60%%)",
    regen = "Регенерация %.2f HP/с",
    magnet = "Радиус притяжения: тело + %.1f",
    metabolism = "Получаемая ДНК (XP) +%.1f%%",
    catalysis = "Урон органов +%.1f%%",
}

local function evolution_details(build, id, rank, scale, multiplier, catalysis)
    if not build:evolved(id) then
        return ""
    end
    local details = ""
    if id == "acid" then
        local damage = Catalog.scaled_damage(3 + rank * 1.5, rank) * multiplier
        details = format("; ответная кислота %.2f DPS, 1,2 с, радиус %.1f, раз в 2 с", two(damage), one(34 * scale * 0.8))
    elseif id == "infection" then
        local damage = Catalog.scaled_damage(4 + rank * 2, rank) * multiplier
        details = format("; споры %.2f DPS, 2,4 с, радиус %.1f за 3 порции", two(damage), one(34 * scale * 2.3))
    elseif id == "tentacle" then
        local acid = build:rank("acid")
        if acid > 0 then
            local damage = Catalog.scaled_damage(1 + acid, acid) * build:power("acid") * catalysis
            details = format("; удерживающая кислота %.2f DPS на цель", two(damage))
        end
    end
    local recipe = Catalog.EVOLUTIONS[id]
    return details .. "; " .. (recipe and recipe.behavior or "Урон эволюции ×1,30")
end

-- These values describe the build before enemy resistance and size attenuation.
function M.effect_text(build, id, scale, tempo)
    scale, tempo = scale or 1, tempo or 1
    local rank = build:rank(id)
    if rank <= 0 then
        return "Не установлено"
    end
    if id == "barrier" then
        return format("Щит %.1f HP; восстановление 8 с", one(Catalog.scaled_damage(8 + rank * 6, rank) * build:power(id)))
    end
    if passive_formats[id] then
        local passive = build:passive(id)
        if id == "regen" then
            return format(passive_formats[id], two(passive))
        end
        return format(passive_formats[id], one(id == "magnet" and passive or passive * 100))
    end
    local attack = attacks[id]
    if not attack then
        return Catalog.item(id).desc or ""
    end

    local catalysis = 1 + build:passive("catalysis")
    local multiplier = build:power(id) * catalysis
    if (id == "devour" and contains(build:active_synergies(), "enzyme_bite")) or
        (id == "trail" and contains(build:active_synergies(), "ferment_cloud")) then
        multiplier = multiplier * 1.25
    end
    local damage = Catalog.scaled_damage(attack.base + attack.growth * rank, rank) * multiplier
    local details = attack_details(build, id, rank, scale, tempo) ..
        evolution_details(build, id, rank, scale, multiplier, catalysis)
    if not attack.interval then
        return format("Урон %.2f/с (DPS)", two(damage)) .. details
    end

    local interval = attack.interval
    if attack.tempo then
        interval = interval * tempo
    elseif id == "devour" then
        interval = interval * build:specialization_value(id, "bite_cooldown_mult")
    end
    return format("Урон %.2f; DPS %.2f; интервал %.2f с", two(damage), two(damage / interval), two(interval)) .. details
end

function M.comparison(build, id, quality, replace_id, scale, tempo)
    replace_id = replace_id or ""
    local projected = Build.new()
    projected:from_dict(build:to_dict())
    local current = M.effect_text(build, replace_id ~= "" and replace_id or id, scale, tempo)
    if projected:apply(id, replace_id, quality) then
        return current .. " → " .. M.effect_text(projected, id, scale, tempo)
    end
    if replace_id == "" and build:rank(id) == 0 and Catalog.item(id).name then
        local target = Catalog.ORGANS[id] and projected.organs or projected.adaptations
        target[id] = 1
        projected.qualities[id] = max(0, min(3, quality or 0))
        return "После выбора замены: " .. M.effect_text(projected, id, scale, tempo) ..
            ". Наследуемые ранг и качество уточнятся после выбора органа."
    end
    return current .. " → недоступно"
end

function M.evolution_preview(build, id, scale, tempo)
    local current = M.effect_text(build, id, scale, tempo)
    local projected = Build.new()
    projected:from_dict(build:to_dict())
    if not projected:evolve(id) then
        return current
    end
    return current .. " → " .. M.effect_text(projected, id, scale, tempo)
end

function M.synergy_lines(build, id)
    local lines = {}
    local specialization = Catalog.specialization_data(id, build.specializations[id])
    if specialization.synergy_power then
        local linked = false
        for _, synergy_id in ipairs(build:active_synergies()) do
            if contains(Catalog.SYNERGIES[synergy_id].needs, id) then
                linked = true
                break
            end
        end
        lines[#lines + 1] = format("✦ %s: сила органа ×%.2f%s.", specialization.name, two(specialization.synergy_power),
            linked and " · активирована синергия" or " · включится при синергии")
    end
    for _, synergy_id in ipairs(Catalog.SYNERGY_IDS) do
        local synergy = Catalog.SYNERGIES[synergy_id]
        local first, second = synergy.needs[1], synergy.needs[2]
        if id == first or id == second then
            local rank_a, rank_b = build:rank(first), build:rank(second)
            lines[#lines + 1] = format("%s%s: %s %d/1 + %s %d/1. %s",
                rank_a > 0 and rank_b > 0 and "✓ " or "◇ ", synergy.name,
                Catalog.item(first).name, rank_a, Catalog.item(second).name, rank_b, synergy.desc)
        end
    end
    for _, organ in ipairs(Catalog.EVOLUTION_IDS) do
        local recipe = Catalog.EVOLUTIONS[organ]
        if id == organ or id == recipe.passive then
            local state = "◇ Эволюция"
            if build:evolved(organ) then
                state = "✓ Эволюция"
            elseif contains(build:evolution_candidates(), organ) then
                state = "Готова эволюция"
            end
            lines[#lines + 1] = format("%s: %s. %s %d/6 + %s %d/3; урон органа ×1,30 (+30%%).",
                state, recipe.name, Catalog.item(organ).name, build:rank(organ),
                Catalog.item(recipe.passive).name, build:rank(recipe.passive))
        end
    end
    return table.concat(lines, "\n")
end

function M.synergy_summary(build, id)
    local lines = {}
    for _, synergy_id in ipairs(Catalog.SYNERGY_IDS) do
        local synergy = Catalog.SYNERGIES[synergy_id]
        local first, second = synergy.needs[1], synergy.needs[2]
        if id == first or id == second then
            local mark = build:rank(first) > 0 and build:rank(second) > 0 and "✓ " or "◇ "
            lines[#lines + 1] = mark .. synergy.name .. " · " ..
                Catalog.item(first).name .. " + " .. Catalog.item(second).name
        end
    end
    return #lines > 0 and table.concat(lines, "\n") or "Нет связей с другими органами."
end

function M.synergy_rows(build, selected)
    local rows, inactive, related = {}, {}, {}
    for _, id in ipairs(Catalog.SYNERGY_IDS) do
        local synergy = Catalog.SYNERGIES[id]
        local first, second = synergy.needs[1], synergy.needs[2]
        local has_first, has_second = build:rank(first) > 0, build:rank(second) > 0
        local active = has_first and has_second
        local matches = selected == first or selected == second
        local group = matches and related or (active and rows or inactive)
        local first_name,second_name=Catalog.item(first).name,Catalog.item(second).name
        local missing = not has_first and not has_second and (first_name.." + "..second_name)
            or (not has_first and first_name or second_name)
        group[#group + 1] = {
            id = id,
            name = synergy.name,
            title = (active and "✓ " or "◇ ") .. synergy.name,
            requirements = (has_first and "✓ " or "+ ") .. first_name ..
                " + " .. (has_second and "✓ " or "+ ") .. second_name,
            description = synergy.desc,
            status = active and "✓ Активна" or ("◇ Неактивна · нужно: "..missing),
            related = matches,
            active = active,
        }
    end
    for _, row in ipairs(rows) do related[#related + 1] = row end
    for _, row in ipairs(inactive) do related[#related + 1] = row end
    return related
end

return M
