local Diagnostics = {}
Diagnostics.__index = Diagnostics
local WINDOW = 2
local WARMUP = 2

function Diagnostics.new()
    return setmetatable({last=socket.gettime(),time=0,frames={},warmup=WARMUP},Diagnostics)
end

function Diagnostics:step()
    local now = socket.gettime()
    local duration = now-self.last
    self.last = now
    if duration<=0 then return end
    if self.warmup>0 then self.warmup=self.warmup-duration return end
    self.time = self.time+duration
    local frames = self.frames
    frames[#frames+1] = duration
    if self.time<WINDOW then return end
    table.sort(frames)
    local count = #frames
    local fps, p95 = count/self.time, frames[math.ceil(count*.95)]*1000
    self.frames,self.time = {},0
    return fps,p95
end

return Diagnostics
