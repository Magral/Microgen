local M = {
    HISTORY_LIMIT = 32,
    SOURCE_LIMIT = 32,
    OTHER_SOURCE_KEY = "__other_sources__",
    OTHER_SOURCE_NAME = "Прочие источники",
}

local UNKNOWN_SOURCE = "Неизвестный источник"
local format = string.format
local min, max, floor = math.min, math.max, math.floor

function M.create()
    return {
        tracking_start = 0,
        damage_dealt = 0,
        damage_taken = 0,
        blocked = 0,
        healed = 0,
        organs = {},
        kills_by_source = {},
        history = {},
        sources = {},
    }
end

local function finite(value)
    if type(value) == "number" and value > -math.huge and value < math.huge then
        return value
    end
    return 0
end

local function number(value)
    return max(0, finite(value))
end

local function dictionary(value)
    return type(value) == "table" and value or {}
end

local function label(name)
    if not name or name:match("^%s*$") then
        return UNKNOWN_SOURCE
    end
    return name
end

local function category(kind)
    return kind and kind ~= "" and kind or "unknown"
end

local function organ_stats(stats, source)
    local organ = stats.organs[source]
    if not organ then
        organ = { damage = 0, hits = 0, kills = 0 }
        stats.organs[source] = organ
    end
    return organ
end

local function record_source(sources, kind, name, damage, hits, overflow)
    kind, name = category(kind), label(name)
    local key = kind .. ":" .. name
    if not overflow and not sources[key] then
        local named_count = 0
        for id in pairs(sources) do
            if id ~= M.OTHER_SOURCE_KEY then
                named_count = named_count + 1
            end
        end
        overflow = named_count >= M.SOURCE_LIMIT
    end
    if overflow then
        key, kind, name = M.OTHER_SOURCE_KEY, "other", M.OTHER_SOURCE_NAME
    end
    local entry = sources[key]
    if not entry then
        entry = { name = name, kind = kind, source_id = "", damage = 0, hits = 0 }
        sources[key] = entry
    end
    entry.damage, entry.hits = entry.damage + damage, entry.hits + hits
end

function M.record_damage(stats, source, amount)
    local actual = number(amount)
    if actual <= 0 then
        return
    end
    local organ = organ_stats(stats, source)
    stats.damage_dealt = stats.damage_dealt + actual
    organ.damage, organ.hits = organ.damage + actual, organ.hits + 1
end

function M.record_kill(stats, source)
    local organ = organ_stats(stats, source)
    organ.kills = organ.kills + 1
    stats.kills_by_source[source] = (stats.kills_by_source[source] or 0) + 1
end

function M.record_heal(stats, actual)
    stats.healed = stats.healed + number(actual)
end

local function position(pos)
    if type(pos) == "userdata" then
        return { finite(pos.x), finite(pos.y) }
    end
    pos = dictionary(pos)
    return { finite(pos.x or pos[1]), finite(pos.y or pos[2]) }
end

function M.record_taken(stats, time, amount, blocked, kind, name, pos, source_id)
    local actual = number(amount)
    stats.blocked = stats.blocked + number(blocked)
    if actual <= 0 then
        return {}
    end

    stats.damage_taken = stats.damage_taken + actual
    local entry = {
        time = number(time), amount = actual, kind = category(kind), name = label(name),
        pos = position(pos), source_id = source_id,
    }
    local history = stats.history
    local last = history[#history]
    if last and last.kind == entry.kind and last.name == entry.name and last.source_id == entry.source_id and
        entry.time >= last.time and entry.time - last.time <= 1 then
        entry.amount = entry.amount + last.amount
        history[#history] = nil
    end
    history[#history + 1] = entry
    while #history > M.HISTORY_LIMIT do
        table.remove(history, 1)
    end
    record_source(stats.sources, entry.kind, entry.name, actual, 1)
    return entry
end

function M.restore(data)
    local clean = M.create()
    data = dictionary(data)
    for _, key in ipairs({ "tracking_start", "damage_dealt", "damage_taken", "blocked", "healed" }) do
        clean[key] = number(data[key])
    end
    for id, raw in pairs(dictionary(data.organs)) do
        if type(raw) == "table" then
            clean.organs[tostring(id)] = {
                damage = number(raw.damage), hits = floor(number(raw.hits)), kills = floor(number(raw.kills)),
            }
        end
    end
    for id, count in pairs(dictionary(data.kills_by_source)) do
        clean.kills_by_source[tostring(id)] = floor(number(count))
    end
    for _, raw in ipairs(dictionary(data.history)) do
        if type(raw) == "table" and number(raw.amount) > 0 then
            local pos = dictionary(raw.pos)
            clean.history[#clean.history + 1] = {
                time = number(raw.time), amount = number(raw.amount),
                kind = tostring(raw.kind or "unknown"), name = label(tostring(raw.name or UNKNOWN_SOURCE)),
                pos = #pos == 2 and position(pos) or { 0, 0 },
                source_id = raw.source_id == nil and "" or raw.source_id,
            }
        end
    end
    while #clean.history > M.HISTORY_LIMIT do
        table.remove(clean.history, 1)
    end
    for id, raw in pairs(dictionary(data.sources)) do
        if type(raw) == "table" then
            record_source(clean.sources, tostring(raw.kind or "unknown"), tostring(raw.name or UNKNOWN_SOURCE),
                number(raw.damage), floor(number(raw.hits)), id == M.OTHER_SOURCE_KEY)
        end
    end
    return clean
end

local kind_names = {
    collision = "Столкновение",
    unknown = "Источник неизвестен",
    contact = "Контакт",
    projectile = "Снаряд",
    hazard = "Среда",
    toxin = "Токсин",
    boss = "Архицит",
    damage = "Повреждение",
    enemy = "Противник",
}

-- LuaJIT rounds halfway values up. Match the Godot journal at exact ties.
local function one(value)
    return value % 1 == 0.25 and value - 0.05 or value
end

local function two(value)
    local fraction = value % 1
    return (fraction == 0.125 or fraction == 0.625) and value - 0.005 or value
end

function M.dps(stats, elapsed)
    return number(stats.damage_dealt) / max(0.01, elapsed - number(stats.tracking_start))
end

function M.summary(stats, elapsed)
    return format("Урон нанесён %.1f · получен %.1f\nDPS %.2f — средний за время учёта · щитом/бронёй заблокировано %.1f · лечение %.1f HP",
        one(number(stats.damage_dealt)), one(number(stats.damage_taken)), two(M.dps(stats, elapsed)),
        one(number(stats.blocked)), one(number(stats.healed)))
end

function M.journal(stats, elapsed)
    local result = { summary = M.summary(stats, elapsed), dps = M.dps(stats, elapsed), sources = {}, history = {} }
    local sorted = {}
    for id, raw in pairs(dictionary(stats.sources)) do
        sorted[#sorted + 1] = { id = id, raw = raw }
    end
    table.sort(sorted, function(a, b)
        local first, second = number(a.raw.damage), number(b.raw.damage)
        if first == second then
            return tostring(a.id) < tostring(b.id)
        end
        return first > second
    end)
    for index = 1, min(8, #sorted) do
        local source = sorted[index].raw
        result.sources[index] = {
            title = label(source.name), kind = category(source.kind),
            detail = format("Всего %.1f HP · событий урона %d (включая тики)",
                one(number(source.damage)), floor(number(source.hits))),
            damage = number(source.damage), hits = floor(number(source.hits)),
        }
    end

    local history = dictionary(stats.history)
    for index = #history, max(1, #history - 9), -1 do
        local entry = history[index]
        local time, kind = floor(number(entry.time)), category(entry.kind)
        result.history[#result.history + 1] = {
            title = format("%02d:%02d · %s", floor(time / 60), time % 60, kind_names[kind] or kind),
            detail = format("%s · −%.1f HP", label(entry.name), one(number(entry.amount))),
            kind = kind, source_id = entry.source_id, pos = entry.pos, amount = number(entry.amount),
        }
    end
    return result
end

return M
