local util = require "main.run.meta_util"
local catalog = require "main.run.catalog"
local legacy = require "main.run.genome_legacy"
local equipment = require "main.run.organism_equipment"
local M = {}
local Store = {}
Store.__index = Store

local function registry()
    return {version = 1, active = "", next_id = 1, items = {}}
end

local function defaults()
    return {
        version = 1, cores = 0, organium = 0, organ_materials = {}, unlocked = catalog.base_unlocked(),
        discovered = {}, synergies = {}, upgrades = {health = 0, collect = 0, regen = 0}, credited = {},
        runs = 0, wins = 0, checkpoint = {}, best = 0, best_stage = 0, legacy = legacy.defaults(),
    }
end

function M.defaults()
    local profile = defaults()
    profile.families = registry()
    return profile
end

local function active_projection(profile)
    local state = {}
    for key, value in pairs(profile) do
        if key ~= "families" then state[key] = util.copy(value) end
    end
    return state
end

local function family_number(id)
    if type(id) ~= "string" then return nil end
    local number = tonumber(id:match("^family%-([1-9]%d*)$"))
    if util.count(number, 1) and id == ("family-%.0f"):format(number) then return number end
end

local function normalize_state(state)
    if type(state) ~= "table" or state.version ~= 1 or state.families ~= nil then return nil end
    for _, key in ipairs({"unlocked", "discovered", "synergies", "credited"}) do
        if state[key] ~= nil and not util.array(state[key]) then return nil end
    end
    for _, key in ipairs({"upgrades", "checkpoint", "organ_materials"}) do
        if state[key] ~= nil and type(state[key]) ~= "table" then return nil end
    end
    for _, key in ipairs({"cores", "runs", "wins", "best", "best_stage"}) do
        if state[key] ~= nil and not util.finite(state[key]) then return nil end
    end
    if state.organium ~= nil and not util.count(state.organium) then return nil end
    for kind, amount in pairs(state.organ_materials or {}) do
        if not (catalog.ORGANS[kind] or kind == "organelle" or kind == "membrane" or kind == "plasma") or not util.count(amount) then
            return nil
        end
    end
    for _, id in ipairs({"health", "collect", "regen"}) do
        local value = util.table(state.upgrades)[id]
        if value ~= nil and not util.finite(value) then return nil end
    end
    if state.organism ~= nil and equipment.validate(state.organism) ~= "" then return nil end
    local clean = defaults()
    for key, value in pairs(state) do clean[key] = util.copy(value) end
    for _, id in ipairs(catalog.base_unlocked()) do
        if not util.index(clean.unlocked, id) then clean.unlocked[#clean.unlocked + 1] = id end
    end
    clean.cores = util.clamp(util.integer(clean.cores), 0, util.MAX_INTEGER)
    clean.best_stage = util.clamp(util.integer(clean.best_stage), 0, 1000000)
    for _, id in ipairs({"health", "collect", "regen"}) do clean.upgrades[id] = util.clamp(util.integer(clean.upgrades[id]), 0, 5) end
    clean.legacy = legacy.normalize(clean)
    return clean
end

-- Active state stays at the top level. Other families carry an independent snapshot.
function M.normalize_profile(profile)
    if type(profile) ~= "table" then return nil end
    local clean = normalize_state(active_projection(profile))
    if not clean then return nil end
    local raw = profile.families
    if raw == nil then
        clean.families = {
            version = 1, active = "family-1", next_id = 2,
            items = {{id = "family-1", name = "Семья 1", form = clean.legacy.selected_form, state = {}}},
        }
        return clean
    end
    if type(raw) ~= "table" or raw.version ~= 1 or type(raw.active) ~= "string"
        or not util.count(raw.next_id, 1) or not util.array(raw.items) then return nil end
    local families = {version = 1, active = raw.active, next_id = raw.next_id, items = {}}
    local ids = {}
    for index, entry in ipairs(raw.items) do
        if type(entry) ~= "table" then return nil end
        local id = entry.id
        local number = family_number(id)
        if not number or number >= raw.next_id or ids[id] then return nil end
        if type(entry.name) ~= "string" or not legacy.FORMS[entry.form] or type(entry.state) ~= "table" then return nil end
        local archived = {}
        local checkpoint
        if id == raw.active then
            if next(entry.state) then return nil end
            checkpoint = clean.checkpoint
        else
            archived = normalize_state(entry.state)
            if not archived then return nil end
            checkpoint = archived.checkpoint
        end
        if checkpoint.family_id ~= nil and checkpoint.family_id ~= id then return nil end
        families.items[index] = {id = id, name = entry.name, form = entry.form, state = archived}
        ids[id] = true
    end
    if (#families.items == 0 and families.active ~= "") or (#families.items > 0 and not ids[families.active]) then return nil end
    clean.families = families
    return clean
end

local function equivalent(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not equivalent(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

function M.new(filename, backend)
    backend = backend or sys
    filename = filename or "profile"
    return setmetatable({
        backend = backend,
        paths = {
            backend.get_save_file("microgen_defold", filename .. ".a"),
            backend.get_save_file("microgen_defold", filename .. ".b"),
        },
        revision = 0, active_file = 0, profile = M.defaults(), last_error = "",
    }, Store)
end

function Store:defaults()
    return M.defaults()
end

local function read_candidate(backend, path)
    local ok, record = pcall(backend.load, path)
    if not ok or type(record) ~= "table" or not util.count(record.revision, 1) then return nil end
    local profile = M.normalize_profile(record.profile)
    if not profile then return nil end
    return profile, record.revision, record.profile
end

function Store:load_profile()
    self.profile, self.revision, self.active_file, self.last_error = M.defaults(), 0, 0, ""
    for index, path in ipairs(self.paths) do
        local profile, revision = read_candidate(self.backend, path)
        if profile and revision > self.revision then self.profile, self.revision, self.active_file = profile, revision, index end
    end
    return self.profile
end

function Store:write_profile(data)
    local profile = M.normalize_profile(data or self.profile)
    if not profile then
        self.last_error = "Некорректные данные семьи"
        return false
    end
    if self.revision >= util.MAX_INTEGER then self.last_error = "Достигнут предел версии сохранения"; return false end
    -- Write only the inactive slot. The last committed slot survives an interrupted save.
    local index = self.active_file == 1 and 2 or 1
    local revision = self.revision + 1
    local ok, saved = pcall(self.backend.save, self.paths[index], {revision = revision, profile = profile})
    if not ok or not saved then self.last_error = "Не удалось записать сохранение"; return false end
    local normalized, actual_revision, actual = read_candidate(self.backend, self.paths[index])
    if not normalized or actual_revision ~= revision or not equivalent(profile, actual) then
        self.last_error = "Проверка сохранения не пройдена"
        pcall(os.remove, self.paths[index])
        return false
    end
    self.profile, self.revision, self.active_file, self.last_error = profile, revision, index, ""
    return true
end

function Store:bank(amount)
    if not util.count(amount) then return false end
    local profile = util.copy(self.profile)
    profile.cores = math.min(util.MAX_INTEGER, profile.cores + amount)
    return self:write_profile(profile)
end

function Store:credit_once(token, amount)
    if type(token) ~= "string" or token == "" or util.index(self.profile.credited, token) or not util.count(amount) then return false end
    local profile = util.copy(self.profile)
    profile.credited[#profile.credited + 1] = token
    profile.cores = math.min(util.MAX_INTEGER, profile.cores + amount)
    return self:write_profile(profile)
end

function Store:unlock(id)
    local item = catalog.ORGANS[id]
    if not item or util.index(self.profile.unlocked, id) or self.profile.cores < (item.unlock or 8) then return false end
    local profile = util.copy(self.profile)
    profile.cores = profile.cores - (item.unlock or 8)
    profile.unlocked[#profile.unlocked + 1] = id
    return self:write_profile(profile)
end

function Store:buy_upgrade(id)
    local rank = self.profile.upgrades[id]
    if not rank or rank >= 5 then return false end
    local price = 4 + 4 * rank
    if self.profile.cores < price then return false end
    local profile = util.copy(self.profile)
    profile.cores = profile.cores - price
    profile.upgrades[id] = rank + 1
    return self:write_profile(profile)
end

function Store:research(id)
    local progress = legacy.focus_progress(self.profile, id)
    if not progress.ready then return false end
    id = progress.id
    local profile = util.copy(self.profile)
    local branch = legacy.RESEARCH[id].branch
    profile.cores = profile.cores - progress.cost
    profile.legacy.knowledge[branch] = math.max(0, profile.legacy.knowledge[branch] - progress.knowledge)
    profile.legacy.research[#profile.legacy.research + 1] = id
    if id == "colony" and not util.index(profile.unlocked, "division") then profile.unlocked[#profile.unlocked + 1] = "division" end
    return self:write_profile(profile)
end

function Store:select_form(id)
    if not util.index(self.profile.legacy.forms, id) then return false end
    local profile = util.copy(self.profile)
    profile.legacy.selected_form = id
    return self:write_profile(profile)
end

function Store:toggle_trait(id)
    if not util.index(self.profile.legacy.traits, id) then return false end
    local profile = util.copy(self.profile)
    local traits = profile.legacy.equipped_traits
    local index = util.index(traits, id)
    if index then table.remove(traits, index)
    elseif #traits < 2 then traits[#traits + 1] = id
    else return false end
    return self:write_profile(profile)
end

function Store:select_imprint(id)
    if id ~= "" and not util.find(self.profile.legacy.imprints, id) then return false end
    local profile = util.copy(self.profile)
    profile.legacy.selected_imprint = id
    return self:write_profile(profile)
end

function Store:reroll_morphology()
    local profile = util.copy(self.profile)
    profile.legacy.morphology_seed = (profile.legacy.morphology_seed * 48271) % 2147483647
    return self:write_profile(profile)
end

local function clean_name(name)
    return util.limit_text(util.string(name):match("^%s*(.-)%s*$"), 32)
end

function Store:save_preset(name)
    name = clean_name(name)
    if name == "" then return false end
    local profile = util.copy(self.profile)
    local preset, presets = legacy.loadout(profile), profile.legacy.presets
    preset.name = name
    for index, entry in ipairs(presets) do
        if entry.name == name then
            presets[index] = preset
            return self:write_profile(profile)
        end
    end
    if #presets >= 6 then return false end
    presets[#presets + 1] = preset
    return self:write_profile(profile)
end

function Store:load_preset(index)
    local preset = self.profile.legacy.presets[index]
    if not preset then return false end
    local profile = util.copy(self.profile)
    profile.legacy.selected_form, profile.legacy.selected_imprint = preset.form, preset.imprint
    profile.legacy.equipped_traits, profile.legacy.morphology_seed = util.copy(preset.traits), preset.seed
    return self:write_profile(profile)
end

function Store:focus_research(id)
    if id ~= "" and (not legacy.RESEARCH[id] or util.index(self.profile.legacy.research, id)) then return false end
    local profile = util.copy(self.profile)
    profile.legacy.focus = id
    return self:write_profile(profile)
end

function Store:claim_imprint(id)
    local profile = util.copy(self.profile)
    local inheritance = profile.legacy
    local chosen = util.find(inheritance.pending, id)
    if not chosen then return false end
    if util.find(inheritance.imprints, id) then
        local branch = chosen.branch
        inheritance.knowledge[branch] = math.min(3, inheritance.knowledge[branch] + 1)
    else
        inheritance.imprints[#inheritance.imprints + 1] = chosen
    end
    inheritance.pending = table.remove(inheritance.pending_queue, 1) or {}
    inheritance.selected_imprint = id
    return self:write_profile(profile)
end

function Store:family_id()
    return self.profile.families.active
end

function Store:family_summaries()
    local summaries = {}
    for index, family in ipairs(self.profile.families.items) do
        local data = family.id == self:family_id() and self.profile or family.state
        local ended = util.string(data.checkpoint.outcome) ~= ""
        summaries[index] = {
            id = family.id, name = family.name, form = family.form,
            alive = next(data.checkpoint) ~= nil and not ended, ended = ended, generation = data.legacy.generation,
            runs = data.runs, cores = data.cores, best = data.best, best_stage = data.best_stage,
        }
    end
    return summaries
end

function Store:select_family(id)
    local profile = util.copy(self.profile)
    local families = profile.families
    local target = util.find(families.items, id)
    if not target then return false end
    if id == families.active then return true end
    local current = util.find(families.items, families.active)
    if current then current.state = active_projection(profile) end
    local projected = target.state
    target.state, families.active = {}, id
    projected.families = families
    return self:write_profile(projected)
end

function Store:create_family(name, form)
    name = clean_name(name)
    if name == "" or not legacy.FORMS[form] or self.profile.families.next_id >= util.MAX_INTEGER then return false end
    local profile = util.copy(self.profile)
    local families = profile.families
    local current = util.find(families.items, families.active)
    local projected = #families.items == 0 and active_projection(profile) or defaults()
    if current then current.state = active_projection(profile) end
    local id = ("family-%.0f"):format(families.next_id)
    families.next_id = families.next_id + 1
    families.items[#families.items + 1] = {id = id, name = name, form = form, state = {}}
    families.active = id
    local research = legacy.FORMS[form].research
    if research ~= "" and not util.index(projected.legacy.research, research) then
        projected.legacy.research[#projected.legacy.research + 1] = research
    end
    if form == "colony" and not util.index(projected.unlocked, "division") then
        projected.unlocked[#projected.unlocked + 1] = "division"
    end
    projected.legacy.selected_form = form
    projected.families = families
    return self:write_profile(projected)
end

function Store:delete_family(id)
    local profile = util.copy(self.profile)
    local families = profile.families
    local _, index = util.find(families.items, id)
    if not index then return false end
    table.remove(families.items, index)
    if id == families.active then
        local survivor = families.items[1]
        if survivor then
            profile, families.active = survivor.state, survivor.id
            survivor.state = {}
        else
            profile, families.active = defaults(), ""
        end
        profile.families = families
    end
    return self:write_profile(profile)
end

function Store:save_checkpoint(snapshot, expected_family_id)
    if expected_family_id == "" or expected_family_id ~= self:family_id() or type(snapshot) ~= "table" then return false end
    if snapshot.family_id ~= nil and snapshot.family_id ~= expected_family_id then return false end
    local profile = util.copy(self.profile)
    profile.checkpoint = util.copy(snapshot)
    return self:write_profile(profile)
end

function Store:finish_run(sim, token, amount)
    local outcome = util.string(sim.outcome)
    if outcome == "" or (sim.family_id and sim.family_id ~= "" and sim.family_id ~= self:family_id()) then return false end
    if not token and type(sim.run_id) == "string" then token = sim.run_id .. ":finished" end
    if type(token) ~= "string" or token == "" then return false end
    if util.index(self.profile.credited, token) then return true end
    local elapsed = math.max(0, util.finite(sim.elapsed) and sim.elapsed or 0)
    amount = amount or (outcome == "victory" and 2 or (elapsed >= 60 and 1 or 0))
    if not util.count(amount) then return false end
    local profile = util.copy(self.profile)
    if not legacy.complete(profile, sim) then
        self.last_error = "Выберите ожидающий отпечаток"
        return false
    end
    local build = util.table(sim.build)
    if build.to_dict then
        local inventory = equipment.refresh(equipment.from_profile(profile), build:to_dict())
        if inventory.ok then profile.organism = inventory.state end
    end
    profile.credited[#profile.credited + 1] = token
    profile.runs = profile.runs + 1
    if outcome == "victory" then profile.wins = profile.wins + 1 end
    profile.cores = math.min(util.MAX_INTEGER, profile.cores + amount)
    local organium_token = type(sim.run_id) == "string" and sim.run_id .. ":organium" or token .. ":organium"
    if not util.index(profile.credited, organium_token) then
        profile.credited[#profile.credited + 1] = organium_token
        local organium = math.max(1, math.floor(util.integer(sim.kills) / 4)) + util.integer(sim.minibosses_spawned) * 2
        if outcome == "victory" then organium = organium + 5 end
        profile.organium = math.min(util.MAX_INTEGER, profile.organium + organium)
    end
    profile.best = math.max(profile.best, elapsed)
    profile.best_stage = math.max(profile.best_stage, util.integer(sim.best_stage))
    profile.checkpoint = {}
    for _, id in ipairs(util.sorted_keys(util.table(build.organs))) do
        if not util.index(profile.discovered, id) then profile.discovered[#profile.discovered + 1] = id end
    end
    if build.active_synergies then
        for _, id in ipairs(build:active_synergies()) do
            if not util.index(profile.synergies, id) then profile.synergies[#profile.synergies + 1] = id end
        end
    end
    return self:write_profile(profile)
end

return M
