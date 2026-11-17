extends RefCounted

# Visual state only: displacement follows the simulation, never feeds back into it.
var rest_angle = 0.0
var angle = 0.0
var strain = Vector2.ZERO
var strain_velocity = Vector2.ZERO
var lag = Vector2.ZERO
var lag_velocity = Vector2.ZERO
var clock = 0.0
var speed_factor = 0.0

func _init(initial_angle: float=0.0):
	rest_angle=initial_angle
	angle=initial_angle

func step(dt: float,actual_velocity: Vector2):
	dt=clampf(dt,0.0,0.25)
	var velocity=actual_velocity.limit_length(320.0)
	var speed=clampf(velocity.length()/145.0,0.0,1.25)
	var target=Vector2.ZERO
	if speed>0.01:
		var heading=velocity.angle()
		target=Vector2(cos(heading*2),sin(heading*2))*0.19*speed
	var count=maxi(1,ceili(dt*120.0))
	var h=dt/count
	for i in range(count):
		if speed>0.025: angle=lerp_angle(angle,velocity.angle(),1.0-exp(-h*9.0))
		strain_velocity+=((target-strain)*210.0-strain_velocity*12.0)*h
		strain=(strain+strain_velocity*h).limit_length(0.28)
		var trailing=-velocity/145.0*0.07
		lag_velocity+=((trailing-lag)*105.0-lag_velocity*11.0)*h
		lag=(lag+lag_velocity*h).limit_length(0.14)
		speed_factor=lerpf(speed_factor,speed,1.0-exp(-h*8.0))
	clock+=dt

func angle_delta() -> float:
	return wrapf(angle-rest_angle,-PI,PI)

func deform_point(point: Vector2,phase: float=0.0) -> Vector2:
	var depth=clampf(point.length(),0.0,1.2)
	var theta=point.angle()
	var wave=1.0+(0.055+0.025*speed_factor)*depth*sin(theta*3.0-clock*2.7+phase)+0.018*depth*sin(theta*5.0+clock*1.8-phase)
	var rotated=(point*wave).rotated(angle_delta())
	var deformed=Vector2((1.0+strain.x)*rotated.x+strain.y*rotated.y,strain.y*rotated.x+(1.0-strain.x)*rotated.y)
	return deformed+lag*(1.0-depth*0.55)

func deform_points(points: PackedVector2Array,phase: float=0.0) -> PackedVector2Array:
	var out=PackedVector2Array()
	out.resize(points.size())
	for i in range(points.size()): out[i]=deform_point(points[i],phase)
	return out
