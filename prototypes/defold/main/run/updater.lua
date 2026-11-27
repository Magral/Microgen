local Updater = {}
Updater.__index = Updater

local REPO = "https://github.com/Magral/Microgen"
local RELEASES = "https://api.github.com/repos/Magral/Microgen/releases"

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
    local best, newest
    for _, release in ipairs(releases) do
        local tag = type(release) == "table" and release.tag_name
        local label = type(tag) == "string" and tag:match("^defold%-(%d+%.%d+%.%d+)$")
        local candidate = version(label)
        if candidate and release.draft == false and release.prerelease == false
            and newer(candidate, current) then
            if not newest or newer(candidate, newest) then newest = candidate end
        end
        if candidate and release.draft == false and release.prerelease == false
            and newer(candidate, current) and (not best or newer(candidate, best.version))
            and type(release.assets) == "table" then
            local name = "Microgen-Defold-" .. label .. ".apk"
            local url = REPO .. "/releases/download/" .. tag .. "/" .. name
            for _, asset in ipairs(release.assets) do
                if type(asset) == "table" and asset.name == name and asset.browser_download_url == url
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
    return best, newest ~= nil and (best == nil or newer(newest, best.version))
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
    self.timer = 5 * 60
    self.asset, self.needs_permission, self.offered = nil, false, false
    self.failure_code = nil
    self:set("checking")
    local headers = {
        Accept="application/vnd.github+json",
        ["User-Agent"]="Microgen-Defold/" .. self.installed,
        ["Cache-Control"]="no-cache",
    }
    local options = {timeout=20, ignore_cache=true}
    local nonce = tostring(os.time())

    local function accept(asset)
        self.asset = asset
        if not self.native then self:set("desktop"); return end
        if self.native.download(asset.url, asset.sha, asset.size) then
            self:set("downloading")
        else
            self:set("download_error")
        end
    end

    local function decode(result)
        if result.status ~= 200 then return end
        local ok, data = pcall(json.decode, result.response or "")
        if ok and type(data) == "table" then return data end
    end

    local request = self.request or http.request
    request(RELEASES .. "/latest?t=" .. nonce, "GET", function(_, _, result)
        local latest = decode(result)
        local asset = Updater.select(latest and {latest}, self.installed)
        if asset then return accept(asset) end

        request(RELEASES .. "?per_page=50&t=" .. nonce, "GET", function(_, _, listing)
            local releases = decode(listing)
            if not releases then self:set("error"); return end
            if type(releases[1]) ~= "table" then self:set("error"); return end
            if latest then releases[#releases+1] = latest end
            local fallback, newer_incomplete = Updater.select(releases, self.installed)
            if fallback and not newer_incomplete then
                accept(fallback)
            elseif newer_incomplete then
                self:set("incomplete")
            else
                self:set("current")
            end
        end, headers, nil, options)
    end, headers, nil, options)
end

function Updater:install()
    if self.state ~= "ready" or not self.native then return end
    local result = self.native.install()
    if result == 3 then self.needs_permission = true; self.changed()
    elseif result == 2 then self.needs_permission = false; self.changed()
    else self:set("install_error") end
end

function Updater:step(dt, safe)
    self.timer = self.timer - dt
    if self.automatic and self.timer <= 0 then self:check() end
    if self.state == "downloading" or self.state == "ready" then
        local status = self.native.status()
        if status < 0 then
            self.timer = 5 * 60
            self.failure_code = status
            self:set(self.state == "ready" and "install_error" or "download_error")
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
