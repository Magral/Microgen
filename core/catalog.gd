extends RefCounted

const ORGANS = {
	"tentacle": {"name":"Щупальца", "branch":"predator", "desc":"Хлещут ближайших врагов. Каждый уровень усиливает удар.", "color":"6ef1cb"},
	"acid": {"name":"Кислотная оболочка", "branch":"toxic", "desc":"Растворяет врагов рядом с телом.", "color":"c3f56e"},
	"spikes": {"name":"Шипы", "branch":"predator", "desc":"Выстреливают веером в ближайшую цель.", "color":"f4d394"},
	"pulse": {"name":"Сокращение мембраны", "branch":"predator", "desc":"Отталкивает врагов круговой волной.", "color":"98caff"},
	"division": {"name":"Деление", "branch":"colony", "desc":"Копии кружат вокруг амёбы и атакуют врагов.", "color":"e7a7f5", "unlock":8},
	"trail": {"name":"Ядовитый след", "branch":"toxic", "desc":"Оставляет за собой отравленную среду.", "color":"9ce57c"},
	"infection": {"name":"Заражение", "branch":"toxic", "desc":"Заражает ближайшего врага; инфекция наносит урон со временем.", "color":"ffafbf"},
	"devour": {"name":"Хищная пасть", "branch":"predator", "desc":"Позволяет поглощать ослабленных врагов раньше и лечиться.", "color":"ffbd88"}
}
const ADAPTATIONS = {
	"armor": {"name":"Плотная мембрана", "desc":"Снижает получаемый урон на 12% за уровень.", "color":"99b7df"},
	"regen": {"name":"Регенерация", "desc":"Восстанавливает 0,5 здоровья в секунду за уровень.", "color":"6ef1cb"},
	"speed": {"name":"Жгутики", "desc":"Увеличивают скорость на 12% за уровень.", "color":"f4d394"},
	"magnet": {"name":"Рецепторы", "desc":"Притягивают ДНК, биомассу и ткань с растущего радиуса. Само поглощение идёт при касании.", "color":"e7a7f5"}
}
const SYNERGIES = {
	"acid_grasp": {"name":"Растворяющий захват", "needs":["tentacle","acid"], "desc":"Щупальца притягивают цели в кислоту и замедляют их."},
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
