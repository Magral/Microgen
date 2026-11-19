local util = require "main.run.meta_util"
local catalog = require "main.run.catalog"
local slots = require "main.run.organism_slots"
local legacy = require "main.run.genome_legacy"
local M = {}
local GROUPS = {"equipped", "stock", "reserve"}

function M.base_capacity(form)
    return ({predator = 6, toxic = 7, colony = 8})[form] or 6
end

function M.cell_cost(kind)
    return catalog.cell_cost(kind)
end

function M.validate(state)
    local error = slots.validate(state)
    if error ~= "" then return error end
    if state.version ~= 1 then return "Неизвестная версия органов" end
    if type(state.form) ~= "string" or not legacy.FORMS[state.form] then return "Неизвестная форма" end
    if not util.array(state.reserve) then return "Некорректный архив органов" end
    if not util.count(state.next_id, 1) then return "Некорректный счётчик органов" end
    local ids = {}
    for _, group in ipairs(GROUPS) do
        for _, part in ipairs(state[group]) do
            if type(part) ~= "table" then return "Некорректный орган" end
            local id = part.id
            if type(id) ~= "string" or id == "" or ids[id] then return "Повторяющийся или отсутствующий орган" end
            ids[id] = true
            local kind = part.kind
            if type(kind) ~= "string" or not catalog.ORGANS[kind] then return "Неизвестный орган" end
            if not util.count(part.cells, 1) or part.cells ~= M.cell_cost(kind) then return "Некорректный размер органа" end
            if not util.count(part.rank, 1) or part.rank > catalog.max_rank(kind) then return "Некорректный ранг органа" end
            local specialization = part.specialization
            if specialization ~= nil and (type(specialization) ~= "string" or (
                specialization ~= "feral" and specialization ~= "resonant" and not catalog.has_specialization(kind, specialization))) then
                return "Некорректная специализация органа"
            end
            if not util.count(part.quality) or part.quality > 3 then return "Некорректное качество органа" end
            if part.evolved ~= nil and type(part.evolved) ~= "boolean" then return "Некорректная эволюция органа" end
            local number = tonumber(id:match("^organ%-([+-]?%d+)$"))
            if number and number >= state.next_id then return "Счётчик органов повторяет идентификатор" end
        end
    end
    return ""
end

local function result(state, error, location, id)
    return {ok = error == nil, error = error or "", state = util.copy(state), location = location or "", id = id or ""}
end

local function new_part(state, kind, rank, quality)
    local part = {
        id = string.format("organ-%.0f", state.next_id), kind = kind,
        cells = M.cell_cost(kind), rank = rank or 1, quality = quality or 0,
    }
    state.next_id = state.next_id + 1
    return part
end

function M.from_profile(profile)
    if profile.organism ~= nil then
        if M.validate(profile.organism) ~= "" then return {} end
        local migrated = util.copy(profile.organism)
        for _, group in ipairs(GROUPS) do
            for _, part in ipairs(migrated[group]) do
                if part.specialization then part.specialization = catalog.legacy_specialization(part.kind, part.specialization) end
            end
        end
        return migrated
    end
    local inheritance = util.table(profile.legacy)
    local form = inheritance.selected_form
    if form == "division" then form = "colony" end
    if not legacy.FORMS[form] then form = "predator" end
    local state = {
        version = 1, next_id = 1, form = form, body_capacity = M.base_capacity(form), stock_capacity = 3,
        equipped = {}, stock = {}, reserve = {},
    }
    local build = util.table(util.table(profile.checkpoint).build)
    local organs, qualities = util.table(build.organs), util.table(build.qualities)
    local specializations = util.table(build.specializations)
    local evolutions = util.table(util.table(build.stats).evolutions)
    local represented = {}
    for _, kind in ipairs(util.sorted_keys(organs)) do
        if catalog.ORGANS[kind] then
            local rank, grade = organs[kind], qualities[kind] or 0
            if not util.count(rank, 1) or rank > catalog.max_rank(kind) or not util.count(grade) or grade > 3 then return {} end
            local part = new_part(state, kind, rank, grade)
            local specialization = catalog.legacy_specialization(kind, util.string(specializations[kind]))
            if specialization ~= "" then part.specialization = specialization end
            if evolutions[kind] then part.evolved = true end
            state.equipped[#state.equipped + 1] = part
            represented[kind] = true
        end
    end
    if #state.equipped == 0 then
        local kind = legacy.FORMS[form].organ
        state.equipped[1], represented[kind] = new_part(state, kind), true
    end
    state.body_capacity = math.max(state.body_capacity, slots.used_cells(state))
    for _, imprint in ipairs(util.array_or_empty(inheritance.imprints)) do
        local record = util.table(imprint)
        local kind = record.id
        if catalog.ORGANS[kind] and not represented[kind] then
            local rank, grade = record.rank or 1, record.quality or 0
            if not util.count(rank, 1) or rank > catalog.max_rank(kind) or not util.count(grade) or grade > 3 then return {} end
            state.reserve[#state.reserve + 1] = new_part(state, kind, rank, grade)
            represented[kind] = true
        end
    end
    return state
end

function M.aggregate(state)
    local build = {organs = {}, qualities = {}, specializations = {}}
    if M.validate(state) ~= "" then return build end
    for _, part in ipairs(state.equipped) do
        local kind = part.kind
        local current = build.organs[kind] or 0
        build.organs[kind] = current + math.min(part.rank, catalog.max_rank(kind) - current)
        build.qualities[kind] = math.max(build.qualities[kind] or 0, part.quality)
        if part.specialization and part.rank >= current then build.specializations[kind] = part.specialization end
    end
    return build
end

function M.upgrade_cost(part)
    local rank = part.rank or 1
    return math.min(util.MAX_INTEGER, 6 + math.floor(4 * rank^0.72))
end

function M.upgrade_ingredient(part)
    return math.min(128, 1 + math.floor((part.rank or 1) / 8))
end

local function part_location(state, id)
    for _, group in ipairs(GROUPS) do
        local part, index = util.find(state[group], id)
        if part then return part, group, index end
    end
end

local function failed_payment(state, organium, materials, error)
    return {
        ok = false, error = error, state = util.copy(state),
        organium = organium, materials = util.copy(materials), spent = 0,
    }
end

function M.upgrade(state, id, organium, materials)
    materials = materials or {}
    local error = M.validate(state)
    if error ~= "" then return failed_payment(state, organium, materials, error) end
    local part, group, index = part_location(state, id)
    if not part then return failed_payment(state, organium, materials, "Орган не найден") end
    local price = M.upgrade_cost(part)
    local ingredient = M.upgrade_ingredient(part)
    if organium < price then return failed_payment(state, organium, materials, ("Нужно органиума: %.0f"):format(price)) end
    if (materials.organelle or 0) < ingredient then
        return failed_payment(state, organium, materials, ("Нужно органелл: %d"):format(ingredient))
    end
    if part.rank >= catalog.max_rank(part.kind) then
        return failed_payment(state, organium, materials, "Достигнут предел точности сохранения")
    end
    local next_state, remaining = util.copy(state), util.copy(materials)
    next_state[group][index].rank = part.rank + 1
    remaining.organelle = remaining.organelle - ingredient
    return {ok = true, error = "", state = next_state, organium = organium - price, materials = remaining, spent = price, ingredient = ingredient}
end

function M.specialize(state, id, specialization, organium, materials)
    materials = materials or {}
    local error = M.validate(state)
    if error ~= "" then return failed_payment(state, organium, materials, error) end
    local part, group, index = part_location(state, id)
    if not part then return failed_payment(state, organium, materials, "Орган не найден") end
    if not catalog.has_specialization(part.kind, specialization) then
        return failed_payment(state, organium, materials, "Неизвестная специализация этого органа")
    end
    if part.specialization == specialization then
        return failed_payment(state, organium, materials, "Эта специализация уже активна")
    end
    local respecializing = part.specialization and part.specialization ~= ""
    local price = respecializing and math.min(util.MAX_INTEGER, 18 + part.rank) or 12
    if organium < price then
        return failed_payment(state, organium, materials, ("Смена специализации стоит %.0f органиума"):format(price))
    end
    local ingredient = respecializing and 2 or 1
    local kind = (materials[part.kind] or 0) >= ingredient and part.kind or "organelle"
    if (materials[kind] or 0) < ingredient then
        return failed_payment(state, organium, materials, ("Нужно фрагментов %s: %d"):format(catalog.item(part.kind).name, ingredient))
    end
    local next_state, remaining = util.copy(state), util.copy(materials)
    next_state[group][index].specialization = specialization
    remaining[kind] = remaining[kind] - ingredient
    return {
        ok = true, error = "", state = next_state, organium = organium - price, materials = remaining,
        spent = price, ingredient = ingredient, ingredient_kind = kind,
    }
end

function M.dismantle(state, id, organium, materials)
    materials = materials or {}
    local error = M.validate(state)
    if error ~= "" then return failed_payment(state, organium, materials, error) end
    local part, group, index = part_location(state, id)
    if not part then return failed_payment(state, organium, materials, "Орган не найден") end
    local next_state, stock = util.copy(state), util.copy(materials)
    local refund = math.max(1, math.floor(0.35 * (part.rank - 1)^0.72))
    table.remove(next_state[group], index)
    stock[part.kind] = math.min(util.MAX_INTEGER, (stock[part.kind] or 0) + part.rank)
    return {
        ok = true, error = "", state = next_state, materials = stock, kind = part.kind, refund = refund,
        organium = math.min(util.MAX_INTEGER, organium + refund),
    }
end

function M.award(state, kind, grade)
    local error = M.validate(state)
    if error ~= "" then return result(state, error) end
    grade = grade or 0
    if not catalog.ORGANS[kind] or not util.count(grade) or grade > 3 then return result(state, "Некорректная награда") end
    local next_state, owns = util.copy(state), false
    for _, part in ipairs(next_state.equipped) do
        if part.kind == kind then
            owns = true
            local rank_limit = catalog.max_rank(kind)
            if part.rank < rank_limit or grade > part.quality then
                part.rank = math.min(rank_limit, part.rank + catalog.duplicate_rank_gain(grade))
                part.quality = math.max(part.quality, grade)
                return result(next_state, nil, "body", part.id)
            end
        end
    end
    if owns then return result(state, "Орган уже развит") end
    if next_state.next_id >= util.MAX_INTEGER then return result(state, "Исчерпаны идентификаторы органов") end
    local part = new_part(next_state, kind, 1, grade)
    local group, location = "reserve", "reserve"
    if part.cells <= next_state.body_capacity - slots.used_cells(next_state) then
        group, location = "equipped", "body"
    elseif #next_state.stock < next_state.stock_capacity then
        group, location = "stock", "stock"
    end
    next_state[group][#next_state[group] + 1] = part
    return result(next_state, nil, location, part.id)
end

function M.draft_exchange(state, kind, grade)
    local error = M.validate(state)
    if error ~= "" then return result(state, error) end
    if not catalog.ORGANS[kind] or state.next_id >= util.MAX_INTEGER then return result(state, "Не удалось подготовить орган") end
    local next_state = util.copy(state)
    local part = new_part(next_state, kind, 1, util.clamp(util.integer(grade), 0, 3))
    next_state.reserve[#next_state.reserve + 1] = part
    return result(next_state, nil, "reserve", part.id)
end

local function matching_equipped(state, kind)
    local matching = {}
    for _, part in ipairs(state.equipped) do
        if part.kind == kind then matching[#matching + 1] = part end
    end
    return matching
end

function M.refresh(state, build)
    local error = M.validate(state)
    if error ~= "" then return result(state, error) end
    local organs, qualities = build.organs or {}, build.qualities or {}
    if type(organs) ~= "table" or type(qualities) ~= "table" then return result(state, "Некорректная сборка") end
    local next_state = util.copy(state)
    for key in pairs(organs) do
        if type(key) ~= "string" then return result(state, "Некорректная сборка") end
    end
    for _, kind in ipairs(util.sorted_keys(organs)) do
        local rank, grade = organs[kind], qualities[kind] or 0
        local limit = catalog.max_rank(kind)
        if not catalog.ORGANS[kind] or not util.count(rank, 1) or rank > limit then return result(state, "Некорректная сборка") end
        if not util.count(grade) or grade > 3 then return result(state, "Некорректное качество") end
        local matching = matching_equipped(next_state, kind)
        if #matching == 0 then
            local addition = M.award(next_state, kind, grade)
            if not addition.ok then return result(state, addition.error) end
            next_state = addition.state
            local group = addition.location == "body" and "equipped" or addition.location
            local part = util.find(next_state[group], addition.id)
            part.rank, part.quality = rank, grade
            if group == "equipped" then matching[1] = part end
        else
            local total, best_grade = 0, 0
            for _, part in ipairs(matching) do
                total = total + math.min(part.rank, limit - total)
                best_grade = math.max(best_grade, part.quality)
            end
            local first = matching[1]
            first.rank = first.rank + math.min(math.max(0, rank - total), limit - first.rank)
            if grade > best_grade then first.quality = grade end
        end
        local specialization = catalog.legacy_specialization(kind, util.string(util.table(build.specializations)[kind]))
        if specialization ~= "" and matching[1] then matching[1].specialization = specialization end
    end
    return result(next_state)
end

function M.move(state, id, destination, replacements)
    local error = M.validate(state)
    if error ~= "" then return result(state, error) end
    replacements = replacements or {}
    if not util.array(replacements) then return result(state, "Некорректная замена органов") end
    if destination == "stock" then return slots.move(state, id, destination, replacements) end
    if destination == "body" then
        local source = util.find(state.stock, id) and "stock" or "reserve"
        local incoming, index = util.find(state[source], id)
        if not incoming then return result(state, "Орган не найден в запасе или архиве") end
        local cells, seen = slots.used_cells(state), {}
        for _, replacement in ipairs(replacements) do
            if type(replacement) ~= "string" or seen[replacement] then return result(state, "Некорректная замена органов") end
            local old = util.find(state.equipped, replacement)
            if not old then return result(state, "Орган для замены не найден в теле") end
            cells, seen[replacement] = cells - old.cells, true
        end
        if incoming.cells > state.body_capacity - cells then
            return result(state, "Не хватает ячеек тела даже после выбранной замены")
        end
        local next_state = util.copy(state)
        next_state.equipped[#next_state.equipped + 1] = table.remove(next_state[source], index)
        for _, replacement in ipairs(replacements) do
            local _, replacement_index = util.find(next_state.equipped, replacement)
            local old = table.remove(next_state.equipped, replacement_index)
            local target = #next_state.stock < next_state.stock_capacity and next_state.stock or next_state.reserve
            target[#target + 1] = old
        end
        return result(next_state)
    end
    if (destination ~= "archive" and destination ~= "stock_from_archive") or #replacements > 0 then
        return result(state, "Неизвестное место установки")
    end
    local _, source, index = part_location(state, id)
    local from_archive = destination == "stock_from_archive"
    if not source or (source == "reserve") ~= from_archive then return result(state, "Орган не найден в исходном месте") end
    if from_archive and #state.stock >= state.stock_capacity then return result(state, "Запас заполнен") end
    local next_state = util.copy(state)
    local target = from_archive and next_state.stock or next_state.reserve
    target[#target + 1] = table.remove(next_state[source], index)
    return result(next_state)
end

function M.expand(state, target)
    local error = M.validate(state)
    if error ~= "" then return result(state, error) end
    return slots.expand(state, target)
end

return M
