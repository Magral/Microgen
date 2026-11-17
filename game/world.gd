extends RefCounted
const W = 52
const H = 38
const TILE = 110.0
var cells: Array = []
var colonies: Array = []
var nests: Array = []
var nutrients: Array = []
var start = Vector2(1100,2090)
var boss_pos = Vector2(4500,2090)
var seed_value = 0
var boundary_phase = 0.0
var conditions: Array = []

func generate(value: int):
	seed_value = value
	var rng = RandomNumberGenerator.new()
	rng.seed = value
	boundary_phase = rng.randf() * TAU
	conditions = [rng.randi_range(0,2),rng.randi_range(0,2)]
	cells = []
	for y in range(H):
		for x in range(W):
			cells.append(1 if x == 0 or y == 0 or x == W-1 or y == H-1 or rng.randf() < 0.39 else 0)
	for iteration in range(3):
		var next = cells.duplicate()
		for y in range(1,H-1):
			for x in range(1,W-1):
				var solid = 0
				for yy in range(y-1,y+2):
					for xx in range(x-1,x+2): solid += cells[yy*W+xx]
				next[y*W+x] = 1 if solid >= 5 else 0
		cells = next
	start = Vector2(10,19)*TILE + Vector2.ONE*TILE/2
	boss_pos = Vector2(rng.randi_range(39,45),rng.randi_range(12,26))*TILE+Vector2.ONE*TILE/2
	colonies = []
	nests = []
	nutrients = []
	for i in range(4):
		var p = Vector2(rng.randi_range(6+int(i/2)*25,22+int(i/2)*24), rng.randi_range(6,31))*TILE+Vector2.ONE*TILE/2
		colonies.append({"pos":p,"id":i,"stock":[],"visited":false})
	for i in range(4):
		nests.append({"pos":Vector2(rng.randi_range(5,46),rng.randi_range(5,32))*TILE+Vector2.ONE*TILE/2,"used":false,"kind":rng.randi_range(0,2)})
	_carve(start,3)
	_carve(boss_pos,3)
	for poi in colonies + nests:
		_connect(start,poi.pos,rng)
		_carve(poi.pos,2)
	_connect(start,boss_pos,rng)
	# Only the flood-connected component is traversable; carve guarantees every landmark joins it.
	var visited = _flood(start)
	for i in range(cells.size()):
		if cells[i] == 0 and not i in visited: cells[i] = 1
	for i in range(180):
		var p = Vector2(rng.randf_range(200,W*TILE-200),rng.randf_range(200,H*TILE-200))
		if walkable(p,35): nutrients.append({"pos":p,"rich":rng.randf()<0.12})

func _carve(p: Vector2, radius: int):
	var c = tile(p)
	for y in range(maxi(1,c.y-radius),mini(H-1,c.y+radius+1)):
		for x in range(maxi(1,c.x-radius),mini(W-1,c.x+radius+1)):
			if Vector2(x-c.x,y-c.y).length() <= radius+0.5: cells[y*W+x] = 0

func _connect(a: Vector2,b: Vector2,rng: RandomNumberGenerator):
	var c = tile(a)
	var goal = tile(b)
	while c != goal:
		_carve(Vector2(c)*TILE+Vector2.ONE*TILE/2,1)
		if (rng.randf()<0.5 and c.x != goal.x) or c.y == goal.y: c.x += signi(goal.x-c.x)
		else: c.y += signi(goal.y-c.y)

func tile(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x/TILE),floori(p.y/TILE))

func _flood(p: Vector2) -> Dictionary:
	var c = tile(p)
	var seen = {c.y*W+c.x:true}
	var queue = [c]
	var head = 0
	while head < queue.size():
		var q = queue[head]
		head += 1
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var n = q+offset
			if n.x<0 or n.y<0 or n.x>=W or n.y>=H: continue
			var idx = n.y*W+n.x
			if cells[idx] == 0 and not idx in seen:
				seen[idx] = true
				queue.append(n)
	return seen

func reachable(p: Vector2) -> bool:
	var c = tile(p)
	return c.y*W+c.x in _flood(start)

func walkable(p: Vector2,radius: float = 0.0) -> bool:
	for offset in [Vector2(-radius,-radius),Vector2(radius,-radius),Vector2(-radius,radius),Vector2(radius,radius)]:
		var c = tile(p+offset)
		if c.x<0 or c.y<0 or c.x>=W or c.y>=H or cells[c.y*W+c.x] == 1: return false
	return true

func move_body(p: Vector2,delta: Vector2,radius: float) -> Vector2:
	# Substeps prevent tunnelling through walls when resuming or on a slow frame.
	var steps = maxi(1,ceili(delta.length()/22.0))
	var d = delta/steps
	for i in range(steps):
		if walkable(p+Vector2(d.x,0),radius): p.x += d.x
		if walkable(p+Vector2(0,d.y),radius): p.y += d.y
	return p

func biome(p: Vector2) -> int:
	var boundary = W*TILE*0.5 + sin(p.y/650.0+boundary_phase)*350.0 + sin(p.y/210.0)*100.0
	return 1 if p.x>boundary else 0

func condition_name(id: int) -> String:
	return ["Питательная взвесь","Вязкая среда","Быстрый метаболизм"][conditions[id]]
