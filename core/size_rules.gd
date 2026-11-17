extends RefCounted

# All distances are radii in world space, never on-screen pixels.
static func profile(player_radius: float,enemy_radius: float,hp_fraction: float,pull_rank: int,mouth_rank: int,frontal: bool) -> Dictionary:
	var ratio=enemy_radius/maxf(1.0,player_radius)
	var health=clampf(hp_fraction,0,1)
	var threshold=0.0
	if ratio<=0.72: threshold=1.0
	elif ratio<0.95:threshold=lerpf(1.0,0.43,smoothstep(0.72,0.95,ratio))
	elif ratio<=1.25:threshold=lerpf(0.43,0.14,smoothstep(0.95,1.25,ratio))
	elif ratio<=1.6 and mouth_rank>0:threshold=0.08+mouth_rank*0.008
	if ratio<=1.25:threshold+=mouth_rank*0.025
	if frontal and mouth_rank>0 and ratio<=1.6:threshold+=0.15+mouth_rank*0.035
	if ratio>=0.9:threshold=minf(threshold,0.58 if frontal and mouth_rank>0 else 0.43)
	if ratio>1.25:threshold=minf(threshold,0.32)
	threshold=clampf(threshold,0,1)
	var pull=0.0
	if pull_rank>0:
		if ratio<0.95:pull=(24.0+20.0*pull_rank)*(1.6-ratio)*(1.0-smoothstep(0.75,0.95,ratio)*0.85)
		elif ratio<=1.25 and pull_rank>=2:pull=3.5*(pull_rank-1)*clampf((1.25-ratio)/0.25,0,1)
		if ratio<=1.6 and health<=0.12 and pull_rank>=1:pull=maxf(pull,(12.0+pull_rank*5)*clampf((1.6-ratio)/0.6,0,1))
	var impact=0.0 if ratio<=1.03 else lerpf(1.5,20.0,smoothstep(1.03,2.4,ratio))
	var duration=lerpf(0.45,1.05,smoothstep(0.55,1.4,ratio))
	if frontal and mouth_rank>0:duration*=0.65
	return {"ratio":ratio,"threshold":threshold,"eligible":health<=threshold and threshold>0.0,"pull":pull,"impact":impact,"speed":clampf(1.0/sqrt(maxf(1.0,ratio)),0.35,1.0),"duration":duration}
