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

static func item(id: String) -> Dictionary:
	return ORGANS.get(id, ADAPTATIONS.get(id, {}))

static func max_rank(id: String) -> int:
	return 10 if id in ORGANS else 6

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
	if rank>=10: return 1.50
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
