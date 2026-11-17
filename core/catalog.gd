extends RefCounted

const ORGANS = {
	"tentacle": {"name":"Щупальца", "branch":"predator", "desc":"Хлещут ближайших врагов. Каждый уровень усиливает удар.", "color":"6ef1cb"},
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
	"armor": {"name":"Плотная мембрана", "desc":"Снижает получаемый урон на 12% за уровень.", "color":"99b7df"},
	"regen": {"name":"Регенерация", "desc":"Восстанавливает 0,5 здоровья в секунду за уровень.", "color":"6ef1cb"},
	"speed": {"name":"Жгутики", "desc":"Увеличивают скорость на 12% за уровень.", "color":"f4d394"},
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
	return 5 if id in ORGANS else 3

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
		"tentacle":return "Удар %.0f; интервал 0,85 с; дальность %.0f ×масштаб тела." % [9+r*7,165+r*12]
		"acid":return "%.0f урона/с рядом; радиус %.0f ×масштаб тела." % [4+r*3,75+r*9]
		"spikes":return "Шип %.0f урона; %d шипов; интервал 1,3 с." % [12+r*5,1+int(r/2.0)]
		"pulse":return "%.0f урона; радиус %.0f ×масштаб тела; каждые 3,2 с." % [12+r*8,130+r*18]
		"division":return "%d копий; контактный урон %.0f/с." % [1+r,8+r*4]
		"trail":return "Поле %.0f урона/с на 3 с; новое каждые 0,6 с." % [5+r*3]
		"infection":return "%.0f урона/с на 4,5 с; запуск каждые 1,6 с." % [4+r*3]
		"devour":return "Укус %.0f каждые 0,45 с; передний сектор 80°; переваривание быстрее на 35%%." % [7+r*5]
		"cilia":return "Веер %.0f урона; сектор 120°; каждые 1,4 с." % [10+r*6]
		"enzymes":return "Ферменты %.0f урона/с на 4 с; каждые 2 с." % [3+r*2]
		"electric":return "%.0f урона по%d целям; каждые 2,6 с." % [12+r*6,1+r]
		"barrier":return "Щит поглощает до%.0f HP; восстанавливается каждые 8 с." % [8+r*6]
		"armor":return "Входящий урон снижен на%d%%." % [r*12]
		"regen":return "Регенерация %.1f HP/с." % [r*0.5]
		"speed":return "Скорость движения +%d%%." % [r*12]
		"magnet":return "Притягивание на радиус тела+%d; без рывков." % [r*55]
		"metabolism":return "Получаемая ДНК +%d%%." % [r*6]
		"catalysis":return "Базовый урон органов +%d%%; стойкая ткань врага ограничивает взрывной урон." % [r*8]
	return item(id).get("desc","")
