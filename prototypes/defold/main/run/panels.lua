local Catalog = require "main.run.catalog"
local Legacy = require "main.run.genome_legacy"
local Rewards = require "main.run.rewards"
local Interface = require "main.run.interface"

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
        ui:surface(x,y,718,286,"panel")
        ui:surface(x,y,710,278,"card")
        ui:box(x,y+123,652,5,accent)
        ui:box(x-352,y,4,222,accent)
        ui:surface(x-288,y+67,96,96,"button")
        if row.icon then
            ui:image("icons","icon_"..row.icon,x-288,y+67,76,76)
        else
            ui:text(x-288,y+67,row.badge or string.format("%02d",(page-1)*PER_PAGE+i),.84,accent,nil,true)
        end
        local title_x=x-225
        ui:fit_text(title_x,y+77,row.title or "",.98,ui.colors.pale,445,63)
        if row.meta then
            ui:surface(title_x+201,y+26,397,36,"button")
            ui:fit_text(title_x,y+26,row.meta,.70,accent,390,32)
        end
        if row.detail then ui:fit_text(x-320,y-30,row.detail,.75,ui.colors.dim,610,70) end
        if row.extra then
            ui:box(x-15,y-72,610,2,Interface.color("294c54"))
            ui:fit_text(x-320,y-101,row.extra,.70,row.extra_color or ui.colors.mint,414,42)
        end
        if row.action then ui:button(x+225,y-101,218,62,row.label or "Открыть",row.action,true,.82) end
    end
    if page>1 then ui:button(cx-285,173,230,62,"Назад",function() open_page(page-1) end) end
    if pages>1 then ui:text(cx,173,page.." / "..pages,.83,ui.colors.dim,nil,true) end
    if page<pages then ui:button(cx+285,173,230,62,"Далее",function() open_page(page+1) end) end
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
        elseif section=="evolutions" then
            local form=data.form and ({predator="Хищная",toxic="Железистая",colony="Колониальная"})[data.form]
            detail=(form and (form.." · ") or "")..title(id).." 6/6 + "..title(data.passive).." 3/3"
        elseif section=="organs" or section=="adaptations" then
            detail=data.signature and (tostring(Catalog.cell_cost(id)).." яч. · гибридный орган") or Catalog.effect_text(id,1)
        end
        local item=Catalog.item(id)
        rows[#rows+1]={id=id,icon=(Catalog.ORGANS[id] or Catalog.ADAPTATIONS[id]) and (item.icon or id) or nil,
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
            local icon=Catalog.item(entry.organ).icon or entry.organ
            ui:image("icons","icon_"..icon,left+193,600,244,244)
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

local RESEARCH_NODES = {
    {"toxic",470,610,"acid"}, {"colony",470,365,"division"},
    {"elastic",1230,610,"speed"}, {"sensory",1230,420,"magnet"}, {"folds",1230,230,"devour"},
    {"memory",1990,610,nil}, {"receptive",1990,365,"magnet"},
}

local function research_tree(app,back)
    local ui,profile=app.modal,app.store.profile
    local legacy=Legacy.normalize(profile)
    app:overlay("legacy_research")
    app.close_current=back
    ui:panel("Наследие генома · исследования",
        string.format("Ядра %d · открытия переходят между поколениями",profile.cores or 0),back,2340)
    local columns={
        {x=470,name="СТРОЕНИЕ",desc="Формы и базовая анатомия",color=Interface.color("65d8bc")},
        {x=1230,name="ПРИСПОСОБЛЕНИЕ",desc="Наследуемые признаки",color=Interface.color("83c9ee")},
        {x=1990,name="ГЕНЕТИЧЕСКАЯ ПАМЯТЬ",desc="Отпечатки и новые ветви",color=Interface.color("c69aef")},
    }
    for _,branch in ipairs(columns) do
        ui:surface(branch.x,801,690,82,"button")
        ui:box(branch.x-331,801,4,54,branch.color)
        ui:text(branch.x-300,814,branch.name,.78,branch.color,590)
        ui:text(branch.x-300,783,branch.desc,.68,ui.colors.dim,590)
    end
    local positions={}
    for _,node in ipairs(RESEARCH_NODES) do positions[node[1]]={x=node[2],y=node[3]} end
    for _,id in ipairs(Legacy.RESEARCH_IDS) do
        local spec=Legacy.RESEARCH[id]
        local child=positions[id]
        for _,required in ipairs(spec.requires) do
            local parent=positions[required]
            if parent and child then
                local dx,dy=child.x-parent.x,child.y-parent.y
                local length=math.sqrt(dx*dx+dy*dy)
                local link=ui:box((child.x+parent.x)/2,(child.y+parent.y)/2,length,4,
                    Interface.color(legacy.research and "35545d" or "35545d"))
                gui.set_rotation(link,vmath.vector3(0,0,-math.deg(math.atan2(dy,dx))))
            end
        end
    end
    for _,node in ipairs(RESEARCH_NODES) do
        local id,x,y,icon=node[1],node[2],node[3],node[4]
        local item=Legacy.RESEARCH[id]
        local progress=Legacy.focus_progress(profile,id)
        local known=false
        for _,owned in ipairs(legacy.research) do if owned==id then known=true;break end end
        local branch=columns[item.branch=="structure" and 1 or item.branch=="adaptation" and 2 or 3]
        local accent=known and ui.colors.mint or progress.ready and ui.colors.gold or branch.color
        ui:surface(x,y,690,160,"panel")
        ui:surface(x,y,682,152,"card")
        ui:box(x-335,y,5,118,accent)
        if icon then ui:image("icons","icon_"..icon,x-279,y+33,62,62)
        else ui:image("collectibles","dna",x-279,y+33,62,62) end
        ui:fit_text(x-228,y+45,item.name,.91,ui.colors.pale,398,50)
        ui:fit_text(x-228,y+6,item.effect,.67,ui.colors.dim,398,42)
        local status
        if known then status="ОТКРЫТО"..(legacy.knowledge[item.branch]>0 and (" · ЗНАНИЕ "..legacy.knowledge[item.branch]) or "")
        elseif #progress.requires>0 then
            local names={}
            for _,required in ipairs(progress.requires) do names[#names+1]=Legacy.RESEARCH[required].name end
            status="НУЖНО · "..table.concat(names,", ")
        elseif not progress.ready then status="НЕ ХВАТАЕТ · "..progress.remaining.." ЯДЕР"
        else status="ГОТОВО К ИССЛЕДОВАНИЮ" end
        ui:fit_text(x-330,y-47,status,.67,accent,340,34)
        local action=known and nil or progress.ready and function()
            if app.store:research(id) then research_tree(app,back) else app:notice(app.store.last_error or "Исследование недоступно") end
        end or nil
        ui:button(x+177,y-49,300,48,known and "Изучено" or ("Изучить · "..progress.cost),action,progress.ready,.70)
    end
end

local UPGRADE_CARDS={
    {id="health",name="Жизнеспособность",atlas="collectibles",frame="heal",value="+5 HP",detail="Максимум здоровья",color=Interface.color("f08f9c")},
    {id="collect",name="Рецепторы",atlas="icons",frame="icon_magnet",value="+8",detail="Радиус обнаружения и притяжения",color=Interface.color("83dce3")},
    {id="regen",name="Регенерация",atlas="icons",frame="icon_regen",value="+0,1 HP/с",detail="Восстановление здоровья",color=Interface.color("85e39c")},
}

local function permanent_upgrades(app,back)
    local ui,profile=app.modal,app.store.profile
    app:overlay("legacy_upgrades")
    app.close_current=back
    ui:panel("Постоянная эволюция",
        string.format("Ядра наследия · %d · усиления действуют в каждом новом забеге",profile.cores or 0),back,2180)
    local selected=app.upgrade_selected or "health"
    local chosen
    for i,item in ipairs(UPGRADE_CARDS) do
        local x=1230+(i-2)*650
        local rank=profile.upgrades[item.id] or 0
        local price=math.min(9007199254740991,4+4*rank)
        local current= item.id=="health" and (100+rank*5).." HP"
            or item.id=="collect" and (rank*8).." ед."
            or string.format("%.1f HP/с",rank*.1):gsub("%.0 HP/с"," HP/с")
        local next_value=item.id=="health" and (100+(rank+1)*5).." HP"
            or item.id=="collect" and ((rank+1)*8).." ед."
            or string.format("%.1f HP/с",(rank+1)*.1):gsub("%.0 HP/с"," HP/с")
        local active=item.id==selected
        if active then chosen={item=item,rank=rank,price=price,current=current,next_value=next_value} end
        local shade=active and item.color or Interface.color("24434b")
        ui:button(x,555,582,560,"",function()
            app.upgrade_selected=item.id
            permanent_upgrades(app,back)
        end,active)
        ui:surface(x,555,576,552,active and "panel" or "card")
        ui:box(x,815,522,4,shade)
        ui:surface(x,713,144,144,"button")
        ui:image(item.atlas,item.frame,x,713,104,104)
        ui:fit_text(x,604,item.name,.99,ui.colors.pale,510,52)
        ui:surface(x,541,202,44,"button")
        ui:fit_text(x,541,("РАНГ %d → %d"):format(rank,rank+1),.78,item.color,188,38)
        ui:surface(x,443,500,112,"button")
        ui:fit_text(x,467,item.detail,.68,ui.colors.dim,450,34)
        ui:fit_text(x,423,current.."  →  "..next_value,.92,item.color,470,50)
        ui:image("collectibles","core",x-145,347,34,34)
        ui:fit_text(x+5,347,"ЦЕНА · "..tostring(price).." ЯДЕР",.76,ui.colors.pale,405,42)
    end
    if chosen then
        local enough=(profile.cores or 0)>=chosen.price
        ui:button(1230,207,680,76,"Усилить · "..chosen.price.." ядер",enough and function()
            if app.store:buy_upgrade(chosen.item.id) then permanent_upgrades(app,back)
            else app:notice(app.store.last_error or "Недостаточно ядер") end
        end or nil,true,1.0)
        ui:text(1230,151,enough and (chosen.current.." → "..chosen.next_value)
            or ("Нужно ещё "..tostring(chosen.price-(profile.cores or 0)).." ядер"),
            .77,enough and chosen.item.color or ui.colors.dim,nil,true)
    end
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
    if section=="research" then research_tree(app,back);return end
    if section=="upgrades" then permanent_upgrades(app,back);return end
    local rows = {}
    local function edit(name,value)
        if store[name](store,value) then open_page(page) else app:notice(store.last_error) end
    end
    if not section then
        ui:panel("Наследие генома",
            string.format("Поколение %d · Ядра %d · Органиум %d",legacy.generation,profile.cores or 0,profile.organium or 0),back,2240)
        local categories={
            {"Форма","form","cells","body_"..(({predator=1,toxic=0,colony=4})[legacy.selected_form] or 1),
                Legacy.FORMS[legacy.selected_form].name.." · стартовый боевой орган",Interface.color("6ce5c1")},
            {"Признаки","trait","icons","icon_speed",#legacy.equipped_traits.." / 2 признака",Interface.color("83cce7")},
            {"Отпечаток","imprint","collectibles","dna",legacy.selected_imprint~="" and Legacy.imprint_name(legacy.selected_imprint) or "Не выбран",Interface.color("c49aef")},
            {"Исследования","research","cells","surge","Дерево постоянных открытий",Interface.color("8fe2d0")},
            {"Органы","equipment","icons","icon_enzymes","Органы тела и семейный запас",Interface.color("e3ca83")},
            {"Наборы","presets","collectibles","core",#legacy.presets.." сохранённых сборок",Interface.color("8fb8ed")},
            {"Постоянные улучшения","upgrades","icons","icon_regen","Усиления для следующих поколений",Interface.color("86e29b")},
        }
        for i,item in ipairs(categories) do
            local column=(i-1)%3
            local row=math.floor((i-1)/3)
            local x=i==7 and 1230 or 520+column*710
            local y=690-row*230
            local callback=item[2]=="equipment" and function() app:inventory(1,false) end
                or function() Panels.legacy(app,item[2],1,back) end
            ui:button(x,y,626,170,"",callback,false)
            ui:surface(x,y,626,170,"card")
            ui:box(x-303,y,5,128,item[6])
            ui:surface(x-222,y,98,98,"button")
            ui:image(item[3],item[4],x-222,y,76,76)
            ui:fit_text(x-147,y+29,item[1],.93,ui.colors.pale,405,54)
            ui:fit_text(x-147,y-25,item[5],.70,item[6],405,48)
        end
        return
    elseif section=="form" then
        for _,id in ipairs(legacy.forms) do
            local entry = Legacy.FORMS[id]
            rows[#rows+1] = {title=entry.name,icon=entry.organ,meta=legacy.selected_form==id and "ТЕКУЩАЯ ФОРМА" or "ФОРМА ТЕЛА",
                detail=entry.passive.name..": "..entry.passive.desc,extra=entry.ability.name,extra_color=Interface.color(entry.ability.color),label=legacy.selected_form==id and "Выбрана" or "Выбрать",
                action=function() edit("select_form",id) end}
        end
    elseif section=="trait" then
        local trait_icons={elastic="speed",sensory="magnet",folds="devour",receptive="infection"}
        for _,id in ipairs(legacy.traits) do
            local entry = Legacy.TRAITS[id]
            local chosen = false
            for _,selected in ipairs(legacy.equipped_traits) do if selected==id then chosen=true end end
            rows[#rows+1] = {title=entry.name,icon=trait_icons[id],meta=chosen and "УСТАНОВЛЕН" or "ДОСТУПЕН",
                detail=entry.desc,extra_color=chosen and ui.colors.mint or ui.colors.dim,
                label=chosen and "Снять" or "Выбрать",action=function() edit("toggle_trait",id) end}
        end
    elseif section=="imprint" then
        local trait_icons={elastic="speed",sensory="magnet",folds="devour",receptive="infection"}
        for _,item in ipairs(legacy.pending) do
            local trait_id=item.id:match("^trait:(.+)$")
            rows[#rows+1] = {title=item.name,icon=Catalog.ORGANS[item.id] and item.id or trait_id and trait_icons[trait_id],
                meta="НОВЫЙ ОТПЕЧАТОК",detail="Ожидает записи",label="Сохранить",action=function() edit("claim_imprint",item.id) end}
        end
        for _,item in ipairs(legacy.imprints) do
            local trait_id=item.id:match("^trait:(.+)$")
            rows[#rows+1] = {title=item.name,icon=Catalog.ORGANS[item.id] and item.id or trait_id and trait_icons[trait_id],
                meta=legacy.selected_imprint==item.id and "АКТИВЕН" or "ДОСТУПЕН ДЛЯ НАСЛЕДИЯ",
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
            rows[#rows+1]={title=entry[2],meta=("РАНГ %d → %d"):format(rank,rank+1),detail="Усиление действует во всех забегах",
                label="Усилить · "..math.min(9007199254740991,4+rank*4),
                action=function() edit("buy_upgrade",id) end}
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
            elseif choice.kind=="evolution" then
                local recipe=Catalog.EVOLUTIONS[id]
                display="Эволюция · "..(recipe and recipe.name or display)
                detail=recipe and recipe.behavior or detail
            elseif choice.kind=="temporary" then display="Временная мутация · "..display end
            local item=Catalog.item(id)
            local icon=(Catalog.ORGANS[id] or Catalog.ADAPTATIONS[id]
                or Catalog.EVOLUTIONS[id]) and (item.icon or id) or (Catalog.TEMP_MUTATIONS[id] or {}).organ
            local image_atlas,image_frame
            if choice.kind=="biomass" then image_atlas,image_frame="collectibles","bio"
            elseif id=="heal" then image_atlas,image_frame="collectibles","heal" end
            items[#items+1] = {id=id,grade=choice.grade or choice.quality or 0,
                title=choice.title or display, icon=icon,image_atlas=image_atlas,image_frame=image_frame,
                rank=choice.rank, detail=detail, meta=choice.meta, rarity=not choice.service and (choice.rarity or Rewards.quality_name(choice.grade or choice.quality or 0)), service=choice.service,
                recommended=choice.recommended, extra=choice.extra, extra_color=choice.extra_color, action=choice.action, sold=choice.sold, data=choice}
        end
    end
    ui:cards(items,y,choose,quality_color,preview)
end

return Panels
