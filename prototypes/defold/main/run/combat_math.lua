local M = {}
M.tau = math.pi * 2

function M.point(x, y)
    return { x = x or 0, y = y or 0 }
end

function M.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = M.copy(item) end
    return result
end

function M.contains(items, value)
    for _, item in ipairs(items) do if item == value then return true end end
    return false
end

function M.distance_squared(a, b)
    return (a.x - b.x)^2 + (a.y - b.y)^2
end

function M.normal(x, y)
    local length = math.sqrt(x * x + y * y)
    if length == 0 then return 0, 0, length end
    return x / length, y / length, length
end

function M.angle(x, y)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

function M.offset(p, angle, length)
    return M.point(p.x + math.cos(angle) * length, p.y + math.sin(angle) * length)
end

function M.segment_distance_squared(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local size = dx * dx + dy * dy
    local t = size > 0 and math.min(1, math.max(0, ((px - ax) * dx + (py - ay) * dy) / size)) or 0
    return (px - ax - dx * t)^2 + (py - ay - dy * t)^2
end

function M.pigment(color, mass)
    local density = {}
    for i = 1, 3 do
        local n = tonumber(color:sub(i * 2 - 1, i * 2), 16) / 255
        local linear = n <= 0.04045 and n / 12.92 or ((n + 0.055) / 1.055)^2.4
        density[i] = -math.log(math.max(0.008, linear))
    end
    return { density = density, mass = mass or 18 }
end

function M.combine(state, incoming)
    local mass, weight = math.max(0.001, state.mass), math.max(0, incoming.mass)
    for i = 1, 3 do
        state.density[i] = (state.density[i] * mass + incoming.density[i] * weight) / (mass + weight)
    end
    state.mass = mass + weight
end

function M.pigment_color(state)
    local channels = {}
    for i = 1, 3 do
        local n = math.exp(-state.density[i])
        local srgb = n <= 0.0031308 and n * 12.92 or 1.055 * n^(1 / 2.4) - 0.055
        channels[i] = math.floor(srgb * 255 + 0.5)
    end
    return string.format("%02x%02x%02x", channels[1], channels[2], channels[3])
end

return M
