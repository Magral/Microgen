-- Microgen v1.4.1 organ, adaptation, and evolution data.
local M = {}

M.ORGAN_IDS = { "tentacle", "acid", "spikes", "pulse", "division", "trail", "infection", "cilia", "enzymes", "electric", "barrier", "devour", "chemoreceptor_ridge", "osmotic_vacuole", "synaptic_node" }

M.ORGANS = {
    tentacle = { name = "Щупальца", branch = "predator", desc = "Хлещут ближайших врагов. Каждый ранг добавляет рабочее щупальце. Суммарная сила залпа распределяется между ними.", color = "6ef1cb" },
    acid = { name = "Кислотная оболочка", branch = "toxic", desc = "Растворяет врагов рядом с телом.", color = "c3f56e" },
    spikes = { name = "Шипы", branch = "predator", desc = "Выстреливают веером в ближайшую цель.", color = "f4d394" },
    pulse = { name = "Сокращение мембраны", branch = "predator", desc = "Отталкивает врагов круговой волной.", color = "98caff" },
    division = { name = "Деление", branch = "colony", desc = "Копии кружат вокруг амёбы и атакуют врагов.", color = "e7a7f5", unlock = 8 },
    trail = { name = "Ядовитый след", branch = "toxic", desc = "Оставляет за собой отравленную среду.", color = "9ce57c" },
    infection = { name = "Заражение", branch = "toxic", desc = "Заражает ближайшего врага; инфекция наносит урон со временем.", color = "ffafbf" },
    cilia = { name = "Ресничный веер", branch = "predator", desc = "Рассекает ткань широким передним веером.", color = "bce9d2" },
    enzymes = { name = "Ферментативные железы", branch = "toxic", desc = "Помечают цель растворяющими ферментами.", color = "f0c575" },
    electric = { name = "Биоразряд", branch = "colony", desc = "Разряд перескакивает между соседними противниками.", color = "9cddf2" },
    barrier = { name = "Сократительный щит", branch = "colony", desc = "Периодически поглощает часть входящего удара.", color = "b6bdec" },
    devour = { name = "Хищная пасть", branch = "predator", desc = "Разрывает ткань спереди: укус, более ранний захват и быстрое переваривание через пасть. Боковое поглощение слабее.", color = "ffbd88" },
    chemoreceptor_ridge = { name = "Хеморецепторный гребень", branch = "predator", desc = "Отмечает одну уязвимую цель каждые 4 с, усиливает пасть. Доступен гибридам после открытия; нужна пасть для бонуса урона.", color = "b58cff", signature = true, form = "predator", icon = "magnet" },
    osmotic_vacuole = { name = "Осмотическая вакуоль", branch = "toxic", desc = "Накапливает заряды от урона ядом. Усиливает Токсический катаклизм после высшей эволюции.", color = "a8e86f", signature = true, form = "toxic", icon = "acid", research_unlock = "toxic" },
    synaptic_node = { name = "Синаптический узел", branch = "colony", desc = "Светящиеся связи копий усиливают согласованные удары. Работает в гибриде с делением, не увеличивая число копий.", color = "c5a0f5", signature = true, form = "colony", icon = "electric", research_unlock = "colony" },
}

M.ADAPTATION_IDS = { "metabolism", "catalysis", "armor", "regen", "speed", "magnet" }

M.ADAPTATIONS = {
    metabolism = { name = "Усиленное усвоение", desc = "Повышает получаемую ДНК.", color = "b7eb9e" },
    catalysis = { name = "Каталитические белки", desc = "Усиливают базовый урон органов.", color = "e9bb91" },
    armor = { name = "Плотная мембрана", desc = "Ранг и качество снижают входящий урон. Предел — 60%.", color = "99b7df" },
    regen = { name = "Регенерация", desc = "Восстанавливает 0,5 здоровья в секунду за уровень.", color = "6ef1cb" },
    speed = { name = "Жгутики", desc = "Ранг и качество увеличивают скорость. Предел — 60%.", color = "f4d394" },
    magnet = { name = "Рецепторы", desc = "Притягивают ДНК, биомассу и ткань с растущего радиуса. Само поглощение идёт при касании.", color = "e7a7f5" },
}

M.FORM_IDS = { "predator", "toxic", "colony" }
M.SIGNATURE_ORGAN_IDS = { "chemoreceptor_ridge", "osmotic_vacuole", "synaptic_node" }

-- Данные формы хранятся отдельно от боевой реализации. Следующие этапы подключат
-- способности, пассивные эффекты и высшие эволюции к симуляции.
M.SIGNATURE_ORGANS = {
    chemoreceptor_ridge = {
        form = "predator", search_radius = 220, mark_duration = 2.5, retarget_interval = 4,
        bite_bonus = 0.08, rank_three_mark_duration = 3.2, rank_six_bite_bonus = 0.12,
    },
    osmotic_vacuole = {
        form = "toxic", charge_target_interval = 8, max_charges = 3, charge_lifetime = 15,
        rank_three_charge_lifetime = 20, rank_six_max_charges = 4,
        radius_per_charge = 0.08, duration_per_charge = 0.25,
    },
    synaptic_node = {
        form = "colony", coordination_radius = 220, coordination_window = 1.2, followup_window = 2,
        bonus_per_clone = 0.05, max_bonus = 0.15, rank_three_radius_multiplier = 1.2,
        rank_six_max_bonus = 0.20,
    },
}

M.FORM_SPECIALIZATIONS = {
    predator = {
        research = "", branch = "predator", signature_organ = "chemoreceptor_ridge",
        ability = {
            id = "predator_primordial_rage", name = "Первобытная ярость", cooldown = 55, icon = "devour", color = "ffbd88",
            desc = "Рывок с тройным усиленным укусом; затем урон пасти повышается на 60% на 5 секунд.",
            distance = 64, duration = 0.24, refund_window = 0, damage_multiplier = 3,
            frenzy_multiplier = 1.60, frenzy_duration = 5,
        },
        defense = {
            id = "predator_instinct", name = "Инстинкт выживания", cooldown = 75, icon = "barrier", color = "ff9b82",
            desc = "Восстанавливает 30% максимального здоровья и ускоряет движение на 45% на 6 секунд.",
            heal_fraction = 0.30, speed_multiplier = 1.45, duration = 6, active_key = "predator_escape_active",
        },
        passive = {
            id = "feast", name = "Пиршество", desc = "Поглощение: +3% макс. HP (до 4), раз в 5 с.", heal_fraction = 0.03,
            heal_cap = 4, cooldown = 5,
        },
        evolution = {
            id = "apex_predator", name = "Вершинный хищник",
            organ = "chemoreceptor_ridge", organ_rank = 6, passive = "magnet", passive_rank = 3,
            marked_bite_bonus = 0.12,
        },
    },
    toxic = {
        research = "toxic", branch = "toxic", signature_organ = "osmotic_vacuole",
        ability = {
            id = "toxic_cataclysm", name = "Токсический катаклизм", cooldown = 60, icon = "acid", color = "b2dd75",
            desc = "Создаёт большое кислотное поле на 8 секунд с усиленным уроном и замедлением врагов на 40%.",
            radius_multiplier = 2.0, duration = 8, damage_multiplier = 1.35, slow = 0.40, slow_duration = 1.5,
            fields_do_not_stack = true,
        },
        defense = {
            id = "toxic_osmotic_cocoon", name = "Осмотический кокон", cooldown = 75, icon = "barrier", color = "83d5c9",
            desc = "На 6 секунд снижает входящий урон на 75% и уничтожает опасные ядовитые облака рядом.",
            duration = 6, damage_reduction = 0.75, clear_radius_multiplier = 2.5, active_key = "toxic_cocoon_active",
        },
        passive = {
            id = "toxic_regulation", name = "Токсикорегуляция", desc = "Контактный урон от отравленных врагов −8%, от боссов −4%.",
            enemy_contact_reduction = 0.08, boss_contact_reduction = 0.04,
        },
        evolution = {
            id = "living_reactor", name = "Живой реактор",
            organ = "osmotic_vacuole", organ_rank = 6, passive = "catalysis", passive_rank = 3,
            slow = 0.40,
        },
    },
    colony = {
        research = "colony", branch = "colony", signature_organ = "synaptic_node",
        ability = {
            id = "colony_great_swarm", name = "Великий рой", cooldown = 65, icon = "division", color = "e7a7f5",
            desc = "На 10 секунд появляются две дополнительные боевые копии, а урон всех копий повышается на 60%.",
            duration = 10, extra_clones = 2, clone_damage_multiplier = 1.60,
        },
        defense = {
            id = "colony_living_bastion", name = "Живой бастион", cooldown = 80, icon = "barrier", color = "c5a0f5",
            desc = "Копии окружают организм и поглощают до 85% входящего урона; прочность оболочки — 70% максимального здоровья.",
            duration = 8, damage_absorption = 0.85, capacity_fraction = 0.70, active_key = "colony_bastion_active",
        },
        passive = {
            id = "shared_membrane", name = "Общая мембрана", desc = "Защита +1,5% за копию, до 7,5%; высшая эволюция повышает предел до 12%.",
            reduction_per_clone = 0.015, maximum_clones = 5, maximum_reduction = 0.075,
        },
        evolution = {
            id = "collective_mind", name = "Коллективный разум",
            organ = "synaptic_node", organ_rank = 6, passive = "armor", passive_rank = 3,
            maximum_reduction = 0.12,
        },
    },
}

function M.form_specialization(form)
    return M.FORM_SPECIALIZATIONS[form] or {}
end

function M.signature_organ(form)
    return M.form_specialization(form).signature_organ or ""
end

function M.signature_organ_for_research(research_id)
    for _, form in ipairs(M.FORM_IDS) do
        local data = M.FORM_SPECIALIZATIONS[form]
        if data.research == research_id then return data.signature_organ end
    end
    return ""
end

M.SYNERGY_IDS = { "enzyme_bite", "conductive_bath", "barbed_cilia", "shield_pulse", "metabolic_colony", "ferment_cloud", "acid_grasp", "spike_pulse", "toxic_colony", "spore_feast", "enzyme_target", "acid_bite", "shared_shell" }

M.SYNERGIES = {
    enzyme_bite = { name = "Ферментативная пасть", needs = { "enzymes", "devour" }, desc = "Укус на 25%сильнее и оставляет ферменты на 3 с." },
    conductive_bath = { name = "Проводящая купель", needs = { "electric", "acid" }, desc = "Биоразряд замедляет цели на 1,2 с и создаёт кислотный очаг." },
    barbed_cilia = { name = "Колючий веер", needs = { "cilia", "spikes" }, desc = "Ресничный удар выпускает три дополнительных шипа." },
    shield_pulse = { name = "Защитное сокращение", needs = { "barrier", "pulse" }, desc = "Импульс сокращает ожидание следующего щита на 2 с." },
    metabolic_colony = { name = "Питающая колония", needs = { "division", "metabolism" }, desc = "Копии обеспечивают регенерацию 0,15HP/с заранг деления." },
    ferment_cloud = { name = "Ферментный след", needs = { "enzymes", "trail" }, desc = "Ядовитые поля на 25%сильнее и покрывают цели ферментами на 2 с." },
    acid_grasp = { name = "Растворяющий захват", needs = { "tentacle", "acid" }, desc = "Щупальца плавно тянут меньших или сильно повреждённых врагов в кислоту и замедляют их." },
    spike_pulse = { name = "Колючий импульс", needs = { "spikes", "pulse" }, desc = "Каждое сокращение мембраны выпускает восемь шипов." },
    toxic_colony = { name = "Токсичная колония", needs = { "division", "trail" }, desc = "Копии оставляют собственные ядовитые облака." },
    spore_feast = { name = "Споровый пир", needs = { "infection", "devour" }, desc = "Поглощение заражённой цели создаёт облако спор." },
    enzyme_target = { name = "Ферментативный прицел", needs = { "chemoreceptor_ridge", "enzymes" }, desc = "Ферменты на отмеченной цели действуют на 25% дольше.", duration_multiplier = 1.25 },
    acid_bite = { name = "Кислотный прикус", needs = { "osmotic_vacuole", "devour" }, desc = "Урон пастью по отравленной цели возвращает 1 с перезарядки способности; раз в 4 с.", cooldown_refund = 1, interval = 4 },
    shared_shell = { name = "Общий панцирь", needs = { "synaptic_node", "barrier" }, desc = "Ёмкость щита +10% за активную копию, до +30%.", per_clone = .10, cap = .30 },
}

M.SPECIALIZATIONS = {
    tentacle = {
        { id = "tentacle_hook_crown", name = "Крючковая корона", desc = "Урон щупалец +14%, дальность +20%; на мембране растёт костяной гребень.", color = "ff9c77", motif = "spines", power = 1.14, reach_mult = 1.2 },
        { id = "tentacle_resonant_grasp", name = "Резонансный захват", desc = "Урон +8%, а в активной синергии +20%; на щупальцах пульсируют узлы.", color = "77e8e0", motif = "nodes", power = 1.08, synergy_power = 1.2 },
    },
    acid = {
        { id = "acid_bile_jet", name = "Жёлчный выброс", desc = "Урон кислоты +14%, радиус +12%; железа светится жёлтым ядром.", color = "e4f578", motif = "glands", power = 1.14, radius_mult = 1.12 },
        { id = "acid_symbiotic_mantle", name = "Симбиотическая мантия", desc = "Урон +8%, а в активной синергии +20%; по оболочке идут кислотные волны.", color = "85e9b4", motif = "waves", power = 1.08, synergy_power = 1.2 },
    },
    spikes = {
        { id = "spikes_piercer", name = "Пробойные шипы", desc = "Урон +14%, в залпе ещё один шип. Пробивают панцирь гигантов и отламывают фрагмент ослабленной мембраны.", color = "ffb66f", motif = "spines", power = 1.14, shot_bonus = 1 },
        { id = "spikes_needle_bloom", name = "Иглистое гнездо", desc = "Урон +8%, а в активной синергии +20%; шипы светятся кольцевыми узлами.", color = "f6e592", motif = "nodes", power = 1.08, synergy_power = 1.2 },
    },
    pulse = {
        { id = "pulse_rupture", name = "Разрывная волна", desc = "Урон импульса +14%, радиус +15%; мембрана формирует ударные рёбра.", color = "ff9d94", motif = "waves", power = 1.14, radius_mult = 1.15 },
        { id = "pulse_recovery_rhythm", name = "Ритм восстановления", desc = "Урон +8%, а в активной синергии +20%; по телу пробегают световые круги.", color = "9bcbff", motif = "rings", power = 1.08, synergy_power = 1.2 },
    },
    division = {
        { id = "division_hunter_buds", name = "Охотничьи почки", desc = "Урон копий +14%; образуется ещё одна боевая копия.", color = "f5a2dc", motif = "buds", power = 1.14, clone_bonus = 1 },
        { id = "division_chorus", name = "Хоровая колония", desc = "Урон +8%, а в активной синергии +20%; копии соединяются светящимися нитями.", color = "b8b2ff", motif = "threads", power = 1.08, synergy_power = 1.2 },
    },
    trail = {
        { id = "trail_caustic", name = "Каустический след", desc = "Урон следа +14%, ядовитое поле живёт на 25% дольше.", color = "c5f56f", motif = "droplets", power = 1.14, duration_mult = 1.25 },
        { id = "trail_adhesive_mucus", name = "Клейкая слизь", desc = "Урон +8%, а в активной синергии +20%; слизистые ленты обвивают тело.", color = "9be8bc", motif = "threads", power = 1.08, synergy_power = 1.2 },
    },
    infection = {
        { id = "infection_virulent_strain", name = "Споровый штамм", desc = "Урон заражения +14%, заражение держится на 25% дольше.", color = "ff879e", motif = "vesicles", power = 1.14, duration_mult = 1.25 },
        { id = "infection_carrier_web", name = "Сетевой носитель", desc = "Урон +8%, а в активной синергии +20%; споровые узлы связаны жилками.", color = "dc9dff", motif = "threads", power = 1.08, synergy_power = 1.2 },
    },
    cilia = {
        { id = "cilia_scythe_fan", name = "Косообразный веер", desc = "Урон ресничек +14%, дальность удара +18%; по краю режущие лопасти.", color = "f0d49c", motif = "frills", power = 1.14, reach_mult = 1.18 },
        { id = "cilia_filter_comb", name = "Фильтрующий гребень", desc = "Урон +8%, а в активной синергии +20%; реснички вспыхивают мерцающими точками.", color = "9fe8d1", motif = "nodes", power = 1.08, synergy_power = 1.2 },
    },
    enzymes = {
        { id = "enzymes_deep_etch", name = "Глубокое травление", desc = "Урон ферментов +14%, их метка держится на 35% дольше.", color = "ffca79", motif = "spines", power = 1.14, duration_mult = 1.35 },
        { id = "enzymes_catalyst_burst", name = "Катализаторный выброс", desc = "Урон +8%, а в активной синергии +20%; железы пульсируют рядами пузырьков.", color = "f5ed98", motif = "vesicles", power = 1.08, synergy_power = 1.2 },
    },
    electric = {
        { id = "electric_arc_web", name = "Дуговая сеть", desc = "Урон разряда +14%, цепь перескакивает ещё на одну цель.", color = "93e8ff", motif = "threads", power = 1.14, target_bonus = 1 },
        { id = "electric_charge_nodes", name = "Аккумуляторные узлы", desc = "Урон +8%, а в активной синергии +20%; узлы вспыхивают в ритме заряда.", color = "c1b7ff", motif = "nodes", power = 1.08, synergy_power = 1.2 },
    },
    barrier = {
        { id = "barrier_armored_film", name = "Панцирная плёнка", desc = "Сила щита +14%; по краю растут плотные защитные пластины.", color = "b6c6ee", motif = "plates", power = 1.14 },
        { id = "barrier_elastic_return", name = "Упругая отдача", desc = "Сила +8%, а в активной синергии +20%; укрепляет поглощение щита.", color = "87e5d9", motif = "waves", power = 1.08, synergy_power = 1.2 },
    },
    devour = {
        { id = "devour_whale_maw", name = "Кашалотова пасть", desc = "Урон пасти +14%, укус срабатывает на 18% чаще; растёт живая мышечная складка.", color = "ff9c82", motif = "jaws", power = 1.14, bite_cooldown_mult = 0.82 },
        { id = "devour_selective_filter", name = "Избирательный фильтр", desc = "Урон +8%, а в активной синергии +20%; пищевые каналы пульсируют бирюзой.", color = "83e9cf", motif = "threads", power = 1.08, synergy_power = 1.2 },
    },
    chemoreceptor_ridge = {
        { id = "chemoreceptor_deep_sensor", name = "Глубокий сенсор", desc = "Радиус поиска +20%.", color = "b9a0ff", motif = "nodes", search_radius_mult = 1.2 },
        { id = "chemoreceptor_neural_sight", name = "Нервный прицел", desc = "Длительность метки +1 с.", color = "8ce7df", motif = "threads", mark_duration_bonus = 1 },
    },
    osmotic_vacuole = {
        { id = "vacuole_hyperosmotic_sac", name = "Гиперосмотический мешок", desc = "Радиус кислотного поля +15%.", color = "d5f47c", motif = "vesicles", field_radius_mult = 1.15 },
        { id = "vacuole_stable_chamber", name = "Стабильная камера", desc = "Заряды хранятся на 6 с дольше.", color = "91e6a8", motif = "glands", charge_lifetime_bonus = 6 },
    },
    synaptic_node = {
        { id = "synapse_branched_network", name = "Разветвлённая сеть", desc = "Радиус координации +20%.", color = "c6a6ff", motif = "threads", coordination_radius_mult = 1.2 },
        { id = "synapse_protective_network", name = "Защитная сеть", desc = "Пассивная защита +1,5 процентного пункта в пределах общего ограничения.", color = "a5e9e0", motif = "nodes", passive_protection_bonus = 0.015 },
    },
}

M.TEMP_MUTATION_IDS = { "acid_vesicles", "spore_pouch", "forked_tendrils", "charged_nucleus", "elastic_cortex", "voracious_ridge" }

M.TEMP_MUTATIONS = {
    acid_vesicles = { name = "Кислотные везикулы", organ = "acid", summary = "Кислота +12% · радиус +8%", desc = "Кислотные железы разрастаются: кислота наносит больше урона и покрывает больший радиус. Сбрасывается после гибели.", color = "d8f36d", motif = "vesicles", power_targets = { acid = 1.12 }, value_targets = { acid = { radius_mult = 1.08 } } },
    spore_pouch = { name = "Споровый мешок", organ = "infection", summary = "Заражение и след держатся дольше", desc = "Выросший мешок удерживает споры дольше; след и заражение действуют продолжительнее. Сбрасывается после гибели.", color = "e9a2d6", motif = "buds", power_targets = { infection = 1.1, trail = 1.08 }, value_targets = { infection = { duration_mult = 1.18 }, trail = { duration_mult = 1.15 } } },
    forked_tendrils = { name = "Разветвлённые усики", organ = "tentacle", summary = "Дальность щупалец и ресничек +12%", desc = "Дополнительные нервные ветви направляют щупальца и реснички дальше. Сбрасывается после гибели.", color = "ffad86", motif = "threads", power_targets = { tentacle = 1.1, cilia = 1.08 }, value_targets = { tentacle = { reach_mult = 1.12 }, cilia = { reach_mult = 1.12 } } },
    charged_nucleus = { name = "Заряженное ядро", organ = "electric", summary = "Разряд +12% · цепь +1 цель", desc = "Электрический заряд устойчивее перескакивает между целями. Сбрасывается после гибели.", color = "8edfff", motif = "nodes", power_targets = { electric = 1.12 }, bonus_targets = { electric = { target_bonus = 1 } } },
    elastic_cortex = { name = "Упругая кора", organ = "barrier", summary = "Щит +14% · броня +4%", desc = "Пружинящая ткань укрепляет щит и немного снижает входящий урон. Сбрасывается после гибели.", color = "a9c5ee", motif = "plates", power_targets = { barrier = 1.14 }, passive_bonuses = { armor = 0.04 } },
    voracious_ridge = { name = "Ненасытный валик", organ = "devour", summary = "Укус +12% · интервал −10%", desc = "Мышечный валик ускоряет укусы и усиливает переднее поглощение. Сбрасывается после гибели.", color = "ff9a7e", motif = "jaws", power_targets = { devour = 1.12 }, value_targets = { devour = { bite_cooldown_mult = 0.9 } } },
}

M.EVOLUTION_IDS = { "tentacle", "acid", "spikes", "pulse", "infection", "electric", "chemoreceptor_ridge", "osmotic_vacuole", "synaptic_node" }

M.EVOLUTIONS = {
    tentacle = { name = "Ловчая корона", passive = "magnet", behavior = "До двух меньших или сильно повреждённых целей окружаются щупальцами и плавно направляются к пасти. Здоровые крупные враги не удерживаются." },
    acid = { name = "Растворяющая мантия", passive = "armor", behavior = "При столкновении мембрана выдавливает кислоту в месте контакта. Повтор не чаще раза в 2 с; защита от столкновения не гарантируется." },
    spikes = { name = "Стремительные шипы", passive = "speed" },
    pulse = { name = "Живое сокращение", passive = "regen" },
    infection = { name = "Споровая утроба", passive = "metabolism", behavior = "Три полностью переваренные заражённые порции наполняют камеры и выпускают облако спор. Заряд сохраняется при выходе." },
    electric = { name = "Каталитический разряд", passive = "catalysis" },
}

-- Высшие эволюции используют прежние ключи органов и прежнюю систему наград.
local form_behaviors = {
    predator = "Вершинный хищник открывает «Первобытную ярость» и «Инстинкт выживания».",
    toxic = "Живой реактор открывает «Токсический катаклизм» и «Осмотический кокон».",
    colony = "Коллективный разум открывает «Великий рой» и «Живой бастион».",
}
for _, form in ipairs(M.FORM_IDS) do
    local evolution=M.FORM_SPECIALIZATIONS[form].evolution
    evolution.form=form
    evolution.behavior=form_behaviors[form]
    evolution.desc=form_behaviors[form]
    M.EVOLUTIONS[evolution.organ]=evolution
end

M.QUALITY_MULTIPLIERS = { 1.0, 1.12, 1.25, 1.45 }

local min = math.min
local max = math.max
local floor = math.floor
local log = math.log
local format = string.format
local cell_costs = {
    devour = 3, division = 3, tentacle = 2, acid = 2, barrier = 2, electric = 2,
    chemoreceptor_ridge = 1, osmotic_vacuole = 2, synaptic_node = 2,
}

function M.item(id)
    return M.ORGANS[id] or M.ADAPTATIONS[id] or {}
end

function M.cell_cost(id)
    if not M.ORGANS[id] then
        return 0
    end
    return cell_costs[id] or 1
end

function M.temporary_mutation(id)
    return M.TEMP_MUTATIONS[id] or {}
end

function M.specialization_ids(kind)
    local ids = {}
    for i, entry in ipairs(M.SPECIALIZATIONS[kind] or {}) do
        ids[i] = entry.id
    end
    return ids
end

function M.specialization_data(kind, id)
    for _, entry in ipairs(M.SPECIALIZATIONS[kind] or {}) do
        if entry.id == id then
            return entry
        end
    end
    return {}
end

function M.has_specialization(kind, id)
    return M.specialization_data(kind, id).id ~= nil
end

function M.specialization_value(kind, id, key, fallback)
    return M.specialization_data(kind, id)[key] or fallback or 1
end

function M.specialization_bonus(kind, id, key)
    return M.specialization_data(kind, id)[key] or 0
end

function M.legacy_specialization(kind, id)
    local choices = M.SPECIALIZATIONS[kind]
    if not choices then
        return ""
    end
    if id == "feral" or id == choices[1].id then
        return choices[1].id
    end
    if id == "resonant" or id == choices[2].id then
        return choices[2].id
    end
    return ""
end

function M.max_rank(id)
    return M.ORGANS[id] and 9007199254740991 or 6
end

function M.effective_rank(rank)
    -- Keep the first ten ranks unchanged and taper further gains in battle.
    local value = max(0, rank)
    if value <= 10 then
        return value
    end
    return 10 + floor(10 * log(1 + (value - 10) / 10))
end

function M.base_unlocked()
    local ids = {}
    for _, id in ipairs(M.ORGAN_IDS) do
        local organ = M.ORGANS[id]
        if organ and not organ.unlock and not organ.research_unlock then
            ids[#ids + 1] = id
        end
    end
    for _, id in ipairs(M.ADAPTATION_IDS) do
        ids[#ids + 1] = id
    end
    return ids
end

function M.synergy_hint(id, equipped)
    local lines = {}
    for _, synergy_id in ipairs(M.SYNERGY_IDS) do
        local synergy = M.SYNERGIES[synergy_id]
        local first, second = synergy.needs[1], synergy.needs[2]
        if id == first or id == second then
            local other = id == first and second or first
            local mark = equipped[other] ~= nil and "✓ " or "+ "
            lines[#lines + 1] = mark .. M.item(other).name .. ": " .. synergy.name
        end
    end
    return table.concat(lines, "\n")
end

local function display_damage(base, rank)
    local damage = M.scaled_damage(base, rank)
    -- Godot's fixed-point formatter rounds exact half-tenths to even.
    if damage % 1 == 0.25 then
        return damage - 0.05
    end
    return damage
end

function M.effect_text(id, rank)
    local r = max(1, rank)
    local damage = display_damage
    if id == "tentacle" then
        return format("%d щупалец; залп %.1f суммарно; интервал 0,85 с; дальность %.1f ×масштаб тела.", M.tentacle_count(r), damage(9 + r * 7, r), 165 + r * 12)
    elseif id == "acid" then
        return format("%.1f урона/с рядом; радиус %.1f ×масштаб тела.", damage(4 + r * 3, r), 75 + r * 9)
    elseif id == "spikes" then
        return format("Шип %.1f урона; %d шипов; интервал 1,3 с.", damage(12 + r * 5, r), M.shot_count(r))
    elseif id == "pulse" then
        return format("%.1f урона; радиус %.1f ×масштаб тела; каждые 3,2 с.", damage(12 + r * 8, r), 130 + r * 18)
    elseif id == "division" then
        return format("%d копий; контактный урон %.1f/с.", M.clone_count(r), damage(8 + r * 4, r))
    elseif id == "trail" then
        return format("Поле %.1f урона/с на 3 с; новое каждые 0,6 с.", damage(5 + r * 3, r))
    elseif id == "infection" then
        return format("%.1f урона/с на 4,5 с; запуск каждые 1,6 с.", damage(4 + r * 3, r))
    elseif id == "devour" then
        return format("Укус %.1f каждые 0,45 с; передний сектор 80°; переваривание быстрее на 35%%.", damage(7 + r * 5, r))
    elseif id == "cilia" then
        return format("Веер %.1f урона; сектор 120°; каждые 1,4 с.", damage(10 + r * 6, r))
    elseif id == "enzymes" then
        return format("Ферменты %.1f урона/с на 4 с; каждые 2 с.", damage(3 + r * 2, r))
    elseif id == "electric" then
        return format("%.1f урона по %d целям; каждые 2,6 с.", damage(12 + r * 6, r), M.electric_targets(r))
    elseif id == "barrier" then
        return format("Щит поглощает до %.1f HP; восстанавливается каждые 8 с.", damage(8 + r * 6, r))
    elseif id == "chemoreceptor_ridge" then
        return format("1 ячейка · гибрид. Метка %.1f с / 4 с; укус +%d%%.", r >= 3 and 3.2 or 2.5, r >= 6 and 12 or 8)
    elseif id == "osmotic_vacuole" then
        return format("2 ячейки · гибрид. До %d зарядов на %d с; поле +8%% и +0,25 с за заряд.", r >= 6 and 4 or 3, r >= 3 and 20 or 15)
    elseif id == "synaptic_node" then
        return format("2 ячейки · гибрид. +5%% за следующую копию, до %d%%; радиус %d.", r >= 6 and 20 or 15, r >= 3 and 264 or 220)
    elseif id == "armor" then
        return format("Входящий урон снижен на %d%%.", floor(M.adaptation_bonus(r) * 100 + 0.5))
    elseif id == "regen" then
        return format("Регенерация %.1f HP/с.", r * 0.5)
    elseif id == "speed" then
        return format("Скорость движения +%d%%.", floor(M.adaptation_bonus(r) * 100 + 0.5))
    elseif id == "magnet" then
        return format("Притягивание на радиус тела+%d; без рывков.", r * 55)
    elseif id == "metabolism" then
        return format("Получаемая ДНК +%d%%.", r * 6)
    elseif id == "catalysis" then
        return format("Базовый урон органов +%d%%; стойкая ткань врага ограничивает взрывной урон.", r * 8)
    end
    return M.item(id).desc or ""
end

function M.milestone_multiplier(rank)
    if rank >= 10 then
        return min(1.85, 1.50 + 0.035 * log(1 + (rank - 10) / 10))
    elseif rank >= 6 then
        return 1.25
    elseif rank >= 3 then
        return 1.10
    end
    return 1
end

function M.scaled_damage(base, rank)
    return base * M.milestone_multiplier(rank)
end

function M.milestone_text(id, rank)
    local mark_three = rank >= 3 and "✓ " or "◇ "
    local mark_six = rank >= 6 and "✓ " or "◇ "
    if not M.ORGANS[id] then
        return format("Рубежи адаптации: %s3 · %s6 — максимум", mark_three, mark_six)
    end
    if M.SIGNATURE_ORGANS[id] then
        return "Рубежи сигнатуры: "..mark_three.."3 · усиление свойства; "..mark_six.."6 · предел базового эффекта."
    end
    local mark_ten = rank >= 10 and "✓ " or "◇ "
    return format("Рубежи: %s3 · формирование ×1,10; %s6 · перестройка ×1,25; %s10 · зрелость ×1,50. Множитель силы органа.", mark_three, mark_six, mark_ten)
end

function M.tentacle_count(rank)
    return max(0, min(10, rank))
end

function M.shot_count(rank)
    local half_rank = rank / 2
    return min(6, 1 + (half_rank < 0 and math.ceil(half_rank) or floor(half_rank)))
end

function M.electric_targets(rank)
    return min(6, 1 + rank)
end

function M.clone_count(rank)
    return min(5, 1 + rank)
end

function M.adaptation_bonus(rank)
    return min(0.6, rank <= 4 and rank * 0.12 or 0.48 + (rank - 4) * 0.06)
end

function M.quality_multiplier(grade)
    return M.QUALITY_MULTIPLIERS[max(0, min(3, grade)) + 1]
end

function M.duplicate_rank_gain(grade)
    return max(0, min(3, grade)) + 1
end

return M
