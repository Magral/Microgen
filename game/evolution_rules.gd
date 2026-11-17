extends RefCounted
const SizeRules=preload("res://core/size_rules.gd")
# Shared eligibility for gameplay and on-body holds; evaluate current health.
static func crown_eligible(radius: float,enemy: Dictionary,pull_rank: int) -> bool:
	if float(enemy.get("hp",0))<=0 or enemy.get("captured",false) or enemy.get("kind","")=="boss":return false
	var health=float(enemy.hp)/maxf(1.0,float(enemy.max_hp))
	if enemy.get("kind","")=="miniboss" and health>0.15:return false
	var ratio=float(enemy.r)/maxf(1.0,radius)
	return (ratio<0.95 or health<=0.12) and SizeRules.profile(radius,enemy.r,health,pull_rank,0,false).pull>0

static func crown_reach(radius: float,rank: int) -> float:
	return (165.0+rank*12)*radius/34.0

static func crown_tip(offset: Vector2,radius: float,side: float,phase: float) -> Vector2:
	# Opposing fingers travel around the prey, never claiming a new attack.
	return offset+offset.normalized().orthogonal()*side*radius*(0.65+0.12*sin(phase))
