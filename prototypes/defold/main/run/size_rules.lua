local M = {}

function M.clamp(value, low, high)
    return math.min(high, math.max(low, value))
end

function M.smoothstep(low, high, value)
    local t = M.clamp((value - low) / (high - low), 0, 1)
    return t * t * (3 - 2 * t)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

function M.profile(player_radius, enemy_radius, hp_fraction, pull_rank, mouth_rank, frontal)
    local ratio = enemy_radius / math.max(1, player_radius)
    local health = M.clamp(hp_fraction, 0, 1)
    local threshold = 0
    if ratio <= 0.72 then threshold = 1
    elseif ratio < 0.95 then threshold = lerp(1, 0.43, M.smoothstep(0.72, 0.95, ratio))
    elseif ratio <= 1.25 then threshold = lerp(0.43, 0.14, M.smoothstep(0.95, 1.25, ratio))
    elseif ratio <= 1.6 and mouth_rank > 0 then threshold = 0.08 + mouth_rank * 0.008 end
    if ratio <= 1.25 then threshold = threshold + mouth_rank * 0.025 end
    if frontal and mouth_rank > 0 and ratio <= 1.6 then threshold = threshold + 0.15 + mouth_rank * 0.035 end
    if ratio >= 0.9 then threshold = math.min(threshold, frontal and mouth_rank > 0 and 0.58 or 0.43) end
    if ratio > 1.25 then threshold = math.min(threshold, 0.32) end
    threshold = M.clamp(threshold, 0, 1)
    local pull = 0
    if pull_rank > 0 then
        if ratio < 0.95 then
            pull = (24 + 20 * pull_rank) * (1.6 - ratio) * (1 - M.smoothstep(0.75, 0.95, ratio) * 0.85)
        elseif ratio <= 1.25 and pull_rank >= 2 then
            pull = 3.5 * (pull_rank - 1) * M.clamp((1.25 - ratio) / 0.25, 0, 1)
        end
        if ratio <= 1.6 and health <= 0.12 then
            pull = math.max(pull, (12 + pull_rank * 5) * M.clamp((1.6 - ratio) / 0.6, 0, 1))
        end
    end
    local duration = lerp(0.45, 1.05, M.smoothstep(0.55, 1.4, ratio))
    if frontal and mouth_rank > 0 then duration = duration * 0.65 end
    return {
        ratio = ratio, threshold = threshold, eligible = health <= threshold and threshold > 0,
        pull = pull, impact = ratio <= 1.03 and 0 or lerp(1.5, 20, M.smoothstep(1.03, 2.4, ratio)),
        speed = M.clamp(1 / math.sqrt(math.max(1, ratio)), 0.35, 1), duration = duration,
    }
end

function M.damage_rate(ratio, elite)
    if elite then return 0.035 end
    if ratio < 0.9 then return lerp(0.36, 0.12, M.smoothstep(0.6, 0.9, ratio)) end
    return lerp(0.075, 0.045, M.smoothstep(1.15, 1.8, ratio))
end

function M.slide_contact(origin, dx, dy, center, radius, slide)
    local x, y = origin.x - center.x, origin.y - center.y
    local approach = x * dx + y * dy
    if approach >= 0 then return dx, dy end
    local clearance = x * x + y * y - radius * radius
    if clearance <= 0 then
        if slide == false then return 0, 0 end
        local distance_squared = x * x + y * y
        return dx - x * approach / distance_squared, dy - y * approach / distance_squared
    end
    local travel_squared = dx * dx + dy * dy
    local discriminant = approach * approach - clearance * travel_squared
    if discriminant <= 0 then return dx, dy end
    local entry = (-approach - math.sqrt(discriminant)) / travel_squared
    if entry >= 1 then return dx, dy end
    entry = math.max(0, entry)
    if slide == false then return dx * entry, dy * entry end
    x, y = x + dx * entry, y + dy * entry
    approach = math.min(0, (x * dx + y * dy) * (1 - entry)) / (x * x + y * y)
    return dx - x * approach, dy - y * approach
end

return M
