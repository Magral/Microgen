extends RefCounted
static func radius(level: int,fraction: float=0.0) -> float:
	return clampf(22.0+(maxi(1,level)-1+clampf(fraction,0,1))*4.0,22.0,96.0)
static func zoom(radius_value: float) -> float:
	return (68.0+log(maxf(1.0,radius_value/22.0))*12.0)/radius_value
