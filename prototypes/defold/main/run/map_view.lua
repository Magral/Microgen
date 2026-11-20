local MapView = {}

local MAP_TEXTURE = "microgen_detailed_map"
local MAP_SCALE = 8
local uploaded_map
local RGB = {
    [0] = {5, 20, 29}, [1] = {11, 35, 44}, [2] = {10, 77, 90},
    [3] = {28, 38, 23}, [4] = {67, 89, 23}, [5] = {30, 21, 50},
    [6] = {63, 35, 111},
}
local MEMBRANE = {[2]={44,223,241}, [4]={185,228,76}, [6]={180,111,255}}

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

local function upload(cache)
    if uploaded_map == cache then return end
    local method = uploaded_map and gui.set_texture_data or gui.new_texture
    method(MAP_TEXTURE, cache.width, cache.height, "rgba", cache.data, true)
    uploaded_map = cache
end

local function raster_map(world, sim, reveal)
    local width, height = world.w * MAP_SCALE, world.h * MAP_SCALE
    local seen_count = 0
    if sim and not reveal then for _ in pairs(sim.explored or {}) do seen_count = seen_count + 1 end end
    local cache = sim and sim.map_raster_cache
    local key = tostring(world.seed_value) .. ":" .. tostring(reveal) .. ":" .. tostring(seen_count)
    if cache and cache.world == world and cache.key == key then return upload(cache) end
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
    -- Texture detail is baked when exploration changes. Zooming reuses the raster.
    local tile_rows = {}
    for gy = 0, world.h - 1 do
        local row = {}
        tile_rows[gy] = row
        for gx = 0, world.w - 1 do
            local kind = tile_kind(gx, gy)
            local base = RGB[kind]
            local membrane = MEMBRANE[kind]
            local left, right = tile_kind(gx - 1, gy), tile_kind(gx + 1, gy)
            local up, down = tile_kind(gx, gy - 1), tile_kind(gx, gy + 1)
            local phase = gy * 2.17 + gx * .61
            local swell = .87 + .13 * math.sin(gx * .64 + gy * .31)
            local seed = (gx * 37 + gy * 71) % 19
            local rows = {}
            for py = 0, MAP_SCALE - 1 do
                local fy = (py + .5) / MAP_SCALE
                local warp_x = .16 + .10 * math.sin(fy * math.pi + phase)
                local scanline = {}
                for px = 0, MAP_SCALE - 1 do
                    local fx = (px + .5) / MAP_SCALE
                    local r, g, b = base[1], base[2], base[3]
                    if membrane then
                        local distance = math.min(left ~= kind and fx or 1, right ~= kind and 1-fx or 1,
                            up ~= kind and fy or 1, down ~= kind and 1-fy or 1)
                        local rim = math.max(0, 1 - math.abs(distance - warp_x) * 4)
                        local glint = seed < 4 and math.max(0, .18 - math.abs(fx-.48) - math.abs(fy-.46)) or 0
                        local light = rim * .69 + glint
                        r = r*swell + (membrane[1]-r)*light
                        g = g*swell + (membrane[2]-g)*light
                        b = b*swell + (membrane[3]-b)*light
                    end
                    scanline[#scanline + 1] = string.char(math.floor(r),math.floor(g),math.floor(b),kind==0 and 64 or 255)
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
    cache={key=key,world=world,data=table.concat(data_rows),width=width,height=height}
    if sim then sim.map_raster_cache=cache end
    upload(cache)
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

function MapView.grid(ui, world, sim, left, bottom, tile, reveal, labels, frameless)
    local width, height = world.w * tile, world.h * tile
    local top = bottom + height
    if not frameless then
        ui:surface(left + width / 2, bottom + height / 2, width + 26, height + 26, "panel")
    end

    raster_map(world, sim, reveal)
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
        local size = radius * (frameless and 3.25 or 1.65)
        local halo=ui:image("cells","surge",x,y,size*1.85,size*1.85)
        gui.set_color(halo,vmath.vector4(color.x,color.y,color.z,.64))
        ui:image(atlas, frame, x, y, size, size)
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
    local mint, pale, dim = ui.colors.mint, ui.colors.pale, ui.colors.dim
    local shield_color = vmath.vector4(.43,.86,1,1)
    ui:box(1230,540,2460,1080,vmath.vector4(.006,.035,.052,.69))
    zoom = clamp(zoom or 1, .76, 1.12)
    local tile = math.min(1540/world.w, 782/world.h) * zoom
    local center_x, center_y = 1400, 461
    MapView.grid(ui, world, sim, center_x - world.w * tile * .5,
        center_y - world.h * tile * .5, tile, false, false, true)

    ui:box(1230,1016,2460,128,vmath.vector4(.008,.043,.057,.91))
    ui:text(62,1019,"МИКРОГЕН",1.14,mint)
    ui:text(389,1034,("Здоровье  %.0f / %.0f"):format(sim.hp,sim.max_hp),.90,pale)
    local function meter(left,width,fraction,color)
        ui:box(left+width/2,991,width,9,vmath.vector4(.11,.24,.30,1))
        local fill=width*clamp(fraction,0,1)
        if fill>0 then ui:box(left+fill/2,991,fill,9,color) end
    end
    meter(389,310,sim.hp/math.max(1,sim.max_hp),mint)
    if sim.build:rank("barrier")>0 then
        local cooldown=sim.cooldowns.barrier or 0
        local shield=cooldown<=0 and ("Щит готов · до %.0f урона"):format(sim:barrier_capacity())
            or ("Щит восстанавливается · %.1f с"):format(cooldown)
        ui:fit_text(770,1034,shield,.90,shield_color,610,42)
        meter(770,480,1-cooldown/8,shield_color)
    else
        ui:text(770,1020,"Щит не установлен",.88,dim)
    end
    ui:text(1450,1020,"Биомасса  "..sim.build.biomass,1.06,mint)
    ui:button(2362,1016,90,86,"×",leave,false,1.4)
    ui:text(64,904,"Карта",1.74,pale)
    for biome=1,2 do
        local tint=MEMBRANE[2+world.conditions[biome]*2]
        local shade=vmath.vector4(tint[1]/255,tint[2]/255,tint[3]/255,1)
        local x=1060+(biome-1)*680
        ui:fit_text(x,921,world:condition_name(biome),.85,shade,600,42,true)
    end

    ui:surface(288,676,464,324,"card")
    ui:text(86,793,"Ступень " .. sim.stage_index,1.08,mint)
    ui:fit_text(86,736,sim:stage_name(),1.00,pale,404,56)
    ui:box(288,690,402,2,vmath.vector4(.27,.55,.57,.75))
    ui:text(86,652,"Цель забега",.82,mint)
    local nest_count = 0
    for _, nest in ipairs(world.nests or {}) do if nest.used then nest_count = nest_count + 1 end end
    ui:fit_text(86, 611, string.format("Гнёзда %d/%d · минибоссы %d/%d",
        nest_count, math.min(4, sim:stage_miniboss_target() * 2),
        sim.minibosses_defeated or 0, sim:stage_miniboss_target()), .82,
        vmath.vector4(.92, .83, .61, 1), 404, 52)
    ui:fit_text(86, 550, "Главная угроза · " .. (sim:boss_title() or "не обнаружена"),
        .86, vmath.vector4(1, .63, .71, 1), 404, 56)

    ui:surface(288,275,464,446,"card")
    ui:text(86,451,"Обозначения",1.02,mint)

    local legend = {
        {"cells", "player", "Твой организм", vmath.vector4(.88, 1, .96, 1)},
        {"collectibles", "bio", "Колония", vmath.vector4(.35, 1, .76, 1)},
        {"cells", "field", "Гнездо", vmath.vector4(.98, .72, .33, 1)},
        {"collectibles", "cyst_2", "Циста с наградой", vmath.vector4(.82, .56, 1, 1)},
        {"collectibles", "core", "Главная угроза", vmath.vector4(1, .43, .49, 1)},
        {nil, nil, "Ценная питательная точка", vmath.vector4(.84, .68, 1, 1)},
    }
    for i, item in ipairs(legend) do
        local y = 390 - (i - 1) * 58
        if item[1] then ui:image(item[1], item[2], 109, y, 36, 36)
        else frame_marker(ui, 109, y, item[4], 10) end
        ui:text(152, y, item[3], .83, pale)
    end
    ui:button(2332, 414, 94, 94, "+", set_zoom and zoom<1.12 and function() set_zoom(math.min(1.12,zoom+.12)) end,false,1.35)
    ui:button(2332, 300, 94, 94, "−", set_zoom and zoom>.76 and function() set_zoom(math.max(.76,zoom-.12)) end,false,1.35)
    ui:button(2228, 174, 304, 78, "Общий вид", locate, false, .98)
end

return MapView
