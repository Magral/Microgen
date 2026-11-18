extends RefCounted

const ORGANS = {
	"tentacle": {"name":"Щупальца", "branch":"predator", "desc":"Хлещут ближайших врагов. Каждый ранг добавляет рабочее щупальце. Суммарная сила залпа распределяется между ними.", "color":"6ef1cb"},
	"acid": {"name":"Кислотная оболочка", "branch":"toxic", "desc":"Растворяет врагов рядом с телом.", "color":"c3f56e"},
	"spikes": {"name":"Шипы", "branch":"predator", "desc":"Выстреливают веером в ближайшую цель.", "color":"f4d394"},
	"pulse": {"name":"Сокращение мембраны", "branch":"predator", "desc":"Отталкивает врагов круговой волной.", "color":"98caff"},
	"division": {"name":"Деление", "branch":"colony", "desc":"Копии кружат вокруг амёбы и атакуют врагов.", "color":"e7a7f5", "unlock":8},
	"trail": {"name":"Ядовитый след", "branch":"toxic", "desc":"Оставляет за собой отравленную среду.", "color":"9ce57c"},
	"infection": {"name":"Заражение", "branch":"toxic", "desc":"Заражает ближайшего врага; инфекция наносит урон со временем.", "color":"ffafbf"},
	"cilia": {"name":"Ресничный веер","branch":"predator","desc":"Рассекает ткань широким передним веером.","color":"bce9d2"},
	"enzymes": {"name":"Ферментативные железы","branch":"toxic","desc":"Помечают цель растворяющими ферментами.","color":"f0c575"},
	"electric": {"name":"Биоразряд","branch":"colony","desc":"Разряд перескакивает между соседними противниками.","color":"9cddf2"},
	"barrier": {"name":"Сократительный щит","branch":"colony","desc":"Периодически поглощает часть входящего удара.","color":"b6bdec"},
	"devour": {"name":"Хищная пасть", "branch":"predator", "desc":"Разрывает ткань спереди: укус, более ранний захват и быстрое переваривание через пасть. Боковое поглощение слабее.", "color":"ffbd88"}
}
const ADAPTATIONS = {
	"metabolism": {"name":"Усиленное усвоение","desc":"Повышает получаемую ДНК.","color":"b7eb9e"},
	"catalysis": {"name":"Каталитические белки","desc":"Усиливают базовый урон органов.","color":"e9bb91"},
	"armor": {"name":"Плотная мембрана", "desc":"Ранг и качество снижают входящий урон. Предел — 60%.", "color":"99b7df"},
	"regen": {"name":"Регенерация", "desc":"Восстанавливает 0,5 здоровья в секунду за уровень.", "color":"6ef1cb"},
	"speed": {"name":"Жгутики", "desc":"Ранг и качество увеличивают скорость. Предел — 60%.", "color":"f4d394"},
	"magnet": {"name":"Рецепторы", "desc":"Притягивают ДНК, биомассу и ткань с растущего радиуса. Само поглощение идёт при касании.", "color":"e7a7f5"}
}
const SYNERGIES = {
	"enzyme_bite": {"name":"Ферментативная пасть","needs":["enzymes","devour"],"desc":"Укус на 25%сильнее и оставляет ферменты на 3 с."},
	"conductive_bath": {"name":"Проводящая купель","needs":["electric","acid"],"desc":"Биоразряд замедляет цели на 1,2 с и создаёт кислотный очаг."},
	"barbed_cilia": {"name":"Колючий веер","needs":["cilia","spikes"],"desc":"Ресничный удар выпускает три дополнительных шипа."},
	"shield_pulse": {"name":"Защитное сокращение","needs":["barrier","pulse"],"desc":"Импульс сокращает ожидание следующего щита на 2 с."},
	"metabolic_colony": {"name":"Питающая колония","needs":["division","metabolism"],"desc":"Копии обеспечивают регенерацию 0,15HP/с заранг деления."},
	"ferment_cloud": {"name":"Ферментный след","needs":["enzymes","trail"],"desc":"Ядовитые поля на 25%сильнее и покрывают цели ферментами на 2 с."},
	"acid_grasp": {"name":"Растворяющий захват", "needs":["tentacle","acid"], "desc":"Щупальца плавно тянут меньших или сильно повреждённых врагов в кислоту и замедляют их."},
	"spike_pulse": {"name":"Колючий импульс", "needs":["spikes","pulse"], "desc":"Каждое сокращение мембраны выпускает восемь шипов."},
	"toxic_colony": {"name":"Токсичная колония", "needs":["division","trail"], "desc":"Копии оставляют собственные ядовитые облака."},
	"spore_feast": {"name":"Споровый пир", "needs":["infection","devour"], "desc":"Поглощение заражённой цели создаёт облако спор."}
}
const SPECIALIZATIONS = {
	"tentacle":[{"id":"tentacle_hook_crown","name":"Крючковая корона","desc":"Урон щупалец +14%, дальность +20%; на мембране растёт костяной гребень.","color":"ff9c77","motif":"spines","power":1.14,"reach_mult":1.20},{"id":"tentacle_resonant_grasp","name":"Резонансный захват","desc":"Урон +8%, а в активной синергии +20%; на щупальцах пульсируют узлы.","color":"77e8e0","motif":"nodes","power":1.08,"synergy_power":1.20}],
	"acid":[{"id":"acid_bile_jet","name":"Жёлчный выброс","desc":"Урон кислоты +14%, радиус +12%; железа светится жёлтым ядром.","color":"e4f578","motif":"glands","power":1.14,"radius_mult":1.12},{"id":"acid_symbiotic_mantle","name":"Симбиотическая мантия","desc":"Урон +8%, а в активной синергии +20%; по оболочке идут кислотные волны.","color":"85e9b4","motif":"waves","power":1.08,"synergy_power":1.20}],
	"spikes":[{"id":"spikes_piercer","name":"Пробойные шипы","desc":"Урон +14%, в залпе ещё один шип. Пробивают панцирь гигантов и отламывают фрагмент ослабленной мембраны.","color":"ffb66f","motif":"spines","power":1.14,"shot_bonus":1},{"id":"spikes_needle_bloom","name":"Иглистое гнездо","desc":"Урон +8%, а в активной синергии +20%; шипы светятся кольцевыми узлами.","color":"f6e592","motif":"nodes","power":1.08,"synergy_power":1.20}],
	"pulse":[{"id":"pulse_rupture","name":"Разрывная волна","desc":"Урон импульса +14%, радиус +15%; мембрана формирует ударные рёбра.","color":"ff9d94","motif":"waves","power":1.14,"radius_mult":1.15},{"id":"pulse_recovery_rhythm","name":"Ритм восстановления","desc":"Урон +8%, а в активной синергии +20%; по телу пробегают световые круги.","color":"9bcbff","motif":"rings","power":1.08,"synergy_power":1.20}],
	"division":[{"id":"division_hunter_buds","name":"Охотничьи почки","desc":"Урон копий +14%; образуется ещё одна боевая копия.","color":"f5a2dc","motif":"buds","power":1.14,"clone_bonus":1},{"id":"division_chorus","name":"Хоровая колония","desc":"Урон +8%, а в активной синергии +20%; копии соединяются светящимися нитями.","color":"b8b2ff","motif":"threads","power":1.08,"synergy_power":1.20}],
	"trail":[{"id":"trail_caustic","name":"Каустический след","desc":"Урон следа +14%, ядовитое поле живёт на 25% дольше.","color":"c5f56f","motif":"droplets","power":1.14,"duration_mult":1.25},{"id":"trail_adhesive_mucus","name":"Клейкая слизь","desc":"Урон +8%, а в активной синергии +20%; слизистые ленты обвивают тело.","color":"9be8bc","motif":"threads","power":1.08,"synergy_power":1.20}],
	"infection":[{"id":"infection_virulent_strain","name":"Споровый штамм","desc":"Урон заражения +14%, заражение держится на 25% дольше.","color":"ff879e","motif":"vesicles","power":1.14,"duration_mult":1.25},{"id":"infection_carrier_web","name":"Сетевой носитель","desc":"Урон +8%, а в активной синергии +20%; споровые узлы связаны жилками.","color":"dc9dff","motif":"threads","power":1.08,"synergy_power":1.20}],
	"cilia":[{"id":"cilia_scythe_fan","name":"Косообразный веер","desc":"Урон ресничек +14%, дальность удара +18%; по краю режущие лопасти.","color":"f0d49c","motif":"frills","power":1.14,"reach_mult":1.18},{"id":"cilia_filter_comb","name":"Фильтрующий гребень","desc":"Урон +8%, а в активной синергии +20%; реснички вспыхивают мерцающими точками.","color":"9fe8d1","motif":"nodes","power":1.08,"synergy_power":1.20}],
	"enzymes":[{"id":"enzymes_deep_etch","name":"Глубокое травление","desc":"Урон ферментов +14%, их метка держится на 35% дольше.","color":"ffca79","motif":"spines","power":1.14,"duration_mult":1.35},{"id":"enzymes_catalyst_burst","name":"Катализаторный выброс","desc":"Урон +8%, а в активной синергии +20%; железы пульсируют рядами пузырьков.","color":"f5ed98","motif":"vesicles","power":1.08,"synergy_power":1.20}],
	"electric":[{"id":"electric_arc_web","name":"Дуговая сеть","desc":"Урон разряда +14%, цепь перескакивает ещё на одну цель.","color":"93e8ff","motif":"threads","power":1.14,"target_bonus":1},{"id":"electric_charge_nodes","name":"Аккумуляторные узлы","desc":"Урон +8%, а в активной синергии +20%; узлы вспыхивают в ритме заряда.","color":"c1b7ff","motif":"nodes","power":1.08,"synergy_power":1.20}],
	"barrier":[{"id":"barrier_armored_film","name":"Панцирная плёнка","desc":"Сила щита +14%; по краю растут плотные защитные пластины.","color":"b6c6ee","motif":"plates","power":1.14},{"id":"barrier_elastic_return","name":"Упругая отдача","desc":"Сила +8%, а в активной синергии +20%; укрепляет поглощение щита.","color":"87e5d9","motif":"waves","power":1.08,"synergy_power":1.20}],
	"devour":[{"id":"devour_whale_maw","name":"Кашалотова пасть","desc":"Урон пасти +14%, укус срабатывает на 18% чаще; растёт живая мышечная складка.","color":"ff9c82","motif":"jaws","power":1.14,"bite_cooldown_mult":0.82},{"id":"devour_selective_filter","name":"Избирательный фильтр","desc":"Урон +8%, а в активной синергии +20%; пищевые каналы пульсируют бирюзой.","color":"83e9cf","motif":"threads","power":1.08,"synergy_power":1.20}]
}
const TEMP_MUTATIONS = {
	"acid_vesicles":{"name":"Кислотные везикулы","organ":"acid","summary":"Кислота +12% · радиус +8%","desc":"Кислотные железы разрастаются: кислота наносит больше урона и покрывает больший радиус. Сбрасывается после гибели.","color":"d8f36d","motif":"vesicles","power_targets":{"acid":1.12},"value_targets":{"acid":{"radius_mult":1.08}}},
	"spore_pouch":{"name":"Споровый мешок","organ":"infection","summary":"Заражение и след держатся дольше","desc":"Выросший мешок удерживает споры дольше; след и заражение действуют продолжительнее. Сбрасывается после гибели.","color":"e9a2d6","motif":"buds","power_targets":{"infection":1.10,"trail":1.08},"value_targets":{"infection":{"duration_mult":1.18},"trail":{"duration_mult":1.15}}},
	"forked_tendrils":{"name":"Разветвлённые усики","organ":"tentacle","summary":"Дальность щупалец и ресничек +12%","desc":"Дополнительные нервные ветви направляют щупальца и реснички дальше. Сбрасывается после гибели.","color":"ffad86","motif":"threads","power_targets":{"tentacle":1.10,"cilia":1.08},"value_targets":{"tentacle":{"reach_mult":1.12},"cilia":{"reach_mult":1.12}}},
	"charged_nucleus":{"name":"Заряженное ядро","organ":"electric","summary":"Разряд +12% · цепь +1 цель","desc":"Электрический заряд устойчивее перескакивает между целями. Сбрасывается после гибели.","color":"8edfff","motif":"nodes","power_targets":{"electric":1.12},"bonus_targets":{"electric":{"target_bonus":1}}},
	"elastic_cortex":{"name":"Упругая кора","organ":"barrier","summary":"Щит +14% · броня +4%","desc":"Пружинящая ткань укрепляет щит и немного снижает входящий урон. Сбрасывается после гибели.","color":"a9c5ee","motif":"plates","power_targets":{"barrier":1.14},"passive_bonuses":{"armor":0.04}},
	"voracious_ridge":{"name":"Ненасытный валик","organ":"devour","summary":"Укус +12% · интервал −10%","desc":"Мышечный валик ускоряет укусы и усиливает переднее поглощение. Сбрасывается после гибели.","color":"ff9a7e","motif":"jaws","power_targets":{"devour":1.12},"value_targets":{"devour":{"bite_cooldown_mult":0.90}}}
}

static func item(id: String) -> Dictionary:
	return ORGANS.get(id, ADAPTATIONS.get(id, {}))

static func temporary_mutation(id: String) -> Dictionary:
	return TEMP_MUTATIONS.get(id,{})

static func specialization_ids(kind: String) -> Array:
	var out=[]
	for entry in SPECIALIZATIONS.get(kind,[]):out.append(str(entry.id))
	return out

static func specialization_data(kind: String,id: String) -> Dictionary:
	for entry in SPECIALIZATIONS.get(kind,[]):
		if str(entry.id)==id:return entry
	return {}

static func has_specialization(kind: String,id: String) -> bool:
	return not specialization_data(kind,id).is_empty()

static func specialization_value(kind: String,id: String,key: String,fallback: float=1.0) -> float:
	return float(specialization_data(kind,id).get(key,fallback))

static func specialization_bonus(kind: String,id: String,key: String) -> int:
	return int(specialization_data(kind,id).get(key,0))

static func legacy_specialization(kind: String,id: String) -> String:
	var choices=specialization_ids(kind)
	if choices.is_empty():return ""
	if id in ["feral",choices[0]]:return str(choices[0])
	if id in ["resonant",choices[1]]:return str(choices[1])
	return ""

static func max_rank(id: String) -> int:
	# Organs are an endless family progression. Adaptations remain finite for now.
	return 9007199254740991 if id in ORGANS else 6

static func effective_rank(rank: int) -> int:
	# Keep all battle formulas finite while allowing stored ranks to grow forever.
	# The first ten ranks retain their original balance; later gains taper smoothly.
	var value=maxi(0,rank)
	if value<=10:return value
	return 10+int(floor(10.0*log(1.0+float(value-10)/10.0)))

static func base_unlocked() -> Array:
	var ids = ORGANS.keys()
	ids.erase("division")
	return ids + ADAPTATIONS.keys()

static func synergy_hint(id: String, equipped: Dictionary) -> String:
	var lines = []
	for s in SYNERGIES.values():
		if id in s.needs:
			var other = s.needs[1] if s.needs[0] == id else s.needs[0]
			lines.append(("✓ " if other in equipped else "+ ") + item(other).name + ": " + s.name)
	return "\n".join(lines)

static func effect_text(id: String,rank: int) -> String:
	var r=maxi(1,rank)
	match id:
		"tentacle":return "%d щупалец; залп %.1f суммарно; интервал 0,85 с; дальность %.1f ×масштаб тела." % [tentacle_count(r),scaled_damage(9+r*7,r),165+r*12]
		"acid":return "%.1f урона/с рядом; радиус %.1f ×масштаб тела." % [scaled_damage(4+r*3,r),75+r*9]
		"spikes":return "Шип %.1f урона; %d шипов; интервал 1,3 с." % [scaled_damage(12+r*5,r),shot_count(r)]
		"pulse":return "%.1f урона; радиус %.1f ×масштаб тела; каждые 3,2 с." % [scaled_damage(12+r*8,r),130+r*18]
		"division":return "%d копий; контактный урон %.1f/с." % [clone_count(r),scaled_damage(8+r*4,r)]
		"trail":return "Поле %.1f урона/с на 3 с; новое каждые 0,6 с." % [scaled_damage(5+r*3,r)]
		"infection":return "%.1f урона/с на 4,5 с; запуск каждые 1,6 с." % [scaled_damage(4+r*3,r)]
		"devour":return "Укус %.1f каждые 0,45 с; передний сектор 80°; переваривание быстрее на 35%%." % [scaled_damage(7+r*5,r)]
		"cilia":return "Веер %.1f урона; сектор 120°; каждые 1,4 с." % [scaled_damage(10+r*6,r)]
		"enzymes":return "Ферменты %.1f урона/с на 4 с; каждые 2 с." % [scaled_damage(3+r*2,r)]
		"electric":return "%.1f урона по %d целям; каждые 2,6 с." % [scaled_damage(12+r*6,r),electric_targets(r)]
		"barrier":return "Щит поглощает до %.1f HP; восстанавливается каждые 8 с." % [scaled_damage(8+r*6,r)]
		"armor":return "Входящий урон снижен на %d%%." % [roundi(adaptation_bonus(r)*100)]
		"regen":return "Регенерация %.1f HP/с." % [r*0.5]
		"speed":return "Скорость движения +%d%%." % [roundi(adaptation_bonus(r)*100)]
		"magnet":return "Притягивание на радиус тела+%d; без рывков." % [r*55]
		"metabolism":return "Получаемая ДНК +%d%%." % [r*6]
		"catalysis":return "Базовый урон органов +%d%%; стойкая ткань врага ограничивает взрывной урон." % [r*8]
	return item(id).get("desc","")

static func milestone_multiplier(rank: int) -> float:
	if rank>=10: return minf(1.85,1.50+0.035*log(1.0+float(rank-10)/10.0))
	if rank>=6: return 1.25
	if rank>=3: return 1.10
	return 1.0

static func scaled_damage(base: float,rank: int) -> float:
	return base*milestone_multiplier(rank)

static func milestone_text(id: String,rank: int) -> String:
	if id not in ORGANS:
		return "Рубежи адаптации: %s3 · %s6 — максимум" % ["✓ " if rank>=3 else "◇ ","✓ " if rank>=6 else "◇ "]
	return "Рубежи: %s3 · формирование ×1,10; %s6 · перестройка ×1,25; %s10 · зрелость ×1,50. Множитель силы органа." % ["✓ " if rank>=3 else "◇ ","✓ " if rank>=6 else "◇ ","✓ " if rank>=10 else "◇ "]

static func tentacle_count(rank: int) -> int:
	return clampi(rank,0,10)

static func shot_count(rank: int) -> int:
	return mini(6,1+int(rank/2.0))

static func electric_targets(rank: int) -> int:
	return mini(6,1+rank)

static func clone_count(rank: int) -> int:
	return mini(5,1+rank)

static func adaptation_bonus(rank: int) -> float:
	# Preserve old ranks 1–3 while giving both final adaptation ranks real value.
	return minf(0.6,rank*0.12 if rank<=4 else 0.48+(rank-4)*0.06)

# Recipes preserve saved IDs and the 30% damage bonus; three also change behavior.
const EVOLUTIONS = {
	"tentacle": {"name":"Ловчая корона", "passive":"magnet", "behavior":"До двух меньших или сильно повреждённых целей окружаются щупальцами и плавно направляются к пасти. Здоровые крупные враги не удерживаются."},
	"acid": {"name":"Растворяющая мантия", "passive":"armor", "behavior":"При столкновении мембрана выдавливает кислоту в месте контакта. Повтор не чаще раза в 2 с; защита от столкновения не гарантируется."},
	"spikes": {"name":"Стремительные шипы", "passive":"speed"},
	"pulse": {"name":"Живое сокращение", "passive":"regen"},
	"infection": {"name":"Споровая утроба", "passive":"metabolism", "behavior":"Три полностью переваренные заражённые порции наполняют камеры и выпускают облако спор. Заряд сохраняется при выходе."},
	"electric": {"name":"Каталитический разряд", "passive":"catalysis"}
}
const QUALITY_MULTIPLIERS = [1.0, 1.12, 1.25, 1.45]

static func quality_multiplier(grade: int) -> float:
	return QUALITY_MULTIPLIERS[clampi(grade, 0, 3)]

static func duplicate_rank_gain(grade: int) -> int:
	# A repeated organ grows by the quality of the find: common +1, rare +2,
	# epic +3, legendary +4. New organs still begin at rank one.
	return clampi(grade, 0, 3) + 1
