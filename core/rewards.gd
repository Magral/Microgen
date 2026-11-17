extends RefCounted
const Catalog = preload("res://core/catalog.gd")
const QUALITY_NAMES = ["обычная", "редкая", "эпическая", "легендарная"]
const QUALITY_COLORS = [Color("cbd8d2"), Color("72bfff"), Color("c297f2"), Color("f5ca72")]

# Rarity represents a real strength bonus, independent of organ identity/color.
# Tier gently improves rewards; even the highest tier retains all four outcomes.
static func quality_weights(tier: int = 0) -> Array:
	var t = clampi(tier, 0, 10)
	return [maxf(30.0, 70.0 - t * 4.0), 23.0 + t * 1.5, 6.0 + t * 1.8, 1.0 + t * 0.7]

static func roll_quality(rng: RandomNumberGenerator, tier: int = 0) -> int:
	var weights = quality_weights(tier)
	var total = 0.0
	for weight in weights: total += weight
	var roll = rng.randf() * total
	for i in range(weights.size()):
		roll -= weights[i]
		if roll < 0.0: return i
	return 3

static func quality_name(grade: int) -> String:
	return QUALITY_NAMES[clampi(grade, 0, 3)]

static func quality_color(grade: int) -> Color:
	return QUALITY_COLORS[clampi(grade, 0, 3)]

static func quality_multiplier(grade: int) -> float:
	return Catalog.quality_multiplier(grade)

static func multiplier(grade: int) -> float:
	return quality_multiplier(grade)
