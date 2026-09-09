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
		var value := entry(str(prop.prop_id), Vector2i(int(prop.offset_q[0]), int(prop.offset_q[1])))
		if int(prop.get("rotation_q", 0)) != 0: value.rotation_q = int(prop.rotation_q)
		result.append(value)
	result.sort_custom(func(a, b): return IDS.find(str(a.prop_id)) < IDS.find(str(b.prop_id)))
	return result

static func offset_allowed(q: Vector2i) -> bool:
	var config := data()
	var bounds: Dictionary = config.bounds_q
	var blocked: Dictionary = config.blocked_outer
	return q.x >= int(bounds.min_x) and q.x <= int(bounds.max_x) and q.y >= int(bounds.min_z) and q.y <= int(bounds.max_z) \
		and absi(q.x) >= int(config.min_abs_x_q) \
		and not (absi(q.x) >= int(blocked.min_abs_x_q) and q.y <= int(blocked.max_z_q))

static func is_valid(props: Array) -> bool:
	if props.size() > IDS.size(): return false
	var seen := {}
	var positions: Array[Vector2i] = []
	for value in props:
		if not value is Dictionary or value.size() < 3 or value.size() > 4: return false
		for key in value:
			if key not in ["anchor_id", "prop_id", "offset_q", "rotation_q"]: return false
		var rotation = value.get("rotation_q", 0)
		if not (rotation is int or rotation is float) or not is_finite(float(rotation)) or float(rotation) != roundf(float(rotation)) or rotation < 0 or rotation > 3: return false
		if str(value.get("anchor_id", "")) != str(data().anchor_id): return false
		var id := str(value.get("prop_id", ""))
		if not IDS.has(id) or seen.has(id): return false
		var offset = value.get("offset_q")
		if not offset is Array or offset.size() != 2: return false
		for number in offset:
			if not (number is int or number is float) or not is_finite(float(number)) or float(number) != roundf(float(number)): return false
		var q := Vector2i(int(offset[0]), int(offset[1]))
		if not offset_allowed(q): return false
		for previous in positions:
			if Vector2(q).distance_squared_to(Vector2(previous)) < pow(float(data().min_distance_q), 2): return false
		positions.append(q)
		seen[id] = true
	return true

static func entry(id: String, q: Vector2i) -> Dictionary:
	return {"anchor_id": str(data().anchor_id), "prop_id": id, "offset_q": [q.x, q.y]}

static func index_of(props: Array, id: String) -> int:
	for index in props.size():
		if str(props[index].get("prop_id", "")) == id: return index
	return -1

static func world_position(prop: Dictionary) -> Vector3:
	var q: Array = prop.get("offset_q", [0, 0])
	var unit := float(data().unit_m)
	return Vector3(float(q[0]) * unit, 0, float(q[1]) * unit)

static func quantize(world: Vector3) -> Vector2i:
	return Vector2i(roundi(world.x / float(data().unit_m)), roundi(world.z / float(data().unit_m)))

static func with_position(props: Array, id: String, q: Vector2i) -> Array:
	var next := props.duplicate(true)
	var index := index_of(next, id)
	if index < 0: next.append(entry(id, q))
	else: next[index].offset_q = [q.x, q.y]
	return canonical(next)

static func first_position(id: String, props: Array) -> Variant:
	if not IDS.has(id): return null
	var preferred: Array = data().props[id].default_offset_q
	var q := Vector2i(int(preferred[0]), int(preferred[1]))
	if is_valid(with_position(props, id, q)): return q
	var bounds: Dictionary = data().bounds_q
	for z in range(int(bounds.min_z), int(bounds.max_z) + 1):
		for x in range(int(bounds.min_x), int(bounds.max_x) + 1):
			q = Vector2i(x, z)
			if is_valid(with_position(props, id, q)): return q
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
