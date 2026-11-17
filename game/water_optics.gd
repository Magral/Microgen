extends RefCounted
# Shared periodic optical atlas: two filtered texture reads replace per-pixel
# procedural noise hashing. The texture is generated once, independently of RNG.
static var _flow: ImageTexture
static var _haze: GradientTexture2D
static var generations=0
static func flow_texture() -> ImageTexture:
	if _flow!=null:return _flow
	var image=Image.create(256,256,false,Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var a=x*TAU/256.0
			var b=y*TAU/256.0
			var cloud=0.5+(sin(a+sin(b)*1.1)+cos(b*2+cos(a))+sin(a*3+b*2)*0.35)/4.7
			var ridge=absf(sin(a*3+sin(b*2)*1.3)+sin(b*3+cos(a*2)*1.2))
			var caustic=1.0-smoothstep(0.035,0.22,ridge)
			var grain=0.5+0.25*sin(a*13+sin(b*7))+0.25*cos(b*11+sin(a*5))
			image.set_pixel(x,y,Color(clampf(cloud,0,1),caustic,grain,1))
	_flow=ImageTexture.create_from_image(image)
	generations+=1
	return _flow
static func haze_texture() -> GradientTexture2D:
	if _haze!=null:return _haze
	var gradient=Gradient.new()
	gradient.offsets=PackedFloat32Array([0.0,0.2,0.5,0.8,1.0])
	gradient.colors=PackedColorArray([Color(1,1,1,0.8),Color(1,1,1,0.68),Color(1,1,1,0.30),Color(1,1,1,0.045),Color(1,1,1,0)])
	_haze=GradientTexture2D.new()
	_haze.gradient=gradient
	_haze.width=64;_haze.height=64
	_haze.fill=GradientTexture2D.FILL_RADIAL
	_haze.fill_from=Vector2(0.5,0.5);_haze.fill_to=Vector2(1,0.5)
	return _haze
