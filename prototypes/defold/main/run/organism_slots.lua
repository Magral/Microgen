local util = require "main.run.meta_util"
local M = {MAX_EXACT_INTEGER = util.MAX_INTEGER, _count = util.count}

function M.used_cells(state)
    local used = 0
    for _, part in ipairs(state.equipped or {}) do
        local cells = part.cells or 0
        if cells > util.MAX_INTEGER - used then return util.MAX_INTEGER + 1 end
        used = used + cells
    end
    return used
end

function M.validate(state)
    if type(state) ~= "table" or not util.count(state.body_capacity, 1) or not util.count(state.stock_capacity) then
        return "Некорректная вместимость"
    end
    if not util.array(state.equipped) or not util.array(state.stock) then return "Некорректный список органов" end
    local ids = {}
    for _, group in ipairs({state.equipped, state.stock}) do
        for _, part in ipairs(group) do
            if type(part) ~= "table" then return "Некорректный орган" end
            local id = part.id
            if type(id) ~= "string" or id == "" or ids[id] then return "Повторяющийся или отсутствующий орган" end
            if not util.count(part.cells, 1) then return "Некорректный размер органа" end
            ids[id] = true
        end
    end
    if M.used_cells(state) > state.body_capacity then return "Не хватает ячеек тела" end
    if #state.stock > state.stock_capacity then return "Запас заполнен" end
    return ""
end

local function result(state, error)
    return {ok = error == nil, error = error or "", state = util.copy(state)}
end

function M.move(state, id, destination, replacements)
    local error = M.validate(state)
    if error ~= "" then return result(state, error) end
    if destination ~= "body" and destination ~= "stock" then return result(state, "Неизвестное место установки") end
    local source = destination == "body" and "stock" or "equipped"
    local _, index = util.find(state[source], id)
    if not index then return result(state, "Орган не найден в исходном месте") end
    replacements = replacements or {}
    if not util.array(replacements) then return result(state, "Некорректная замена органов") end
    if destination == "stock" and #replacements > 0 then return result(state, "Замена применима только к телу") end
    local seen = {}
    for _, replacement in ipairs(replacements) do
        if type(replacement) ~= "string" or seen[replacement] or not util.find(state.equipped, replacement) then
            return result(state, "Некорректная замена органов")
        end
        seen[replacement] = true
    end
    local next_state = util.copy(state)
    local incoming = table.remove(next_state[source], index)
    if destination == "body" then
        for _, replacement in ipairs(replacements) do
            local _, replacement_index = util.find(next_state.equipped, replacement)
            next_state.stock[#next_state.stock + 1] = table.remove(next_state.equipped, replacement_index)
        end
        next_state.equipped[#next_state.equipped + 1] = incoming
    else
        next_state.stock[#next_state.stock + 1] = incoming
    end
    error = M.validate(next_state)
    if error ~= "" then return result(state, error) end
    return result(next_state)
end

function M.expand(state, target)
    local error = M.validate(state)
    if error ~= "" then return result(state, error) end
    if target ~= "body" and target ~= "stock" then return result(state, "Неизвестный тип расширения") end
    local key = target .. "_capacity"
    if state[key] >= util.MAX_INTEGER then return result(state, "Недопустимая вместимость") end
    local next_state = util.copy(state)
    next_state[key] = next_state[key] + 1
    return result(next_state)
end

return M
