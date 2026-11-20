local MapView = {}

local MAP_TEXTURE = "microgen_detailed_map"
local MAP_SCALE = 8
local map_texture_created = false
local RGB = {
    [0] = {6, 19, 28}, [1] = {9, 27, 38}, [2] = {26, 117, 122},
    [3] = {23, 38, 31}, [4] = {107, 122, 61}, [5] = {18, 15, 38},
    [6] = {84, 61, 133},
}

local function cell_index(world, x, y)
    return y * world.w + x + 1
end

local function cell_tint(world, x, y, sim, reveal)
    local index = cell_index(world, x, y)
    local seen = reveal or (sim and sim.explored and sim.explored[index])
    if not seen then return 0 end
    local biome = world:biome((x + .5) * world.tile_size, (y + .5) * world.tile_size)
    local condition = world.conditions[biome]
    if condition == 1 then return world.cells[index] == 1 and 3 or 4 end
    if condition == 2 then return world.cells[index] == 1 and 5 or 6 end
    return world.cells[index] == 1 and 1 or 2
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function rgb_bytes(red, green, blue)
    return string.char(red, green, blue)
end

local function raster_map(ui, world, sim, reveal)
    local width, height = world.w * MAP_SCALE, world.h * MAP_SCALE
    local seen_count = 0
    if sim and not reveal then for _ in pairs(sim.explored or {}) do seen_count = seen_count + 1 end end
    local cache = sim and sim.map_raster_cache
    local key = tostring(world.seed_value) .. ":" .. tostring(reveal) .. ":" .. tostring(seen_count)
    if cache and cache.key == key then
        if not map_texture_created then
            gui.new_texture(MAP_TEXTURE, width, height, "rgb", cache.data, true)
            map_texture_created = true
        elseif cache.key ~= cache.uploaded then
            gui.set_texture_data(MAP_TEXTURE, width, height, "rgb", cache.data, true)
            cache.uploaded = cache.key
        end
        return
    end
    local kinds = {}
    for y = 0, world.h - 1 do
        local row = {}
        kinds[y] = row
        for x = 0, world.w - 1 do row[x] = cell_tint(world, x, y, sim, reveal) end
    end
    local function tile_kind(x, y)
        if x < 0 or y < 0 or x >= world.w or y >= world.h then return 0 end
        return kinds[y][x]
    end
    -- Rasterize each cell once, then stitch scanlines. The same detail remains,
    -- while trig and temporary pixel strings are no longer repeated per pixel.
    local tile_rows = {}
    for gy = 0, world.h - 1 do
        local row = {}
        tile_rows[gy] = row
        for gx = 0, world.w - 1 do
            local kind = tile_kind(gx, gy)
            local base = RGB[kind] or RGB[0]
            local left, right = tile_kind(gx - 1, gy), tile_kind(gx + 1, gy)
            local up, down = tile_kind(gx, gy - 1), tile_kind(gx, gy + 1)
            local warp_x = .125 + .125 * (.5 + .5 * math.sin(gy * 2.17 + gx * .61))
            local warp_y = .125 + .125 * (.5 + .5 * math.sin(gx * 2.03 - gy * .73))
            local seed = (gx * 37 + gy * 71) % 19
            local rows = {}
            for py = 0, MAP_SCALE - 1 do
                local fy = py / MAP_SCALE
                local scanline = {}
                for px = 0, MAP_SCALE - 1 do
                    local fx = px / MAP_SCALE
                    local edge = (left ~= kind and fx < warp_x and fx >= warp_x - .25)
                        or (right ~= kind and fx > 1 - warp_x and fx <= 1 - warp_x + .25)
                        or (up ~= kind and fy < warp_y and fy >= warp_y - .25)
                        or (down ~= kind and fy > 1 - warp_y and fy <= 1 - warp_y + .25)
                    local glint = math.abs(fx - .5) <= .126 and math.abs(fy - .5) <= .126 and seed < 3
                    local r, g, b = base[1], base[2], base[3]
                    if edge then
                        r, g, b = math.min(255, r * 1.45 + 15), math.min(255, g * 1.38 + 20), math.min(255, b * 1.35 + 20)
                    elseif glint then
                        r, g, b = math.min(255, r * 1.55), math.min(255, g * 1.55), math.min(255, b * 1.55)
                    end
                    scanline[#scanline + 1] = rgb_bytes(math.floor(r), math.floor(g), math.floor(b))
                end
                rows[py] = table.concat(scanline)
            end
            row[gx] = rows
        end
    end
    local data_rows = {}
    for gy = 0, world.h - 1 do
        for py = 0, MAP_SCALE - 1 do
            local scanline = {}
            for gx = 0, world.w - 1 do scanline[gx + 1] = tile_rows[gy][gx][py] end
            data_rows[#data_rows + 1] = table.concat(scanline)
        end
    end
    local data = table.concat(data_rows)
    if not map_texture_created then
        gui.new_texture(MAP_TEXTURE, width, height, "rgb", data, true)
        map_texture_created = true
    else
        gui.set_texture_data(MAP_TEXTURE, width, height, "rgb", data, true)
    end
    if sim then
        sim.map_raster_cache={key=key,data=data,uploaded=key}
    end
end

local function discovered(sim, world, point)
    if not sim or not sim.explored or not point then return false end
    local x = math.floor(point.x / world.tile_size)
    local y = math.floor(point.y / world.tile_size)
    return sim.explored[cell_index(world, x, y)] == true
end

local function map_point(world, p, left, top, tile)
    return left + p.x / world.tile_size * tile,
        top - p.y / world.tile_size * tile
end

local function frame_marker(ui, x, y, shade, radius)
    local halo = ui:box(x, y, radius * 2, radius * 2, vmath.vector4(shade.x, shade.y, shade.z, .20))
    gui.set_blend_mode(halo, gui.BLEND_ADD)
    ui:box(x, y, radius, radius, shade)
end

local function draw_route(ui, world, from, target, left, top, tile, reveal, sim)
    if not from or not target then return end
    local x1, y1 = map_point(world, from, left, top, tile)
    local x2, y2 = map_point(world, target, left, top, tile)
    local dx, dy = x2 - x1, y2 - y1
    local distance = math.sqrt(dx * dx + dy * dy)
    local steps = math.max(1, math.floor(distance / 14))
    for i = 1, steps do
        local t = i / steps
        local wx = from.x + (target.x - from.x) * t
        local wy = from.y + (target.y - from.y) * t
        local gx = math.floor(wx / world.tile_size)
        local gy = math.floor(wy / world.tile_size)
        local known = sim and sim.explored and sim.explored[cell_index(world, gx, gy)]
        if not reveal and known and world.cells[cell_index(world, gx, gy)] == 0 then
            local x, y = x1 + dx * t, y1 + dy * t
            local dot = ui:box(x, y, 5, 5, vmath.vector4(.63, .95, .88, .76))
            gui.set_blend_mode(dot, gui.BLEND_ADD)
        elseif reveal then
            local x, y = x1 + dx * t, y1 + dy * t
            ui:box(x, y, 5, 5, vmath.vector4(.63, .95, .88, .76))
        end
    end
end

function MapView.grid(ui, world, sim, left, bottom, tile, reveal, labels)
    local width, height = world.w * tile, world.h * tile
    local top = bottom + height
    ui:surface(left + width / 2, bottom + height / 2, width + 26, height + 26, "panel")
    ui:box(left + width / 2, bottom + height / 2, width + 10, height + 10,
        vmath.vector4(.012, .055, .075, .96))

    raster_map(ui, world, sim, reveal)
    local map = ui:box(left + width / 2, bottom + height / 2, width, height, vmath.vector4(1,1,1,1))
    gui.set_texture(map, MAP_TEXTURE)

    -- A few deterministic nutrient glints give rare resource points a clear
    -- visual language without creating one node for every pickup.
    local nutrient_count = 0
    for i, nutrient in ipairs(world.nutrients or {}) do
        if nutrient.rich and (reveal or (sim and sim.explored and sim.explored[cell_index(world,
            math.floor(nutrient.pos.x / world.tile_size), math.floor(nutrient.pos.y / world.tile_size))])) then
            local x, y = map_point(world, nutrient.pos, left, top, tile)
            local color = i % 2 == 0 and vmath.vector4(.82, .62, 1, .95) or vmath.vector4(.55, 1, .83, .95)
            frame_marker(ui, x, y, color, tile * .25)
            nutrient_count = nutrient_count + 1
            if nutrient_count >= 24 then break end
        end
    end

    if sim and sim.player then
        local target
        local best = math.huge
        local function consider(point)
            local dx, dy = point.x - sim.player.x, point.y - sim.player.y
            local visible = discovered(sim, world, point)
            local distance = dx * dx + dy * dy
            if visible and distance < best then target, best = point, distance end
        end
        for _, nest in ipairs(world.nests or {}) do
            if not nest.used then consider(nest.pos) end
        end
        for _, cyst in ipairs(sim.cysts or {}) do
            if not cyst.consumed then consider(cyst.pos) end
        end
        target = target or (sim.boss_spawned and (sim.boss_marker or world.boss_pos) or nil)
        draw_route(ui, world, sim.player, target, left, top, tile, reveal, sim)
    elseif labels and world.start and world.boss_pos then
        draw_route(ui, world, world.start, world.boss_pos, left, top, tile, true, nil)
    end

    local function mark(point, color, radius, atlas, frame)
        local x, y = map_point(world, point, left, top, tile)
        frame_marker(ui, x, y, color, radius)
        if atlas and frame then ui:image(atlas, frame, x, y, radius * 1.45, radius * 1.45) end
    end
    for _, colony in ipairs(world.colonies or {}) do
        if colony.visited or reveal or discovered(sim, world, colony.pos) then
            mark(colony.pos, vmath.vector4(.35, 1, .76, 1), tile * .46, "collectibles", "bio")
        end
    end
    for _, nest in ipairs(world.nests or {}) do
        if reveal or (sim and sim.explored and sim.explored[cell_index(world,
            math.floor(nest.pos.x / world.tile_size), math.floor(nest.pos.y / world.tile_size))]) then
            mark(nest.pos, vmath.vector4(.98, .72, .33, 1), tile * .49, "cells", "field")
        end
    end
    if sim then
        for _, cyst in ipairs(sim.cysts or {}) do
            local gx = math.floor(cyst.pos.x / world.tile_size)
            local gy = math.floor(cyst.pos.y / world.tile_size)
            if not cyst.consumed and (reveal or (sim.explored and sim.explored[cell_index(world, gx, gy)])) then
                mark(cyst.pos, vmath.vector4(.82, .56, 1, 1), tile * .43,
                    "collectibles", "cyst_" .. tostring(cyst.tier or 1))
            end
        end
    end
    local boss = (sim and sim.boss_marker) or world.boss_pos
    if boss and (reveal or (sim and sim.boss_spawned) or discovered(sim, world, boss)) then
        mark(boss, vmath.vector4(1, .43, .49, 1), tile * .55, "collectibles", "core")
    end
    if sim and sim.player then
        mark(sim.player, vmath.vector4(.88, 1, .96, 1), tile * .58, "cells", "player")
    elseif world.start then
        mark(world.start, vmath.vector4(.88, 1, .96, 1), tile * .58, "cells", "player")
    end

    if labels then
        local first_condition=world:condition_name(1)
        local second_condition=world:condition_name(2)
        local regions = {
            {x = left + width * .25, text = "СРЕДА I · " .. first_condition, color = vmath.vector4(.43, .91, .89, .95)},
            {x = left + width * .75, text = "СРЕДА II · " .. second_condition, color = vmath.vector4(.80, .78, 1, .95)},
        }
        for _, region in ipairs(regions) do
            ui:text(region.x, bottom + height * .82, region.text, .58, region.color, nil, true)
        end
    end
    return {left = left, bottom = bottom, top = top, width = width, height = height}
end

function MapView.screen(ui, sim, leave, zoom, set_zoom, locate)
    local world = sim.world
    ui:panel("Карта микромира", sim:stage_name(), leave, 2340)
    zoom = clamp(zoom or 1, .82, 1.02)
    local tile = 20.4 * zoom
    local center_x = 946 + world.w * 20.4 * .5
    local center_y = 52 + world.h * 20.4 * .5
    MapView.grid(ui, world, sim, center_x - world.w * tile * .5,
        center_y - world.h * tile * .5, tile, false, true)

    ui:surface(440, 517, 650, 836, "card")
    ui:box(440, 895, 582, 4, vmath.vector4(.34, .94, .78, 1))
    ui:text(170, 875, "СТУПЕНЬ " .. tostring(sim.stage_index), .84, vmath.vector4(.53, .96, .83, 1))
    ui:fit_text(170, 815, sim:stage_name(), 1.02, vmath.vector4(.88, .96, .91, 1), 520, 72)
    ui:text(170, 733, "ЦЕЛЬ ЗАБЕГА", .77, vmath.vector4(.68, .85, .82, 1))
    local nest_count = 0
    for _, nest in ipairs(world.nests or {}) do if nest.used then nest_count = nest_count + 1 end end
    ui:fit_text(170, 683, string.format("Гнёзда %d/%d · мини-боссы %d/%d",
        nest_count, math.min(4, sim:stage_miniboss_target() * 2),
        sim.minibosses_defeated or 0, sim:stage_miniboss_target()), .82,
        vmath.vector4(.92, .83, .61, 1), 520, 62)
    ui:fit_text(170, 600, "Главная угроза · " .. (sim:boss_title() or "не обнаружена"),
        .88, vmath.vector4(1, .57, .63, 1), 520, 60)
    ui:box(440, 546, 582, 2, vmath.vector4(.22, .40, .43, 1))
    ui:text(170, 491, "ОБОЗНАЧЕНИЯ", .76, vmath.vector4(.68, .85, .82, 1))

    local legend = {
        {"cells", "player", "Твой организм", vmath.vector4(.88, 1, .96, 1)},
        {"collectibles", "bio", "Колония", vmath.vector4(.35, 1, .76, 1)},
        {"cells", "field", "Гнездо", vmath.vector4(.98, .72, .33, 1)},
        {"collectibles", "cyst_2", "Циста с наградой", vmath.vector4(.82, .56, 1, 1)},
        {"collectibles", "core", "Главная угроза", vmath.vector4(1, .43, .49, 1)},
        {nil, nil, "Ценная питательная точка", vmath.vector4(.84, .68, 1, 1)},
    }
    for i, item in ipairs(legend) do
        local y = 424 - (i - 1) * 47
        if item[1] then ui:image(item[1], item[2], 196, y, 32, 32)
        else frame_marker(ui, 196, y, item[4], 9) end
        ui:text(232, y, item[3], .78, vmath.vector4(.78, .9, .87, 1))
    end
    ui:button(440, 135, 540, 60, "Вернуться к организму", leave, false, .86)
    ui:button(2290, 520, 84, 84, "+", set_zoom and function() set_zoom(clamp(zoom + .08, .82, 1.02)) end,
        false, 1.35)
    ui:button(2290, 420, 84, 84, "−", set_zoom and function() set_zoom(clamp(zoom - .08, .82, 1.02)) end,
        false, 1.35)
    ui:button(2155, 300, 354, 68, "Общий вид", locate, true, .85)
end

return MapView
