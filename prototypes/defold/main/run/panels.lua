local Catalog = require "main.run.catalog"
local Legacy = require "main.run.genome_legacy"
local Rewards = require "main.run.rewards"

local Panels = {}
local PER_PAGE = 4
local cx = 1230

local function title(id)
    local item = Catalog.item(id)
    return item and item.name or id
end

local function quality_color(item)
    local hex = Rewards.quality_color(item.grade or item.quality or 0)
    local rgb = tonumber(hex:gsub("#",""),16)
    return vmath.vector4(math.floor(rgb/65536)/255,math.floor(rgb/256)%256/255,rgb%256/255,1)
end

function Panels.list(ui,heading,subtext,rows,page,open_page,leave)
    ui:panel(heading,subtext,leave)
    local pages = math.max(1,math.ceil(#rows/PER_PAGE))
    page = math.min(page or 1,pages)
    if #rows == 0 then
        ui:surface(cx,550,790,245,"card")
        ui:text(cx,550,"Пока пусто",1.13,ui.colors.dim,nil,true)
    end
    for i=1,PER_PAGE do
        local row = rows[(page-1)*PER_PAGE+i]
        if not row then break end
        local column=(i-1)%2
        local line=math.floor((i-1)/2)
        local x=cx+(column==0 and -367 or 367)
        local y=line==0 and 680 or 374
        local accent=row.color or ui.colors.mint
        ui:surface(x,y,710,278,"card")
        ui:box(x,y+123,646,5,accent)
        ui:surface(x-288,y+71,92,92,"button")
        if row.icon then
            ui:image("icons","icon_"..row.icon,x-288,y+71,72,72)
        else
            ui:text(x-288,y+71,row.badge or tostring((page-1)*PER_PAGE+i),.78,accent,nil,true)
        end
        local title_x=x-225
        ui:fit_text(title_x,y+77,row.title or "",.98,ui.colors.pale,445,63)
        if row.meta then ui:fit_text(title_x,y+28,row.meta,.73,accent,445,40) end
        if row.detail then ui:fit_text(x-320,y-35,row.detail,.76,ui.colors.dim,610,78) end
        if row.extra then ui:fit_text(x-320,y-83,row.extra,.72,row.extra_color or ui.colors.mint,420,45) end
        if row.action then ui:button(x+225,y-101,210,58,row.label or "Открыть",row.action,true,.82) end
    end
    if page>1 then ui:button(cx-285,173,230,62,"‹ Назад",function() open_page(page-1) end) end
    if pages>1 then ui:text(cx,173,page.." / "..pages,.83,ui.colors.dim,nil,true) end
    if page<pages then ui:button(cx+285,173,230,62,"Далее ›",function() open_page(page+1) end) end
end

local CATEGORIES={
    {"Органы","organs"},{"Адаптации","adaptations"},{"Временные мутации","temporary"},
    {"Синергии","synergies"},{"Специализации","specializations"},{"Эволюции","evolutions"},
}

local function entries(section)
    local rows={}
    local ids=({organs=Catalog.ORGAN_IDS,adaptations=Catalog.ADAPTATION_IDS,
        temporary=Catalog.TEMP_MUTATION_IDS,synergies=Catalog.SYNERGY_IDS,evolutions=Catalog.EVOLUTION_IDS})[section]
    if section=="specializations" then
        for _,id in ipairs(Catalog.ORGAN_IDS) do
            for _,item in ipairs(Catalog.SPECIALIZATIONS[id] or {}) do
                rows[#rows+1]={id=item.id,organ=id,title=item.name,detail=title(id),desc=item.desc}
            end
        end
        return rows
    end
    for _,id in ipairs(ids or {}) do
        local data=section=="synergies" and Catalog.SYNERGIES[id]
            or section=="temporary" and Catalog.TEMP_MUTATIONS[id]
            or section=="evolutions" and Catalog.EVOLUTIONS[id]
            or Catalog.item(id)
        local detail=data.summary or ""
        if section=="synergies" then detail=title(data.needs[1]).." + "..title(data.needs[2])
        elseif section=="evolutions" then detail=title(id).." 6/6 + "..title(data.passive).." 3/3"
        elseif section=="organs" or section=="adaptations" then detail=Catalog.effect_text(id,1) end
        rows[#rows+1]={id=id,icon=(Catalog.ORGANS[id] or Catalog.ADAPTATIONS[id]) and id or nil,
            organ=section=="temporary" and data.organ or id,title=data.name,
            detail=detail,desc=data.desc or data.summary or detail}
    end
    return rows
end

function Panels.catalog(app,section,page,leave,selected)
    local ui=app.modal
    local back=leave or function() app:show_home() end
    app:overlay("codex")
    app.close_current=back
    if not section then
        ui:panel("Кодекс","Подробности органов и взаимодействий",back,1275)
        for i,category in ipairs(CATEGORIES) do
            local x=1230+((i-1)%2==0 and -303 or 303)
            local y=764-math.floor((i-1)/2)*139
            ui:button(x,y,572,114,category[1].." · "..#entries(category[2]),function()
                Panels.catalog(app,category[2],1,back)
            end,true,.87)
        end
        ui:button(1230,237,1160,75,"Назад",back)
        return
    end
    local rows=entries(section)
    local function open(entry)
        app:overlay("codex_entry")
        local close=selected and back or function() Panels.catalog(app,section,page,back) end
        app.close_current=close
        local left=ui:panel(entry.title,entry.detail,close,1545)
        if Catalog.ORGANS[entry.organ] or Catalog.ADAPTATIONS[entry.organ] then
            ui:image("icons","icon_"..entry.organ,left+193,600,244,244)
        end
        ui:text(left+361,638,entry.desc,1.02,ui.colors.pale,1110)
        ui:button(1230,206,1480,75,"Назад",close)
    end
    local caption="Кодекс"
    for _,category in ipairs(CATEGORIES) do
        if category[2]==section then caption=category[1];break end
    end
    for _,entry in ipairs(rows) do
        if entry.id==selected then open(entry);return end
        entry.action=function() open(entry) end
    end
    local function close() Panels.catalog(app,nil,nil,back) end
    app.close_current=close
    Panels.list(ui,caption,"Выбери запись для подробного описания",rows,page,
        function(p) Panels.catalog(app,section,p,back) end,close)
end

function Panels.legacy(app,section,page,leave)
    local ui, store = app.modal,app.store
    local profile = store.profile
    local legacy = Legacy.normalize(profile)
    app:overlay("legacy")
    local back=leave or function() app:show_home() end
    app.close_current=back
    local function root() Panels.legacy(app,nil,nil,back) end
    local function open_page(p) Panels.legacy(app,section,p,back) end
    local rows = {}
    local function edit(name,value)
        if store[name](store,value) then open_page(page) else app:notice(store.last_error) end
    end
    if not section then
        ui:panel("Наследие генома",
            string.format("Поколение %d  ·  Ядра %d  ·  Органиум %d",legacy.generation,profile.cores or 0,profile.organium or 0),
            back)
        local names = {{"Форма","form"},{"Признаки","trait"},{"Отпечатки","imprint"},
            {"Исследования","research"},{"Органы","equipment"},{"Наборы","presets"},{"Улучшения","upgrades"}}
        for i,item in ipairs(names) do
            local x,y = 1230+((i-1)%3-1)*440,675-math.floor((i-1)/3)*148
            if i==7 then x=1230 end
            ui:button(x,y,392,100,item[1],function()
                if item[2]=="equipment" then app:inventory(1,false) else Panels.legacy(app,item[2],1,back) end
            end)
        end
        return
    elseif section=="form" then
        for _,id in ipairs(legacy.forms) do
            local entry = Legacy.FORMS[id]
            rows[#rows+1] = {title=entry.name,meta=legacy.selected_form==id and "ТЕКУЩАЯ ФОРМА" or "ФОРМА ТЕЛА",
                detail=entry.desc,label=legacy.selected_form==id and "Выбрана" or "Выбрать",
                action=function() edit("select_form",id) end}
        end
    elseif section=="trait" then
        for _,id in ipairs(legacy.traits) do
            local entry = Legacy.TRAITS[id]
            local chosen = false
            for _,selected in ipairs(legacy.equipped_traits) do if selected==id then chosen=true end end
            rows[#rows+1] = {title=entry.name,meta=chosen and "УСТАНОВЛЕН" or "ДОСТУПЕН",
                detail=entry.desc,extra_color=chosen and ui.colors.mint or ui.colors.dim,
                label=chosen and "Снять" or "Выбрать",action=function() edit("toggle_trait",id) end}
        end
    elseif section=="imprint" then
        for _,item in ipairs(legacy.pending) do
            rows[#rows+1] = {title=item.name,meta="НОВЫЙ ОТПЕЧАТОК",detail="Ожидает записи",label="Сохранить",action=function() edit("claim_imprint",item.id) end}
        end
        for _,item in ipairs(legacy.imprints) do
            rows[#rows+1] = {title=item.name,meta=legacy.selected_imprint==item.id and "АКТИВЕН" or "ДОСТУПЕН ДЛЯ НАСЛЕДИЯ",
                detail=item.desc or "Наследуемая особенность",
                label="Выбрать", action=function() edit("select_imprint",item.id) end}
        end
    elseif section=="research" then
        local ids = {}
        for id in pairs(Legacy.RESEARCH) do ids[#ids+1]=id end
        table.sort(ids)
        for _,id in ipairs(ids) do
            local item = Legacy.RESEARCH[id]
            rows[#rows+1] = {title=item.name,meta="СТОИМОСТЬ · "..item.cost.." ЯДЕР",detail=item.effect,
                action=function() edit("research",id) end}
        end
    elseif section=="upgrades" then
        for _,entry in ipairs({{"health","Здоровье"},{"collect","Рецепторы"},{"regen","Регенерация"}}) do
            local id=entry[1]
            local rank=profile.upgrades[id] or 0
            rows[#rows+1]={title=entry[2],meta=("РАНГ %d / 5"):format(rank),detail="Усиление действует во всех забегах",
                label=rank==5 and "Предел" or ("Усилить · "..(4+rank*4)),
                action=function() if rank<5 then edit("buy_upgrade",id) end end}
        end
    elseif section=="presets" then
        rows[1] = {title="Текущий набор",label="Записать",action=function() edit("save_preset","Набор "..(#legacy.presets+1)) end}
        for i,item in ipairs(legacy.presets) do
            rows[#rows+1] = {title=item.name or ("Набор "..i),label="Применить",action=function() edit("load_preset",i) end}
        end
    end
    local names = {form="Форма",trait="Признаки",imprint="Отпечатки",research="Исследования",equipment="Организм",presets="Наборы",upgrades="Постоянные улучшения"}
    Panels.list(ui,names[section],nil,rows,page,open_page,root)
end

function Panels.offer_cards(ui,choices,y,choose,preview)
    local items = {}
    for _,raw in ipairs(choices) do
        local choice = type(raw)=="string" and {id=raw} or raw
        local id = choice.id or choice.kind or choice.organ
        local rank = choice.rank or 1
        if id then
            local item = Catalog.item(id)
            if not item.name then item=Catalog.temporary_mutation(id) end
            local display = item.name or id
            local detail = choice.detail or item.summary or Catalog.effect_text(id,rank)
            if choice.kind=="biomass" then display,detail="Биомасса","+"..choice.amount
            elseif choice.kind=="evolution" then display="Эволюция · "..display
            elseif choice.kind=="temporary" then display="Временная мутация · "..display end
            items[#items+1] = {id=id,grade=choice.grade or choice.quality or 0,
                title=choice.title or display, icon=(Catalog.ORGANS[id] or Catalog.ADAPTATIONS[id]) and id or nil,
                rank=choice.rank, detail=detail, meta=choice.meta, rarity=choice.rarity or Rewards.quality_name(choice.grade or choice.quality or 0),
                extra=choice.extra, extra_color=choice.extra_color, action=choice.action, sold=choice.sold, data=choice}
        end
    end
    ui:cards(items,y,choose,quality_color,preview)
end

return Panels
