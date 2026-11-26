local Audio = {}
Audio.__index = Audio

local VOICE_CAP = 6
local GLOBAL_INTERVAL = 0.4
local PRIORITY = {"miniboss", "danger", "hurt", "level_up", "organ", "heal", "reward", "nest", "biome"}
local MENU_CUE = {level_up = true, organ = true, heal = true}
local PENDING_KIND = {}
for _, kind in ipairs(PRIORITY) do PENDING_KIND[kind] = true end
local CUE = {
    miniboss = "/audio#miniboss",
    danger = "/audio#danger",
    hurt = "/audio#hurt",
    attack_warning = "/audio#attack_warning",
    level_up = "/audio#level_up",
    organ = "/audio#organ",
    heal = "/audio#heal",
    nest = "/audio#nest",
    biome = "/audio#biome",
    reward = "/audio#reward",
    reward_rare = "/audio#reward_rare",
    absorb = "/audio#absorb",
    movement = "/audio#movement",
}
local INTERVAL = {
    warning = 1.4, attack_warning = 0.85, hurt = 0.85, reward = 1.2, absorb = 0.65,
    level_up = 0.6, organ = 0.6, heal = 0.7, nest = 1.0, biome = 3.0,
}
local GAIN = {
    warning = .28, attack_warning = .38, hurt = .35, reward = .22, absorb = .16,
    level_up = .34, organ = .29, heal = .29, nest = .32, biome = .25,
}

function Audio.new()
    local mixer = setmetatable({
        clock = -1, last_global = -100, last = {}, pending = {}, voices = {},
        paused = false, movement_gain = 0, sent_gain = 0, sent_rate = 0,
    }, Audio)
    for i = 1, VOICE_CAP do mixer.voices[i] = {} end
    mixer.on_sound_finished = function(_, _, message)
        for _, voice in ipairs(mixer.voices) do
            if voice.id == message.play_id then
                voice.id = nil
                return
            end
        end
    end
    return mixer
end

local function stop_movement(self)
    if self.sent_gain > 0 then
        msg.post("/audio#movement_driver", "movement_sound", {gain = 0})
        self.sent_gain = 0
    end
end

local function stop_sounds(self)
    for _, voice in ipairs(self.voices) do
        if voice.id then
            sound.stop(voice.url, {play_id = voice.id})
            voice.id = nil
        end
    end
    stop_movement(self)
    self.paused, self.movement_gain = false, 0
    for kind in pairs(self.pending) do self.pending[kind] = nil end
end

function Audio:stop()
    stop_sounds(self)
    self.clock, self.elapsed, self.run_id, self.last_global = -1, nil, nil, -100
    for kind in pairs(self.last) do self.last[kind] = nil end
end

local function set_paused(self, paused)
    if paused == self.paused then return end
    for kind, url in pairs(CUE) do
        if not MENU_CUE[kind] then sound.pause(url, paused) end
    end
    self.paused = paused
end

local function update_movement(self, sim, dt)
    local velocity = sim.player_velocity
    local speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
    local target = speed > 3 and 0.24 * math.min(speed / 110, 1) or 0
    local gain = self.movement_gain + (target - self.movement_gain) * (1 - math.exp(-dt * 8))
    self.movement_gain = gain
    if gain < 0.002 and target == 0 then
        stop_movement(self)
        return
    end
    local rate = math.max(0.72, math.min(1.25, 1.07 - sim:body_radius() * 0.003 + speed * 0.001))
    if self.sent_gain == 0 or math.abs(gain - self.sent_gain) >= 0.001 or math.abs(rate - self.sent_rate) >= 0.005 then
        msg.post("/audio#movement_driver", "movement_sound", {gain = gain, rate = rate})
        self.sent_gain, self.sent_rate = gain, rate
    end
end

local function play(self, kind, now, event)
    local group = (kind == "miniboss" or kind == "danger") and "warning" or kind
    if now - (self.last[group] or -100) < INTERVAL[group] then return false end
    local clip = kind
    if kind == "reward" and (event.tier or 1) >= 2 then
        clip = "reward_rare"
    end

    local chosen = self.voices[1]
    for _, voice in ipairs(self.voices) do
        if not voice.id then
            chosen = voice
            break
        end
        if voice.started < chosen.started then chosen = voice end
    end
    if chosen.id then sound.stop(chosen.url, {play_id = chosen.id}) end
    chosen.url, chosen.started = CUE[clip], now
    chosen.id = sound.play(chosen.url, {gain = GAIN[group]}, self.on_sound_finished)
    self.last[group], self.last_global = now, now
    return true
end

-- Read each frame's feedback after simulation, before the caller discards it.
function Audio:consume(sim, enabled, paused, dt)
    if sim.run_id ~= self.run_id or (self.elapsed and sim.elapsed < self.elapsed) then self:stop() end
    local movement_dt = self.elapsed and math.min(sim.elapsed - self.elapsed, 0.1) or 0.016
    local now = math.max(self.clock, 0) + dt
    self.clock, self.elapsed, self.run_id = now, sim.elapsed, sim.run_id
    if not enabled then
        stop_sounds(self)
        return
    end

    local absorb, attack_warning
    for _, event in ipairs(sim.feedback) do
        local kind = event.kind
        if PENDING_KIND[kind] then self.pending[kind] = {event = event, time = now}
        elseif kind == "attack_warning" then attack_warning = event
        elseif kind == "absorb" then absorb = event end
    end
    set_paused(self, not not (paused or sim.paused))
    if not self.paused then
        update_movement(self, sim, movement_dt)
        -- Сигнал должен прозвучать до атаки, поэтому в очередь его не ставим.
        if attack_warning and play(self, "attack_warning", now, attack_warning) then return end
    end
    for _, kind in ipairs(PRIORITY) do
        local pending = self.pending[kind]
        if pending and now - pending.time > 1.5 then self.pending[kind] = nil end
    end
    if now - self.last_global < GLOBAL_INTERVAL - 0.000001 then return end
    for _, kind in ipairs(PRIORITY) do
        local pending = self.pending[kind]
        if pending and (not self.paused or MENU_CUE[kind]) and play(self, kind, now, pending.event) then
            self.pending[kind] = nil
            if kind == "miniboss" then self.pending.danger = nil end
            return
        end
    end
    if absorb and not self.paused then play(self, "absorb", now, absorb) end
end

return Audio
