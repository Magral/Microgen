local SizeRules = require("main.run.size_rules")

local M = {}

function M.crown_eligible(radius, enemy, pull_rank)
    local hp = enemy.hp or 0
    if hp <= 0 or enemy.captured or enemy.kind == "boss" then
        return false
    end
    local health = hp / math.max(1, enemy.max_hp)
    if enemy.kind == "miniboss" and health > 0.15 then
        return false
    end
    local ratio = enemy.r / math.max(1, radius)
    return (ratio < 0.95 or health <= 0.12) and
        SizeRules.profile(radius, enemy.r, health, pull_rank, 0, false).pull > 0
end

function M.crown_reach(radius, rank)
    return (165 + rank * 12) * radius / 34
end

function M.crown_tip(offset, radius, side, phase)
    local x, y = offset.x, offset.y
    local length = math.sqrt(x * x + y * y)
    if length == 0 then
        return { x = x, y = y }
    end
    local displacement = side * radius * (0.65 + 0.12 * math.sin(phase)) / length
    return { x = x + y * displacement, y = y - x * displacement }
end

return M
