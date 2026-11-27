local Simulation = require "main.run.simulation"
local Catalog = require "main.run.catalog"
local Build = require "main.run.build_model"
local Legacy = require "main.run.genome_legacy"
local Size = require "main.run.size_rules"
local SaveStore = require "main.run.save_store"
local StageRewards = require "main.run.stage_rewards"
local Util = require "main.run.meta_util"
local Effects = require "main.run.effects_view"

local M = {}
local STEP = 1 / 60
local HORIZON_SECONDS = 600
-- Одинаковые карты для всех форм: сравнение без подмены географии.
local SEEDS = {147, 171, 247, 271, 347, 371}
local BRANCHES = {
    {form = "predator", starter = "devour"},
    {form = "toxic", starter = "acid"},
    {form = "colony", starter = "division"},
}
local HYBRID_SEEDS = {147, 247, 347}
local SPECIALIZATION_SEEDS = {147, 347}
local HYBRID_SCENARIOS = {
    {form="predator",starter="devour",name="acid_bite",
        seed_organs={chemoreceptor_ridge=6,devour=3,tentacle=2,osmotic_vacuole=2,acid=2},
        seed_adaptations={magnet=3,armor=2,regen=2},evolve=true,
        expected_synergies={"acid_bite"}},
    {form="toxic",starter="acid",name="enzyme_target",
        seed_organs={chemoreceptor_ridge=2,enzymes=2,devour=2},
        seed_marked_target=true,expected_synergies={"enzyme_target"}},
    {form="toxic",starter="acid",name="shared_shell",
        seed_organs={synaptic_node=2,division=3,barrier=2},expected_synergies={"shared_shell"}},
}
local EVOLUTION_SCENARIOS = {
    {form="predator",starter="devour",name="apex_predator",
        seed_organs={chemoreceptor_ridge=6,devour=3,tentacle=2},
        seed_adaptations={magnet=3,armor=2,regen=2}},
    {form="toxic",starter="acid",name="living_reactor",
        seed_organs={osmotic_vacuole=6,acid=3,infection=2},
        seed_adaptations={catalysis=3,armor=2,regen=2}},
    {form="colony",starter="division",name="collective_mind",
        seed_organs={synaptic_node=6,division=4,barrier=2},
        seed_adaptations={armor=3,regen=2}},
}
local DIRECTIONS = {
    {1, 0}, {0.70710678, 0.70710678}, {0, 1}, {-0.70710678, 0.70710678},
    {-1, 0}, {-0.70710678, -0.70710678}, {0, -1}, {0.70710678, -0.70710678},
}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local PILOT_PRIORITY = {
    predator = { chemoreceptor_ridge = 98, devour = 120, tentacle = 115, spikes = 110, cilia = 100, pulse = 95, acid = 60 },
    toxic = { osmotic_vacuole = 98, acid = 120, infection = 115, enzymes = 110, trail = 100, electric = 70, barrier = 80 },
    colony = { synaptic_node = 98, division = 120, electric = 115, barrier = 110, pulse = 95, spikes = 80 },
}

local function mutation_priority(sim, id)
    local branch = PILOT_PRIORITY[sim.build.branch] or {}
    local priority = branch[id] or 35
    if sim.build:rank(id) > 0 then priority = priority + 12 end
    if id == "regen" then return 105 end
    if id == "armor" then return 90 end
    if id == "speed" then return 78 end
    if id == "catalysis" and sim.build:used_organ_cells() > 0 then return 88 end
    if id == "magnet" then return 18 end
    return priority
end

local function settle_levels(sim)
    while sim.pending_levels > 0 do
        local offers = sim:prepare_offers()
        table.sort(offers, function(a, b)
            local score_a, score_b = mutation_priority(sim, a), mutation_priority(sim, b)
            if score_a == score_b then return a < b end
            return score_a > score_b
        end)
        local selected = false
        for _, id in ipairs(offers) do
            if sim:choose_mutation(id) then
                selected = true
                break
            end
        end
        if not selected then
            if not sim:take_level_biomass() then sim:commit_level_pick() end
        end
    end
end

local function settle_rewards(sim)
    local attempts = 0
    while #sim.reward_queue > 0 and attempts < 16 do
        attempts = attempts + 1
        local options = sim:prepare_reward()
        local claimed = false
        for index = 1, #options do
            if sim:claim_reward(index) then
                claimed = true
                break
            end
        end
        if not claimed then break end
    end
end

local function settle_stage(sim)
    if not sim.stage_transition then return end
    if sim.boss_reward and sim.boss_reward.organ then
        local claimed = sim:claim_boss_reward()
        if not claimed then
            for _, id in ipairs(Catalog.ORGAN_IDS) do
                if sim.build:rank(id) > 0 and sim:claim_boss_reward(id) then
                    claimed = true
                    break
                end
            end
        end
    end
    assert(sim:enter_next_stage(), "Balance run could not enter the next stage")
end

local colony_direction

local function direction(sim, tick)
    if sim.run_loadout.form=="colony" then
        local x,y=colony_direction(sim,tick)
        if x then return x,y end
    end
    local player, radius = sim.player, sim:body_radius()
    local colony_pilot=sim.run_loadout.form=="colony"
    local toxic_pilot=sim.run_loadout.form=="toxic"
    local cautious_pilot=colony_pilot or toxic_pilot
    local threat_radius=colony_pilot and 500 or (toxic_pilot and 480 or 380)
    local danger_radius=colony_pilot and 650 or (toxic_pilot and 620 or 520)
    local away_x, away_y, nearest_target, target_score = 0, 0, nil, math.huge
    for _, enemy in ipairs(sim.enemies) do
        if enemy.hp > 0 and not enemy.captured then
            local dx, dy = player.x - enemy.pos.x, player.y - enemy.pos.y
            local distance = math.sqrt(dx * dx + dy * dy)
            local edible = enemy.kind == "prey" or
                (enemy.r <= radius * 1.2 and sim:interaction(enemy).eligible)
            if edible then
                local cost = distance + (enemy.kind == "prey" and 0 or 80)
                if cost < target_score then nearest_target, target_score = enemy, cost end
            elseif distance < threat_radius then
                local weight = (threat_radius - distance) / threat_radius / math.max(40, distance)
                away_x, away_y = away_x + dx * weight, away_y + dy * weight
            end
        end
    end
    if sim.elapsed >= 8 then
        for _, resident in ipairs(sim.residents) do
            if not resident.dead and not resident.active then
                local dx, dy = player.x - resident.pos.x, player.y - resident.pos.y
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance < threat_radius then
                    local weight = (threat_radius - distance) / threat_radius / math.max(40, distance)
                    away_x, away_y = away_x + dx * weight, away_y + dy * weight
                end
            end
        end
    end

    local away_length = math.sqrt(away_x * away_x + away_y * away_y)
    local desired_x, desired_y
    if away_length > 0.0001 then
        desired_x, desired_y = away_x / away_length, away_y / away_length
    elseif nearest_target then
        local dx, dy = nearest_target.pos.x - player.x, nearest_target.pos.y - player.y
        local distance = math.max(0.0001, math.sqrt(dx * dx + dy * dy))
        if toxic_pilot and nearest_target.kind ~= "prey" then
            -- Токсичная форма наносит урон кислотной аурой: держим безопасный
            -- радиус вместо бесполезного сближения до столкновения.
            local acid_reach=(75+sim.build:rank("acid")*9)
                *sim.build:specialization_value("acid","radius_mult")*sim:ability_scale()
            local safe=nearest_target.r+radius*.75+28
            local desired_range=math.max(safe,acid_reach*.78)
            local radial=math.max(-1,math.min(1,(distance-desired_range)/36))
            local tangent=math.abs(distance-desired_range)<24 and .32 or 0
            local ux,uy=dx/distance,dy/distance
            desired_x,desired_y=ux*radial-uy*tangent,uy*radial+ux*tangent
        else
            desired_x, desired_y = dx / distance, dy / distance
        end
    else
        local roam = DIRECTIONS[math.floor(sim.elapsed / 12) % #DIRECTIONS + 1]
        desired_x, desired_y = roam[1], roam[2]
    end

    local best_x, best_y, best_score = desired_x, desired_y, -math.huge
    local step_distance = math.max(16, 85 * STEP * 2)
    for _, candidate in ipairs(DIRECTIONS) do
        local nx, ny = player.x + candidate[1] * step_distance, player.y + candidate[2] * step_distance
        local score = candidate[1] * desired_x + candidate[2] * desired_y
        if not sim.world:walkable(nx, ny, math.min(26, radius * 0.65)) then
            score = score - 100
        end
        for _, enemy in ipairs(sim.enemies) do
            if enemy.hp > 0 and not enemy.captured and enemy.kind ~= "prey" then
                local current_x, current_y = player.x - enemy.pos.x, player.y - enemy.pos.y
                local next_x, next_y = nx - enemy.pos.x, ny - enemy.pos.y
                local current_distance = math.sqrt(current_x * current_x + current_y * current_y)
                local next_distance = math.sqrt(next_x * next_x + next_y * next_y)
                if current_distance < danger_radius or next_distance < danger_radius then
                    local clearance = enemy.r + radius * 0.75 + (colony_pilot and 115 or (toxic_pilot and 90 or 65))
                    local separation_weight=colony_pilot and 0.045 or (toxic_pilot and 0.035 or 0.025)
                    local collision_weight=colony_pilot and 0.055 or (toxic_pilot and 0.045 or 0.03)
                    score = score + (next_distance - current_distance) * separation_weight
                        - math.max(0, clearance - next_distance) * collision_weight
                end
            end
        end
        for _, field in ipairs(sim.fields) do
            if field.hostile then
                local fx, fy = nx - field.pos.x, ny - field.pos.y
                local distance = math.sqrt(fx * fx + fy * fy)
                local clearance = field.r + radius * 0.65 + (colony_pilot and 90 or 60)
                score = score - math.max(0, clearance - distance) * (colony_pilot and 0.04 or 0.025)
            end
        end
        for _, colony in ipairs(sim.world.colonies) do
            local cx, cy = nx - colony.pos.x, ny - colony.pos.y
            if cx * cx + cy * cy < 150 * 150 then score = score + 0.08 end
        end
        if score > best_score then best_x, best_y, best_score = candidate[1], candidate[2], score end
    end
    return best_x, best_y
end

-- Маршрутный пилот используется только в отдельной матрице прохождения.
-- Поиск пути по сетке мира; никакого изменения координат или здоровья объектов.
local function route_waypoint(world, from, goal, clearance, cache)
    local tile=world.tile_size
    local w,h=world.w,world.h
    local function cell(p)
        local x,y=math.floor(p.x/tile),math.floor(p.y/tile)
        if x<0 or y<0 or x>=w or y>=h then return nil end
        return y*w+x+1
    end
    local function center(i)
        return {x=((i-1)%w+.5)*tile,y=(math.floor((i-1)/w)+.5)*tile}
    end
    local start,finish=cell(from),cell(goal)
    if not start or not finish then return nil end
    if start==finish then return goal end
    if cache.world==world and cache.start==start and cache.finish==finish and cache.clearance==clearance then
        return cache.next
    end
    local queue,seen,first={start},{[start]=true},{}
    local head=1
    local next_point
    while head<=#queue do
        local current=queue[head];head=head+1
        if current==finish then next_point=center(first[current]);break end
        local x,y=(current-1)%w,math.floor((current-1)/w)
        for _,delta in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
            local nx,ny=x+delta[1],y+delta[2]
            local id=ny*w+nx+1
            if nx>=0 and ny>=0 and nx<w and ny<h and not seen[id] then
                seen[id]=true
                local p=center(id)
                if world:walkable(p.x,p.y,clearance) then
                    first[id]=first[current] or id
                    queue[#queue+1]=id
                end
            end
        end
    end
    cache.world,cache.start,cache.finish,cache.clearance,cache.next=world,start,finish,clearance,next_point
    return next_point
end

local function distance(a,b)
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end

local function colony_attack_target(sim)
    local radius=sim:body_radius()
    local health=sim.hp/math.max(1,sim.max_hp)
    local best,best_score
    for _,enemy in ipairs(sim.enemies) do
        if enemy.hp>0 and not enemy.captured and enemy.kind~="prey" then
            local ratio=enemy.r/math.max(1,radius)
            local giant=enemy.kind=="boss" or ratio>=1.6
            local vulnerable=enemy.fractured or (enemy.enzyme_time or 0)>0
                or (enemy.boss_exposed or 0)>0
            local critical_large=health<.42 and ratio>1.08 and not vulnerable
            if (not giant or vulnerable) and not critical_large then
                local d=distance(sim.player,enemy.pos)
                -- Сначала выбираем небольшие цели, чтобы не входить в контакт с крупными амёбами.
                local size_penalty=ratio>1.08 and (220+(ratio-1.08)*180) or 0
                if health<.55 and ratio>1.08 then size_penalty=size_penalty+150 end
                local score=d+size_penalty-(enemy.kind=="miniboss" and 55 or 0)
                if not best or score<best_score then best,best_score=enemy,score end
            end
        end
    end
    return best
end

local function colony_attack_range(sim,enemy)
    local radius=sim:body_radius()
    return math.max(enemy.r+radius*.75+40,enemy.r+111)
end

colony_direction=function(sim,tick)
    local target=colony_attack_target(sim)
    local health=sim.hp/math.max(1,sim.max_hp)
    if health<.68 then
        local heal,best_distance
        for _,item in ipairs(sim.pickups) do
            if item.type=="heal" and not item.captured and item.pos then
                local d=distance(sim.player,item.pos)
                if not heal or d<best_distance then heal,best_distance=item,d end
            end
        end
        -- При критическом здоровье колония сначала восстанавливается,
        -- даже если рядом остаётся доступная для копий цель.
        if heal then target=nil end
    end
    local player,radius=sim.player,sim:body_radius()
    if not target then
        -- Если все противники слишком велики для копий, не отдаём управление
        -- общему автопилоту: тот мог выбирать сближение с добычей прямо под телами врагов.
        local health=sim.hp/math.max(1,sim.max_hp)
        local supply
        local best_supply_distance=math.huge
        for _,item in ipairs(sim.pickups) do
            if not item.captured and item.pos and
                ((health<.82 and item.type=="heal") or (sim.level<6 and item.type=="dna")) then
                local d=distance(player,item.pos)
                if d<best_supply_distance then supply,best_supply_distance=item,d end
            end
        end
        local dx,dy=0,0
        if supply then
            dx,dy=supply.pos.x-player.x,supply.pos.y-player.y
        else
            for _,enemy in ipairs(sim.enemies) do
                if enemy.hp>0 and not enemy.captured and enemy.kind~="prey" then
                    local ex,ey=player.x-enemy.pos.x,player.y-enemy.pos.y
                    local d=math.max(40,math.sqrt(ex*ex+ey*ey))
                    local weight=1/(d*d)
                    dx,dy=dx+ex*weight,dy+ey*weight
                end
            end
            for _,resident in ipairs(sim.residents) do
                if not resident.dead and not resident.active then
                    local ex,ey=player.x-resident.pos.x,player.y-resident.pos.y
                    local d=math.max(40,math.sqrt(ex*ex+ey*ey))
                    local weight=1/(d*d)
                    dx,dy=dx+ex*weight,dy+ey*weight
                end
            end
            if dx*dx+dy*dy<.000001 then
                local roam=DIRECTIONS[math.floor(sim.elapsed/8)%#DIRECTIONS+1]
                dx,dy=roam[1],roam[2]
            end
        end
        local length=math.max(.001,math.sqrt(dx*dx+dy*dy))
        dx,dy=dx/length,dy/length
        local best_x,best_y,best_score=0,0,-math.huge
        local step_distance=math.max(16,85*STEP*2)
        for _,candidate in ipairs(DIRECTIONS) do
            local nx,ny=player.x+candidate[1]*step_distance,player.y+candidate[2]*step_distance
            local score=candidate[1]*dx+candidate[2]*dy
            if not sim.world:walkable(nx,ny,math.min(26,radius*.65)) then score=score-100 end
            for _,enemy in ipairs(sim.enemies) do
                if enemy.hp>0 and not enemy.captured and enemy.kind~="prey" then
                    local current=distance(player,enemy.pos)
                    local next_d=distance({x=nx,y=ny},enemy.pos)
                    local safe=enemy.r+radius*.75+150
                    score=score+(next_d-current)*.12-math.max(0,safe-next_d)*.09
                end
            end
            for _,field in ipairs(sim.fields) do
                if field.hostile then
                    local next_d=distance({x=nx,y=ny},field.pos)
                    score=score-math.max(0,field.r+radius*.65+100-next_d)*.06
                end
            end
            if score>best_score then best_x,best_y,best_score=candidate[1],candidate[2],score end
        end
        return best_x,best_y
    end
    local d=math.max(.001,distance(player,target.pos))
    local range=colony_attack_range(sim,target)
    local ux,uy=(target.pos.x-player.x)/d,(target.pos.y-player.y)/d
    local error=d-range
    local radial=math.max(-1,math.min(1,error/48))
    local tangent=.28
    if math.abs(error)<24 then radial=0;tangent=.72 end
    local desired_x,desired_y=ux*radial-uy*tangent,uy*radial+ux*tangent
    local length=math.sqrt(desired_x*desired_x+desired_y*desired_y)
    if length>.001 then desired_x,desired_y=desired_x/length,desired_y/length end

    local best_x,best_y,best_score=0,0,-math.huge
    local step_distance=math.max(16,85*STEP*2)
    for _,candidate in ipairs(DIRECTIONS) do
        local nx,ny=player.x+candidate[1]*step_distance,player.y+candidate[2]*step_distance
        local next_pos={x=nx,y=ny}
        local next_distance=distance(next_pos,target.pos)
        local score=candidate[1]*desired_x+candidate[2]*desired_y
        score=score-math.abs(next_distance-range)*.0015
        score=score-math.max(0,target.r+radius*.75+40-next_distance)*.16
        if not sim.world:walkable(nx,ny,math.min(26,radius*.65)) then score=score-100 end
        for _,other in ipairs(sim.enemies) do
            if other~=target and other.hp>0 and not other.captured and other.kind~="prey" then
                local current=distance(player,other.pos)
                local next_enemy=distance(next_pos,other.pos)
                local safe=other.r+radius*.75+115
                score=score+(next_enemy-current)*.045-math.max(0,safe-next_enemy)*.055
            end
        end
        if sim.elapsed>=8 then
            for _,resident in ipairs(sim.residents) do
                if not resident.dead and not resident.active then
                    local safe=resident.r+radius+65
                    score=score-math.max(0,safe-distance(next_pos,resident.pos))*.045
                end
            end
        end
        for _,field in ipairs(sim.fields) do
            if field.hostile then
                local safe=field.r+radius*.65+90
                score=score-math.max(0,safe-distance(next_pos,field.pos))*.04
            end
        end
        for _,colony in ipairs(sim.world.colonies) do
            if distance(next_pos,colony.pos)<150 then score=score+.08 end
        end
        for _,shot in ipairs(sim.shots) do
            if shot.hostile then
                local vx,vy=shot.vel.x,shot.vel.y
                local speed2=vx*vx+vy*vy
                if speed2>1 then
                    local t=math.max(0,math.min(.65,((nx-shot.pos.x)*vx+(ny-shot.pos.y)*vy)/speed2))
                    local sx,sy=shot.pos.x+vx*t,shot.pos.y+vy*t
                    local separation=math.sqrt((nx-sx)^2+(ny-sy)^2)
                    score=score-math.max(0,radius*.78+22-separation)*.10
                end
            end
        end
        if score>best_score then best_x,best_y,best_score=candidate[1],candidate[2],score end
    end
    return best_x,best_y
end

local function progression_supply_target(sim)
    local health=sim.hp/math.max(1,sim.max_hp)
    local function nearest(kind,limit)
        local best,best_distance
        for _,item in ipairs(sim.pickups) do
            if item.type==kind and not item.captured and item.pos then
                local d=distance(sim.player,item.pos)
                if d<=limit and (not best or d<best_distance) then best,best_distance=item,d end
            end
        end
        return best
    end
    if health<.78 then
        local heal=nearest("heal",620)
        if heal then return heal.pos,nil,"supply_heal" end
    end
    if sim.level<5 then
        local dna=nearest("dna",380)
        if dna then return dna.pos,nil,"supply_dna" end
    end
end

local function progression_target(sim)
    local best,best_d
    for _,enemy in ipairs(sim.enemies) do
        if enemy.hp>0 and not enemy.captured and (enemy.kind=="boss" or enemy.kind=="miniboss") then
            local d=distance(sim.player,enemy.pos)
            if not best or d<best_d then best,best_d=enemy,d end
        end
    end
    local supply_pos,supply_enemy,supply_kind=progression_supply_target(sim)
    if supply_pos and sim.hp<=sim.max_hp*.55 then return supply_pos,supply_enemy,supply_kind end
    if best then return best.pos,best,best.kind end
    if supply_pos then return supply_pos,supply_enemy,supply_kind end
    for _,nest in ipairs(sim.world.nests) do
        if not nest.used then
            local d=distance(sim.player,nest.pos)
            if not best or d<best_d then best,best_d=nest,d end
        end
    end
    if best then return best.pos,nil,"nest" end
    if sim.boss_spawned then return sim.boss_marker,nil,"boss_marker" end
    return nil,nil,"search"
end

local function objective_attack_range(sim,enemy)
    local radius=sim:body_radius()
    -- Повреждающее столкновение начинается на enemy.r + radius*0.75,
    -- а не на меньшем радиусе блокирования тел.
    local damage_contact=enemy.r+radius*0.75
    local form=sim.run_loadout.form
    if form=="predator" then
        -- Рывок пересекает запас дистанции и всё ещё достигает рта цели.
        return damage_contact+35
    elseif form=="toxic" then
        local rank=sim.build:rank("acid")
        local acid=(75+rank*9)*sim.build:specialization_value("acid","radius_mult")*sim:ability_scale()
        return math.max(damage_contact+35,math.min(enemy.r*.78+acid*.90,enemy.r+acid))
    elseif form=="colony" then
        -- Безопасная дистанция одновременно оставляет цель в зоне орбиты копий.
        return colony_attack_range(sim,enemy)
    end
    return damage_contact+35
end

local function progression_direction(sim,tick,cache)
    local goal,enemy=progression_target(sim)
    if not goal then return direction(sim,tick) end
    local p,r=sim.player,sim:body_radius()
    local clearance=math.min(26,r*.65)
    local d=distance(p,goal)
    local dx,dy=0,0
    local waypoint=goal
    local combat_range
    if enemy then
        combat_range=objective_attack_range(sim,enemy)
        local ux,uy=(p.x-goal.x)/math.max(d,.001),(p.y-goal.y)/math.max(d,.001)
        waypoint={x=goal.x+ux*combat_range,y=goal.y+uy*combat_range}
    end
    local direct=true
    local route_distance=distance(p,waypoint)
    local samples=math.max(1,math.ceil(route_distance/30))
    if route_distance>450 then direct=false else
        for i=1,samples do
            if not sim.world:walkable(p.x+(waypoint.x-p.x)*i/samples,p.y+(waypoint.y-p.y)*i/samples,clearance) then
                direct=false;break
            end
        end
    end
    if enemy and d<combat_range+50 then
        local ux,uy=(goal.x-p.x)/math.max(d,.001),(goal.y-p.y)/math.max(d,.001)
        local error=d-combat_range
        local radial=math.max(-1,math.min(1,error/34))
        local tangent=.28
        if enemy.kind=="boss" and (enemy.boss_windup or 0)>0 then
            radial=d>combat_range+35 and .35 or -.45
            tangent=1
        elseif enemy.kind=="boss" and (enemy.boss_exposed or 0)>0 then
            -- Не бросаемся в тело босса в окно уязвимости: держим радиус атаки.
            radial=math.max(-.45,math.min(.45,error/36))
            tangent=.10
        elseif enemy.kind=="boss" then
            radial=math.max(-.70,math.min(.70,error/38))
            tangent=.42
        end
        dx,dy=ux*radial-uy*tangent,uy*radial+ux*tangent
    else
        local route=direct and waypoint or route_waypoint(sim.world,p,waypoint,clearance,cache)
        if not route then return direction(sim,tick) end
        dx,dy=route.x-p.x,route.y-p.y
    end
    local len=math.sqrt(dx*dx+dy*dy)
    if len>.001 then dx,dy=dx/len,dy/len end
    local best_x,best_y,best_score=0,0,-math.huge
    for _,candidate in ipairs(DIRECTIONS) do
        local nx,ny=p.x+candidate[1]*22,p.y+candidate[2]*22
        if sim.world:walkable(nx,ny,clearance) then
            local next_pos={x=nx,y=ny}
            local score=candidate[1]*dx+candidate[2]*dy
            if enemy then
                local next_distance=distance(next_pos,enemy.pos)
                local safe_distance=enemy.r+r*.75+24
                score=score-math.max(0,safe_distance-next_distance)*.14
                if enemy.kind=="boss" and (enemy.boss_windup or 0)>0 then
                    local angle=enemy.boss_angle or 0
                    local rx,ry=nx-enemy.pos.x,ny-enemy.pos.y
                    local along=rx*math.cos(angle)+ry*math.sin(angle)
                    local side=math.abs(-rx*math.sin(angle)+ry*math.cos(angle))
                    if along>0 and along<520 then
                        score=score-math.max(0,r*.9+34-side)*.055
                    end
                end
            end
            for _,other in ipairs(sim.enemies) do
                if other~=enemy and other.hp>0 and not other.captured and other.kind~="prey" then
                    local safe=other.r+r*.75+42
                    score=score-math.max(0,safe-distance(next_pos,other.pos))*.045
                end
            end
            for _,field in ipairs(sim.fields) do
                if field.hostile then
                    local fx,fy=nx-field.pos.x,ny-field.pos.y
                    local dfield=math.sqrt(fx*fx+fy*fy)
                    local safe=field.r+r*.65+35
                    score=score-math.max(0,safe-dfield)*.045
                end
            end
            for _,shot in ipairs(sim.shots) do
                if shot.hostile then
                    local vx,vy=shot.vel.x,shot.vel.y
                    local speed2=vx*vx+vy*vy
                    if speed2>1 then
                        local t=math.max(0,math.min(.65,((nx-shot.pos.x)*vx+(ny-shot.pos.y)*vy)/speed2))
                        local sx,sy=shot.pos.x+vx*t,shot.pos.y+vy*t
                        local separation=math.sqrt((nx-sx)^2+(ny-sy)^2)
                        score=score-math.max(0,r*.78+20-separation)*.12
                    end
                end
            end
            if score>best_score then best_x,best_y,best_score=candidate[1],candidate[2],score end
        end
    end
    return best_x,best_y
end

local function validate_colony_combat_pilot()
    local sim=Simulation.new(147,nil,nil,"colony",{form="colony",branch="colony",seed=147})
    local radius=sim:body_radius()
    local target={id=9901,kind="hostile",r=radius*1.25,pos={x=sim.player.x+500,y=sim.player.y},hp=100,max_hp=100}
    local giant={id=9902,kind="hostile",r=radius*1.8,pos={x=sim.player.x+900,y=sim.player.y},hp=100,max_hp=100}
    sim.enemies={target,giant}
    assert(colony_attack_target(sim)==target,"Colony pilot must select a target that clones can damage")
    local range=colony_attack_range(sim,target)
    assert(range>=target.r+radius*.75+34,"Colony copies must attack outside body collision range")
    assert(range-105<=target.r+18,"Colony copies must reach the selected target from their orbit")
    local dx,dy=colony_direction(sim,1)
    assert(dx>0 and dx*dx+dy*dy>.5,"Colony pilot must approach a distant clone target")
    sim.enemies={giant}
    assert(not colony_attack_target(sim),"Colony pilot must not chase a giant that clones cannot damage")
    local flee_x,flee_y=colony_direction(sim,1)
    assert(flee_x and flee_x<0 and flee_x*flee_x+flee_y*flee_y>.5,
        "Colony pilot must evade a giant when no clone-attack target exists")
    sim.hp=sim.max_hp*.5
    sim.enemies={target}
    sim.pickups={{type="heal",captured=false,pos={x=sim.player.x-120,y=sim.player.y}}}
    local heal_x,heal_y=colony_direction(sim,2)
    assert(heal_x<0 and heal_x*heal_x+heal_y*heal_y>.5,
        "Colony pilot must prioritize nearby healing at critical health over combat")
    print("MICROGEN COLONY COMBAT PILOT READY")
end

local function validate_toxic_combat_pilot()
    local sim=Simulation.new(147,nil,nil,"toxic",{form="toxic",branch="toxic",seed=147})
    local radius=sim:body_radius()
    local target=assert(sim:spawn_enemy({x=sim.player.x+40,y=sim.player.y},"hunter"))
    target.r=radius*.8
    target.hp=target.max_hp*.4
    sim.enemies={target}
    assert(sim:interaction(target).eligible,"Toxic pilot fixture must be a valid small enemy")
    local x,y=direction(sim,1)
    assert(x<0 and x*x+y*y>.5,
        "Toxic pilot must retreat when a target enters the acid aura's safe orbit")
    target.pos={x=sim.player.x+220,y=sim.player.y}
    x,y=direction(sim,2)
    assert(x>0 and x*x+y*y>.5,
        "Toxic pilot must approach a distant target while preserving acid range")
    print("MICROGEN TOXIC COMBAT PILOT READY")
end

local function validate_progression_pilot()
    for _,seed in ipairs(SPECIALIZATION_SEEDS) do
        local sim=Simulation.new(seed,nil,nil,"colony",{form="colony",branch="colony",seed=seed})
        local p=sim.player
        for _,nest in ipairs(sim.world.nests) do
            assert(route_waypoint(sim.world,p,nest.pos,14,{}),"No walkable route to nest")
        end
        assert(route_waypoint(sim.world,p,sim.world.boss_pos,14,{}),"No walkable route to boss")
        local goal,enemy,kind=progression_target(sim)
        assert(goal and not enemy and kind=="supply_dna","Progression pilot must collect early DNA before the first nest")
        sim.level=5
        goal,enemy,kind=progression_target(sim)
        assert(goal and not enemy and kind=="nest","Progression pilot must return to nest objectives after early growth")
    end
    print("MICROGEN OBJECTIVE PILOT READY")
end

-- Катаклизм применяется на входе врагов в фактический радиус поля,
-- а не после того, как они подошли вплотную к организму.
local function ability_trigger_radius(sim)
    local ability=sim:form_ability()
    if ability.id~="toxic_cataclysm" then return 115 end
    local rank=sim.build:rank("acid")
    local radius=(75+rank*9)*sim.build:specialization_value("acid","radius_mult")*sim:ability_scale()
    local charges=sim:vacuole_charge_count()
    local cfg=Catalog.SIGNATURE_ORGANS.osmotic_vacuole
    local field_radius=radius*(ability.radius_multiplier or 1)*(1+charges*(cfg.radius_per_charge or 0))
    return field_radius*sim.build:specialization_value("osmotic_vacuole","field_radius_mult",1)
end

local function validate_objective_combat_range()
    for _,scenario in ipairs(EVOLUTION_SCENARIOS) do
        local sim=Simulation.new(147,nil,nil,scenario.form,
            {form=scenario.form,branch=scenario.form,seed=147})
        for id,rank in pairs(scenario.seed_organs or {}) do sim.build.organs[id]=rank end
        for id,rank in pairs(scenario.seed_adaptations or {}) do sim.build.adaptations[id]=rank end
        sim.build._synergy_signature=nil
        assert(sim.build:evolve(Catalog.signature_organ(scenario.form)),
            "Combat-range fixture must reach its form evolution: "..scenario.form)
        local boss={kind="boss",r=140,pos={x=sim.player.x+140,y=sim.player.y}}
        local range=objective_attack_range(sim,boss)
        local damage_contact=boss.r+sim:body_radius()*.75
        assert(range>=damage_contact+34,
            "Objective pilot must remain outside actual collision damage range: "..scenario.form)
        if scenario.form=="predator" then
            assert(range<boss.r+sim:body_radius()*1.18+64,
                "Predator dash must still reach the boss from its safe ring")
        elseif scenario.form=="toxic" then
            assert(range<ability_trigger_radius(sim)+boss.r*.5,
                "Toxic field must reach the boss from its safe ring")
        elseif scenario.form=="colony" then
            assert(range-105<boss.r+18,
                "Colony copies must reach the boss from their safe ring")
        end
    end
    print("MICROGEN OBJECTIVE COMBAT RANGE READY")
end

-- Регенерация главного босса ограничена отдельно от обычных амёб:
-- снижение не должно случайно ослабить весь набор противников.
local function validate_boss_regeneration()
    local sim=Simulation.new(147,nil,nil,"colony",{form="colony",branch="colony",seed=147})
    assert(type(sim._update_enemy_status)=="function",
        "Combat status update must be available for regeneration checks")
    local function regenerated_hp(kind)
        local enemy={kind=kind,r=40,hp=500,max_hp=1000,traits={"regen"},infect=0,
            slow=0,rupture_slow=0,grasp=0,crown_time=0,enzyme_time=0,tissue_budget=0}
        sim:_update_enemy_status(enemy,1,sim:body_radius())
        return enemy.hp
    end
    local boss_hp=regenerated_hp("boss")
    local common_hp=regenerated_hp("common")
    assert(math.abs(boss_hp-506)<0.001,
        "Boss regeneration must remain at 0.6% max HP per second")
    assert(math.abs(common_hp-512)<0.001,
        "Common amoeba regeneration must remain at 1.2% max HP per second")
    print("MICROGEN BOSS REGENERATION BALANCE READY")
end

-- Катаклизм не должен тратить перезарядку на безвредную добычу или уже
-- захваченную цель: способность предназначена для сдерживания угроз.
local function toxic_ability_target(sim)
    return sim:_nearest(ability_trigger_radius(sim), function(enemy)
        return enemy.kind ~= "prey" and not sim:_is_engulfing(enemy)
    end)
end

local function run(seed, scenario, horizon_seconds)
    horizon_seconds = horizon_seconds or HORIZON_SECONDS
    local branch, starter = scenario.form, scenario.starter
    local unlocked=Catalog.base_unlocked()
    local signature=Catalog.signature_organ(branch)
    if not Util.index(unlocked,signature) then unlocked[#unlocked+1]=signature end
    for id in pairs(scenario.seed_organs or {}) do
        if not Util.index(unlocked,id) then unlocked[#unlocked+1]=id end
    end
    local sim = Simulation.new(seed, unlocked, nil, branch, {form = branch, branch = branch, seed = seed, imprint = signature})
    assert(sim.build:rank(starter) == 1, "Balance run must start with its form's organ")
    assert(sim.build:rank(signature) > 0, "Balance run must equip its form signature organ")
    for id,rank in pairs(scenario.seed_organs or {}) do sim.build.organs[id]=rank end
    for id,rank in pairs(scenario.seed_adaptations or {}) do sim.build.adaptations[id]=rank end
    if scenario.seed_marked_target then
        -- Гарантируем интеграционному сценарию уязвимую цель в радиусе
        -- хеморецептора: тест проверяет реальное продление ферментов меткой,
        -- а не случайность появления подходящего противника на карте.
        local target=assert(sim:spawn_enemy({x=sim.player.x+90,y=sim.player.y},"hunter"))
        target.hp=target.max_hp*.5
    end
    sim.build._synergy_signature=nil
    if scenario.evolve then assert(sim.build:evolve(signature),"Advanced evolution fixture must meet its requirements") end
    if scenario.block_evolution then sim.build.evolution_candidates=function() return {} end end
    for _,id in ipairs(scenario.expected_synergies or {}) do
        assert(Util.index(sim.build:active_synergies(),id),"Hybrid fixture must activate "..id)
    end
    if scenario.disabled_synergy then
        local active_synergies=sim.build.active_synergies
        sim.build.active_synergies=function(self)
            local active,filtered=active_synergies(self),{}
            for _,id in ipairs(active) do if id~=scenario.disabled_synergy then filtered[#filtered+1]=id end end
            return filtered
        end
        assert(not Util.index(sim.build:active_synergies(),scenario.disabled_synergy),
            "Hybrid control must actually disable "..scenario.disabled_synergy)
    end
    local synergy_triggers={acid_bite=0,enzyme_target=0,shared_shell=0}
    local track_acid=Util.index(scenario.expected_synergies or {},"acid_bite")~=nil or scenario.disabled_synergy=="acid_bite"
    local track_enzyme=Util.index(scenario.expected_synergies or {},"enzyme_target")~=nil or scenario.disabled_synergy=="enzyme_target"
    local track_shell=Util.index(scenario.expected_synergies or {},"shared_shell")~=nil or scenario.disabled_synergy=="shared_shell"
    if track_acid then
        local original=sim._acid_bite_refund
        sim._acid_bite_refund=function(self)
            local before=self.cooldowns.special_attack or 0
            original(self)
            if (self.cooldowns.special_attack or 0)<before then synergy_triggers.acid_bite=synergy_triggers.acid_bite+1 end
        end
    end
    if track_enzyme then
        local original=sim._apply_enzymes
        sim._apply_enzymes=function(self,enemy,duration)
            local active=Util.index(self.build:active_synergies(),"enzyme_target")~=nil
            local marked=self:is_chemoreceptor_marked(enemy)
            local before=enemy.enzyme_time or 0
            original(self,enemy,duration)
            if active and marked and (enemy.enzyme_time or 0)>before then
                synergy_triggers.enzyme_target=synergy_triggers.enzyme_target+1
            end
        end
    end
    if track_shell then
        local original=sim.barrier_capacity
        sim.barrier_capacity=function(self)
            local capacity=original(self)
            if capacity>0 and Util.index(self.build:active_synergies(),"shared_shell") then
                synergy_triggers.shared_shell=synergy_triggers.shared_shell+1
            end
            return capacity
        end
    end
    -- Считаем успешные активации, а не попытки нажатия.
    local attack_uses,defense_uses=0,0
    local activate_attack,activate_defense=sim.activate_form_ability,sim.activate_form_defense
    sim.activate_form_ability=function(self,...)
        local used=activate_attack(self,...)
        if used then attack_uses=attack_uses+1 end
        return used
    end
    sim.activate_form_defense=function(self,...)
        local used=activate_defense(self,...)
        if used then defense_uses=defense_uses+1 end
        return used
    end
    local max_enemies, max_fields, max_remains = 0, 0, 0
    local steps, first_hit = 0, nil
    local toxin_sources = {}
    local contact_damage, contact_hits = 0, 0
    local clone_damage,clone_hits,clone_swarm_damage,clone_swarm_hits=0,0,0,0
    if branch=="colony" then
        local original_clone_hit=sim._synaptic_hit
        sim._synaptic_hit=function(self,enemy,amount,index)
            local swarm=(self.cooldowns.colony_swarm_active or 0)>0
            local dealt=original_clone_hit(self,enemy,amount,index)
            if dealt>0 then
                clone_damage,clone_hits=clone_damage+dealt,clone_hits+1
                if swarm then clone_swarm_damage,clone_swarm_hits=clone_swarm_damage+dealt,clone_swarm_hits+1 end
            end
            return dealt
        end
    end
    local boss_contact_damage,miniboss_contact_damage=0,0
    local original_hurt = sim.hurt_player
    sim.hurt_player = function(self, amount, source)
        local health_before = self.hp
        original_hurt(self, amount, source)
        local dealt = health_before - self.hp
        if dealt > 0 and source and source.kind == "collision" then
            contact_damage, contact_hits = contact_damage + dealt, contact_hits + 1
            if source.enemy and source.enemy.kind=="boss" then boss_contact_damage=boss_contact_damage+dealt end
            if source.enemy and source.enemy.kind=="miniboss" then miniboss_contact_damage=miniboss_contact_damage+dealt end
        end
        if dealt > 0 and source and source.kind == "toxin" then
            local id = tostring(source.id or 0)
            local entry = toxin_sources[id]
            if not entry then
                entry = { id = id, name = source.name or "Источник неизвестен", damage = 0, hits = 0, first = self.elapsed }
                toxin_sources[id] = entry
            end
            entry.damage, entry.hits, entry.last = entry.damage + dealt, entry.hits + 1, self.elapsed
        end
    end

    local pilot_cache={}
    local nests_seen,minibosses,boss_damage,exposed_damage,boss_hp_remaining=0,0,0,0,0
    local boss_healing,boss_regen=0,false
    if scenario.progression then
        local original_status=sim._update_enemy_status
        sim._update_enemy_status=function(self,enemy,dt,radius)
            local hp_before=enemy.hp
            original_status(self,enemy,dt,radius)
            if enemy.kind=="boss" then
                if Util.index(enemy.traits or {},"regen") then boss_regen=true end
                boss_healing=boss_healing+math.max(0,enemy.hp-hp_before)
            end
        end
        local original_hit=sim.hit_enemy
        sim.hit_enemy=function(self,enemy,...)
            local exposed=(enemy.boss_exposed or 0)>0
            local dealt=original_hit(self,enemy,...)
            if enemy.kind=="boss" then
                boss_damage=boss_damage+dealt
                if exposed then exposed_damage=exposed_damage+dealt end
                boss_hp_remaining=math.max(0,enemy.hp)
            end
            return dealt
        end
    end
    for tick = 1, horizon_seconds * 60 do
        if sim.outcome ~= "" or (scenario.progression and sim.stage_index>=2) then break end
        settle_stage(sim)
        settle_levels(sim)
        settle_rewards(sim)

        local move_x, move_y
        if scenario.progression then move_x,move_y=progression_direction(sim,tick,pilot_cache)
        else move_x,move_y=direction(sim,tick) end
        local health_before = sim.hp
        if scenario.use_ability ~= false and sim:form_ability_ready() and tick % 30 == 0 then
            local _,elite=progression_target(sim)
            if branch=="predator" then
                local target=sim:_nearest(110,function(e) return not e.captured and sim:_can_be_absorbed(e) end)
                if scenario.progression and elite and distance(sim.player,elite.pos)<sim:body_radius()+elite.r+64
                    and (elite.kind~="boss" or (elite.boss_exposed or 0)>0) then target=elite end
                if target then sim:activate_form_ability(target.pos.x-sim.player.x,target.pos.y-sim.player.y) end
            elseif branch=="toxic" then
                local target=toxic_ability_target(sim)
                if scenario.progression and elite then
                    local range=ability_trigger_radius(sim)+elite.r*.5
                    if distance(sim.player,elite.pos)<=range
                        and (elite.kind~="boss" or (elite.boss_exposed or 0)>0 or (elite.boss_windup or 0)>0) then
                        target=elite
                    end
                end
                if target then sim:activate_form_ability() end
            else
                local target=scenario.progression and elite or colony_attack_target(sim)
                local use=false
                if target then
                    local d=distance(sim.player,target.pos)
                    local reach=105+target.r+18
                    local safe=target.r+sim:body_radius()*.75+12
                    use=d<=reach and d>=safe
                        and (target.kind~="boss" or (target.boss_exposed or 0)>0 or (target.boss_windup or 0)>0)
                end
                if use then sim:activate_form_ability() end
            end
        end
        -- Колониальный бастион включается до опасного контакта с элитой.
        local _,objective_elite=progression_target(sim)
        local defense_threshold=branch=="colony" and .95 or .90
        local boss_windup= scenario.progression and objective_elite and objective_elite.kind=="boss"
            and (objective_elite.boss_windup or 0)>0
        local defensive_window=scenario.progression and branch=="colony" and boss_windup
            and distance(sim.player,objective_elite.pos)<520
        if scenario.use_defense ~= false and sim:form_defense_ready()
            and (sim.hp<=sim.max_hp*defense_threshold or defensive_window) and tick%30==0 then
            sim:activate_form_defense()
        end
        sim:step(STEP, move_x, move_y)
        if scenario.progression then
            local visited=0
            for _,nest in ipairs(sim.world.nests) do if nest.used then visited=visited+1 end end
            nests_seen=math.max(nests_seen,visited)
            minibosses=math.max(minibosses,sim.minibosses_defeated)
            for _,enemy in ipairs(sim.enemies) do
                if enemy.kind=="boss" then
                    boss_hp_remaining=enemy.hp
                    if Util.index(enemy.traits or {},"regen") then boss_regen=true end
                end
            end
        end
        if not first_hit and sim.hp < health_before then
            local hit = sim.last_damage
            if hit then first_hit = string.format("%.1f/%s/%s", hit.time, hit.kind, hit.name) end
        end
        settle_levels(sim)
        settle_rewards(sim)
        settle_stage(sim)
        sim.feedback = {}

        steps = tick
        max_enemies = math.max(max_enemies, #sim.enemies)
        max_fields = math.max(max_fields, #sim.fields)
        max_remains = math.max(max_remains, #sim.remains)

        assert(finite(sim.elapsed) and finite(sim.hp) and finite(sim.player.x) and finite(sim.player.y),
            "Balance run produced a non-finite simulation value")
        assert(#sim.enemies <= Simulation.ENEMY_CAP, "Balance run exceeded the enemy cap")
        assert(#sim.fields <= 80, "Balance run exceeded the field cap")
        assert(#sim.remains <= 96, "Balance run exceeded the remains cap")
    end

    assert(finite(sim.elapsed) and finite(sim.build.biomass) and finite(sim.kills) and finite(sim.absorbed)
        and finite(sim.combat_stats.damage_dealt) and finite(sim.combat_stats.damage_taken)
        and finite(sim.combat_stats.blocked) and finite(sim.combat_stats.healed),
        "Balance run ended with invalid summary values")
    local history = sim.combat_stats.history
    local last_hit = history[#history]
    local cause = last_hit and string.format("%s/%s/%.1f", last_hit.kind, last_hit.name, last_hit.amount) or "none"
    local sources = {}
    for _, entry in pairs(sim.combat_stats.sources) do
        if entry.damage > 0 then sources[#sources + 1] = entry end
    end
    table.sort(sources, function(a, b)
        if a.damage == b.damage then return a.name < b.name end
        return a.damage > b.damage
    end)
    local source_labels = {}
    for index = 1, math.min(3, #sources) do
        local entry = sources[index]
        source_labels[index] = string.format("%s/%s=%.1f(%d)", entry.kind, entry.name, entry.damage, entry.hits)
    end
    local source_summary = #source_labels > 0 and table.concat(source_labels, ";") or "none"
    local toxin_labels = {}
    for _, entry in pairs(toxin_sources) do toxin_labels[#toxin_labels + 1] = entry end
    table.sort(toxin_labels, function(a, b)
        if a.damage == b.damage then return a.id < b.id end
        return a.damage > b.damage
    end)
    local toxin_summary = {}
    for index = 1, math.min(4, #toxin_labels) do
        local entry = toxin_labels[index]
        toxin_summary[index] = string.format("%s/%s=%.1f(%d)@%.1f-%.1f", entry.id, entry.name,
            entry.damage, entry.hits, entry.first, entry.last or entry.first)
    end
    local toxin_source_summary = #toxin_summary > 0 and table.concat(toxin_summary, ";") or "none"
    assert(scenario.use_ability~=false or attack_uses==0,"Attack-disabled control activated an attack")
    assert(scenario.use_defense~=false or defense_uses==0,"Defense-disabled control activated a defense")
    for _,id in ipairs(scenario.expected_synergies or {}) do
        assert(synergy_triggers[id]>0,"Expected synergy produced no real combat trigger: "..id)
    end
    if scenario.disabled_synergy then
        assert(synergy_triggers[scenario.disabled_synergy]==0,
            "Disabled synergy unexpectedly affected combat: "..scenario.disabled_synergy)
    end
    if scenario.progression then
        print(string.format("MICROGEN OBJECTIVE RESULT form=%s seed=%d build=%s nests=%d minibosses=%d boss_damage=%.1f boss_hp=%.1f boss_healing=%.1f boss_regen=%d exposed_damage=%.1f boss_contact=%.1f miniboss_contact=%.1f clone_damage=%.1f clone_hits=%d swarm_damage=%.1f swarm_hits=%d reached_two=%d seconds=%.1f contact_damage=%.1f contact_hits=%d attack_uses=%d defense_uses=%d outcome=%s",
            branch,seed,scenario.evolve and "evolved" or "base",nests_seen,minibosses,boss_damage,boss_hp_remaining,boss_healing,boss_regen and 1 or 0,
            exposed_damage,boss_contact_damage,miniboss_contact_damage,clone_damage,clone_hits,clone_swarm_damage,clone_swarm_hits,
            sim.stage_index>=2 and 1 or 0,sim.elapsed,contact_damage,contact_hits,attack_uses,defense_uses,
            sim.stage_index>=2 and "stage2" or (sim.outcome=="" and "timeout" or sim.outcome)))
    end
    local marker=scenario.run_marker or "MICROGEN BALANCE RUN"
    print(string.format(
        "%s seed=%d branch=%s starter=%s signature=%s signature_rank=%d scenario=%s pilot=%s seconds=%.1f stage=%d level=%d kills=%d absorbed=%d hp=%.1f damage_dealt=%.1f damage_taken=%.1f contact_damage=%.1f contact_hits=%d clone_damage=%.1f clone_hits=%d swarm_damage=%.1f swarm_hits=%d damage_blocked=%.1f healed=%.1f attack_uses=%d defense_uses=%d first_hit=%s last_hit=%s damage_sources=%s toxin_sources=%s outcome=%s steps=%d peak_enemies=%d peak_fields=%d peak_remains=%d synergy_triggers=acid:%d,enzyme:%d,shell:%d",
        marker,seed,branch,starter,signature,sim.build:rank(signature),scenario.name or "base",scenario.progression and "objective" or "kite",sim.elapsed,sim.stage_index,sim.level,sim.kills,
        sim.absorbed or 0,sim.hp,sim.combat_stats.damage_dealt,sim.combat_stats.damage_taken,contact_damage,contact_hits,
        clone_damage,clone_hits,clone_swarm_damage,clone_swarm_hits,
        sim.combat_stats.blocked,sim.combat_stats.healed,attack_uses,defense_uses,first_hit or "none",cause,source_summary,toxin_source_summary,
        sim.outcome=="" and "alive" or sim.outcome,steps,max_enemies,max_fields,max_remains,
        synergy_triggers.acid_bite,synergy_triggers.enzyme_target,synergy_triggers.shared_shell))
    return {alive=sim.outcome=="",seconds=sim.elapsed,hp=sim.hp,level=sim.level,kills=sim.kills,
        absorbed=sim.absorbed or 0,stage=sim.stage_index,damage_dealt=sim.combat_stats.damage_dealt,
        damage_taken=sim.combat_stats.damage_taken,contact_damage=contact_damage,contact_hits=contact_hits,
        clone_damage=clone_damage,clone_hits=clone_hits,clone_swarm_damage=clone_swarm_damage,clone_swarm_hits=clone_swarm_hits,
        blocked=sim.combat_stats.blocked,healed=sim.combat_stats.healed,
        attack_uses=attack_uses,defense_uses=defense_uses,synergy_triggers=synergy_triggers,
        boss_damage=boss_damage,boss_healing=boss_healing,boss_regen=boss_regen,
        boss_contact_damage=boss_contact_damage,miniboss_contact_damage=miniboss_contact_damage}
end

local function run_batch(marker,scenario,seeds)
    local seconds,levels,kills,absorbed,dealt,damage,blocked,healed,stages,survivors=0,0,0,0,0,0,0,0,0,0
    local acid_triggers,enzyme_triggers,shell_triggers=0,0,0
    local attack_uses,defense_uses=0,0
    local contact_damage,contact_hits=0,0
    local clone_damage,clone_hits,clone_swarm_damage,clone_swarm_hits=0,0,0,0
    local boss_damage,boss_contact_damage,miniboss_contact_damage=0,0,0
    local boss_healing,regen_bosses=0,0
    local results={}
    for _,seed in ipairs(seeds) do
        local config=Util.copy(scenario)
        config.run_marker=marker
        local result=run(seed,config)
        results[seed]=result
        seconds,levels,kills,absorbed,dealt,damage,blocked,healed,stages=seconds+result.seconds,levels+result.level,
            kills+result.kills,absorbed+result.absorbed,dealt+result.damage_dealt,
            damage+result.damage_taken,blocked+result.blocked,healed+result.healed,stages+result.stage
        attack_uses=attack_uses+result.attack_uses
        defense_uses=defense_uses+result.defense_uses
        contact_damage=contact_damage+result.contact_damage
        contact_hits=contact_hits+result.contact_hits
        boss_damage=boss_damage+(result.boss_damage or 0)
        boss_healing=boss_healing+(result.boss_healing or 0)
        if result.boss_regen then regen_bosses=regen_bosses+1 end
        boss_contact_damage=boss_contact_damage+(result.boss_contact_damage or 0)
        miniboss_contact_damage=miniboss_contact_damage+(result.miniboss_contact_damage or 0)
        clone_damage=clone_damage+(result.clone_damage or 0)
        clone_hits=clone_hits+(result.clone_hits or 0)
        clone_swarm_damage=clone_swarm_damage+(result.clone_swarm_damage or 0)
        clone_swarm_hits=clone_swarm_hits+(result.clone_swarm_hits or 0)
        acid_triggers=acid_triggers+result.synergy_triggers.acid_bite
        enzyme_triggers=enzyme_triggers+result.synergy_triggers.enzyme_target
        shell_triggers=shell_triggers+result.synergy_triggers.shared_shell
        if result.alive then survivors=survivors+1 end
        collectgarbage("collect")
    end
    local summary=marker:gsub(" RUN$"," SUMMARY")
    print(string.format("%s form=%s scenario=%s maps=%d mean_seconds=%.1f mean_stage=%.2f mean_level=%.2f mean_kills=%.2f mean_absorbed=%.2f mean_damage_dealt=%.1f mean_damage_taken=%.1f mean_contact_damage=%.1f mean_contact_hits=%.1f mean_clone_damage=%.1f mean_clone_hits=%.1f mean_swarm_damage=%.1f mean_swarm_hits=%.1f mean_boss_damage=%.1f mean_boss_healing=%.1f regen_bosses=%d mean_boss_contact=%.1f mean_miniboss_contact=%.1f mean_damage_blocked=%.1f mean_healed=%.1f survivors=%d attack_uses=%d defense_uses=%d mean_synergy_triggers=acid:%.2f,enzyme:%.2f,shell:%.2f",
        summary,scenario.form,scenario.name or "base",#seeds,seconds/#seeds,stages/#seeds,
        levels/#seeds,kills/#seeds,absorbed/#seeds,dealt/#seeds,damage/#seeds,contact_damage/#seeds,contact_hits/#seeds,
        clone_damage/#seeds,clone_hits/#seeds,clone_swarm_damage/#seeds,clone_swarm_hits/#seeds,
        boss_damage/#seeds,boss_healing/#seeds,regen_bosses,boss_contact_damage/#seeds,miniboss_contact_damage/#seeds,blocked/#seeds,healed/#seeds,
        survivors,attack_uses,defense_uses,acid_triggers/#seeds,enzyme_triggers/#seeds,shell_triggers/#seeds))
    return results
end

local function print_pair_comparison(label,with_effect,without_effect,seeds)
    local totals={seconds=0,stage=0,level=0,kills=0,absorbed=0,damage_dealt=0,damage_taken=0,blocked=0,healed=0,hp=0}
    local wins=0
    for _,seed in ipairs(seeds) do
        local a,b=assert(with_effect[seed],"Missing paired run with effect"),assert(without_effect[seed],"Missing paired control run")
        local delta={}
        for key in pairs(totals) do
            delta[key]=a[key]-b[key]
            totals[key]=totals[key]+delta[key]
        end
        if a.alive and not b.alive then wins=wins+1 elseif b.alive and not a.alive then wins=wins-1 end
        print(string.format("MICROGEN PAIRED RESULT comparison=%s seed=%d delta_seconds=%.1f delta_stage=%.2f delta_level=%.2f delta_kills=%.2f delta_absorbed=%.2f delta_damage_dealt=%.1f delta_damage_taken=%.1f delta_damage_blocked=%.1f delta_healed=%.1f delta_hp=%.1f outcome_with=%s outcome_without=%s",
            label,seed,delta.seconds,delta.stage,delta.level,delta.kills,delta.absorbed,delta.damage_dealt,
            delta.damage_taken,delta.blocked,delta.healed,delta.hp,a.alive and "alive" or "death",b.alive and "alive" or "death"))
    end
    local n=#seeds
    print(string.format("MICROGEN PAIRED SUMMARY comparison=%s pairs=%d mean_delta_seconds=%.1f mean_delta_stage=%.2f mean_delta_level=%.2f mean_delta_kills=%.2f mean_delta_absorbed=%.2f mean_delta_damage_dealt=%.1f mean_delta_damage_taken=%.1f mean_delta_damage_blocked=%.1f mean_delta_healed=%.1f mean_delta_hp=%.1f survival_pair_wins=%d",
        label,n,totals.seconds/n,totals.stage/n,totals.level/n,totals.kills/n,totals.absorbed/n,
        totals.damage_dealt/n,totals.damage_taken/n,totals.blocked/n,totals.healed/n,totals.hp/n,wins))
end

local function validate_resident_start_safety()
    local sim = Simulation.new(347, nil, nil, "colony")
    local resident = sim.residents[1]
    resident.pos = { x = sim.player.x, y = sim.player.y }
    for index = 2, #sim.residents do
        sim.residents[index].pos = { x = sim.player.x + 1200 + index * 100, y = sim.player.y }
    end

    sim.elapsed = 0
    sim:_update_ecology()
    assert(not resident.active and #sim.enemies == 0,
        "Resident amoeba became hostile during the initial safety window")

    sim.elapsed = 7.99
    sim:_update_ecology()
    assert(not resident.active and #sim.enemies == 0,
        "Resident amoeba became hostile before the eight-second safety window ended")

    sim.elapsed = 8
    sim:_update_ecology()
    assert(resident.active and #sim.enemies == 1,
        "Resident amoeba did not activate after the initial safety window")
    print("MICROGEN RESIDENT START SAFETY READY")
end

local function validate_combat_checkpoint()
    local sim = Simulation.new(347, nil, nil, "predator", {form = "predator", seed = 347})
    sim.elapsed, sim.hp, sim.bite_flash, sim._danger_at = 120, 20, 0.8, 119.5
    sim.cooldowns.devour = 0.25
    local spitter = assert(sim:spawn_enemy({x = sim.player.x + 300, y = sim.player.y}, "spitter"))
    spitter.shot_cd = 0
    sim:_spitter_windup(spitter, STEP, 300)
    local saved = sim:snapshot()
    local restored = assert(Simulation.restore(saved))
    assert(restored.bite_flash == sim.bite_flash and restored._danger_at == sim._danger_at
        and restored.cooldowns.devour == sim.cooldowns.devour,
        "Reload must preserve bite state and cooldowns")

    local resumed_spitter = restored.enemies[1]
    assert(resumed_spitter.spit_windup == spitter.spit_windup
        and resumed_spitter.spit_angle == spitter.spit_angle,
        "Reload must preserve an ongoing enemy windup")
    local delay = spitter.spit_windup
    sim:_spitter_windup(spitter, delay, 300)
    restored:_spitter_windup(resumed_spitter, delay, 300)
    local shot, resumed_shot = sim.shots[1], restored.shots[1]
    assert(shot and resumed_shot and shot.vel.x == resumed_shot.vel.x and shot.vel.y == resumed_shot.vel.y,
        "Resumed enemy attack must follow the original direction")

    saved.bite_flash, saved._danger_at = nil, nil
    local legacy = assert(Simulation.restore(saved))
    assert(legacy.bite_flash == 0 and legacy._danger_at == -10, "Older saves must remain readable")
    print("MICROGEN COMBAT CHECKPOINT READY")
end

local function validate_contact_balance()
    local sim = Simulation.new(147, nil, nil, "colony", {form="colony",branch="colony",seed=147})
    local function impact(ratio, elite)
        local rules = Size.profile(100, 100 * ratio, 1, 0, 0, false)
        return sim:contact_impact(rules, elite), rules.impact
    end
    local small, original_small = impact(1.2, false)
    local medium, original_medium = impact(1.8, false)
    local large, original_large = impact(2.4, false)
    local elite, original_elite = impact(2.4, true)
    assert(small == original_small, "Small contact damage must remain unchanged")
    assert(medium < original_medium and medium > small, "Large contact damage must scale smoothly")
    assert(math.abs(large - original_large * 0.75) < 0.00001 and large > medium,
        "Largest ordinary amoebas must deal 25 percent less contact damage")
    assert(math.abs(elite - original_elite * 1.2) < 0.00001, "Elite contact damage must remain unchanged")
    local predator = Simulation.new(147, nil, nil, "predator", {form="predator",branch="predator",seed=147})
    local predator_medium = predator:contact_impact(Size.profile(100,180,1,0,0,false),false)
    assert(medium < predator_medium,
        "Base colony must reduce medium-large contact damage before its evolution")
    local toxic = Simulation.new(147,nil,nil,"toxic",{form="toxic",branch="toxic",seed=147})
    local target = {kind="hunter",r=20,hp=100,max_hp=100,captured=false,infect=0,
        pos={x=toxic.player.x+10000,y=toxic.player.y}}
    assert(math.abs(toxic:damage_reduction({kind="collision",enemy=target})-0.06)<0.00001,
        "Toxic form must reduce ordinary contact damage even before poisoning")
    target.pos={x=toxic.player.x,y=toxic.player.y}
    assert(math.abs(toxic:damage_reduction({kind="collision",enemy=target})-0.18)<0.00001,
        "Toxic regulation must stack its poison-specific protection")
    target.kind="boss"
    assert(math.abs(toxic:damage_reduction({kind="collision",enemy=target})-0.09)<0.00001,
        "Boss contact protection must remain lower than ordinary enemy protection")
    assert(math.abs(toxic:damage_reduction({kind="projectile",enemy=target}))<0.00001,
        "Toxic contact protection must not reduce projectile damage")
    print("MICROGEN EARLY FORM DEFENSE READY")
    -- Проверяем отдельную защиту высших форм, не меняя обычные формы и элиту.
    for _, form in ipairs({"predator", "toxic", "colony"}) do
        local evolved = Simulation.new(147, nil, nil, form, {form=form, branch=form, seed=147})
        local cfg = Catalog.FORM_SPECIALIZATIONS[form].evolution
        evolved.build.organs[cfg.organ] = cfg.organ_rank
        evolved.build.adaptations[cfg.passive] = cfg.passive_rank
        assert(evolved.build:evolve(cfg.organ), "Contact fixture must unlock form evolution")
        local rules = Size.profile(100, 240, 1, 0, 0, false)
        local multiplier = form == "predator" and .75 or (form=="colony" and .45 or .55)
        assert(math.abs(evolved:contact_impact(rules, false) - rules.impact * multiplier) < .00001,
            "Large ordinary contact protection must match evolved form: "..form)
        assert(math.abs(evolved:contact_impact(rules, true) - rules.impact * 1.2) < .00001,
            "Elite contact remains unchanged: "..form)
        local below_large_rules = Size.profile(100, 108, 1, 0, 0, false)
        assert(math.abs(evolved:contact_impact(below_large_rules, false) - below_large_rules.impact) < .00001,
            "Evolved protection must not affect amoebas at the large-size threshold: "..form)
        local large_label_rules = Size.profile(100, 120, 1, 0, 0, false)
        local large_label_multiplier
        if form=="predator" then
            large_label_multiplier=1
        elseif form=="colony" then
            large_label_multiplier=1-(0.20+0.35*Size.smoothstep(1.08,2.4,large_label_rules.ratio))
        else
            large_label_multiplier=1-(0.15+0.30*Size.smoothstep(1.08,2.4,large_label_rules.ratio))
        end
        assert(math.abs(evolved:contact_impact(large_label_rules, false) - large_label_rules.impact * large_label_multiplier) < .00001,
            "Evolved glandular and colony forms must scale protection with large-label size: "..form)
    end
    for _, kind in ipairs({"hunter", "spitter", "prey", "miniboss", "boss"}) do
        local enemy = {kind=kind, rupture_slow=1.5, rupture_strength=.40}
        local expected = (kind == "boss" or kind == "miniboss") and .80 or .60
        assert(math.abs(sim:rupture_speed_multiplier(enemy)-expected)<.00001,
            "Cataclysm movement multiplier: "..kind)
        enemy.rupture_slow=0
        assert(sim:rupture_speed_multiplier(enemy)==1, "Expired cataclysm does not slow: "..kind)
    end
    print("MICROGEN CONTACT BALANCE READY")
end

local function validate_colony_coverage()
    local sim = Simulation.new(147, nil, nil, "colony", {form = "colony", branch = "colony", seed = 147})
    assert(sim.build:rank("division") == 1, "Colony must start with division")
    assert(Catalog.clone_count(1) == 2 and Catalog.clone_count(2) == 3
        and Catalog.clone_count(3) == 4 and Catalog.clone_count(4) == 5 and Catalog.clone_count(10) == 5,
        "Early clone count and late clone cap must match the balance rules")
    local clones = sim:clone_positions()
    assert(#clones == 2, "Colony must start with two actual clones")
    for index, p in ipairs(clones) do
        local q = clones[index % #clones + 1]
        local dx, dy = p.x - q.x, p.y - q.y
        assert(math.abs(dx * dx + dy * dy - 4 * 105 * 105) < 0.01,
            "Two clones must be opposite each other")
    end
    local restored = assert(Simulation.restore(sim:snapshot()))
    assert(#restored:clone_positions() == 2, "Reload must preserve colony coverage")
    print("MICROGEN COLONY COVERAGE READY")
end

local function validate_toxin_overlap()
    local sim = Simulation.new(147, nil, nil, "colony")
    sim.world.colonies = {}
    local p = sim.player
    local hits = {}
    sim.hurt_player = function(_, amount, source)
        hits[#hits + 1] = { amount = amount, id = source.id }
    end
    sim:_field(p, 48, 6, 2.8, "enemy_toxin", true, "Токсин", 101)
    sim:_field(p, 48, 8, 2.8, "enemy_toxin", true, "Токсин", 101)
    sim:_field({ x = p.x + 1000, y = p.y }, 48, 100, 2.8, "enemy_toxin", true, "Дальний токсин", 101)
    sim:_field(p, 48, 6, 2.8, "enemy_toxin", true, "Другой токсин", 102)
    sim:_field(p, 48, 4, 2.8, "enemy_toxin", true, "Старое поле")
    sim:_field(p, 48, 4, 2.8, "enemy_toxin", true, "Старое поле")
    sim:_update_fields(0.25)
    local totals, counts = {}, {}
    for _, hit in ipairs(hits) do
        local id = hit.id or 0
        totals[id] = (totals[id] or 0) + hit.amount
        counts[id] = (counts[id] or 0) + 1
    end
    assert(counts[101] == 1 and totals[101] == 2, "Same-source overlap must use only the strongest local field")
    assert(counts[102] == 1 and totals[102] == 1.5, "Independent hostile sources must retain their damage")
    assert(counts[0] == 2 and totals[0] == 2, "Legacy unidentified fields must remain independent")
    sim.world.colonies = {{ pos = p }}
    hits = {}
    sim:_update_fields(0.25)
    assert(#hits == 0, "Safe zones must still protect against hostile fields")
    print("MICROGEN TOXIN OVERLAP READY")
end

local function validate_save_recovery()
    -- Изолированный backend: настоящие файлы профиля игрока не затрагиваются.
    local records, fail_write = {}, false
    local backend = {
        get_save_file = function(_, filename) return filename end,
        load = function(path) return Util.copy(records[path]) end,
        save = function(path, record)
            if fail_write then return false end
            records[path] = Util.copy(record)
            return true
        end,
    }
    local store = SaveStore.new("balance_recovery", backend)
    assert(store:create_family("Первая", "predator"), "Initial family must be saved")
    local family = store:family_id()
    local sim = Simulation.new(147, nil, nil, "predator", {form = "predator", branch = "predator", seed = 147})
    sim.family_id, sim.hp, sim.elapsed, sim.absorbed = family, 62, 45, 3
    assert(store:save_checkpoint(sim:snapshot(), family), "Checkpoint must be committed")
    assert(store:credit_once("test-reward", 7), "Reward must be credited once")
    local committed = store.revision
    fail_write = true
    assert(not store:bank(9) and store.revision == committed and store.profile.cores == 7,
        "Failed write must not change the committed in-memory profile")
    fail_write = false
    local reopened = SaveStore.new("balance_recovery", backend)
    reopened:load_profile()
    assert(reopened.revision == committed and reopened.profile.cores == 7,
        "Failed write must leave the last committed profile readable")
    assert(not reopened:credit_once("test-reward", 7) and reopened.profile.cores == 7,
        "Reload must not duplicate a previously credited reward")
    local restored = assert(Simulation.restore(reopened.profile.checkpoint))
    assert(restored.family_id == family and restored.hp == 62 and restored.elapsed == 45 and restored.absorbed == 3,
        "Reload must preserve the checkpoint, family identity and absorption count")
    local old_checkpoint=Util.copy(reopened.profile.checkpoint)
    old_checkpoint.absorbed=nil
    local old_restore=assert(Simulation.restore(old_checkpoint))
    assert(old_restore.absorbed==0,"Older checkpoints must default the absorption counter to zero")
    -- Повреждаем только самый свежий слот и проверяем предыдущую ревизию.
    records[reopened.paths[reopened.active_file]] = { revision = committed, profile = { version = -1 } }
    local fallback = SaveStore.new("balance_recovery", backend)
    fallback:load_profile()
    assert(fallback.revision == committed - 1 and fallback:family_id() == family,
        "Corrupted newest slot must fall back to the previous valid revision")
    local previous = assert(Simulation.restore(fallback.profile.checkpoint))
    assert(previous.hp == 62 and previous.elapsed == 45, "Fallback must retain the last valid checkpoint")
    assert(fallback:create_family("Вторая", "colony"), "Second family must be saved")
    assert(not fallback:save_checkpoint(sim:snapshot(), family), "Stale checkpoint must not overwrite another family")
    assert(fallback:select_family(family), "Original family must remain selectable")
    assert(fallback.profile.checkpoint.family_id == family, "Family switching must retain its own checkpoint")
    print("MICROGEN SAVE RECOVERY READY")
end

local function validate_form_specialization_data()
    local expected = {
        predator = {organ = "chemoreceptor_ridge", cells = 1},
        toxic = {organ = "osmotic_vacuole", cells = 2},
        colony = {organ = "synaptic_node", cells = 2},
    }
    for _, form_id in ipairs(Catalog.FORM_IDS) do
        local data, expected_form = Catalog.form_specialization(form_id), expected[form_id]
        assert(data and data.ability and data.passive and data.evolution, "Every form must define its ability, passive and evolution")
        assert(data.signature_organ == expected_form.organ, "Form signature organ must be stable")
        local organ = Catalog.ORGANS[data.signature_organ]
        assert(organ and organ.signature and organ.form == form_id, "Signature organ must belong to its form")
        assert(Catalog.cell_cost(data.signature_organ) == expected_form.cells, "Signature organ cell cost changed")
        assert(Catalog.SIGNATURE_ORGANS[data.signature_organ].form == form_id, "Signature organ parameters must match their form")
        assert(data.evolution.passive and data.evolution.passive_rank == 3, "Form evolution must use the shared passive-rank contract")
        assert(#(Catalog.SPECIALIZATIONS[data.signature_organ] or {}) == 2, "Every signature organ must have two specializations")
        local legacy_form = Legacy.FORMS[form_id]
        assert(legacy_form.signature_organ == data.signature_organ and legacy_form.ability == data.ability
            and legacy_form.passive == data.passive, "Legacy form metadata must point to the shared form model")
    end

    local baseline = Catalog.base_unlocked()
    assert(Util.index(baseline, "chemoreceptor_ridge"), "Predator signature organ must be available by default")
    assert(not Util.index(baseline, "osmotic_vacuole") and not Util.index(baseline, "synaptic_node")
        and not Util.index(baseline, "division"), "Research-gated organs must not be available by default")

    local staged = Build.new()
    staged.unlocked = {"chemoreceptor_ridge", "osmotic_vacuole", "synaptic_node"}
    local offers = staged:offers({randf = function() return 0 end})
    assert(#offers == 3, "Unlocked signature organs must enter hybrid level-up offers")

    local old_unlocked = {
        "tentacle", "acid", "spikes", "pulse", "trail", "infection", "cilia", "enzymes",
        "electric", "barrier", "devour", "metabolism", "catalysis", "armor", "regen", "speed", "magnet",
    }
    local old_profile = SaveStore.defaults()
    old_profile.unlocked = Util.copy(old_unlocked)
    old_profile.legacy = Legacy.defaults()
    old_profile.legacy.research = {"toxic", "colony"}
    old_profile.legacy.selected_form = "toxic"
    old_profile.checkpoint = Simulation.new(147, nil, nil, "predator",
        {form = "predator", branch = "predator", seed = 147}):snapshot()
    old_profile.checkpoint.build.unlocked = Util.copy(old_unlocked)

    local migrated = SaveStore.normalize_profile(old_profile)
    assert(migrated, "An older profile with both form researches must remain valid")
    assert(Util.index(migrated.unlocked, "chemoreceptor_ridge")
        and Util.index(migrated.unlocked, "osmotic_vacuole")
        and Util.index(migrated.unlocked, "synaptic_node")
        and Util.index(migrated.unlocked, "division"), "Migration must restore all organs granted by existing research")
    assert(Util.index(migrated.checkpoint.build.unlocked, "chemoreceptor_ridge")
        and Util.index(migrated.checkpoint.build.unlocked, "osmotic_vacuole")
        and Util.index(migrated.checkpoint.build.unlocked, "synaptic_node"),
        "Migration must update the unlocked list inside an old checkpoint")
    local restored = Simulation.restore(migrated.checkpoint)
    assert(restored and Util.index(restored.build.unlocked, "osmotic_vacuole")
        and Util.index(restored.build.unlocked, "synaptic_node"), "Migrated checkpoint must restore with researched organs")

    local old_colony = SaveStore.defaults()
    old_colony.unlocked = Util.copy(old_unlocked)
    old_colony.unlocked[#old_colony.unlocked + 1] = "division"
    old_colony.legacy = Legacy.defaults()
    local migrated_colony = SaveStore.normalize_profile(old_colony)
    assert(migrated_colony and Util.index(migrated_colony.legacy.research, "colony")
        and Util.index(migrated_colony.unlocked, "synaptic_node"),
        "Legacy division unlock must imply colony research and its new signature organ")

    local archived_state = SaveStore.defaults()
    archived_state.families = nil
    archived_state.unlocked = Util.copy(old_unlocked)
    archived_state.legacy = Legacy.defaults()
    archived_state.legacy.research = {"toxic"}
    archived_state.legacy.selected_form = "toxic"
    local old_with_archive = Util.copy(old_profile)
    old_with_archive.checkpoint.family_id = "family-2"
    old_with_archive.families = {
        version = 1, active = "family-2", next_id = 3,
        items = {
            {id = "family-1", name = "Архивная железистая", form = "toxic", slot = 1, state = archived_state},
            {id = "family-2", name = "Активная хищная", form = "predator", slot = 2, state = {}},
        },
    }
    local migrated_archive = SaveStore.normalize_profile(old_with_archive)
    assert(migrated_archive, "Archived family profile must remain valid after migration")
    assert(Util.index(migrated_archive.families.items[1].state.unlocked, "osmotic_vacuole"),
        "Archived family migration must restore the signature organ from its saved research")

    local fresh = SaveStore.defaults()
    fresh.unlocked = Util.copy(old_unlocked)
    fresh.legacy = Legacy.defaults()
    local fresh_clean = SaveStore.normalize_profile(fresh)
    assert(fresh_clean and not Util.index(fresh_clean.unlocked, "osmotic_vacuole")
        and not Util.index(fresh_clean.unlocked, "synaptic_node"),
        "Migration must not grant forms that have not been researched")

    local records = {}
    local backend = {
        get_save_file = function(_, filename) return filename end,
        load = function(path) return Util.copy(records[path]) end,
        save = function(path, record) records[path] = Util.copy(record); return true end,
    }
    local store = SaveStore.new("signature_research", backend)
    store.profile.cores = 12
    assert(not store:unlock("osmotic_vacuole"), "Research-gated organ must not be purchased outside its research")
    assert(store:research("toxic") and Util.index(store.profile.unlocked, "osmotic_vacuole"),
        "Toxic research must unlock the osmotic vacuole")
    assert(store:research("colony") and Util.index(store.profile.unlocked, "synaptic_node")
        and Util.index(store.profile.unlocked, "division"), "Colony research must unlock division and the synaptic node")

    local family_records = {}
    local family_backend = {
        get_save_file = function(_, filename) return filename end,
        load = function(path) return Util.copy(family_records[path]) end,
        save = function(path, record) family_records[path] = Util.copy(record); return true end,
    }
    local family_store = SaveStore.new("signature_families", family_backend)
    assert(family_store:create_family("Железистая", "toxic")
        and Util.index(family_store.profile.unlocked, "osmotic_vacuole"),
        "Creating a researched toxic family must unlock its signature organ")
    assert(family_store:create_family("Колониальная", "colony")
        and Util.index(family_store.profile.unlocked, "synaptic_node")
        and Util.index(family_store.profile.unlocked, "division"),
        "Creating a colony family must unlock its signature organ and division")

    local old_build = Build.new()
    old_build:from_dict({unlocked = old_unlocked, organs = {devour = 1}})
    assert(Util.index(old_build.unlocked, "chemoreceptor_ridge"),
        "Loading a legacy build must append the new baseline signature organ")
    print("MICROGEN FORM SPECIALIZATION DATA READY")
end

local function validate_enemy_markers()
    local sim = Simulation.new(147, nil, nil, "toxic", {form = "toxic", seed = 147})
    local radius = sim:body_radius()
    local frames, labels = {}, {}
    local scene = {
        scale = 3, effects = {},
        draw_combat = function(_, _, frame, _, _, _, color)
            frames[#frames + 1] = {frame = frame, color = color}
        end,
        draw_number = function(_, _, label) labels[#labels + 1] = label end,
    }
    local function inspect(kind, ratio, hp, captured)
        frames, labels = {}, {}
        local actor = {kind = kind, pos = {x = sim.player.x + 100, y = sim.player.y},
            r = radius * ratio, hp = hp, max_hp = 100, captured = captured}
        Effects.draw_enemy_marker(scene, sim, actor, 0.2)
        local green = false
        for _, item in ipairs(frames) do
            assert(item.frame ~= "barb", "Hunter must never show the old orange icon")
            if item.frame == "ring" and item.color.y > 0.9 and item.color.x < 0.6 then green = true end
        end
        local marked = #labels > 0 and labels[#labels] == "ПОГЛОТИТЬ"
        assert(green == marked, "Absorption label and green ring must agree")
        return marked, actor
    end
    assert(inspect("prey", 0.5, 100), "Small prey must be clearly marked")
    assert(inspect("hunter", 1.0, 10), "Weakened edible hunter must be marked")
    assert(not inspect("hunter", 1.0, 100), "Healthy non-edible hunter must not be marked")
    assert(not inspect("hunter", 2.0, 1) and #frames == 1 and frames[1].frame == "ring",
        "Oversized hunter must show threat ring, not an absorption marker")
    assert(not inspect("miniboss", 0.5, 20), "Miniboss above 15 percent health must not be marked")
    assert(inspect("miniboss", 0.5, 15), "Eligible weakened miniboss must be marked")
    assert(not inspect("boss", 0.5, 1), "Boss must never have an absorption marker")
    assert(not inspect("prey", 0.5, 0) and #frames == 0, "Dead actor must not be marked")
    assert(not inspect("prey", 0.5, 100, true) and #frames == 0, "Captured actor must not be marked")
    assert(not inspect("clone", 0.5, 100) and #frames == 0, "Friendly clone must not be marked")
    assert(not inspect(nil, 0.5, 100) and #frames == 0, "Inactive resident must not be marked")
    assert(not inspect("spitter", 1.0, 100) and #frames == 1 and frames[1].frame == "plume",
        "Non-edible spitter must retain its distinct marker")
    print("MICROGEN ENEMY MARKERS READY")
end

local function validate_form_passives()
    local function new(form, branch, traits)
        return Simulation.new(147, nil, nil, branch or form,
            {form = form, branch = branch or form, seed = 147, traits = traits or {}})
    end
    local function near(actual, expected, label)
        assert(math.abs(actual - expected) < 0.00001, label .. ": " .. tostring(actual))
    end
    local function take(sim, amount, source, expected, label)
        sim.hp = sim.max_hp
        sim:hurt_player(amount, source)
        near(sim.max_hp - sim.hp, expected, label)
    end

    -- Убийство не лечит; завершённое поглощение лечит в дополнение к старой пасти.
    local predator = new("predator", "toxic")
    predator.hp = 50
    predator.enemies = {}
    predator:spawn_enemy(predator.player, "prey")
    predator:_die(1, false)
    near(predator.hp, 50, "Kill without absorption must not heal")
    predator:spawn_enemy(predator.player, "prey")
    predator:_die(1, true)
    near(predator.hp, 53.8, "Feast plus existing mouth healing")
    assert(predator.absorbed==1,"Absorption counter must distinguish completed absorption from kills")
    near(predator.cooldowns.form_feast, 5, "Feast cooldown")
    predator:spawn_enemy(predator.player, "prey")
    predator:_die(1, true)
    near(predator.hp, 54.6, "Second absorption must not bypass cooldown")
    assert(predator.absorbed==2,"Absorption counter must include each completed absorption")
    predator.cooldowns.form_feast = 2.5
    local restored = assert(Simulation.restore(predator:snapshot()))
    near(restored.cooldowns.form_feast, 2.5, "Feast cooldown survives checkpoint")
    restored.stage_transition, restored.pending_stage_seed = true, 171
    assert(restored:enter_next_stage())
    near(restored.cooldowns.form_feast, 2.5, "Stage transition must not reset feast cooldown")
    restored.cooldowns.form_feast = 0
    restored.max_hp, restored.hp = 200, 100
    restored:_feast()
    near(restored.hp, 104, "Feast capped at four HP")
    local folds = new("predator", "predator", {"folds"})
    folds.hp = 50
    folds:_feast()
    near(folds.hp, 52.7, "Feast respects inherited healing penalty")
    folds.cooldowns.form_feast, folds.hp = 0, 99
    folds:_feast()
    near(folds.hp, 100, "Feast cannot exceed maximum health")
    local legacy = predator:snapshot()
    legacy.cooldowns.form_feast = nil
    local old = assert(Simulation.restore(legacy))
    assert(old:_ready("form_feast"), "Old checkpoint defaults to ready")

    local toxic = new("toxic", "colony")
    toxic.build.organs.acid = nil
    toxic.enemies = {}
    local enemy = assert(toxic:spawn_enemy(toxic.player, "hunter"))
    enemy.infect = 2
    local contact = {kind = "collision", enemy = enemy}
    take(toxic, 10, contact, 8.2, "Toxic form infected contact")
    enemy.kind = "boss"
    take(toxic, 10, contact, 9.1, "Boss contact reduction")
    enemy.kind = "miniboss"
    take(toxic, 10, contact, 9.1, "Miniboss contact reduction")
    enemy.kind = "hunter"
    take(toxic, 10, {kind = "projectile", enemy = enemy}, 10, "Projectiles unaffected")
    take(toxic, 10, {kind = "toxin", enemy = enemy}, 10, "Hostile toxins unaffected")
    enemy.infect = 0
    enemy.enzyme_time = 2
    toxic.fields = {}
    toxic:_field(enemy.pos, 48, 6, 2, "enemy_toxin", true)
    take(toxic, 10, contact, 9.4, "Enemy toxin and enzymes alone do not qualify for poison bonus")
    toxic:_field(enemy.pos, 48, 6, 2, "poison")
    toxic:_field(enemy.pos, 48, 6, 2, "spore")
    take(toxic, 10, contact, 8.2, "Overlapping player poison does not stack defense")
    enemy.infect = 2
    take(toxic, 10, contact, 8.2, "Infection and fields do not stack defense")
    enemy.infect = 0
    toxic.fields[2].life, toxic.fields[3].life = 0, 0
    take(toxic, 10, contact, 9.4, "Expired player poison does not qualify for poison bonus")
    toxic.build.organs.acid = 1
    take(toxic, 10, contact, 8.2, "Active acid aura counts as player poison")
    toxic.build.adaptations.armor = 3
    take(toxic, 10, contact, 4.6, "Toxic defense adds to armor")
    toxic.build.adaptations.armor = 6
    take(toxic, 10, contact, 4, "Toxic defense obeys 60 percent cap")

    local colony = new("colony", "predator")
    local projectile = {kind = "projectile"}
    take(colony, 10, projectile, 9.7, "Two starter copies protect at three percent")
    colony.build.organs.division = 4
    take(colony, 10, projectile, 9.25, "Five copies protect at seven and a half percent")
    colony.build.specializations.division = "division_hunter_buds"
    assert(colony:active_clone_count() == 6, "Existing specialization still grants sixth copy")
    take(colony, 10, projectile, 9.25, "Sixth copy cannot exceed defense cap")
    colony.build.adaptations.armor = 6
    take(colony, 10, projectile, 4, "Colony and armor obey shared cap")
    colony.build.adaptations.armor = nil
    colony.build.organs.division = nil
    assert(#colony:clone_positions() == 0, "No division means no active copies")
    take(colony, 10, projectile, 10, "No copies means no defense")
    colony.hp = 50
    colony:_feast()
    near(colony.hp, 50, "Colony cannot inherit feast from foreign mouth")
    colony.build.organs.devour, colony.build.organs.acid = 1, 1
    take(colony, 10, contact, 10, "Colony cannot inherit toxic regulation")
    predator.build.organs.division = 4
    predator.build.organs.synaptic_node = 1
    take(predator, 10, projectile, 10, "Foreign copies and signature cannot grant colony passive")
    toxic.hp = 50
    toxic.build.organs.devour = 1
    toxic:_feast()
    near(toxic.hp, 50, "Foreign mouth cannot grant feast")
    local unselected = Simulation.new(147, nil, nil, "colony")
    unselected.build.organs.division = 4
    take(unselected, 10, projectile, 10, "Legacy no-form run retains original behavior")
    print("MICROGEN FORM PASSIVES READY")
end

local function validate_form_abilities()
    local function near(actual,expected,label)
        assert(math.abs(actual-expected)<.0001,label..": "..tostring(actual))
    end
    local expected={
        predator={organ="chemoreceptor_ridge",adapt="magnet",attack="predator_primordial_rage",defense="predator_instinct"},
        toxic={organ="osmotic_vacuole",adapt="catalysis",attack="toxic_cataclysm",defense="toxic_osmotic_cocoon"},
        colony={organ="synaptic_node",adapt="armor",attack="colony_great_swarm",defense="colony_living_bastion"},
    }
    local function fresh(form)
        local sim=Simulation.new(147,nil,nil,form,{form=form,branch=form,seed=147})
        sim.enemies,sim.residents,sim.fields={},{},{}
        local spec=expected[form]
        sim.build.organs[spec.organ]=6
        sim.build.adaptations[spec.adapt]=3
        assert(not sim:form_ability().id and not sim:form_defense().id,
            "Both ultimate abilities stay locked before claiming the form evolution: "..form)
        assert(not sim:form_ability_ready() and not sim:form_defense_ready(),
            "Locked abilities cannot be activated: "..form)
        assert(sim.build:evolve(spec.organ),"Form evolution must unlock after organ VI and adaptation III: "..form)
        assert(sim:form_ability().id==spec.attack and sim:form_defense().id==spec.defense,
            "Only the selected form receives its own unique abilities: "..form)
        return sim
    end

    local predator=fresh("predator")
    local origin=Util.copy(predator.player)
    predator._move_player_against_bodies=function(self,x,y) return {x=self.player.x+x,y=self.player.y+y} end
    local prey=assert(predator:spawn_enemy({x=origin.x+45,y=origin.y},"prey"))
    prey.r,prey.hp,prey.max_hp,prey.tissue_budget=12,100,100,100
    predator.hp=predator.max_hp*.5
    assert(predator:activate_form_defense(),"Predator survival instinct activates")
    near(predator.hp,predator.max_hp*.8,"Predator instantly restores 30% maximum health")
    local hp_before_repeat=predator.hp
    predator.effects={{type="heal",life=1}}
    predator:heal_player(1)
    near(predator.hp,hp_before_repeat+1,"Healing can safely reuse a visual effect without an amount")
    assert(predator.effects[1].amount==1,"Repeated healing initializes a missing effect amount")
    predator.effects={}
    assert(predator.cooldowns.predator_escape_active==6 and predator.cooldowns.special_defense==75,
        "Predator defense duration and long cooldown")
    local fast,normal=fresh("predator"),fresh("predator")
    fast.enemies,fast.residents,fast.fields={}, {}, {}
    normal.enemies,normal.residents,normal.fields={}, {}, {}
    local function free_move(self,dx,dy) return {x=self.player.x+dx,y=self.player.y+dy} end
    fast._move_player_against_bodies,normal._move_player_against_bodies=free_move,free_move
    fast.cooldowns.predator_escape_active=6
    local fast_start,normal_start=fast.player.x,normal.player.x
    fast:step(.1,1,0)
    normal:step(.1,1,0)
    near((fast.player.x-fast_start)/(normal.player.x-normal_start),1.45,
        "Survival instinct increases actual movement speed by 45%")
    assert(predator:activate_form_ability(1,0) and not predator:activate_form_ability(1,0),
        "Predator ultimate attack starts once")
    assert(predator.form_action.kind=="dash" and predator.cooldowns.special_attack==55
        and predator.cooldowns.predator_frenzy_active==5,"Primordial rage starts dash and bite frenzy")
    near(predator:form_ability().damage_multiplier,3,"Primordial rage triple bite")
    near(predator:form_ability().frenzy_multiplier,1.60,"Primordial rage follow-up bite bonus")
    local restored_predator=assert(Simulation.restore(predator:snapshot()))
    assert(restored_predator.form_action.kind=="dash" and restored_predator.cooldowns.special_attack==55
        and restored_predator.cooldowns.special_defense==75
        and restored_predator.cooldowns.predator_escape_active==6
        and restored_predator.cooldowns.predator_frenzy_active==5,
        "Predator ultimate effects and both cooldowns survive checkpoint")
    local legacy_checkpoint=predator:snapshot()
    legacy_checkpoint.cooldowns.special_attack=nil
    legacy_checkpoint.cooldowns.special_defense=nil
    legacy_checkpoint.cooldowns.form_ability=12
    legacy_checkpoint.cooldowns.defense_active=3
    legacy_checkpoint.cooldowns.defense_cooldown=21
    legacy_checkpoint.cooldowns.emergency_regen_cooldown=14
    legacy_checkpoint.cooldowns.toxic_cocoon_active=3
    legacy_checkpoint.cooldowns.colony_swarm_active=3
    legacy_checkpoint.cooldowns.colony_bastion_active=3
    legacy_checkpoint.colony_bastion_hp=20
    local migrated=assert(Simulation.restore(legacy_checkpoint))
    assert(migrated.cooldowns.special_attack==12 and migrated.cooldowns.special_defense==nil
        and migrated.cooldowns.form_ability==nil and migrated.cooldowns.defense_active==nil
        and migrated.cooldowns.defense_cooldown==nil and migrated.cooldowns.emergency_regen_cooldown==nil,
        "Legacy checkpoints migrate attack cooldown and remove universal defensive timers")
    assert(migrated.cooldowns.predator_escape_active==6 and migrated.cooldowns.predator_frenzy_active==5
        and migrated.cooldowns.toxic_cocoon_active==nil and migrated.cooldowns.colony_swarm_active==nil
        and migrated.cooldowns.colony_bastion_active==nil and migrated.colony_bastion_hp==0,
        "Checkpoint restore rejects active effects belonging to other forms")
    restored_predator.stage_transition=true
    restored_predator.pending_stage_seed=restored_predator.world.seed_value+100
    assert(restored_predator:enter_next_stage(),"Predator can enter next stage")
    assert(restored_predator.cooldowns.special_attack==55 and restored_predator.cooldowns.special_defense==75
        and restored_predator.cooldowns.predator_escape_active==6 and restored_predator.cooldowns.predator_frenzy_active==5
        and not restored_predator.form_action.kind,
        "Attack/defense cooldowns and active effects survive stage transition")
    predator:_advance_dash(.24)
    local rank=predator.build:rank("devour")
    local expected_dash_damage=Catalog.scaled_damage(7+rank*5,rank)*3
    near(100-prey.hp,expected_dash_damage,
        "Primordial rage dash bite is exactly triple power; the follow-up frenzy does not multiply it again")
    assert(not predator.form_action.kind and predator.player.x>origin.x,
        "Primordial rage performs a collision-checked dash bite")
    prey.hp,prey.tissue_budget=100,100
    local followup_damage=predator:hit_enemy(prey,Catalog.scaled_damage(12,1),"devour")
    near(followup_damage,Catalog.scaled_damage(12,1)*1.60,
        "Primordial rage increases subsequent ordinary bites by 60%")

    local toxic=fresh("toxic")
    toxic.fields={
        {pos=Util.copy(toxic.player),r=90,life=4,damage=3,hostile=true,kind="enemy_spore"},
        {pos=Util.copy(toxic.player),r=70,life=4,damage=3,hostile=true,kind="enemy_toxin"},
        {pos=Util.copy(toxic.player),r=70,life=4,damage=3,hostile=true,kind="enemy_projectile"},
        {pos=Util.copy(toxic.player),r=70,life=4,damage=3,hostile=false,kind="poison"},
    }
    assert(toxic:activate_form_defense(),"Osmotic cocoon activates")
    assert(#toxic.fields==2 and toxic.fields[1].kind=="enemy_projectile" and toxic.fields[2].kind=="poison"
        and toxic.cooldowns.toxic_cocoon_active==6 and toxic.cooldowns.special_defense==75,
        "Osmotic cocoon clears only nearby enemy toxin/spore clouds")
    local toxic_hp=toxic.hp
    toxic:hurt_player(100,{kind="projectile",name="Проверка осмотического кокона"})
    near(toxic.hp,toxic_hp-25,"Osmotic cocoon reduces incoming damage by 75%")
    assert(toxic:activate_form_ability(),"Toxic cataclysm activates")
    local field=toxic.fields[#toxic.fields]
    assert(field and field.kind=="rupture" and field.source=="acid")
    near(field.life,8,"Toxic cataclysm field duration")
    near(field.damage,Catalog.scaled_damage(7,1)*1.35,"Toxic cataclysm enhanced acid damage")
    near(field.rupture_strength,.40,"Toxic cataclysm slow strength")
    assert(toxic.cooldowns.special_attack==60,"Toxic cataclysm long attack cooldown")
    local toxic_enemy=assert(toxic:spawn_enemy(toxic.player,"hunter"))
    toxic_enemy.r,toxic_enemy.hp,toxic_enemy.max_hp,toxic_enemy.tissue_budget=12,100,100,100
    toxic:_update_fields(.1)
    near(toxic_enemy.rupture_strength,.40,"Toxic cataclysm applies the promised slow")
    local restored_toxic=assert(Simulation.restore(toxic:snapshot()))
    assert(restored_toxic.cooldowns.special_attack==60 and restored_toxic.cooldowns.special_defense==75
        and restored_toxic.cooldowns.toxic_cocoon_active>0 and restored_toxic.fields[#restored_toxic.fields].kind=="rupture",
        "Toxic abilities, active field and cooldowns survive checkpoint")

    local colony=fresh("colony")
    colony.build.organs.division=4
    local base_clones=#colony:clone_positions()
    assert(colony:activate_form_defense(),"Living bastion activates")
    assert(colony.cooldowns.colony_bastion_active==8 and colony.colony_bastion_hp==colony.max_hp*.70
        and colony.cooldowns.special_defense==80,"Living bastion has limited durability and long cooldown")
    assert(colony:activate_form_ability(),"Great swarm activates")
    assert(colony.cooldowns.colony_swarm_active==10 and colony.cooldowns.special_attack==65
        and #colony:clone_positions()==base_clones+2,
        "Great swarm creates two additional visible combat copies")
    local colony_base,colony_swarm=fresh("colony"),fresh("colony")
    colony_base.build.organs.division=4
    colony_swarm.build.organs.division=4
    colony_swarm.cooldowns.colony_swarm_active=10
    local base_target=assert(colony_base:spawn_enemy(Util.copy(colony_base.player),"prey"))
    local swarm_target=assert(colony_swarm:spawn_enemy(Util.copy(colony_swarm.player),"prey"))
    base_target.r,base_target.hp,base_target.max_hp,base_target.tissue_budget=12,1000,1000,1000
    swarm_target.r,swarm_target.hp,swarm_target.max_hp,swarm_target.tissue_budget=12,1000,1000,1000
    local base_clone_damage=colony_base:hit_enemy(base_target,10,"division")
    local swarm_clone_damage=colony_swarm:hit_enemy(swarm_target,10,"division")
    near(swarm_clone_damage,base_clone_damage*1.60,"Great swarm increases real clone damage by 60%")
    local restored_colony=assert(Simulation.restore(colony:snapshot()))
    near(restored_colony.colony_bastion_hp,colony.max_hp*.70,"Living bastion durability survives checkpoint")
    assert(restored_colony.cooldowns.colony_bastion_active==8 and restored_colony.cooldowns.colony_swarm_active==10
        and restored_colony.cooldowns.special_attack==65 and restored_colony.cooldowns.special_defense==80
        and #restored_colony:clone_positions()==base_clones+2,
        "Colony ultimate effects and both cooldowns survive checkpoint")
    restored_colony.stage_transition=true
    restored_colony.pending_stage_seed=restored_colony.world.seed_value+100
    assert(restored_colony:enter_next_stage(),"Colony can enter next stage")
    near(restored_colony.colony_bastion_hp,colony.max_hp*.70,"Living bastion durability survives stage transition")
    assert(restored_colony.cooldowns.colony_bastion_active==8 and restored_colony.cooldowns.colony_swarm_active==10
        and restored_colony.cooldowns.special_attack==65 and restored_colony.cooldowns.special_defense==80,
        "Colony shield, swarm and both cooldowns survive stage transition")
    local hp_before=colony.hp
    local function expected_bastion_damage(amount)
        local residual=amount*(1-colony:damage_reduction({kind="projectile"}))
        local absorbed=math.min(residual*.85,colony.colony_bastion_hp)
        return residual-absorbed,absorbed
    end
    local expected1,absorbed1=expected_bastion_damage(20)
    colony:hurt_player(20,{kind="projectile",name="Проверка бастиона"})
    near(colony.hp,hp_before-expected1,"Living bastion absorbs 85% of first hit")
    near(colony.colony_bastion_hp,colony.max_hp*.70-absorbed1,"Living bastion spends limited durability")
    local hp_before_second=colony.hp
    local expected2=expected_bastion_damage(1000)
    colony:hurt_player(1000,{kind="projectile",name="Проверка бастиона"})
    near(colony.hp,hp_before_second-math.min(hp_before_second,expected2),
        "Living bastion allows damage through after its finite shield is depleted")
    assert(colony.colony_bastion_hp==0 and colony.cooldowns.colony_bastion_active==0,
        "Living bastion ends when its finite shield is depleted")

    local hybrid=Simulation.new(147,nil,nil,"predator",{form="predator",branch="predator",seed=147})
    hybrid.build.organs.osmotic_vacuole=6
    hybrid.build.adaptations.catalysis=3
    hybrid.build.stats.evolutions.osmotic_vacuole=true
    assert(not hybrid.build:evolved("osmotic_vacuole") and not hybrid:form_ability().id
        and not hybrid:form_defense().id,
        "A foreign signature organ never unlocks another form's ultimate buttons")
    local hollow_colony=fresh("colony")
    hollow_colony.build.organs.division=0
    assert(hollow_colony:form_defense().id=="colony_living_bastion"
        and not hollow_colony:form_defense_ready() and not hollow_colony:activate_form_defense(),
        "Living bastion remains unlocked but cannot activate without living copies")
    assert(Catalog.FORM_SPECIALIZATIONS.colony.defense.capacity_fraction==.70,
        "Colony bastion capacity is raised to 55 percent after balance review")
    assert(Catalog.FORM_SPECIALIZATIONS.colony.evolution.maximum_reduction==.12,
        "Collective mind membrane reduction cap is raised to nine percent")
    print("MICROGEN FORM ULTIMATE ABILITIES READY")
    print("MICROGEN COLONY BALANCE READY")
end

local function validate_signature_organs()
    local function near(a,b,msg) assert(math.abs(a-b)<.00001,msg..": "..tostring(a)) end
    local function fresh(form)
        local sim=Simulation.new(147,nil,nil,form,{form=form,branch=form,seed=147})
        sim.enemies,sim.residents,sim.fields={}, {}, {}
        return sim
    end
    local function enemy(sim,x,kind,hp,r)
        local e=assert(sim:spawn_enemy({x=sim.player.x+x,y=sim.player.y},kind))
        e.hp,e.max_hp,e.r,e.tissue_budget=hp,100,r,100
        return e
    end
    local sim=fresh("toxic")
    sim.build.organs.chemoreceptor_ridge=1
    local weak=enemy(sim,50,"hunter",50,sim:body_radius())
    local prey=enemy(sim,100,"prey",8,8)
    sim:_update_chemoreceptor()
    assert(sim:is_chemoreceptor_marked(prey) and not sim:is_chemoreceptor_marked(weak),"Prefer absorbable target")
    near(sim:marked_bite_multiplier(prey),1.08,"Base marked bite")
    near(sim.cooldowns.chemoreceptor_mark,4,"Retarget interval")
    near(sim.signature_mark_until-sim.elapsed,2.5,"Base mark duration")
    local saved=assert(Simulation.restore(sim:snapshot()))
    assert(saved:is_chemoreceptor_marked(saved.enemies[2]),"Mark survives checkpoint")
    sim.build.organs.chemoreceptor_ridge=6
    sim.build.specializations.chemoreceptor_ridge="chemoreceptor_deep_sensor"
    local radius,duration,bonus=sim:chemoreceptor_parameters()
    near(radius,264,"Deep sensor");near(duration,3.2,"Rank three");near(bonus,.12,"Rank six")
    sim.build.specializations.chemoreceptor_ridge="chemoreceptor_neural_sight"
    radius,duration=sim:chemoreceptor_parameters()
    near(radius,220,"Exclusive specialization");near(duration,4.2,"Neural sight")
    local prev=sim.signature_mark_id
    sim:_update_chemoreceptor()
    assert(sim.signature_mark_id==prev,"No premature retarget")
    sim.build.organs.chemoreceptor_ridge=nil
    assert(not sim:is_chemoreceptor_marked(prey),"Removed organ loses mark")

    local toxic=fresh("toxic")
    toxic.build.organs.osmotic_vacuole=6
    toxic.build.adaptations.catalysis=3
    toxic.build.specializations.osmotic_vacuole="vacuole_stable_chamber"
    assert(toxic.build:evolve("osmotic_vacuole"),"Vacuole charge fixture must receive its own ultimate evolution")
    local a=enemy(toxic,30,"hunter",100,10)
    toxic:hit_enemy(a,1,"acid")
    toxic:hit_enemy(a,1,"acid")
    assert(toxic:vacuole_charge_count()==1,"Repeated ticks cannot farm charges")
    near(toxic.vacuole_charges[1]-toxic.elapsed,26,"Stable chamber")
    for i=1,5 do local e=enemy(toxic,40+i,"hunter",100,10);toxic:hit_enemy(e,1,"infection") end
    assert(toxic:vacuole_charge_count()==4,"Rank six cap")
    local restored=assert(Simulation.restore(toxic:snapshot()))
    assert(restored:vacuole_charge_count()==4,"Charges survive checkpoint")
    toxic.build.specializations.osmotic_vacuole="vacuole_hyperosmotic_sac"
    assert(toxic:activate_form_ability())
    local f=toxic.fields[1]
    near(f.life,9,"Cataclysm duration includes four stored charges")
    local base=(75+9)*toxic.build:specialization_value("acid","radius_mult")*toxic:ability_scale()
    near(f.r,base*2.0*1.32*1.15,"Cataclysm radius includes ability and vacuole charge multipliers")
    near(f.damage,Catalog.scaled_damage(7,1)*1.35,"Cataclysm damage multiplier")
    assert(toxic:vacuole_charge_count()==0,"Activation consumes charges")
    toxic.elapsed=8
    toxic:_vacuole_charge(a)
    assert(toxic:vacuole_charge_count()==1,"Target can charge again after eight seconds")
    toxic.elapsed=35
    assert(toxic:vacuole_charge_count()==0,"Expired charges disappear after their full lifetime")

    local colony=fresh("predator")
    colony.build.organs.division=4
    colony.build.organs.synaptic_node=6
    local target=enemy(colony,100,"hunter",100,10)
    local hits={}
    colony.hit_enemy=function(_,e,amount,source) hits[#hits+1]=amount;return amount end
    colony:_synaptic_hit(target,10,1)
    colony:_synaptic_hit(target,10,1)
    colony:_synaptic_hit(target,10,2)
    colony:_synaptic_hit(target,10,3)
    colony:_synaptic_hit(target,10,4)
    colony:_synaptic_hit(target,10,5)
    colony:_synaptic_hit(target,10,6)
    near(hits[1],10,"First copy");near(hits[2],10,"Same copy cannot stack")
    near(hits[3],10.5,"Second copy");near(hits[6],12,"Rank six cap");near(hits[7],12,"Sixth copy capped")
    colony.elapsed=2.01
    colony:_synaptic_hit(target,10,1)
    near(hits[8],10,"Coordination expires")
    colony.build.specializations.synaptic_node="synapse_branched_network"
    local r=colony:synaptic_parameters()
    near(r,316.8,"Branched network radius")
    colony.build.specializations.synaptic_node="synapse_protective_network"
    near(colony:damage_reduction({kind="projectile"}),.015,"Gear protection in hybrid")
    colony.build.adaptations.armor=6
    near(colony:damage_reduction({kind="projectile"}),.6,"Armor cap")
    assert(not colony:form_ability().id and not colony:form_defense().id and colony:form_passive().id=="feast",
        "A signature organ does not unlock ultimate abilities before the matching evolution")
    print("MICROGEN SIGNATURE ORGANS READY")
end

local function validate_form_evolutions_and_synergies()
    local function near(a,b,label) assert(math.abs(a-b)<.00001,label..": "..tostring(a)) end
    local function fresh(form)
        local sim=Simulation.new(147,nil,nil,form,{form=form,branch=form,seed=147})
        sim.enemies,sim.fields,sim.residents={},{},{}
        sim.build.organ_capacity=40
        return sim
    end
    local function target(sim)
        local e=assert(sim:spawn_enemy({x=sim.player.x+100,y=sim.player.y},"hunter"))
        e.r,e.hp,e.max_hp,e.tissue_budget=10,100,100,100
        return e
    end
    local function evolve(sim,id,adapt)
        sim.build.organs[id]=5;sim.build.adaptations[adapt]=3
        assert(not sim.build:evolve(id),"Rank five is insufficient")
        sim.build.organs[id]=6;sim.build.adaptations[adapt]=2
        assert(not sim.build:evolve(id),"Adaptation rank two is insufficient")
        sim.build.adaptations[adapt]=3
        sim.reward_queue={{tier=2,token="form-evolution-fixture"}}
        sim.reward_options={}
        local options=sim:prepare_reward()
        assert(options[1].kind=="evolution" and options[1].id==id,"Own form evolution offered through reward")
        assert(sim:claim_reward(1) and sim.build:evolved(id),"Reward activates evolution")
        assert(not sim.build:evolve(id),"Evolution cannot be claimed twice")
    end
    local function equipment_roundtrip(sim,id,adapt,form)
        local profile=SaveStore.defaults()
        profile.organism=nil
        profile.legacy=Legacy.defaults()
        profile.legacy.selected_form=form
        profile.checkpoint={build=sim.build:to_dict()}
        local state,err=StageRewards.capture_equipment(profile,sim.build)
        assert(state,err or "Evolved equipment must be capturable")
        local found=false
        for _,part in ipairs(state.equipped) do if part.kind==id and part.evolved then found=true end end
        assert(found,"Evolution flag must survive family equipment capture")
        local family=Build.new()
        family.form=form
        family.unlocked=Util.copy(Catalog.base_unlocked())
        StageRewards.apply_equipment(state,family)
        assert(family:rank(id)==6 and family.stats.evolutions[id],"Family equipment must restore evolved organ")
        assert(not family:evolved(id),"Evolution stays dormant until its passive requirement is met")
        family.adaptations[adapt]=3
        assert(family:evolved(id),"Restored evolution activates again when its requirement is met")
    end
    local pred=fresh("predator")
    pred.build.branch="toxic"
    evolve(pred,"chemoreceptor_ridge","magnet")
    near(pred:form_ability().cooldown, 55,"Primordial rage cooldown")
    near(pred.build:power("chemoreceptor_ridge"),1,"No generic damage multiplier on form evolution")
    local restored=assert(Simulation.restore(pred:snapshot()))
    near(restored:form_ability().cooldown, 55,"Evolution survives reload")
    equipment_roundtrip(pred,"chemoreceptor_ridge","magnet","predator")
    local foreign=fresh("toxic")
    foreign.build.organs.chemoreceptor_ridge=6
    foreign.build.adaptations.magnet=3
    assert(not foreign.build:evolve("chemoreceptor_ridge"),"Foreign form cannot evolve signature")
    foreign.build.stats.evolutions.chemoreceptor_ridge=true
    assert(not foreign.build:evolved("chemoreceptor_ridge") and not foreign:form_ability().id and not foreign:form_defense().id,
        "Foreign evolved organ never unlocks another form's ultimate abilities")
    local toxic=fresh("toxic")
    evolve(toxic,"osmotic_vacuole","catalysis")
    assert(toxic:activate_form_ability())
    near(toxic.fields[1].life,8,"Toxic cataclysm duration")
    near(toxic.fields[1].rupture_strength,.40,"Toxic cataclysm slow")
    near(toxic.fields[1].damage,Catalog.scaled_damage(7,1)*1.35,"Toxic cataclysm enhanced DPS")
    local e=target(toxic);e.pos=toxic.player
    toxic:_update_fields(.1)
    near(e.rupture_strength,.40,"Toxic cataclysm slows actual target")
    equipment_roundtrip(toxic,"osmotic_vacuole","catalysis","toxic")
    local colony=fresh("colony")
    evolve(colony,"synaptic_node","armor")
    colony.build.organs.division=4
    near(colony:form_ability().cooldown,65,"Great swarm cooldown")
    near(colony:damage_reduction({kind="projectile"}),colony.build:passive("armor")+.12,"Collective defense")
    colony.build.adaptations.armor=6
    near(colony:damage_reduction({kind="projectile"}),.60,"Armor cap")
    equipment_roundtrip(colony,"synaptic_node","armor","colony")
    local base_clone_count=#colony:clone_positions()
    assert(colony:activate_form_ability())
    assert(colony.cooldowns.colony_swarm_active==10 and #colony:clone_positions()==base_clone_count+2,
        "Great swarm adds two temporary combat copies")
    local reload=assert(Simulation.restore(colony:snapshot()))
    assert(reload.cooldowns.colony_swarm_active==10 and #reload:clone_positions()==base_clone_count+2,
        "Temporary combat copies and their timer survive checkpoint")
    local cap_target=target(colony)
    cap_target.tissue_budget=1
    local swarm_actual=colony:hit_enemy(cap_target,100,"division")
    near(swarm_actual,1,"Great swarm still respects the enemy tissue damage budget")

    pred.build.organs.enzymes=1
    local marked=target(pred)
    pred.signature_mark_id,pred.signature_mark_until=marked.id,pred.elapsed+3
    pred:_apply_enzymes(marked,4)
    near(marked.enzyme_time,5,"Marked enzyme duration")
    pred:_apply_enzymes(marked,4)
    near(marked.enzyme_time,5,"Enzyme duration not multiplied repeatedly")
    local unmarked=target(pred)
    pred:_apply_enzymes(unmarked,4);near(unmarked.enzyme_time,4,"Unmarked duration")
    pred.build.organs.osmotic_vacuole=1
    marked.infect=2
    pred.cooldowns.special_attack=8
    pred.vacuole_charges={pred.elapsed+10}
    pred:hit_enemy(marked,1,"devour")
    near(pred.cooldowns.special_attack,7,"Acid bite refund")
    assert(pred:vacuole_charge_count()==1,"Acid bite must not consume a vacuole charge")
    pred:hit_enemy(marked,1,"devour")
    near(pred.cooldowns.special_attack,7,"Acid bite cooldown prevents repeat")
    pred.cooldowns.acid_bite=0;marked.infect=0;pred.fields={}
    pred:hit_enemy(marked,1,"devour")
    near(pred.cooldowns.special_attack,7,"Unpoisoned bite does not refund")
    pred.build.organs.synaptic_node=1;pred.build.organs.barrier=1;pred.build.organs.division=1
    local base=Catalog.scaled_damage(14,1)*pred.build:power("barrier")
    near(pred:barrier_capacity(),base*1.2,"Two clones increase shield")
    pred.build.organs.division=4
    near(pred:barrier_capacity(),base*1.3,"Shield cap")
    pred.build.organs.division=nil
    near(pred:barrier_capacity(),base,"No copies, no shield bonus")
    local protected,unprotected=fresh("toxic"),fresh("toxic")
    for _,probe in ipairs({protected,unprotected}) do
        probe.build.organs.synaptic_node=1;probe.build.organs.barrier=1;probe.build.organs.division=1
        probe.hp=100
    end
    unprotected.build.active_synergies=function() return {} end
    protected:hurt_player(100,{kind="projectile"})
    unprotected:hurt_player(100,{kind="projectile"})
    assert(protected.hp>unprotected.hp,"Shared shell must reduce actual damage through the barrier, not only the preview value")
    assert(#Catalog.EVOLUTION_IDS==9 and #Catalog.SYNERGY_IDS==13,"Preserve old recipes and add three each")
    print("MICROGEN FORM EVOLUTIONS SYNERGIES READY")
end
-- Изолированная проверка цепочки стадий; не измеряет боевую сложность.
local function validate_stage_progression()
    for _, scenario in ipairs(BRANCHES) do
        local sim=Simulation.new(147,nil,nil,scenario.form,{form=scenario.form,branch=scenario.form,seed=147})
        for stage=1,2 do
            sim.enemies={}
            local target=sim:stage_miniboss_target()
            assert(#sim.world.nests>=target*2,"Not enough nests for stage progression")
            for n=1,target do
                for j=1,n*2 do sim.world.nests[j].used=true end
                sim:_update_minibosses()
                assert(sim.minibosses_spawned==n,"Miniboss gate")
                assert(sim.enemies[#sim.enemies].kind=="miniboss")
                sim:_die(#sim.enemies,false)
                assert(sim.minibosses_defeated==n,"Miniboss defeat gate")
            end
            local boss=assert(sim:spawn_enemy(sim.world.boss_pos,"boss"))
            assert(boss.kind=="boss")
            sim:_die(#sim.enemies,false)
            assert(sim.stage_transition and sim.boss_reward.organ,"Boss defeat must unlock stage")
            settle_stage(sim)
            assert(sim.stage_index==stage+1 and not sim.stage_transition and sim.minibosses_defeated==0,"Stage transition/reset")
        end
        print("MICROGEN STAGE PROGRESSION READY form="..scenario.form.." stage="..sim.stage_index)
    end
end

function M.run()
    validate_colony_combat_pilot()
    validate_toxic_combat_pilot()
    validate_stage_progression()
    validate_progression_pilot()
    validate_objective_combat_range()
    validate_boss_regeneration()
    validate_form_specialization_data()
    validate_form_evolutions_and_synergies()
    validate_signature_organs()
    validate_form_abilities()
    validate_form_passives()
    validate_enemy_markers()
    validate_save_recovery()
    validate_toxin_overlap()
    validate_colony_coverage()
    validate_contact_balance()
    validate_resident_start_safety()
    validate_combat_checkpoint()
    local active_form_results={}
    local form_ability_counters={}
    for _,scenario in ipairs(BRANCHES) do
        local seconds,levels,kills,absorbed,dealt,damage,stages,survivors=0,0,0,0,0,0,0,0
        local paired={}
        for _,seed in ipairs(SEEDS) do
            local result=run(seed,scenario)
            paired[seed]=result
            seconds,levels,kills,absorbed,dealt,damage,stages=seconds+result.seconds,levels+result.level,
                kills+result.kills,absorbed+result.absorbed,dealt+result.damage_dealt,
                damage+result.damage_taken,stages+result.stage
            if result.alive then survivors=survivors+1 end
            collectgarbage("collect")
        end
        active_form_results[scenario.form]=paired
        print(string.format("MICROGEN BALANCE SUMMARY branch=%s maps=%d mean_seconds=%.1f mean_stage=%.2f mean_level=%.2f mean_kills=%.2f mean_absorbed=%.2f mean_damage_dealt=%.1f mean_damage_taken=%.1f survivors=%d",
            scenario.form,#SEEDS,seconds/#SEEDS,stages/#SEEDS,levels/#SEEDS,kills/#SEEDS,
            absorbed/#SEEDS,dealt/#SEEDS,damage/#SEEDS,survivors))
    end
    -- BRANCHES — контрольные базовые забеги без высшей эволюции; обе способности закрыты.
    for _,scenario in ipairs(HYBRID_SCENARIOS) do
        local active=run_batch("MICROGEN HYBRID BALANCE RUN",scenario,HYBRID_SEEDS)
        local control=Util.copy(scenario)
        control.name=scenario.name.." · без эффекта синергии"
        control.expected_synergies=nil
        control.disabled_synergy=scenario.expected_synergies[1]
        local controls=run_batch("MICROGEN HYBRID CONTROL RUN",control,HYBRID_SEEDS)
        print_pair_comparison("синергия_"..scenario.name,active,controls,HYBRID_SEEDS)
    end
    for _,scenario in ipairs(EVOLUTION_SCENARIOS) do
        local control=Util.copy(scenario)
        control.name="без высшей эволюции"
        control.block_evolution=true
        local controls=run_batch("MICROGEN EVOLUTION BALANCE RUN",control,SEEDS)
        local evolved=Util.copy(scenario)
        evolved.name="с высшей эволюцией"
        evolved.evolve=true
        local active=run_batch("MICROGEN EVOLUTION BALANCE RUN",evolved,SEEDS)
        print_pair_comparison("высшая_эволюция_"..scenario.name,active,controls,SEEDS)

        local specialization=Util.copy(evolved)
        specialization.name="атака + защита"
        local combined=run_batch("MICROGEN SPECIALIZATION RUN",specialization,SPECIALIZATION_SEEDS)

        local attack_control=Util.copy(specialization)
        attack_control.name="только защита"
        attack_control.use_ability=false
        local defense_only=run_batch("MICROGEN SPECIALIZATION RUN",attack_control,SPECIALIZATION_SEEDS)
        print_pair_comparison("атака_"..scenario.name,combined,defense_only,SPECIALIZATION_SEEDS)

        local defense_control=Util.copy(specialization)
        defense_control.name="только атака"
        defense_control.use_defense=false
        local attack_only=run_batch("MICROGEN SPECIALIZATION RUN",defense_control,SPECIALIZATION_SEEDS)
        print_pair_comparison("защита_"..scenario.name,combined,attack_only,SPECIALIZATION_SEEDS)

        local ability=Catalog.form_specialization(scenario.form)
        local attack_count,defense_count=0,0
        for _,seed in ipairs(SPECIALIZATION_SEEDS) do
            attack_count=attack_count+(combined[seed].attack_uses or 0)+(attack_only[seed].attack_uses or 0)
            defense_count=defense_count+(combined[seed].defense_uses or 0)+(defense_only[seed].defense_uses or 0)
        end
        assert(attack_count>0,"Evolved form attack ability was never activated: "..scenario.form)
        assert(defense_count>0,"Evolved form defense ability was never activated: "..scenario.form)
        form_ability_counters[scenario.form]={attack_id=ability.ability.id,attack_uses=attack_count,
            defense_id=ability.defense.id,defense_uses=defense_count}

        -- Контроль с той же высшей эволюцией, но без обеих активных кнопок:
        -- отделяет эффект способностей от постоянных бонусов эволюции.
        local no_abilities=Util.copy(specialization)
        no_abilities.name="без обеих способностей"
        no_abilities.use_ability=false
        no_abilities.use_defense=false
        local neither=run_batch("MICROGEN SPECIALIZATION RUN",no_abilities,SPECIALIZATION_SEEDS)
        print_pair_comparison("обе_способности_"..scenario.name,combined,neither,SPECIALIZATION_SEEDS)
    end
    -- Не заменяем контрольную матрицу: ещё 12 честных прогонов на тех же seed.
    -- Обычный старт и подготовленная высшая форма измеряются отдельно.
    for _,scenario in ipairs(BRANCHES) do
        local objective=Util.copy(scenario)
        objective.progression=true
        objective.name="прохождение со старта"
        run_batch("MICROGEN OBJECTIVE RUN",objective,SPECIALIZATION_SEEDS)
    end
    for _,scenario in ipairs(EVOLUTION_SCENARIOS) do
        local objective=Util.copy(scenario)
        objective.progression=true
        objective.evolve=true
        objective.name="прохождение высшей формой"
        run_batch("MICROGEN OBJECTIVE RUN",objective,SPECIALIZATION_SEEDS)
    end
    for _,form in ipairs({"predator","toxic","colony"}) do
        local counters=assert(form_ability_counters[form],"Missing six-ability counter row: "..form)
        print(string.format("MICROGEN FORM ABILITY COUNTERS form=%s attack_id=%s attack_uses=%d defense_id=%s defense_uses=%d",
            form,counters.attack_id,counters.attack_uses,counters.defense_id,counters.defense_uses))
    end
    print("MICROGEN FORM ABILITY COUNTERS READY")
    print("MICROGEN OBJECTIVE MATRIX READY")
    print("MICROGEN STAGE SIX BALANCE READY")
    print("MICROGEN BALANCE SMOKE READY")
end

return M
