local M = {}

M.MAX_INTEGER = 9007199254740991

function M.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = M.copy(item) end
    return result
end

function M.table(value)
    return type(value) == "table" and value or {}
end

function M.finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function M.integer(value, fallback)
    if not M.finite(value) then return fallback or 0 end
    return value >= 0 and math.floor(value) or math.ceil(value)
end

function M.clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

function M.count(value, minimum)
    return M.finite(value) and value == math.floor(value) and value >= (minimum or 0) and value <= M.MAX_INTEGER
end

function M.string(value, fallback)
    return type(value) == "string" and value or (fallback or "")
end

function M.array(value)
    if type(value) ~= "table" then return false end
    local size = #value
    for key in pairs(value) do
        if not M.count(key, 1) or key > size then return false end
    end
    for index = 1, size do
        if value[index] == nil then return false end
    end
    return true
end

function M.array_or_empty(value)
    return M.array(value) and value or {}
end

function M.index(values, value)
    for index, item in ipairs(values) do
        if item == value then return index end
    end
end

function M.find(parts, id)
    for index, part in ipairs(parts) do
        if part.id == id then return part, index end
    end
end

function M.sorted_keys(values)
    local keys = {}
    for key in pairs(values) do
        if type(key) == "string" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

function M.limit_text(value, count)
    local remaining = count
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 128 or byte >= 192 then
            if remaining == 0 then return value:sub(1, index - 1) end
            remaining = remaining - 1
        end
    end
    return value
end

return M
