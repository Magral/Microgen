local Jelly = {}
Jelly.__index = Jelly

local PI = math.pi
local TAU = 2 * PI
local atan2 = math.atan2 or math.atan

local function limit(x, y, maximum)
    local squared = x * x + y * y
    if squared <= maximum * maximum then return x, y end
    local factor = maximum / math.sqrt(squared)
    return x * factor, y * factor
end

function Jelly.new(angle)
    return setmetatable({
        rest_angle = angle, angle = angle, clock = 0, speed = 0,
        strain_x = 0, strain_y = 0, strain_vx = 0, strain_vy = 0,
        lag_x = 0, lag_y = 0, lag_vx = 0, lag_vy = 0,
    }, Jelly)
end

function Jelly:turn()
    return (self.angle - self.rest_angle + PI) % TAU - PI
end

-- The 1.4.1 visual spring uses substeps so low render rates do not destabilize it.
function Jelly:step(dt, vx, vy)
    dt = math.min(0.25, math.max(0, dt))
    vx, vy = limit(vx, vy, 320)
    local speed = math.min(math.sqrt(vx * vx + vy * vy) / 145, 1.25)
    local target_x, target_y, heading = 0, 0, self.angle
    if speed > 0.01 then
        heading = atan2(vy, vx)
        target_x = math.cos(heading * 2) * 0.19 * speed
        target_y = math.sin(heading * 2) * 0.19 * speed
    end
    local trail_x, trail_y = -vx * (0.07 / 145), -vy * (0.07 / 145)
    local count = math.max(1, math.ceil(dt * 120))
    local h = dt / count
    local turn, ease = 1 - math.exp(-h * 9), 1 - math.exp(-h * 8)
    for _ = 1, count do
        if speed > 0.025 then
            self.angle = self.angle + ((heading - self.angle + PI) % TAU - PI) * turn
        end
        self.strain_vx = self.strain_vx + ((target_x - self.strain_x) * 210 - self.strain_vx * 12) * h
        self.strain_vy = self.strain_vy + ((target_y - self.strain_y) * 210 - self.strain_vy * 12) * h
        self.strain_x, self.strain_y = limit(self.strain_x + self.strain_vx * h, self.strain_y + self.strain_vy * h, 0.28)
        self.lag_vx = self.lag_vx + ((trail_x - self.lag_x) * 105 - self.lag_vx * 11) * h
        self.lag_vy = self.lag_vy + ((trail_y - self.lag_y) * 105 - self.lag_vy * 11) * h
        self.lag_x, self.lag_y = limit(self.lag_x + self.lag_vx * h, self.lag_y + self.lag_vy * h, 0.14)
        self.speed = self.speed + (speed - self.speed) * ease
    end
    self.clock = self.clock + dt
end

return Jelly
