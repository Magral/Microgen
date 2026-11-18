extends RefCounted

const WINDUP_SECONDS = 1.1
const BREAKUP_SECONDS = 1.35
const EXPOSED_DAMAGE_MULTIPLIER = 1.6

const PATTERNS = [
	{"name": "Игольчатый веер", "hint": "Уйди вбок от лучей", "organ": "spikes", "count": 7, "spread": 0.18, "speed": 210.0, "color": Color("ffb57c")},
	{"name": "Споровое кольцо", "hint": "Останься между лучами", "organ": "infection", "count": 12, "spread": TAU / 12.0, "speed": 165.0, "color": Color("e492ec")},
	{"name": "Кислотный поток", "hint": "Уйди поперёк потока", "organ": "acid", "count": 3, "spread": 0.10, "speed": 250.0, "color": Color("d8ef8b")},
]

static func pattern(seed_value: int, stage_index: int) -> Dictionary:
	return PATTERNS[posmod(seed_value + stage_index, PATTERNS.size())]

static func direction(attack: Dictionary, angle: float, ray: int) -> Vector2:
	var offset = (float(ray) - (int(attack.count) - 1) * 0.5) * float(attack.spread)
	return Vector2.from_angle(angle + offset)

static func health(stage_index: int) -> float:
	return 1600.0 * (1.0 + 0.14 * float(stage_index - 1))
