local M = {}

local function safe_bounds(window_width, window_height, scene_width, scene_height, area, margin_x, margin_y)
    margin_x = margin_x or 42
    margin_y = margin_y or 33
    if not area or window_width <= 0 or window_height <= 0
        or scene_width <= 0 or scene_height <= 0 then
        return margin_x, scene_width - margin_x, scene_height - margin_y, margin_y
    end

    -- Координаты GUI могут растягиваться независимо по осям. Переводим
    -- экранные отступы в координаты сцены с соответствующим масштабом оси.
    local scale_x = window_width / scene_width
    local scale_y = window_height / scene_height
    local left = margin_x + math.max(0, area.inset_left or 0) / scale_x
    local right = scene_width - margin_x - math.max(0, area.inset_right or 0) / scale_x
    local top = scene_height - margin_y - math.max(0, area.inset_top or 0) / scale_y
    local bottom = margin_y + math.max(0, area.inset_bottom or 0) / scale_y

    if right < left then left, right = scene_width / 2, scene_width / 2 end
    if top < bottom then bottom, top = scene_height / 2, scene_height / 2 end
    return left, right, top, bottom
end

M.safe_bounds = safe_bounds

function M.test()
    local function near(actual, expected)
        assert(math.abs(actual - expected) < 0.001,
            ("screen layout mismatch: %.4f ~= %.4f"):format(actual, expected))
    end

    local left, right, top, bottom = safe_bounds(1230, 540, 2460, 1080,
        {inset_left=24,inset_right=36,inset_top=20,inset_bottom=16})
    near(left, 90)
    near(right, 2346)
    near(top, 1007)
    near(bottom, 65)

    -- Wide landscape: horizontal and vertical pixel scales differ.
    left, right, top, bottom = safe_bounds(2800, 1080, 2460, 1080,
        {inset_left=40,inset_right=60,inset_top=24,inset_bottom=16})
    near(left, 42 + 40 / (2800 / 2460))
    near(right, 2418 - 60 / (2800 / 2460))
    near(top, 1029)
    near(bottom, 49)

    -- Taller landscape: vertical inset conversion must not reuse X scale.
    left, right, top, bottom = safe_bounds(2400, 1200, 2460, 1080,
        {inset_left=30,inset_right=40,inset_top=44,inset_bottom=22})
    near(left, 42 + 30 / (2400 / 2460))
    near(right, 2418 - 40 / (2400 / 2460))
    near(top, 1047 - 44 / (1200 / 1080))
    near(bottom, 33 + 22 / (1200 / 1080))

    -- Narrow landscape: horizontal inset conversion uses the narrower X scale.
    left, right, top, bottom = safe_bounds(1920, 1080, 2460, 1080,
        {inset_left=32,inset_right=48,inset_top=18,inset_bottom=12})
    near(left, 42 + 32 / (1920 / 2460))
    near(right, 2418 - 48 / (1920 / 2460))
    near(top, 1023)
    near(bottom, 45)

    -- Insets that consume the available area collapse safely to its center.
    left, right, top, bottom = safe_bounds(1230, 540, 2460, 1080,
        {inset_left=700,inset_right=700,inset_top=400,inset_bottom=400})
    near(left, 1230)
    near(right, 1230)
    near(top, 540)
    near(bottom, 540)

    -- Missing platform safe-area data keeps the ordinary scene margins.
    left, right, top, bottom = safe_bounds(1230, 540, 2460, 1080, nil)
    near(left, 42)
    near(right, 2418)
    near(top, 1047)
    near(bottom, 33)

    return true
end

return M
