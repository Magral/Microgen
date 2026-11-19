local Updater = {}
Updater.__index = Updater

local REPO = "https://github.com/Magral/Microgen"
local RELEASES = "https://api.github.com/repos/Magral/Microgen/releases?per_page=50"

local function version(value)
    if type(value) ~= "string" then return end
    local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
    if major then return {tonumber(major), tonumber(minor), tonumber(patch)} end
end

local function newer(a, b)
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] > b[i] end
    end
    return false
end

function Updater.select(releases, installed)
    local current = version(installed)
    if type(releases) ~= "table" or not current then return end
    local best
    for _, release in ipairs(releases) do
        local tag = type(release) == "table" and release.tag_name
        local label = type(tag) == "string" and tag:match("^defold%-(%d+%.%d+%.%d+)$")
        local candidate = version(label)
        if candidate and release.draft == false and release.prerelease == false
            and newer(candidate, current) and (not best or newer(candidate, best.version))
            and type(release.assets) == "table" then
            local name = "Microgen-Defold-" .. label .. ".apk"
            local url = REPO .. "/releases/download/" .. tag .. "/" .. name
            for _, asset in ipairs(release.assets) do
                if asset.name == name and asset.browser_download_url == url
                    and type(asset.digest) == "string" and type(asset.size) == "number"
                    and asset.size == math.floor(asset.size) and asset.size > 0 and asset.size <= 150 * 1024 * 1024 then
                    local sha = asset.digest:match("^sha256:([a-f0-9]+)$")
                    if sha and #sha == 64 then
                        best = {version = candidate, label = label, sha = sha, size = asset.size, url = url}
                        break
                    end
                end
            end
        end
    end
    return best
end

function Updater.new(installed, native, automatic, changed)
    return setmetatable({installed=installed, native=native, automatic=automatic, changed=changed,
        state="idle", timer=12}, Updater)
end

function Updater:set(state)
    self.state = state
    self.changed()
end

function Updater:check()
    if self.state == "checking" or self.state == "downloading" or self.state == "verifying" or self.state == "ready" then return end
    self.timer = 6 * 60 * 60
    self:set("checking")
    http.request(RELEASES, "GET", function(_, _, result)
        local ok, data = pcall(json.decode, result.response or "")
        if result.status ~= 200 or not ok or type(data) ~= "table" then
            self.timer = 15 * 60
            self:set("error")
            return
        end
        local asset = Updater.select(data, self.installed)
        if not asset then self:set("current"); return end
        self.asset = asset
        if not self.native then self:set("desktop"); return end
        if self.native.download(asset.url, asset.sha, asset.size) then
            self:set("downloading")
        else
            self:set("error")
        end
    end, { Accept="application/vnd.github+json" }, nil, { timeout=20, ignore_cache=true })
end

function Updater:install()
    local result = self.native.install()
    if result == 3 then self.needs_permission = true; self.changed()
    elseif result == 2 then self.needs_permission = false; self.changed()
    else self:set("error") end
end

function Updater:step(dt, safe)
    self.timer = self.timer - dt
    if self.automatic and self.timer <= 0 then self:check() end
    if self.state == "downloading" or self.state == "ready" then
        local status = self.native.status()
        if status < 0 then self.timer = 15 * 60; self:set("error")
        elseif status == 2 and self.state == "downloading" then
            self.offered = false
            self:set("ready")
        end
    end
    if self.state == "ready" and safe and not self.offered then
        self.offered = true
        self:install()
    end
end

return Updater
