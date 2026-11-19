local Catalog = require("main.run.catalog")

local M = {
    QUALITY_NAMES = { "обычная", "редкая", "эпическая", "легендарная" },
    QUALITY_COLORS = { "cbd8d2", "72bfff", "c297f2", "f5ca72" },
}

function M.quality_weights(tier)
    local t = math.max(0, math.min(10, tier or 0))
    return { math.max(30, 70 - t * 4), 23 + t * 1.5, 6 + t * 1.8, 1 + t * 0.7 }
end

function M.roll_quality(rng, tier)
    local weights = M.quality_weights(tier)
    local total = 0
    for _, weight in ipairs(weights) do
        total = total + weight
    end
    local roll = rng:randf() * total
    for index, weight in ipairs(weights) do
        roll = roll - weight
        if roll < 0 then
            return index - 1
        end
    end
    return 3
end

function M.quality_name(grade)
    return M.QUALITY_NAMES[math.max(0, math.min(3, grade)) + 1]
end

function M.quality_color(grade)
    return M.QUALITY_COLORS[math.max(0, math.min(3, grade)) + 1]
end

M.quality_multiplier = Catalog.quality_multiplier
M.multiplier = Catalog.quality_multiplier

return M
