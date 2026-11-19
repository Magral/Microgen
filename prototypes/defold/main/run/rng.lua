local M = {}
local Rng = {}
Rng.__index = Rng

local floor = math.floor
local WORD = 65536
local UINT32 = 4294967296

-- Godot's PCG32 uses a 64-bit state. Four 16-bit limbs keep the multiply
-- and carry exact in a Lua number, including runtimes without bit operators.
local MULTIPLIER = {32557, 19605, 62509, 22609}
local INCREMENT = {671, 61135, 63229, 10250}

local function advance(state)
    local low, middle, high, top = state[1], state[2], state[3], state[4]
    local value = low * MULTIPLIER[1] + INCREMENT[1]
    state[1] = value % WORD
    value = floor(value / WORD) + low * MULTIPLIER[2] + middle * MULTIPLIER[1] + INCREMENT[2]
    state[2] = value % WORD
    value = floor(value / WORD) + low * MULTIPLIER[3] + middle * MULTIPLIER[2]
        + high * MULTIPLIER[1] + INCREMENT[3]
    state[3] = value % WORD
    value = floor(value / WORD) + low * MULTIPLIER[4] + middle * MULTIPLIER[3]
        + high * MULTIPLIER[2] + top * MULTIPLIER[1] + INCREMENT[4]
    state[4] = value % WORD
end

local function xor(a, b)
    local result, place = 0, 1
    while a > 0 and b > 0 do
        result = result + ((a + b) % 2) * place
        a, b, place = floor(a / 2), floor(b / 2), place * 2
    end
    return result + (a + b) * place
end

local function float32(value)
    local fraction, exponent = math.frexp(value)
    local scaled = fraction * 16777216
    local rounded = floor(scaled)
    local remainder = scaled - rounded
    if remainder > 0.5 or (remainder == 0.5 and rounded % 2 == 1) then
        rounded = rounded + 1
    end
    return rounded * 2 ^ (exponent - 24)
end

function M.new(seed)
    local state = {}
    local remaining = seed
    local carry = 0
    for i = 1, 4 do
        local word = remaining % WORD + INCREMENT[i] + carry
        state[i] = word % WORD
        carry = floor(word / WORD)
        remaining = floor(remaining / WORD)
    end
    advance(state)
    return setmetatable({state = state}, Rng)
end

function Rng:randi()
    local state = self.state
    local low = state[1] + state[2] * WORD
    local high = state[3] + state[4] * WORD
    advance(state)

    -- PCG XSH-RR: xor the state with its 18-bit shift, then rotate the
    -- resulting 32 bits by the top five bits of the original state.
    local shifted_low = floor(low / 262144) + (high % 262144) * 16384
    local shifted_high = floor(high / 262144)
    local xorshifted = floor(xor(shifted_low, low) / 134217728)
        + (xor(shifted_high, high) % 134217728) * 32
    local rotation = floor(high / 134217728)
    local divisor = 2 ^ rotation
    return floor(xorshifted / divisor) + (xorshifted % divisor) * (UINT32 / divisor)
end

function Rng:randi_range(from, to)
    local low = math.min(from, to)
    local count = math.abs(to - from) + 1
    if count == 1 then
        return low
    end
    local threshold = UINT32 % count
    local draw = self:randi()
    while draw < threshold do
        draw = self:randi()
    end
    return low + draw % count
end

function Rng:randf()
    local exponent = self:randi()
    if exponent == 0 then
        return 0
    end
    local _, bits = math.frexp(exponent)
    local fraction = self:randi()
    -- Set the high and low bits before Godot rounds the significand to float.
    fraction = 2147483649 + fraction % 2147483648 - fraction % 2
    return float32(fraction) * 2 ^ (bits - 64)
end

function Rng:randf_range(from, to)
    from, to = float32(from), float32(to)
    local span = float32(to - from)
    return float32(float32(self:randf() * span) + from)
end

return M
