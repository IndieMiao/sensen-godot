class_name DecorationLayout
extends RefCounted

const DATA_PATH := "res://assets/farm/data/decorations.json"
const IDS := ["bench", "planter", "lantern", "fountain", "sign", "crate"]
const Scenery = preload("res://modules/farm/place_scenery.gd")
const FarmProps = preload("res://modules/farm/farm_props.gd")
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary: _data = parsed
	return _data

static func name_of(id: String) -> String:
	return str(data().get("props", {}).get(id, {}).get("name", id.capitalize()))

static func unlocked(state: Dictionary) -> bool:
	if JourneyProgress.active(state): return JourneyProgress.fact(state, "planter_crafted") or JourneyProgress.unlocked(state, "decorations")
	return state.get("growth_choice", {}).get("purchase") in ["tool", "field"]

static func saved(state: Dictionary) -> Array:
	var value = state.get("decorations", [])
	return canonical(value) if value is Array and is_valid(value) else []

static func canonical(props: Array) -> Array:
	var result := []
	for prop in props:
		var value := entry(str(prop.prop_id), Vector2i(int(prop.cell[0]), int(prop.cell[1])))
		if int(prop.get("rotation_q", 0)) != 0: value.rotation_q = int(prop.rotation_q)
		result.append(value)
	result.sort_custom(func(a, b): return IDS.find(str(a.prop_id)) < IDS.find(str(b.prop_id)))
	return result

## 一个道具占的全部格；左上角为锚点，向东南铺开。与服务端 footprintCells 同一套规则。
static func footprint_cells(id: String, q: Vector2i) -> Array:
	var size: Array = data().props.get(id, {}).get("footprint", [1, 1])
	var out: Array = []
	for dj in int(size[1]):
		for di in int(size[0]):
			out.append(q + Vector2i(di, dj))
	return out

## 能不能放在这里：地面「可放置」属性 ∧ 没有开垦过的地 ∧ 不与别的道具重叠。
## 与 server/src/domain/handlers/decorations.ts 的 propPlacementAllowed 三条判据一致。
static func cell_allowed(bp: FarmBlueprint, cells: Dictionary, taken: Dictionary, id: String, q: Vector2i) -> bool:
	if bp == null: return false
	for cell in footprint_cells(id, q):
		if not bp.mask_has("buildable", cell): return false
		if cells.has("%d,%d" % [(cell as Vector2i).x, (cell as Vector2i).y]): return false
		if taken.has(cell): return false
	return true

static func is_valid(props: Array) -> bool:
	if props.size() > IDS.size(): return false
	var seen := {}
	var positions: Array[Vector2i] = []
	for value in props:
		if not value is Dictionary or value.size() < 2 or value.size() > 3: return false
		for key in value:
			if key not in ["prop_id", "cell", "rotation_q"]: return false
		var rotation = value.get("rotation_q", 0)
		if not (rotation is int or rotation is float) or not is_finite(float(rotation)) or float(rotation) != roundf(float(rotation)) or rotation < 0 or rotation > 3: return false
		var id := str(value.get("prop_id", ""))
		if not IDS.has(id) or seen.has(id): return false
		var offset = value.get("cell")
		if not offset is Array or offset.size() != 2: return false
		for number in offset:
			if not (number is int or number is float) or not is_finite(float(number)) or float(number) != roundf(float(number)): return false
		var q := Vector2i(int(offset[0]), int(offset[1]))
		for cell in footprint_cells(id, q):
			if positions.has(cell): return false
			positions.append(cell)
		seen[id] = true
	return true

static func entry(id: String, q: Vector2i) -> Dictionary:
	return {"prop_id": id, "cell": [q.x, q.y]}

static func index_of(props: Array, id: String) -> int:
	for index in props.size():
		if str(props[index].get("prop_id", "")) == id: return index
	return -1

## 摆件区的局部原点。**存档坐标是农场格**（服务端按 farm_plot 的「可放置」属性校验），
## 但布置界面目前挂在 journey 的 courtyard 场景里，那里的相机在自己的原点附近。
## 这个偏移是两套坐标之间的唯一换算点；把面板搬进农场场景后可以直接去掉。
const LOCAL_ORIGIN := Vector2i(32, 12)

static func world_position(prop: Dictionary) -> Vector3:
	var q: Array = prop.get("cell", [0, 0])
	var unit := float(data().unit_m)
	return Vector3((float(q[0]) - float(LOCAL_ORIGIN.x)) * unit, 0,
		-(float(q[1]) - float(LOCAL_ORIGIN.y)) * unit)

static func quantize(world: Vector3) -> Vector2i:
	var unit := float(data().unit_m)
	return LOCAL_ORIGIN + Vector2i(roundi(world.x / unit), roundi(-world.z / unit))

static func with_position(props: Array, id: String, q: Vector2i) -> Array:
	var next := props.duplicate(true)
	var index := index_of(next, id)
	if index < 0: next.append(entry(id, q))
	else: next[index].cell = [q.x, q.y]
	return canonical(next)

static func first_position(id: String, props: Array, bp: FarmBlueprint = null, cells: Dictionary = {}) -> Variant:
	if not IDS.has(id): return null
	var preferred: Array = data().props[id].default_cell
	var q := Vector2i(int(preferred[0]), int(preferred[1]))
	if bp != null:
		var taken := {}
		for prop in props:
			if str(prop.prop_id) == id: continue
			for cell in footprint_cells(str(prop.prop_id), Vector2i(int(prop.cell[0]), int(prop.cell[1]))): taken[cell] = true
		if cell_allowed(bp, cells, taken, id, q): return q
		var closest: Variant = null
		var distance := INF
		for y in bp.grid.y:
			for x in bp.grid.x:
				var candidate := Vector2i(x, y)
				var candidate_distance := Vector2(candidate - q).length_squared()
				if candidate_distance >= distance or not cell_allowed(bp, cells, taken, id, candidate): continue
				closest = candidate
				distance = candidate_distance
		return closest
	if is_valid(with_position(props, id, q)): return q
	# 默认位置被占了：在它附近螺旋找一格空的。真正的可放置性由 cell_allowed 判定，
	# 这里只保证不与已放的道具重叠。
	for radius in range(1, 8):
		for dj in range(-radius, radius + 1):
			for di in range(-radius, radius + 1):
				if maxi(absi(di), absi(dj)) != radius: continue
				var near := q + Vector2i(di, dj)
				if near.x < 0 or near.y < 0: continue
				if is_valid(with_position(props, id, near)): return near
	return null

static func build(props: Array, selected_id := "", planted := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Decorations"
	if not is_valid(props): return root
	for prop in props:
		var id := str(prop.prop_id)
		var mesh := _prop(id, planted)
		mesh.name = id
		mesh.position = world_position(prop)
		mesh.rotation.y = int(prop.get("rotation_q", 0)) * PI * 0.5
		mesh.set_meta("prop_id", id)
		root.add_child(mesh)
		if id == selected_id:
			var ring := MeshInstance3D.new()
			ring.name = "SelectedDecoration"
			var torus := TorusMesh.new()
			torus.inner_radius = 0.43
			torus.outer_radius = 0.47
			torus.rings = 24
			torus.ring_segments = 6
			ring.mesh = torus
			ring.position = mesh.position + Vector3(0, 0.025, 0)
			var highlight := StandardMaterial3D.new()
			highlight.albedo_color = GameUi.GOLD
			highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ring.material_override = highlight
			root.add_child(ring)
	return root

static func _prop(id: String, planted := true) -> MeshInstance3D:
	if id == "crate": return FarmProps.build("storage", Vector3.ZERO, 1.0)
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	match id:
		"bench": Scenery._bench(s, Vector3.ZERO, Scenery.BLUE)
		"planter":
			Scenery._planter(s, Vector3.ZERO, Vector2(0.65, 0.6), Scenery.CORAL)
			if planted: Scenery._plants(s, "H", [Vector3(-0.13, 0.57, 0), Vector3(0.14, 0.53, 0.08)], 0.48)
		"lantern":
			Scenery._cylinder(s, 0.25, 0.07, Vector3(0, 0.035, 0), Scenery.STONE)
			Scenery._box(s, Vector3(0.07, 0.5, 0.07), Vector3(0, 0.30, 0), Scenery.GREEN)
			Scenery._box(s, Vector3(0.34, 0.035, 0.34), Vector3(0, 0.57, 0), Scenery.GREEN)
			Scenery._box(s, Vector3(0.25, 0.29, 0.25), Vector3(0, 0.73, 0), GameUi.GOLD.lightened(0.35))
			for side in [-1.0, 1.0]:
				for front in [-1.0, 1.0]: Scenery._box(s, Vector3(0.03, 0.3, 0.03), Vector3(side * 0.14, 0.73, front * 0.14), Scenery.GREEN)
			Scenery._cylinder(s, 0.26, 0.075, Vector3(0, 0.915, 0), Scenery.GREEN, Vector3.ONE, 4)
			Scenery._oval(s, Vector3(0.10, 0.13, 0.10), Vector3(0, 0.99, 0), Scenery.CORAL)
		"fountain":
			Scenery._cylinder(s, 0.37, 0.15, Vector3(0, 0.075, 0), Scenery.STONE, Vector3.ONE, 20)
			Scenery._cylinder(s, 0.30, 0.018, Vector3(0, 0.16, 0), Scenery.BLUE.lightened(0.28), Vector3.ONE, 20)
			Scenery._cylinder(s, 0.075, 0.42, Vector3(0, 0.35, 0), Scenery.STONE)
			Scenery._cylinder(s, 0.22, 0.065, Vector3(0, 0.575, 0), Scenery.STONE, Vector3.ONE, 16)
			Scenery._cylinder(s, 0.18, 0.012, Vector3(0, 0.615, 0), Scenery.BLUE.lightened(0.28), Vector3.ONE, 16)
			Scenery._oval(s, Vector3(0.075, 0.18, 0.075), Vector3(0, 0.73, 0), Scenery.BLUE.lightened(0.50))
		"sign":
			Scenery._box(s, Vector3(0.08, 0.73, 0.08), Vector3(0, 0.365, 0), Scenery.WOOD)
			Scenery._box(s, Vector3(0.65, 0.28, 0.065), Vector3(0, 0.70, 0), Scenery.PAPER)
			Scenery._oval(s, Vector3(0.14, 0.18, 0.04), Vector3(-0.06, 0.71, 0.05), Scenery.GREEN, Basis(Vector3.BACK, 0.4))
			Scenery._oval(s, Vector3(0.14, 0.18, 0.04), Vector3(0.06, 0.71, 0.05), Scenery.GREEN, Basis(Vector3.BACK, -0.4))
	s.index()
	var instance := MeshInstance3D.new()
	instance.mesh = s.commit()
	if id == "bench": instance.scale = Vector3.ONE * 0.52
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	instance.material_override = material
	return instance
