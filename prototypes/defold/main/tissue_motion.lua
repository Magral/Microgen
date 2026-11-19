-- Keep the draw bounds in sync with the padded local coordinates in tissue.fp.
local tissue = {OVERSCAN = 1.24}
local atlas_property = hash("tissue_atlas")
local motion_property = hash("tissue_motion")
local contact_property = hash("tissue_contact")
local pigment_property = hash("tissue_pigment")

local function region(geometry, texture)
    -- The resource API gives pixel coordinates measured from the top left.
    -- Defold shaders sample normalized UVs measured from the bottom left.
    local uvs = geometry.uvs
    if #uvs < 6 then return nil end
    local left, right, top, bottom = uvs[1], uvs[1], uvs[2], uvs[2]
    for i = 3, #uvs, 2 do
        left = math.min(left, uvs[i])
        right = math.max(right, uvs[i])
        top = math.min(top, uvs[i + 1])
        bottom = math.max(bottom, uvs[i + 1])
    end
    local half_width = (right - left) / (2 * texture.width)
    local half_height = (bottom - top) / (2 * texture.height)
    if half_width == 0 or half_height == 0 then return nil end
    return vmath.vector4(
        (left + right) / (2 * texture.width),
        1 - (top + bottom) / (2 * texture.height),
        geometry.rotated and -half_width or half_width,
        half_height)
end

function tissue.load_atlas()
    local atlas = resource.get_atlas("/main/cells.a.texturesetc")
    local texture = resource.get_texture_info(atlas.texture)
    local regions = {}
    for _, animation in ipairs(atlas.animations) do
        local geometry = atlas.geometries[animation.frames[1]]
        if geometry then regions[animation.id] = region(geometry, texture) end
    end
    return regions
end

function tissue.attach(atlas, node, frame)
    local bounds = atlas[frame]
    if not bounds then return nil end

    local size = gui.get_size(node)
    gui.set_size(node, vmath.vector3(size.x * tissue.OVERSCAN, size.y * tissue.OVERSCAN, size.z))
    gui.set_material(node, "tissue")
    gui.set(node, atlas_property, bounds)
    return {node = node}
end

local function bounded_direction(x, y)
    local length_squared = x * x + y * y
    if length_squared > 1 then
        local length = math.sqrt(length_squared)
        return x / length, y / length
    end
    return x, y
end

local function unit(value)
    return math.min(math.max(value or 0, 0), 1)
end

function tissue.update(state, phase, motion_x, motion_y, contact_x, contact_y, bite, pigment, pigment_hex)
    if not state then return end
    local node = state.node
    motion_x, motion_y = bounded_direction(motion_x or 0, motion_y or 0)
    contact_x, contact_y = bounded_direction(contact_x or 0, contact_y or 0)
    bite = unit(bite)
    if contact_x == 0 and contact_y == 0 then bite = 0 end

    gui.set(node, motion_property, vmath.vector4(motion_x, motion_y,
        math.sin(phase * 2.8), math.cos(phase * 2.03)))
    gui.set(node, contact_property, vmath.vector4(contact_x, contact_y, bite,
        math.sin(phase * 10.2)))

    pigment = unit(pigment)
    if state.pigment ~= pigment or state.pigment_hex ~= pigment_hex then
        local r, g, b = 0.76, 0.58, 0.83
        local hex = type(pigment_hex) == "string" and pigment_hex:match("^#(%x%x%x%x%x%x)$")
        local rgb = hex and tonumber(hex, 16)
        if rgb then
            r = math.floor(rgb / 65536) / 255
            g = (math.floor(rgb / 256) % 256) / 255
            b = (rgb % 256) / 255
        end
        gui.set(node, pigment_property, vmath.vector4(r, g, b, pigment))
        state.pigment, state.pigment_hex = pigment, pigment_hex
    end
end

return tissue
