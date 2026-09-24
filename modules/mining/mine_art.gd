extends RefCounted

const Art = preload("res://modules/farm/farm_art.gd")
const Layout = preload("res://modules/mining/mine_layout.gd")
const Meshes = preload("res://modules/mining/mine_mesh.gd")
const FLOOR_COLORS := [Color("dca26e"), Color("cfaa79"), Color("c69b80"), Color("af9183"), Color("ab877f")]
const WALL_COLORS := [Color("b85e43"), Color("a59a77"), Color("94768d"), Color("7684ad"), Color("8b6b90")]
const TEAL := Color("347878")
const WOOD := Color("87553b")
const EDGE := Color("c18a57")
const IRON := Color("334c50")
const BRASS := Color("d19b56")
const VIEW_BOUNDS := AABB(Vector3(-0.95, -0.5, -9.05), Vector3(11.6, 2.8, 9.85))
static var _floor_cache: Dictionary = {}
static var _rock_cache: Dictionary = {}
const STONE := Color("71857e")
const TIMBER := Color("ae9173")
const METAL := Color("456d70")

static func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface

static func _mesh(surface: SurfaceTool, node_name: String) -> MeshInstance3D:
	surface.index()
	var result := MeshInstance3D.new()
	result.name = node_name
	result.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	result.material_override = material
	return result

static func entrance() -> Node3D:
	var result := Node3D.new()
	result.name = "MineEntrance"
	var surface := _surface()
	for side in [-1.0, 1.0]:
		PlaceScenery._oval(surface, Vector3(0.8, 1.4, 0.65), Vector3(side * 0.6, 0.6, 0), STONE)
		PlaceScenery._box(surface, Vector3(0.16, 1.25, 0.18), Vector3(side * 0.43, 0.63, 0.39), TIMBER)
	PlaceScenery._oval(surface, Vector3(1.9, 0.65, 0.9), Vector3(0, 1.35, -0.1), STONE.lightened(0.08))
	PlaceScenery._box(surface, Vector3(0.9, 1.2, 0.05), Vector3(0, 0.61, 0.05), Color("243e39"))
	PlaceScenery._box(surface, Vector3(1.12, 0.2, 0.2), Vector3(0, 1.3, 0.4), TIMBER)
	for x in [-0.22, 0.22]:
		PlaceScenery._box(surface, Vector3(0.035, 0.04, 1.3), Vector3(x, 0.03, 0.76), METAL)
	for i in 5:
		PlaceScenery._box(surface, Vector3(0.63, 0.025, 0.1), Vector3(0, 0.018, 0.3 + i * 0.25), TIMBER)
	result.add_child(_mesh(surface, "MineArch"))
	return result

static func floor_scenery(floor_number: int, elevator_unlocked: bool) -> Node3D:
	var number := clampi(floor_number, 1, 5)
	if not _floor_cache.has(number):
		var template := _chamber(number)
		for child in template.get_children(): child.owner = template
		var packed := PackedScene.new()
		packed.pack(template)
		template.free()
		_floor_cache[number] = packed
	var root := (_floor_cache[number] as PackedScene).instantiate() as Node3D
	if number in [1, 5]: root.add_child(elevator(elevator_unlocked))
	root.add_child(ladder(Layout.UP, true))
	return root

static func _outline(number: int) -> PackedVector2Array:
	# Shell variations stay outside the authoritative walkable rectangle. Art never
	# creates an invisible shortcut or a decorative obstacle in a saved route.
	var points := PackedVector2Array([Vector2(-0.48, -8.12), Vector2(0.0, -8.65), Vector2(9.45, -8.65),
		Vector2(10.0, -8.12), Vector2(10.0, -0.35), Vector2(9.5, 0.28), Vector2(0, 0.28), Vector2(-0.48, -0.35)])
	if number == 2:
		points = PackedVector2Array([Vector2(-0.55,-8.1),Vector2(0,-8.7),Vector2(5.8,-8.7),Vector2(6.5,-8.85),
			Vector2(9.5,-8.55),Vector2(10.1,-7.9),Vector2(10.1,-5.7),Vector2(9.95,-4.3),Vector2(10.1,-2.4),
			Vector2(10.0,-0.4),Vector2(9.45,0.3),Vector2(0.0,0.3),Vector2(-0.55,-0.4),Vector2(-0.65,-2.8),Vector2(-0.38,-4.1),Vector2(-0.65,-6.0)])
	elif number >= 3:
		points = PackedVector2Array([Vector2(-0.58,-7.8),Vector2(0,-8.65),Vector2(2.5,-8.8),Vector2(5.4,-8.62),
			Vector2(8.7,-8.8),Vector2(9.6,-8.55),Vector2(10.12,-7.7),Vector2(10.2,-5.6),Vector2(10.03,-3.4),
			Vector2(10.15,-1.2),Vector2(9.8,-0.12),Vector2(8.8,0.4),Vector2(1.0,0.4),Vector2(-0.35,-0.12),Vector2(-0.6,-1.2),Vector2(-0.48,-4.4)])
	return points

static func _chamber(number: int) -> Node3D:
	var root := Node3D.new()
	root.name = "MineScenery"
	var stone := Meshes.surface()
	var earth := Meshes.surface()
	var wood := Meshes.surface()
	var metal := Meshes.surface()
	var glow := Meshes.surface()
	var crystal := Meshes.surface()
	var contact := Meshes.surface()
	var rng := RandomNumberGenerator.new()
	rng.seed = 240924 + number * 197
	var outline := _outline(number)
	var ground: Color = FLOOR_COLORS[number - 1]
	var wall: Color = WALL_COLORS[number - 1]
	var base := Meshes.surface()
	var expanded := PackedVector2Array()
	for p in outline:
		expanded.append(p + (p - Vector2(4.75,-4.0)).normalized() * 0.23)
	Meshes.slab(base, expanded, -0.10, 0.3, wall.darkened(0.15))
	root.add_child(Meshes.finish(base, "CavernPlinth"))
	Meshes.slab(earth, outline, -0.018, 0.14, ground)
	# Individually hewn wall segments and a thin foreground wall with an entry gap.
	for segment in outline.size():
		var a := outline[segment]
		var b := outline[(segment + 1) % outline.size()]
		var length := a.distance_to(b)
		var count := maxi(1, roundi(length / 1.05))
		for i in count:
			var p := a.lerp(b, (float(i) + 0.5) / count)
			if p.y > -0.15 and p.x > 3.9 and p.x < 5.6: continue
			var front := p.y > -0.35
			var height := rng.randf_range(0.50, 0.63) if front else rng.randf_range(0.96, 1.24)
			var color := wall.lightened(rng.randf_range(0, 0.10)).darkened(rng.randf_range(0, 0.07))
			var yaw := -atan2(b.y - a.y, b.x - a.x)
			Meshes.soft_disc(contact,Vector3(p.x,0.004,p.y),Vector2(length/count*0.70,0.66),yaw)
			Meshes.block(stone, Vector3(p.x, height * 0.5 - 0.045, p.y), Vector3(length / count - 0.025, height, 0.69), color, i + segment * 11 + number * 17, 0.18, yaw)
			var inward := (Vector2(4.75,-4.0) - p).normalized()
			if i % 2 == 0:
				var face := Vector3(p.x + inward.x * 0.351, height * 0.56, p.y + inward.y * 0.351)
				var along := Vector3(b.x-a.x,0,b.y-a.y).normalized()
				Meshes.ribbon(stone,[face-along*0.36,face-along*0.09+Vector3.UP*0.022,face+along*0.20-Vector3.UP*0.02],0.014,color.darkened(0.22),Vector3(inward.x,0,inward.y))
			for j in 3:
				var rubble := p + inward * rng.randf_range(0.32,0.45) + (b-a).normalized() * rng.randf_range(-0.3,0.3)
				var r := rng.randf_range(0.08,0.15)
				Meshes.pebble(stone, Vector3(rubble.x,r * 0.35,rubble.y), Vector3(r * 1.5,r,r * 1.35), wall.lightened(0.18), i * 31 + j)
			if number == 2 and not front:
				var moss := Vector3(p.x, height + 0.003, p.y)
				Meshes.oval(stone, moss, Vector3(0.5,0.024,0.35), Color("83875a"))
			if number == 5 and i % 3 == 0:
				# Narrow gold seams stay on the visible inward face.
				var face := Vector3(p.x + inward.x * 0.33,height * 0.42,p.y + inward.y * 0.33)
				var along := Vector3(b.x-a.x,0,b.y-a.y).normalized() * 0.34
				Meshes.ribbon(stone, [face-along,face+Vector3(0,0.055,0),face+along], 0.023, Color("b29865"), Vector3(inward.x,0,inward.y))
	# Flat stone fragments and fine sandy variation do not alter movement geometry.
	for i in 16:
		var p := Vector3(rng.randf_range(0.8,9.0), 0.006, rng.randf_range(-7.9,-0.4))
		for j in rng.randi_range(2,4):
			var offset := Vector3(rng.randf_range(-0.32,0.32),0,rng.randf_range(-0.25,0.25))
			Meshes.block(stone,p+offset,Vector3(rng.randf_range(0.18,0.44),0.018,rng.randf_range(0.18,0.36)),ground.lerp(wall.lightened(0.20),0.43),i*7+j,0.07,rng.randf_range(-PI,PI))
	for i in 200:
		var p := Vector3(rng.randf_range(0.3,9.4),0.002,rng.randf_range(-8.1,0))
		var r := rng.randf_range(0.008,0.024)
		Meshes.oval(earth,p,Vector3(r*2,0.006,r),ground.lightened(rng.randf_range(-0.12,0.08)))
	# Back-wall timber alcove, supplies and the lamp beside the return ladder.
	if number != 5: _alcove(wood,metal,Vector3(5.1,0,-8.1),number == 1)
	for p in [Vector3(2.75,0,-8.02),Vector3(6.32,0,-8.12),Vector3(0.09,0,-1.85)]:
		_crate(wood,metal,p,0.41,rng.randf_range(-0.2,0.2))
	_crate(wood,metal,Vector3(2.72,0.39,-8.08),0.28,-0.13)
	for p in [Vector3(0.08,0,-5.3),Vector3(7.7,0,-8.12)]: _barrel(wood,metal,p)
	var lamps := [Vector3(0.18,0,-1.12),Vector3(3.25,0,-8.10),Vector3(8.75,0,-8.10)]
	if number >= 4: lamps.append(Vector3(9.69,0,-3.5))
	for p in lamps:
		_lantern(wood,metal,glow,p)
		var lamp := OmniLight3D.new()
		lamp.name = "WarmLantern"
		lamp.position = p + Vector3(0,0.98,0.14)
		lamp.light_color = Color("ffbd6b")
		lamp.light_energy = 0.7
		lamp.omni_range = 2.25
		lamp.omni_attenuation = 1.35
		lamp.shadow_enabled = false
		root.add_child(lamp)
		var pool := Meshes.pool(Vector3(p.x,0.022,p.z+0.18),1.05,Color(1.0,0.54,0.18,0.21))
		pool.name = "LanternPool"
		root.add_child(pool)
	if number == 2:
		for p in [Vector3(0.05,0,-3.8),Vector3(0.1,0,-6.5),Vector3(7.85,0,-8.1),Vector3(9.65,0,-1.85)]:
			_fern(stone,p)
	if number == 3:
		for p in [Vector3(0.04,0,-6.5),Vector3(7.0,0,-8.25),Vector3(9.68,0,-5.7),Vector3(9.65,0,-1.6)]:
			_mushrooms(stone,crystal,p)
	if number == 4:
		for p in [Vector3(0.02,0,-3.0),Vector3(2.04,0,-8.1),Vector3(7.0,0,-8.05),Vector3(9.65,0,-5.6)]:
			for i in 4:
				var offset := Vector3(sin(i*2.1)*0.19,0,cos(i*2.1)*0.17)
				Meshes.pebble(stone,p+offset+Vector3.UP*0.06,Vector3(0.3,0.20,0.28),wall.lightened(0.1),i)
				Meshes.crystal(crystal,p+offset,0.12 if i == 0 else 0.075,0.7 if i == 0 else 0.39,Color("9376f2"),Vector3(sin(i)*0.28,0,cos(i)*0.22))
	root.add_child(Meshes.finish(earth,"SandstoneFloor","earth"))
	var shade := Meshes.finish(contact,"WallContactShade","shadow")
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shade)
	root.add_child(Meshes.finish(stone,"CarvedWallsAndDetails"))
	root.add_child(Meshes.finish(wood,"TimberAndSupplies","wood"))
	root.add_child(Meshes.finish(metal,"TealIronwork","metal"))
	root.add_child(Meshes.finish(glow,"LanternGlass","glow"))
	if number in [3,4]: root.add_child(Meshes.finish(crystal,"CaveGrowth","crystal"))
	return root

static func _crate(wood: SurfaceTool, metal: SurfaceTool, p: Vector3, size: float, yaw: float) -> void:
	Meshes.block(wood,p+Vector3.UP*size*0.5,Vector3.ONE*size,WOOD.darkened(0.15),15,0.022,yaw)
	var basis := Basis(Vector3.UP,yaw)
	for i in 4:
		var x := (float(i)/3-0.5)*size*0.82
		PlaceScenery._box(wood,Vector3(size*0.18,size*0.88,0.022),p+basis*Vector3(x,size*0.5,size*0.51),WOOD.lightened(i*0.025),basis)
	for y in [size*0.1,size*0.9]:
		PlaceScenery._box(wood,Vector3(size*1.06,size*0.10,0.04),p+basis*Vector3(0,y,size*0.54),EDGE,basis)
	for x in [-size*0.44,size*0.44]:
		PlaceScenery._box(wood,Vector3(size*0.10,size,0.035),p+basis*Vector3(x,size*0.5,size*0.55),EDGE,basis)
	Meshes.beam(wood,p+basis*Vector3(-size*0.33,size*0.18,size*0.57),p+basis*Vector3(size*0.33,size*0.82,size*0.57),size*0.08,EDGE)
	for x in [-size*0.42,size*0.42]:
		for y in [size*0.12,size*0.88]: Meshes.oval(metal,p+basis*Vector3(x,y,size*0.58),Vector3.ONE*0.032,IRON)
	for i in 4:
		PlaceScenery._box(wood,Vector3(size*0.2,0.018,size*0.92),p+basis*Vector3((i-1.5)*size*0.235,size*1.01,0),EDGE.darkened(0.1+i*0.04),basis)

static func _barrel(wood: SurfaceTool, metal: SurfaceTool, p: Vector3) -> void:
	for i in 12:
		var a := TAU*i/12
		var b := TAU*(i+1)/12
		var color := WOOD.lightened(float(i%3)*0.035)
		for tier in 2:
			var r0 := 0.18 if tier == 0 else 0.22
			var r1 := 0.22 if tier == 0 else 0.18
			Meshes.quad(wood,p+Vector3(cos(a)*r0,tier*0.23,sin(a)*r0),p+Vector3(cos(b)*r0,tier*0.23,sin(b)*r0),
				p+Vector3(cos(b)*r1,(tier+1)*0.23,sin(b)*r1),p+Vector3(cos(a)*r1,(tier+1)*0.23,sin(a)*r1),color)
	for y in [0.07,0.37]: Meshes.ring(metal,p+Vector3.UP*y,0.198,0.017,IRON)
	Meshes.oval(wood,p+Vector3.UP*0.445,Vector3(0.34,0.018,0.34),WOOD.darkened(0.55))
	Meshes.ring(wood,p+Vector3.UP*0.46,0.17,0.018,EDGE)

static func _alcove(wood: SurfaceTool, metal: SurfaceTool, p: Vector3, boarded: bool) -> void:
	Meshes.box(wood,p+Vector3(0,0.55,-0.10),Vector3(1.6,1.12,0.05),WOOD.darkened(0.65))
	for x in [-0.84,0.84]:
		Meshes.block(wood,p+Vector3(x,0.63,0.05),Vector3(0.19,1.36,0.3),WOOD,23,0.04)
		Meshes.box(metal,p+Vector3(x,0.21,0.05),Vector3(0.21,0.14,0.32),TEAL)
		Meshes.box(metal,p+Vector3(x,1.13,0.05),Vector3(0.21,0.15,0.32),TEAL)
	Meshes.block(wood,p+Vector3(0,1.37,0.05),Vector3(2.0,0.24,0.5),EDGE,37,0.04)
	Meshes.box(metal,p+Vector3(0,1.48,0.08),Vector3(1.35,0.045,0.52),TEAL)
	for x in [-0.76,0.76]: Meshes.box(metal,p+Vector3(x,1.40,0.31),Vector3(0.18,0.24,0.05),TEAL)
	if boarded:
		for i in 3:
			Meshes.block(wood,p+Vector3(0,0.24+i*0.29,0.14),Vector3(1.5,0.20,0.1),WOOD.lightened(i*0.045),31+i,0.025)
	else:
		_crate(wood,metal,p+Vector3(0.48,0,0.1),0.37,0.1)
		_barrel(wood,metal,p+Vector3(-0.48,0,0.12))

static func _lantern(wood: SurfaceTool, metal: SurfaceTool, glow: SurfaceTool, p: Vector3) -> void:
	Meshes.block(wood,p+Vector3(0,0.66,0),Vector3(0.14,1.35,0.16),WOOD,24,0.025)
	for y in [0.20,1.2]: Meshes.box(metal,p+Vector3(0,y,0),Vector3(0.165,0.09,0.18),TEAL)
	Meshes.box(metal,p+Vector3(0,1.35,0.13),Vector3(0.22,0.09,0.46),TEAL)
	Meshes.ring(metal,p+Vector3(0,1.24,0.26),0.055,0.012,IRON,Basis(Vector3.RIGHT,PI/2))
	Meshes.box(glow,p+Vector3(0,1.00,0.27),Vector3(0.115,0.20,0.12),Color("ffe5aa"))
	for y in [0.87,1.13]: Meshes.block(metal,p+Vector3(0,y,0.27),Vector3(0.20,0.08,0.20),BRASS,1,0.02)
	for x in [-0.078,0.078]:
		for z in [0.20,0.34]: Meshes.box(metal,p+Vector3(x,1.0,z),Vector3(0.023,0.23,0.023),IRON)
	Meshes.oval(glow,p+Vector3(0,0.99,0.278),Vector3(0.07,0.14,0.08),Color("fff4cd"))

static func _fern(s: SurfaceTool,p: Vector3) -> void:
	for i in 7:
		var a := i*2.4
		var end := p+Vector3(cos(a)*0.3,0.15+float(i%3)*0.09,sin(a)*0.3)
		var mid := p.lerp(end,0.55)+Vector3.UP*0.16
		var side := Vector3(-sin(a),0,cos(a))*0.07
		Meshes.tri(s,p,mid-side,end,Color("677346"))
		Meshes.tri(s,p,end,mid+side,Color("8d9859"))

static func _mushrooms(stone: SurfaceTool,caps: SurfaceTool,p: Vector3) -> void:
	for i in 5:
		var big := i == 0
		var h := 0.61 if big else 0.23 + i*0.032
		var r := 0.29 if big else 0.095
		var q := p+Vector3(sin(i*2.1)*0.26,0,cos(i*2.1)*0.21)
		Meshes.oval(stone,q+Vector3.UP*h*0.42,Vector3(r*0.43,h*0.9,r*0.43),Color("e4c7af"))
		var tint := Color("e2a7c2") if big else Color("8bc7e3")
		Meshes.oval(caps,q+Vector3.UP*h,Vector3(r*2,r*0.95,r*2),tint)
		Meshes.oval(stone,q+Vector3.UP*(h-r*0.18),Vector3(r*1.92,0.025,r*1.92),Color("f6d9bd"))
		for dot in 3:
			Meshes.oval(caps,q+Vector3(sin(dot*2.1)*r*0.4,h+r*0.40,cos(dot*2.1)*r*0.4),Vector3(r*0.22,0.016,r*0.18),tint.lightened(0.3))

static func elevator(unlocked: bool) -> MeshInstance3D:
	var s := Meshes.surface()
	var p := Layout.ELEVATOR
	Meshes.block(s,p+Vector3(0,0.06,0),Vector3(1.40,0.15,1.3),IRON,4,0.045)
	for i in 7: Meshes.box(s,p+Vector3((i-3)*0.175,0.15,0),Vector3(0.16,0.045,1.14),WOOD.lightened(float(i%3)*0.04))
	for x in [-0.62,0.62]:
		for z in [-0.48,0.46]:
			Meshes.block(s,p+Vector3(x,0.93,z),Vector3(0.11,1.72,0.12),TEAL,8,0.02)
			for y in [0.26,1.63]: Meshes.oval(s,p+Vector3(x,y,z+0.07),Vector3.ONE*0.047,BRASS)
	for z in [-0.5,0.48]: Meshes.block(s,p+Vector3(0,1.80,z),Vector3(1.43,0.14,0.14),TEAL,6,0.025)
	for x in [-0.63,0.63]: Meshes.box(s,p+Vector3(x,1.80,0),Vector3(0.14,0.14,1.12),WOOD)
	for i in 7:
		Meshes.box(s,p+Vector3(-0.53+i*0.175,0.87,-0.49),Vector3(0.035,1.40,0.035),IRON)
	for x in [-0.63,0.63]:
		Meshes.beam(s,p+Vector3(x,0.24,-0.43),p+Vector3(x,1.56,0.40),0.034,TEAL)
	# Hoist drum, axle, rope and a crossed-pick plaque.
	Meshes.beam(s,p+Vector3(-0.73,2.03,-0.23),p+Vector3(0.73,2.03,-0.23),0.09,IRON)
	for i in 9: Meshes.ring(s,p+Vector3((i-4)*0.046,2.03,-0.23),0.15,0.018,EDGE,Basis(Vector3.FORWARD,PI/2))
	Meshes.beam(s,p+Vector3(0,2.03,-0.08),p+Vector3(0,1.28,-0.08),0.025,EDGE)
	for i in 3: Meshes.ring(s,p+Vector3(0.69,0.034+i*0.02,0.63),0.14-i*0.025,0.012,EDGE)
	Meshes.block(s,p+Vector3(0,0.99,0.50),Vector3(0.65,0.62,0.06),EDGE,4,0.02)
	for sign_value in [-1,1]:
		Meshes.beam(s,p+Vector3(-0.17*sign_value,0.79,0.54),p+Vector3(0.15*sign_value,1.16,0.54),0.035,WOOD.darkened(0.5))
		Meshes.beam(s,p+Vector3(0.02*sign_value,1.19,0.54),p+Vector3(0.24*sign_value,1.08,0.54),0.045,IRON)
	Meshes.box(s,p+Vector3(0.8,0.6,0.3),Vector3(0.18,1.2,0.18),WOOD)
	Meshes.box(s,p+Vector3(0.8,0.68,0.41),Vector3(0.22,0.32,0.09),TEAL)
	Meshes.oval(s,p+Vector3(0.8,0.73,0.47),Vector3(0.095,0.095,0.045),Color("a5e3bc") if unlocked else Color("dba158"))
	var result := Meshes.finish(s,"MineElevator","metal")
	return result

static func ladder(position: Vector3, upward: bool) -> MeshInstance3D:
	var s := Meshes.surface()
	Meshes.block(s,position+Vector3(0,0.016,0),Vector3(1.04,0.035,1.08),Color("2a2728"),1,0.06)
	for x in [-0.51,0.51]:
		Meshes.block(s,position+Vector3(x,0.09,0),Vector3(0.15,0.13,1.22),TEAL,11,0.025)
	for z in [-0.55,0.55]:
		Meshes.block(s,position+Vector3(0,0.07,z),Vector3(1.18,0.1,0.16),WOOD,14,0.022)
		for x in [-0.5,0.5]: Meshes.oval(s,position+Vector3(x,0.163,z),Vector3(0.07,0.025,0.07),BRASS)
	var height := 0.78 if upward else 0.28
	for x in [-0.31,0.31]:
		Meshes.beam(s,position+Vector3(x,0.045,0.4),position+Vector3(x,height,-0.39),0.075,WOOD)
	for i in 5:
		var t := float(i)/4
		Meshes.block(s,position+Vector3(0,lerpf(0.05,height,t),lerpf(0.4,-0.39,t)),Vector3(0.72,0.085,0.10),EDGE,13+i,0.019)
	return Meshes.finish(s,"UpLadder" if upward else "DownLadder","wood")

static func rock(position: Vector3, index: int, floor_number: int) -> Node3D:
	var key := "%d:%d" % [clampi(floor_number,1,5),index%6]
	if not _rock_cache.has(key): _rock_cache[key] = _ore(index%6,floor_number)
	var root := Node3D.new()
	root.position = position
	var node := MeshInstance3D.new()
	node.name = "Rock"
	node.mesh = _rock_cache[key]
	node.material_override = Meshes.material()
	root.add_child(node)
	BlobShadow.attach(root,0.52)
	return root

static func _ore(index: int, floor_number: int) -> ArrayMesh:
	var s := Meshes.surface()
	var rng := RandomNumberGenerator.new()
	rng.seed = index*121 + floor_number*317
	var rings: Array = []
	for tier in 4:
		var ring: Array[Vector3] = []
		for i in 7:
			var angle := TAU*i/7 + index*0.75
			var radius: float = [0.36,0.47,0.34,0.15][tier] * rng.randf_range(0.9,1.1)
			var y: float = [0.025,0.15,0.49,0.61][tier]
			ring.append(Vector3(cos(angle)*radius,y + rng.randf_range(-0.02,0.02),sin(angle)*radius))
		rings.append(ring)
	var mineral: Color = [Color("d88d50"),Color("d6d6c1"),Color("d0a268"),Color("a690e2"),Color("c9a462")][clampi(floor_number-1,0,4)]
	var stone := Color("687376")
	for tier in 3:
		for i in 7:
			var j := (i+1)%7
			var a: Vector3 = rings[tier][i]
			var b: Vector3 = rings[tier][j]
			var c: Vector3 = rings[tier+1][j]
			var d: Vector3 = rings[tier+1][i]
			var color := stone.lightened(rng.randf_range(0,0.10)).darkened(rng.randf_range(0,0.07))
			Meshes.quad(s,a,b,c,d,color)
			if i in [1,4,6]:
				var normal := (d-a).cross(b-a).normalized()*0.003
				var u := 0.36+sin(tier*1.6+i)*0.09
				var v := 0.36+sin((tier+1)*1.6+i)*0.09
				Meshes.quad(s,a.lerp(b,u)+normal,a.lerp(b,u+0.095)+normal,d.lerp(c,v+0.095)+normal,d.lerp(c,v)+normal,mineral)
	for i in 7: Meshes.tri(s,Vector3(0,0.63,0),rings[3][i],rings[3][(i+1)%7],stone.lightened(0.12))
	s.index()
	return s.commit()
