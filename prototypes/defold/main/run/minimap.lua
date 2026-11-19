local Minimap = {}
Minimap.__index = Minimap

local TEXTURE = "discovered_map"
local UNKNOWN = string.char(10,32,39,255)
local WALL = string.char(25,57,66,255)
local COLD = string.char(66,129,127,255)
local WARM = string.char(119,136,78,255)
local COLONY = string.char(114,237,203,255)
local NEST = string.char(225,166,98,255)
local THREAT = string.char(243,103,135,255)
local PLAYER = string.char(224,255,240,255)

local function index(world,p)
    return math.floor(p.y/world.tile_size)*world.w+math.floor(p.x/world.tile_size)+1
end

function Minimap.new(world)
    local visible = {}
    for i=1,world.w*world.h do visible[i]=UNKNOWN end
    local created=gui.new_texture(TEXTURE,world.w,world.h,"rgba",table.concat(visible),true)
    return setmetatable({visible=visible,created=created},Minimap)
end

function Minimap:attach(node)
    if self.created then gui.set_texture(node,TEXTURE) end
end

function Minimap:update(sim)
    if not self.created then return end
    local world=sim.world
    local player=index(world,sim.player)
    local active=sim.boss_spawned and index(world,sim.boss_marker or world.boss_pos) or -1
    local marker = player..":"..active..":"..sim.stage_index
    if self.marker==marker then return end
    self.marker=marker
    local pixels=self.visible
    for i=1,world.w*world.h do
        local tile=UNKNOWN
        if sim.explored[i] then
            if world.cells[i]==1 then tile=WALL
            else
                local x=((i-1)%world.w+.5)*world.tile_size
                local y=(math.floor((i-1)/world.w)+.5)*world.tile_size
                tile=world:biome(x,y)==1 and COLD or WARM
            end
        end
        pixels[i]=tile
    end
    for _,colony in ipairs(world.colonies) do
        local at=index(world,colony.pos)
        if colony.visited then pixels[at]=COLONY end
    end
    for _,nest in ipairs(world.nests) do
        local at=index(world,nest.pos)
        if sim.explored[at] and not nest.used then pixels[at]=NEST end
    end
    if active>=1 and active<=#pixels then pixels[active]=THREAT end
    pixels[player]=PLAYER
    gui.set_texture_data(TEXTURE,world.w,world.h,"rgba",table.concat(pixels),true)
end

return Minimap
