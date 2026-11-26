local Catalog = require("main.run.catalog")

local Build = {}
Build.__index = Build
Build.cell_cost = Catalog.cell_cost

local min = math.min
local max = math.max
local floor = math.floor

local function integer(value, default)
    if type(value) == "boolean" then
        return value and 1 or 0
    end
    local number = tonumber(value)
    if not number or number ~= number then
        return default or 0
    end
    return number < 0 and math.ceil(number) or floor(number)
end

local function dictionary(value)
    return type(value) == "table" and value or {}
end

local function clamp_grade(value)
    return max(0, min(3, integer(value)))
end

local function copy(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = type(value) == "table" and copy(value) or value
    end
    return result
end

local function contains(values, entry)
    for _, value in ipairs(values) do
        if value == entry then
            return true
        end
    end
    return false
end

local function reset_ranks(self)
    self.organs = {}
    self.adaptations = {}
    self.qualities = {}
    self.specializations = {}
    self.temporary_mutations = {}
    self.stats = { evolutions = {} }
    self._synergy_signature = nil
    self._synergy_cache = {}
end

function Build.new()
    local self = setmetatable({
        organ_capacity = 0,
        extra_organ_cells = 0,
        biomass = 0,
        unlocked = Catalog.base_unlocked(),
        branch = "predator",
        branch_weight = 1.35,
    }, Build)
    reset_ranks(self)
    return self
end

function Build:stored_rank(id)
    return integer(self.organs[id] or self.adaptations[id])
end

function Build:rank(id)
    local rank = self:stored_rank(id)
    if rank > 10 and Catalog.ORGANS[id] then
        return Catalog.effective_rank(rank)
    end
    return rank
end

function Build:used_organ_cells()
    local total = max(0, self.extra_organ_cells)
    for id in pairs(self.organs) do
        total = total + Catalog.cell_cost(id)
    end
    return total
end

function Build:can_fit(id, replace_id)
    replace_id = replace_id or ""
    local is_organ = Catalog.ORGANS[id] ~= nil
    if not is_organ and not Catalog.ADAPTATIONS[id] then
        return false
    end
    local target = is_organ and self.organs or self.adaptations
    if target[id] ~= nil then
        return replace_id == ""
    end
    if replace_id ~= "" and target[replace_id] == nil then
        return false
    end
    if is_organ and self.organ_capacity > 0 then
        return self:used_organ_cells() + Catalog.cell_cost(id) - Catalog.cell_cost(replace_id) <= self.organ_capacity
    end
    if replace_id ~= "" then
        return true
    end
    local count = 0
    for _ in pairs(target) do
        count = count + 1
    end
    return count < (is_organ and 6 or 4)
end

function Build:apply(id, replace_id, grade)
    replace_id = replace_id or ""
    grade = clamp_grade(grade)
    if not contains(self.unlocked, id) or not self:can_fit(id, replace_id) then
        return false
    end
    local is_organ = Catalog.ORGANS[id] ~= nil
    local target = is_organ and self.organs or self.adaptations
    if target[id] ~= nil then
        local limit = Catalog.max_rank(id)
        local current_quality = self:quality(id)
        if target[id] >= limit and grade <= current_quality then
            return false
        end
        if target[id] < limit then
            local gain = is_organ and Catalog.duplicate_rank_gain(grade) or 1
            target[id] = target[id] + min(gain, limit - target[id])
        end
        self.qualities[id] = max(current_quality, grade)
        return true
    end
    if replace_id ~= "" then
        local inherited = 1 + floor((target[replace_id] - 1) / 2)
        local inherited_quality = self:quality(replace_id)
        target[replace_id] = nil
        self.qualities[replace_id] = nil
        self.specializations[replace_id] = nil
        self.stats.evolutions[replace_id] = nil
        target[id] = min(inherited, Catalog.max_rank(id))
        self.qualities[id] = max(inherited_quality, grade)
        return true
    end
    target[id] = 1
    self.qualities[id] = grade
    return true
end

function Build:active_synergies()
    -- Direct edits to the public ranks also invalidate the equipped-state cache.
    local signature = 0
    local bit = 1
    for _, id in ipairs(Catalog.ORGAN_IDS) do
        if self:stored_rank(id) > 0 then
            signature = signature + bit
        end
        bit = bit * 2
    end
    if self:stored_rank("metabolism") > 0 then
        signature = signature + bit
    end
    if signature == self._synergy_signature then
        return self._synergy_cache
    end
    local active = {}
    for _, id in ipairs(Catalog.SYNERGY_IDS) do
        local needs = Catalog.SYNERGIES[id].needs
        if self:stored_rank(needs[1]) > 0 and self:stored_rank(needs[2]) > 0 then
            active[#active + 1] = id
        end
    end
    self._synergy_signature = signature
    self._synergy_cache = active
    return active
end

function Build:offers(rng, filter_branch)
    filter_branch = filter_branch or ""
    local pool, weights, offers = {}, {}, {}
    local total = 0
    for _, id in ipairs(self.unlocked) do
        local entry = Catalog.item(id)
        if entry.name and entry.offer_enabled ~= false and self:stored_rank(id) < Catalog.max_rank(id) and
           (filter_branch == "" or entry.branch == filter_branch) then
            local weight = entry.branch == self.branch and self.branch_weight or 1
            pool[#pool + 1] = id
            weights[#weights + 1] = weight
            total = total + weight
        end
    end
    while #offers < 3 and #pool > 0 do
        local roll = rng:randf() * total
        local index = 1
        for i, weight in ipairs(weights) do
            roll = roll - weight
            if roll <= 0 then
                index = i
                break
            end
        end
        offers[#offers + 1] = table.remove(pool, index)
        total = total - table.remove(weights, index)
    end
    return offers
end

function Build:spend(amount)
    if amount < 0 or amount > self.biomass then
        return false
    end
    self.biomass = self.biomass - amount
    return true
end

function Build:to_dict()
    return {
        organ_capacity = self.organ_capacity,
        extra_organ_cells = self.extra_organ_cells,
        organs = copy(self.organs),
        adaptations = copy(self.adaptations),
        biomass = self.biomass,
        unlocked = copy(self.unlocked),
        branch = self.branch,
        qualities = copy(self.qualities),
        specializations = copy(self.specializations),
        temporary_mutations = copy(self.temporary_mutations),
        stats = copy(self.stats),
    }
end

local function load_ranks(self, source, catalog, target)
    local ids = {}
    for id in pairs(source) do
        if catalog[id] then
            ids[#ids + 1] = id
        end
    end
    -- Godot writes these dictionaries through JSON.stringify with sorted keys.
    table.sort(ids)
    for _, id in ipairs(ids) do
        if self:can_fit(id) then
            target[id] = max(1, min(Catalog.max_rank(id), integer(source[id])))
        end
    end
end

local function load_quality(target, ranks, saved)
    for id in pairs(ranks) do
        target[id] = clamp_grade(saved[id])
    end
end

function Build:from_dict(data)
    data = dictionary(data)
    self.organ_capacity = max(0, integer(data.organ_capacity))
    self.extra_organ_cells = max(0, integer(data.extra_organ_cells))
    self.biomass = max(0, integer(data.biomass))
    self.branch = tostring(data.branch or "predator")
    reset_ranks(self)
    self.unlocked = {}
    for _, entry in ipairs(dictionary(data.unlocked or Catalog.base_unlocked())) do
        local id = tostring(entry)
        if Catalog.item(id).name and not contains(self.unlocked, id) then
            self.unlocked[#self.unlocked + 1] = id
        end
    end
    -- Сохранения старых версий не содержат новый базовый орган хищной формы.
    for _, id in ipairs(Catalog.base_unlocked()) do
        if not contains(self.unlocked, id) then self.unlocked[#self.unlocked + 1] = id end
    end

    load_ranks(self, dictionary(data.organs), Catalog.ORGANS, self.organs)
    load_ranks(self, dictionary(data.adaptations), Catalog.ADAPTATIONS, self.adaptations)
    local saved_qualities = dictionary(data.qualities)
    load_quality(self.qualities, self.organs, saved_qualities)
    load_quality(self.qualities, self.adaptations, saved_qualities)
    local saved_specializations = dictionary(data.specializations)
    for id in pairs(self.organs) do
        local specialization = Catalog.legacy_specialization(id, tostring(saved_specializations[id] or ""))
        if specialization ~= "" then
            self.specializations[id] = specialization
        end
    end
    for _, entry in ipairs(dictionary(data.temporary_mutations)) do
        if #self.temporary_mutations >= 3 then
            break
        end
        if type(entry) == "table" and Catalog.TEMP_MUTATIONS[entry.id] and self:temporary_mutation_rank(entry.id) == 0 then
            self.temporary_mutations[#self.temporary_mutations + 1] = {
                id = entry.id,
                rank = max(1, min(3, integer(entry.rank, 1))),
                quality = clamp_grade(entry.quality),
            }
        end
    end
    local saved_evolutions = dictionary(dictionary(data.stats).evolutions)
    for _, id in ipairs(Catalog.EVOLUTION_IDS) do
        local evolved = saved_evolutions[id]
        if self:rank(id) > 0 and evolved and evolved ~= 0 and evolved ~= "" then
            self.stats.evolutions[id] = true
        end
    end
end

function Build:quality(id)
    return self:stored_rank(id) > 0 and clamp_grade(self.qualities[id]) or 0
end

local function potency(active)
    return (active.rank or 1) * Catalog.quality_multiplier(active.quality or 0)
end

function Build:power(id)
    local quality = Catalog.quality_multiplier(self:quality(id))
    local evolved = self:evolved(id) and 1.30 or 1
    local saved_rank = self:stored_rank(id)
    local specialization = self.specializations[id]
    if (not specialization or specialization == "") and #self.temporary_mutations == 0 and
       (not Catalog.ORGANS[id] or saved_rank <= 10) then
        return quality * evolved
    end

    local mutation = 1
    if specialization and specialization ~= "" then
        local specification = Catalog.specialization_data(id, specialization)
        mutation = specification.power or 1
        if specification.synergy_power then
            for _, synergy_id in ipairs(self:active_synergies()) do
                if contains(Catalog.SYNERGIES[synergy_id].needs, id) then
                    mutation = specification.synergy_power
                    break
                end
            end
        end
    end
    local endless = 1
    if Catalog.ORGANS[id] and saved_rank > 10 then
        endless = 1 + min(0.45, 0.02 * math.log(1 + saved_rank - 10))
    end
    local temporary = 1
    for _, active in ipairs(self.temporary_mutations) do
        local targets = Catalog.temporary_mutation(active.id).power_targets
        if targets and targets[id] then
            temporary = temporary * targets[id] ^ potency(active)
        end
    end
    return quality * mutation * endless * temporary * evolved
end

function Build:specialization_value(id, key, fallback)
    local value = Catalog.specialization_value(id, self.specializations[id], key, fallback)
    for _, active in ipairs(self.temporary_mutations) do
        local groups = Catalog.temporary_mutation(active.id).value_targets
        local targets = groups and groups[id]
        if targets and targets[key] then
            value = value * targets[key] ^ potency(active)
        end
    end
    return value
end

function Build:specialization_bonus(id, key)
    local value = Catalog.specialization_bonus(id, self.specializations[id], key)
    for _, active in ipairs(self.temporary_mutations) do
        local groups = Catalog.temporary_mutation(active.id).bonus_targets
        local targets = groups and groups[id]
        if targets and targets[key] then
            value = value + targets[key] * (active.rank or 1)
        end
    end
    return value
end

function Build:can_apply_temporary_mutation(id, grade)
    if not Catalog.TEMP_MUTATIONS[id] then
        return false
    end
    local rank = self:temporary_mutation_rank(id)
    if rank == 0 then
        return #self.temporary_mutations < 3
    end
    return rank < 3 or self:temporary_mutation_quality(id) < (grade or 0)
end

function Build:apply_temporary_mutation(id, grade)
    if not self:can_apply_temporary_mutation(id, grade) then
        return false
    end
    grade = clamp_grade(grade)
    for _, active in ipairs(self.temporary_mutations) do
        if active.id == id then
            active.rank = min(3, (active.rank or 1) + 1)
            active.quality = max(active.quality or 0, grade)
            return true
        end
    end
    self.temporary_mutations[#self.temporary_mutations + 1] = { id = id, rank = 1, quality = grade }
    return true
end

function Build:temporary_mutation_rank(id)
    for _, active in ipairs(self.temporary_mutations) do
        if active.id == id then
            return active.rank or 1
        end
    end
    return 0
end

function Build:temporary_mutation_quality(id)
    for _, active in ipairs(self.temporary_mutations) do
        if active.id == id then
            return active.quality or 0
        end
    end
    return 0
end

function Build:temporary_passive_bonus(id)
    local total = 0
    for _, active in ipairs(self.temporary_mutations) do
        local bonuses = Catalog.temporary_mutation(active.id).passive_bonuses
        if bonuses and bonuses[id] then
            total = total + bonuses[id] * potency(active)
        end
    end
    return total
end

function Build:passive(id)
    local rank = self:rank(id)
    local multiplier = Catalog.quality_multiplier(self:quality(id))
    if id == "armor" then
        return min(0.60, Catalog.adaptation_bonus(rank) * multiplier + self:temporary_passive_bonus(id))
    elseif id == "speed" then
        return min(0.60, Catalog.adaptation_bonus(rank) * multiplier)
    elseif id == "regen" then
        return 0.5 * rank * multiplier
    elseif id == "magnet" then
        return 55 * rank * multiplier
    elseif id == "metabolism" then
        return 0.06 * rank * multiplier
    elseif id == "catalysis" then
        return 0.08 * rank * multiplier
    end
    return 0
end

function Build:evolved(id)
    return self:stored_rank(id) > 0 and self.stats.evolutions[id] == true
end

function Build:evolution_candidates()
    local candidates = {}
    for _, id in ipairs(Catalog.EVOLUTION_IDS) do
        local recipe = Catalog.EVOLUTIONS[id]
        if not self:evolved(id) and self:rank(id) >= 6 and self:rank(recipe.passive) >= 3 then
            candidates[#candidates + 1] = id
        end
    end
    return candidates
end

function Build:evolve(id)
    if not contains(self:evolution_candidates(), id) then
        return false
    end
    self.stats.evolutions[id] = true
    return true
end

return Build
