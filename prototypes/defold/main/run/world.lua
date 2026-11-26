local rng = require "main.run.rng"

local M = {}
local World = {}
World.__index = World

local WIDTH = 52
local HEIGHT = 38
local TILE = 110
local NEIGHBORS = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
local CONDITION_NAMES = {"Питательная взвесь", "Вязкая среда", "Быстрый метаболизм"}
local floor = math.floor

local function index(x, y)
    return y * WIDTH + x + 1
end

local function tile(x, y)
    return floor(x / TILE), floor(y / TILE)
end

local function tile_center(x, y)
    return {x = (x + 0.5) * TILE, y = (y + 0.5) * TILE}
end

local function carve(cells, cx, cy, radius)
    local extent = (radius + 0.5) ^ 2
    for y = math.max(1, cy - radius), math.min(HEIGHT - 2, cy + radius) do
        for x = math.max(1, cx - radius), math.min(WIDTH - 2, cx + radius) do
            if (x - cx) ^ 2 + (y - cy) ^ 2 <= extent then
                cells[index(x, y)] = 0
            end
        end
    end
end

local function connect(cells, start, goal, random)
    local x, y = tile(start.x, start.y)
    local goal_x, goal_y = tile(goal.x, goal.y)
    while x ~= goal_x or y ~= goal_y do
        carve(cells, x, y, 1)
        if (random:randf() < 0.5 and x ~= goal_x) or y == goal_y then
            x = x + (goal_x > x and 1 or -1)
        else
            y = y + (goal_y > y and 1 or -1)
        end
    end
end

local function flood(cells, position)
    local x, y = tile(position.x, position.y)
    local start = index(x, y)
    local seen = {[start] = true}
    local queue = {start}
    local head = 1
    while head <= #queue do
        local cell = queue[head] - 1
        head = head + 1
        local cx, cy = cell % WIDTH, floor(cell / WIDTH)
        for _, neighbor in ipairs(NEIGHBORS) do
            local nx, ny = cx + neighbor[1], cy + neighbor[2]
            if nx >= 0 and nx < WIDTH and ny >= 0 and ny < HEIGHT then
                local next_cell = index(nx, ny)
                if cells[next_cell] == 0 and not seen[next_cell] then
                    seen[next_cell] = true
                    queue[#queue + 1] = next_cell
                end
            end
        end
    end
    return seen
end

function M.generate(seed)
    local random = rng.new(seed)
    local world = setmetatable({
        w = WIDTH,
        h = HEIGHT,
        tile_size = TILE,
        seed_value = seed,
        cells = {},
        colonies = {},
        nests = {},
        nutrients = {},
    }, World)
    world.boundary_phase = random:randf() * 2 * math.pi
    world.conditions = {random:randi_range(0, 2), random:randi_range(0, 2)}

    local cells = world.cells
    for y = 0, HEIGHT - 1 do
        for x = 0, WIDTH - 1 do
            local border = x == 0 or y == 0 or x == WIDTH - 1 or y == HEIGHT - 1
            cells[index(x, y)] = (border or random:randf() < 0.39) and 1 or 0
        end
    end
    for _ = 1, 3 do
        local next_cells = {}
        for i = 1, #cells do
            next_cells[i] = cells[i]
        end
        for y = 1, HEIGHT - 2 do
            for x = 1, WIDTH - 2 do
                local solid = 0
                for yy = y - 1, y + 1 do
                    for xx = x - 1, x + 1 do
                        solid = solid + cells[index(xx, yy)]
                    end
                end
                next_cells[index(x, y)] = solid >= 5 and 1 or 0
            end
        end
        cells = next_cells
    end
    world.cells = cells
    world.start = tile_center(10, 19)
    local boss_x, boss_y = random:randi_range(39, 45), random:randi_range(12, 26)
    world.boss_pos = tile_center(boss_x, boss_y)

    for id = 0, 3 do
        local side = floor(id / 2)
        local x = random:randi_range(6 + side * 25, 22 + side * 24)
        local y = random:randi_range(6, 31)
        world.colonies[id + 1] = {pos = tile_center(x, y), id = id, stock = {}, visited = false}
    end
    for i = 1, 4 do
        local x, y = random:randi_range(5, 46), random:randi_range(5, 32)
        world.nests[i] = {pos = tile_center(x, y), used = false, kind = random:randi_range(0, 2)}
    end

    local start_x, start_y = tile(world.start.x, world.start.y)
    carve(cells, start_x, start_y, 3)
    carve(cells, boss_x, boss_y, 3)
    for _, landmarks in ipairs({world.colonies, world.nests}) do
        for _, landmark in ipairs(landmarks) do
            connect(cells, world.start, landmark.pos, random)
            local x, y = tile(landmark.pos.x, landmark.pos.y)
            carve(cells, x, y, 2)
        end
    end
    connect(cells, world.start, world.boss_pos, random)

    local visited = flood(cells, world.start)
    for i = 1, #cells do
        if not visited[i] then
            cells[i] = 1
        end
    end
    for _ = 1, 180 do
        local x = random:randf_range(200, WIDTH * TILE - 200)
        local y = random:randf_range(200, HEIGHT * TILE - 200)
        if world:walkable(x, y, 35) then
            world.nutrients[#world.nutrients + 1] = {
                pos = {x = x, y = y},
                rich = random:randf() < 0.12,
            }
        end
    end
    return world
end

function World:reachable(x, y)
    local cx, cy = tile(x, y)
    if cx < 0 or cy < 0 or cx >= WIDTH or cy >= HEIGHT then
        return false
    end
    return flood(self.cells, self.start)[index(cx, cy)] == true
end

function World:walkable(x, y, radius)
    local extent = math.abs(radius or 0)
    local low_x, low_y = tile(x - extent, y - extent)
    local high_x, high_y = tile(x + extent, y + extent)
    if low_x < 0 or low_y < 0 or high_x >= WIDTH or high_y >= HEIGHT then
        return false
    end
    local cells = self.cells
    return cells[index(low_x, low_y)] == 0 and cells[index(high_x, low_y)] == 0
        and cells[index(low_x, high_y)] == 0 and cells[index(high_x, high_y)] == 0
end

function World:move_body(x, y, dx, dy, radius)
    -- Test each axis separately to slide along walls. Substeps prevent a
    -- large frame delta from carrying the body through a tile.
    local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / 22))
    local step_x, step_y = dx / steps, dy / steps
    for _ = 1, steps do
        if self:walkable(x + step_x, y, radius) then
            x = x + step_x
        end
        if self:walkable(x, y + step_y, radius) then
            y = y + step_y
        end
    end
    return x, y
end

function World:biome(x, y)
    local boundary = WIDTH * TILE * 0.5 + math.sin(y / 650 + self.boundary_phase) * 350
        + math.sin(y / 210) * 100
    return x > boundary and 2 or 1
end

function World:biome_name(biome)
    return biome == 1 and "Холодная зона" or "Тёплая зона"
end

function World:condition_name(biome)
    return CONDITION_NAMES[self.conditions[biome] + 1]
end

return M
