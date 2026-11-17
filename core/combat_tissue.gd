extends RefCounted
# Regenerating impact capacity makes tissue resist stacked burst attacks.
# Small prey remains fragile; equal/large organisms sustain deliberate fights.
static func damage_rate(ratio: float,elite: bool=false) -> float:
	if elite:return 0.035
	if ratio<0.9:return lerpf(0.36,0.12,smoothstep(0.6,0.9,ratio))
	return lerpf(0.075,0.045,smoothstep(1.15,1.8,ratio))
