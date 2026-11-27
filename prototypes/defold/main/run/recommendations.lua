local Catalog = require "main.run.catalog"
local M = {}

-- Рекомендация не меняет пул, порядок и доступность наград.
function M.score(build, form, item)
    local id, kind = item.id, item.kind or "mutation"
    local signature = Catalog.signature_organ(form)
    if kind == "biomass" then return 0 end
    if kind == "evolution" then
        if id == signature then return 120, "Высшая эволюция твоей формы" end
        return 65, "Развитие установленного органа"
    end
    if kind == "temporary" then
        local data = Catalog.temporary_mutation(id)
        local count = 0
        for target in pairs(data.power_targets or {}) do
            if build:stored_rank(target)>0 then count=count+1 end
        end
        if count>0 then return 48+count*8, "Усиливает установленные органы" end
        if next(data.passive_bonuses or {}) then return 25, "Повышает выживаемость" end
        return 0
    end
    local organ = Catalog.ORGANS[id]
    if not organ and not Catalog.ADAPTATIONS[id] then return 0 end
    local rank=build:stored_rank(id)
    local grade=item.grade or item.quality or 0
    if rank>=Catalog.max_rank(id) and grade<=build:quality(id) then return 0 end
    -- Не советовать новичку замену существующих органов или адаптаций.
    if not build:can_fit(id,"") then return 0 end
    local score, reason = 0, nil
    if organ and organ.branch==form then
        score,reason=60,"Подходит твоей форме"
        if id==signature then
            local partner = ({predator="devour",toxic="acid",colony="division"})[form]
            if partner and build:stored_rank(partner)>0 then score,reason=90,"Орган твоей формы"
            else score,reason=45,"Орган твоей формы" end
        end
    elseif id=="armor" or id=="regen" or id=="speed" then score,reason=30,"Повышает выживаемость" end
    if rank>0 then
        score=math.max(score,40)+10
        if not reason then reason="Усиливает установленный орган" end
        if organ and build.specializations and Catalog.has_specialization(id,build.specializations[id]) then
            score=score+8
            if score<90 then reason="Усиливает специализированный орган" end
        end
    end
    for _, sid in ipairs(Catalog.SYNERGY_IDS) do
        local synergy=Catalog.SYNERGIES[sid]
        local a,b=synergy.needs[1],synergy.needs[2]
        local partner=id==a and b or id==b and a or nil
        if partner and build:stored_rank(partner)>0 then
            local usable = true
            if sid=="shared_shell" then usable=build:stored_rank("division")>0 end
            if sid=="enzyme_target" then usable=build:stored_rank("devour")>0 end
            if sid=="acid_bite" then usable=build:stored_rank("acid")>0 or build:stored_rank("infection")>0 or build:stored_rank("trail")>0 end
            if usable then
                if rank==0 then score=math.max(score,64)+22;reason="Откроет синергию: "..synergy.name
                else score=score+6 end
            end
        end
    end
    if score>0 then score=score+math.min(3,grade) end
    return score,reason
end

function M.mark(build,form,choices)
    local best, best_score, reason=nil,0,nil
    for _,item in ipairs(choices) do
        item.recommended=nil
        item.recommendation=nil
        local score,why=M.score(build,form,item)
        if score>best_score then best,best_score,reason=item,score,why end
    end
    if best then best.recommended=true;best.recommendation=reason end
    return best
end
return M
