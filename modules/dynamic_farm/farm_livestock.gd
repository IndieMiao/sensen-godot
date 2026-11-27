extends RefCounted
## Livestock buildings' art and layout (C-154, the coop): what `assets/farm/data/dynamic_farm_art.json` says about a
## building type (its scene or parts, fence, feeders), its animals (model, which way they face, their three clips) and
## the drops they leave (model), plus the pickup's feel. Replacing a file at a path named there needs no code change;
## a path that does not exist yet draws a placeholder of the parts' own sizes (the yard's art is SEN-C-155, the hens
## and the egg SEN-C-156).
##
## Positions in the file are in cells (1 U = one tilled cell edge, C-134 attachment-1195) in a building's own unturned
## frame: origin at the footprint's rear-left corner, x to the right, z toward the entry (the front, the model's +Z).
## FarmBuilding puts a model's pivot on the footprint's middle, so `model_point` shifts by half the footprint.
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const ART_PATH := "res://assets/farm/data/dynamic_farm_art.json"
## Placeholder ground sits just above the farm ground so the two never fight.
const GROUND_LIFT := 0.004
## Pickup feel (C-154#19 design) when the file leaves it out.
const PICKUP_DEFAULTS := {"reach_m": 1.2, "hop_m": 0.25, "flight_s": 0.35, "shrink": 0.6, "chest_m": 0.9}
## Laying (the owner on SEN-C-154#145, PM C-154#146) when a drop's art leaves `lay` out: the drop leaves the animal
## `from_m` above the ground, `toss_m` (horizontal) from where it lands, arcs `rise_m` above the straight line down over
## `fall_s`, then bounces once `bounce_m` high over `bounce_s`. The animal stands `toss_m` from the drop's spot to lay.
const LAY_DEFAULTS := {"from_m": 0.2, "toss_m": 0.3, "rise_m": 0.2, "fall_s": 0.45, "bounce_m": 0.06, "bounce_s": 0.2}
const SIDES := ["back", "front", "left", "right"]
## Width the player's centre has to pass an opening (C-154#89) when the art file's fence leaves `entry_clear_m` out.
const ENTRY_CLEAR_M := 0.4

static var _art := {}

## The art file, read once; {} when missing or not a v1 object.
static func art() -> Dictionary:
	if _art.is_empty():
		var raw = JSON.parse_string(FileAccess.get_file_as_string(ART_PATH)) if FileAccess.file_exists(ART_PATH) else null
		_art = raw if raw is Dictionary and int(raw.get("version", 0)) == 1 else {"version": 1}
	return _art

static func building_art(type: String) -> Dictionary:
	var b = art().get("buildings", {}).get(type)
	return b if b is Dictionary else {}

static func animal_art(kind: String) -> Dictionary:
	var a = art().get("animals", {}).get(kind)
	return a if a is Dictionary else {}

static func drop_art(item: String) -> Dictionary:
	var d = art().get("drops", {}).get(item)
	return d if d is Dictionary else {}

static func pickup() -> Dictionary:
	var out := PICKUP_DEFAULTS.duplicate()
	var raw = art().get("pickup")
	if raw is Dictionary:
		for key: String in out:
			if raw.get(key) is float or raw.get(key) is int: out[key] = float(raw[key])
	return out

## How a drop of `item` is laid (LAY_DEFAULTS, overridden key by key by the drop's `lay`).
static func lay(item: String) -> Dictionary:
	var out := LAY_DEFAULTS.duplicate()
	var raw = drop_art(item).get("lay")
	if raw is Dictionary:
		for key: String in out:
			if (raw.get(key) is float or raw.get(key) is int) and float(raw[key]) >= 0.0: out[key] = float(raw[key])
	return out

## A drop's size against its model (the drop's `scale`, default 1; SEN-C-154#145: the egg is drawn bigger than life).
static func drop_scale(item: String) -> float:
	var raw = drop_art(item).get("scale")
	return float(raw) if (raw is float or raw is int) and float(raw) > 0.0 else 1.0

## A point of the building's own frame (cells) on the ground of the model's frame (metres, pivot on the middle).
static func model_point(local: Vector2, base: Vector2i, cell_m: float) -> Vector3:
	return Vector3((local.x - base.x * 0.5) * cell_m, 0.0, (local.y - base.y * 0.5) * cell_m)

## The inverse of model_point for a point already in the model's frame.
static func local_point(model: Vector3, base: Vector2i, cell_m: float) -> Vector2:
	return Vector2(model.x / cell_m + base.x * 0.5, model.z / cell_m + base.y * 0.5)

static func _vec(raw: Variant, fallback := Vector2.ZERO) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1])) if raw is Array and raw.size() == 2 else fallback

## The type's parts: [{id, center: Vector2, size: Vector2, height, round, feeder, model, color}], centres and sizes in
## cells.
static func parts(type: String) -> Array:
	var out := []
	for p in building_art(type).get("parts", []):
		if not p is Dictionary: continue
		out.append({"id": str(p.get("id", "")), "center": _vec(p.get("center")), "size": _vec(p.get("size"), Vector2.ONE),
			"height": float(p.get("height", 0.5)), "round": bool(p.get("round", false)), "feeder": bool(p.get("feeder", false)),
			"model": str(p.get("model", "")), "color": Color.from_string(str(p.get("color", "#9b7a55")), Color(0.6, 0.48, 0.33))})
	return out

## Cells outside the footprint the type's art needs kept (`keep_clear`, rects [x, z, width, depth] in cells of the
## unturned frame): [{cell: Vector2i, walk: bool}]. A `walk` one stays walkable (the cell outside the entry); the
## others hold art drawn past the footprint (the rear hedge). A cell inside the footprint, or a rect wider than a
## building side, is left out.
static func keep_clear(type: String, base: Vector2i) -> Array:
	var out := []
	for k in building_art(type).get("keep_clear", []):
		if not k is Dictionary or not k.get("cells") is Array or k.cells.size() != 4: continue
		var r: Array = k.cells
		if not r.all(func(v): return (v is int or v is float) and absf(float(v)) <= 16.0 and float(v) == floorf(float(v))): continue
		var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if not Rect2i(Vector2i.ZERO, base).has_point(Vector2i(x, z)):
					out.append({"cell": Vector2i(x, z), "walk": bool(k.get("walk", false))})
	return out

## The fence's runs along the footprint's edge, openings left out: [{from: Vector2, to: Vector2, open_from: bool,
## open_to: bool}] in cells; `open_*` says that end stops at an opening.
static func fence_runs(type: String, base: Vector2i) -> Array:
	var fence = building_art(type).get("fence")
	if not fence is Dictionary: return []
	var gaps := {}
	for side: String in SIDES: gaps[side] = []
	for o in fence.get("openings", []):
		if o is Dictionary and gaps.has(str(o.get("side", ""))): gaps[o.side].append(Vector2(float(o.get("from", 0)), float(o.get("to", 0))))
	var w := float(base.x)
	var d := float(base.y)
	var sides := {"back": [Vector2(0, 0), Vector2(w, 0)], "front": [Vector2(0, d), Vector2(w, d)],
		"left": [Vector2(0, 0), Vector2(0, d)], "right": [Vector2(w, 0), Vector2(w, d)]}
	var runs := []
	for side: String in SIDES:
		var a: Vector2 = sides[side][0]
		var b: Vector2 = sides[side][1]
		var along := 0 if side in ["back", "front"] else 1
		var cuts: Array = gaps[side].duplicate()
		cuts.sort_custom(func(p: Vector2, q: Vector2): return p.x < q.x)
		var start := a[along]
		var after_cut := false
		for cut: Vector2 in cuts:
			if cut.x > start: runs.append(_run(a, along, start, cut.x, after_cut, true))
			if cut.y >= start:
				start = cut.y
				after_cut = true
		if b[along] > start: runs.append(_run(a, along, start, b[along], after_cut, false))
	return runs

static func _run(a: Vector2, along: int, from: float, to: float, open_from: bool, open_to: bool) -> Dictionary:
	var p := a
	var q := a
	p[along] = from
	q[along] = to
	return {"from": p, "to": q, "open_from": open_from, "open_to": open_to}

## The fence's `entry_clear_m`: how wide (metres) the player's centre can pass each opening; at least 0.
static func entry_clear_m(type: String) -> float:
	var fence = building_art(type).get("fence")
	var raw = fence.get("entry_clear_m") if fence is Dictionary else null
	return maxf(0.0, float(raw)) if raw is float or raw is int else ENTRY_CLEAR_M

## How far (cells) a fence run's wall is pulled back from an opening's edge, past the half thickness it already
## reaches into it, so the player's centre passes the narrowest opening `entry_clear_m` wide; 0 when wide enough. Only
## the wall the player stops at moves, not the fence's art.
static func entry_pullback(type: String, cell_m: float) -> float:
	var fence = building_art(type).get("fence")
	if not fence is Dictionary: return 0.0
	var t := float(fence.get("thickness", 0.125))
	var need := (entry_clear_m(type) + 2.0 * Walk.BODY_RADIUS) / cell_m
	var pull := 0.0
	for o in fence.get("openings", []):
		if o is Dictionary:
			pull = maxf(pull, (need - (float(o.get("to", 0)) - float(o.get("from", 0)) - t)) * 0.5)
	return pull

## Walls the player stops at, as FarmPropProxy profiles in the model's frame: every fence run and every part (a round
## one as a cylinder). The entry is the fence's opening; a run's wall stops short of it by `entry_pullback` so the
## player's centre passes `entry_clear_m` wide (C-154#89).
static func profiles(type: String, base: Vector2i, cell_m: float) -> Array:
	var out := []
	var fence = building_art(type).get("fence")
	if fence is Dictionary:
		var t := float(fence.get("thickness", 0.125))
		var h := float(fence.get("height", 0.75))
		var pull := entry_pullback(type, cell_m)
		for run: Dictionary in fence_runs(type, base):
			var along := 0 if is_equal_approx(run.from.y, run.to.y) else 1
			var axis := Vector2.ZERO
			axis[along] = 1.0
			var length: float = run.to[along] - run.from[along]
			# Keep at least the fence's thickness of wall at each run.
			var cut_from := minf(pull if run.open_from else 0.0, length * 0.5)
			var cut_to := minf(pull if run.open_to else 0.0, length * 0.5)
			var from: Vector2 = run.from + axis * cut_from
			var to: Vector2 = run.to - axis * cut_to
			var mid: Vector3 = model_point((from + to) * 0.5, base, cell_m)
			var span: Vector2 = (to - from).abs() + Vector2(t, t)
			out.append({"solid": true, "shape": "box", "center_xz_m": [mid.x, mid.z], "size_xz_m": [span.x * cell_m, span.y * cell_m],
				"height_m": h * cell_m})
	for p: Dictionary in parts(type):
		var mid := model_point(p.center, base, cell_m)
		if p.round:
			out.append({"solid": true, "shape": "cylinder", "center_xz_m": [mid.x, mid.z], "radius_m": p.size.x * 0.5 * cell_m,
				"height_m": p.height * cell_m})
		else:
			out.append({"solid": true, "shape": "box", "center_xz_m": [mid.x, mid.z], "size_xz_m": [p.size.x * cell_m, p.size.y * cell_m],
				"height_m": p.height * cell_m})
	return out

## The walls at a placed building: one FarmPropProxy per profile, in scene space.
static func proxies(type: String, base: Vector2i, cell_m: float, at: Transform3D) -> Array:
	var out := []
	for profile: Dictionary in profiles(type, base, cell_m): out.append(Proxy.new(profile, at, 1.0))
	return out

## Feeder centres in the building's own frame (cells).
static func feeders(type: String) -> Array:
	return parts(type).filter(func(p): return p.feeder).map(func(p): return p.center)

## Where animals may not stand, in cells: every part grown by `radius`, and the fence's inside band.
static func blocked_rects(type: String, radius: float) -> Array:
	var out := []
	for p: Dictionary in parts(type):
		out.append(Rect2(p.center - p.size * 0.5, p.size).grow(radius))
	return out

## The open floor inside the fence for an animal of `radius` (cells).
static func floor_rect(type: String, base: Vector2i, radius: float) -> Rect2:
	var fence = building_art(type).get("fence")
	var t := float(fence.get("thickness", 0.125)) * 0.5 if fence is Dictionary else 0.0
	return Rect2(Vector2.ZERO, Vector2(base)).grow(-(t + radius))

## The building's model in its own frame (pivot on the footprint's middle): the art's scene where it exists (built
## in cells, so scaled by `cell_m`), else a placeholder of the parts, the fence and the sandy floor.
static func model(type: String, base: Vector2i, cell_m: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Livestock_" + type
	var path := str(building_art(type).get("scene", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var scene = load(path)
		if scene is PackedScene:
			var yard: Node3D = scene.instantiate()
			yard.scale = Vector3.ONE * cell_m
			yard.position = model_point(Vector2.ZERO, base, cell_m) + Vector3(0, GROUND_LIFT, 0)
			root.add_child(yard)
			return root
	root.add_child(_placeholder(type, base, cell_m))
	return root

## Boxes and cylinders of the parts' sizes and colours, the fence's runs as low rails and a sand floor; a part whose
## own model exists is drawn with it.
static func _placeholder(type: String, base: Vector2i, cell_m: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Placeholder"
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(base) * cell_m
	var ground := MeshInstance3D.new()
	ground.name = "Floor"
	ground.mesh = floor_mesh
	ground.position.y = GROUND_LIFT
	ground.material_override = _flat(Color.from_string(str(building_art(type).get("ground", {}).get("color", "#e7cf98")), Color.TAN))
	root.add_child(ground)
	var fence = building_art(type).get("fence")
	if fence is Dictionary:
		var t := float(fence.get("thickness", 0.125))
		var h := float(fence.get("height", 0.75))
		var wood := _flat(Color(0.93, 0.89, 0.8))
		for run: Dictionary in fence_runs(type, base):
			var span: Vector2 = (run.to - run.from).abs()
			for rail_y in [0.25, 0.5]:
				var rail := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(maxf(span.x, t), t * 0.8, maxf(span.y, t)) * cell_m
				rail.mesh = box
				rail.material_override = wood
				rail.position = model_point((run.from + run.to) * 0.5, base, cell_m) + Vector3(0, rail_y * cell_m, 0)
				root.add_child(rail)
			for end in [run.from, run.to]:
				var post := MeshInstance3D.new()
				var pole := BoxMesh.new()
				pole.size = Vector3(t, h, t) * cell_m
				post.mesh = pole
				post.material_override = wood
				post.position = model_point(end, base, cell_m) + Vector3(0, h * 0.5 * cell_m, 0)
				root.add_child(post)
	for p: Dictionary in parts(type):
		var at := model_point(p.center, base, cell_m)
		if not p.model.is_empty() and ResourceLoader.exists(p.model) and load(p.model) is PackedScene:
			var part: Node3D = (load(p.model) as PackedScene).instantiate()
			part.scale = Vector3.ONE * cell_m
			part.position = at
			root.add_child(part)
			continue
		var node := MeshInstance3D.new()
		node.name = "Part_" + p.id
		if p.round:
			var cone := CylinderMesh.new()
			cone.top_radius = p.size.x * 0.12 * cell_m
			cone.bottom_radius = p.size.x * 0.5 * cell_m
			cone.height = p.height * cell_m
			node.mesh = cone
		else:
			var box := BoxMesh.new()
			box.size = Vector3(p.size.x, p.height, p.size.y) * cell_m
			node.mesh = box
		node.material_override = _flat(p.color)
		node.position = at + Vector3(0, p.height * 0.5 * cell_m, 0)
		root.add_child(node)
	return root

static func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m

## An animal's model under a pivot whose −Z is where it faces (the art's `facing` says which way the model looks),
## scaled from cells to metres; {node, player, clips}. Without the model: the art's `placeholder` (C-181, the cow) or a
## small round body.
static func animal(kind: String, cell_m: float) -> Dictionary:
	var a := animal_art(kind)
	var pivot := Node3D.new()
	pivot.name = "Animal_" + kind
	var path := str(a.get("model", ""))
	var player: AnimationPlayer = null
	if not path.is_empty() and ResourceLoader.exists(path) and load(path) is PackedScene:
		var body: Node3D = (load(path) as PackedScene).instantiate()
		body.scale = Vector3.ONE * cell_m
		body.rotation.y = {"-x": -PI * 0.5, "+x": PI * 0.5, "+z": PI, "-z": 0.0}.get(str(a.get("facing", "-z")), 0.0)
		pivot.add_child(body)
		var found := body.find_children("*", "AnimationPlayer", true, false)
		if not found.is_empty(): player = found[0]
	elif a.get("placeholder") is Dictionary:
		pivot.add_child(_animal_placeholder(a.placeholder, cell_m))
	else:
		var blob := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.22 * cell_m
		sphere.height = 0.4 * cell_m
		blob.mesh = sphere
		blob.position.y = 0.2 * cell_m
		blob.material_override = _flat(Color(0.95, 0.93, 0.88))
		pivot.add_child(blob)
	return {"node": pivot, "player": player, "clips": a.get("clips", {}), "radius": float(a.get("radius", 0.2))}

## C-181: a four-legged stand-in from the art's `placeholder` (`size` [width, height, length] in cells, `color`, `patch`):
## a body on four legs, the head toward −Z (where the pivot faces), a patch on the back. No clips; it slides.
static func _animal_placeholder(raw: Dictionary, cell_m: float) -> Node3D:
	var size := Vector3(0.5, 0.5, 1.0)
	if raw.get("size") is Array and raw.size.size() == 3 and (raw.size as Array).all(func(v): return (v is int or v is float) and float(v) > 0.0):
		size = Vector3(float(raw.size[0]), float(raw.size[1]), float(raw.size[2]))
	size *= cell_m
	var body_color := Color.from_string(str(raw.get("color", "#f4f1ea")), Color(0.95, 0.94, 0.9))
	var patch_color := Color.from_string(str(raw.get("patch", "#3b3332")), Color(0.23, 0.2, 0.2))
	var root := Node3D.new()
	root.name = "Placeholder"
	var leg_h := size.y * 0.45
	var box := func(name_: String, extent: Vector3, at: Vector3, color: Color) -> void:
		var node := MeshInstance3D.new()
		node.name = name_
		var mesh := BoxMesh.new()
		mesh.size = extent
		node.mesh = mesh
		node.position = at
		node.material_override = _flat(color)
		root.add_child(node)
	box.call("Body", Vector3(size.x, size.y - leg_h, size.z * 0.75), Vector3(0, leg_h + (size.y - leg_h) * 0.5, size.z * 0.1), body_color)
	box.call("Patch", Vector3(size.x * 1.02, (size.y - leg_h) * 0.5, size.z * 0.3), Vector3(0, size.y * 0.8, size.z * 0.2), patch_color)
	box.call("Head", Vector3(size.x * 0.7, size.y * 0.4, size.z * 0.25), Vector3(0, size.y * 0.85, -size.z * 0.38), body_color)
	box.call("Muzzle", Vector3(size.x * 0.5, size.y * 0.16, size.z * 0.06), Vector3(0, size.y * 0.76, -size.z * 0.52), Color(0.93, 0.7, 0.7))
	for i in 4:
		var x := size.x * (0.3 if i % 2 else -0.3)
		var z := size.z * (-0.2 if i < 2 else 0.38)
		box.call("Leg%d" % i, Vector3(size.x * 0.2, leg_h, size.x * 0.2), Vector3(x, leg_h * 0.5, z), patch_color if i == 0 else body_color)
	return root

## A drop's model on the ground (cells to metres, times `drop_scale`), or a small egg-shaped placeholder (C-181: or the
## art's placeholder `shape`, a bottle for the milk). The size is
## on the model under the holder, so the holder's own scale stays 1 for the lay and pickup animations.
static func drop_model(item: String, cell_m: float) -> Node3D:
	var path := str(drop_art(item).get("model", ""))
	var size := drop_scale(item)
	if not path.is_empty() and ResourceLoader.exists(path) and load(path) is PackedScene:
		var node: Node3D = (load(path) as PackedScene).instantiate()
		node.scale = Vector3.ONE * cell_m * size
		var holder := Node3D.new()
		holder.name = "Drop_" + item
		holder.add_child(node)
		return holder
	var holder := Node3D.new()
	holder.name = "Drop_" + item
	var look = drop_art(item).get("placeholder")
	if look is Dictionary and str(look.get("shape", "")) == "bottle":
		holder.add_child(_bottle(look, cell_m * size))
		return holder
	var blob := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.055 * cell_m
	sphere.height = 0.15 * cell_m
	blob.mesh = sphere
	blob.scale = Vector3.ONE * size
	blob.position.y = 0.075 * cell_m * size
	blob.material_override = _flat(Color(0.98, 0.94, 0.84))
	holder.add_child(blob)
	return holder

## C-181: a small bottle (the milk's stand-in, the art's `placeholder` shape `bottle`): a body, a neck and a cap, `unit`
## metres a cell (times the drop's scale).
static func _bottle(look: Dictionary, unit: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Placeholder"
	var glass := _flat(Color.from_string(str(look.get("color", "#fbfaf4")), Color(0.98, 0.98, 0.95)))
	var cap := _flat(Color.from_string(str(look.get("cap", "#4f86c6")), Color(0.31, 0.53, 0.78)))
	for part: Array in [["Body", 0.09, 0.09, 0.2, 0.1, glass], ["Neck", 0.045, 0.08, 0.06, 0.23, glass], ["Cap", 0.05, 0.05, 0.035, 0.278, cap]]:
		var node := MeshInstance3D.new()
		node.name = part[0]
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(part[1]) * unit
		mesh.bottom_radius = float(part[2]) * unit
		mesh.height = float(part[3]) * unit
		node.mesh = mesh
		node.position.y = float(part[4]) * unit
		node.material_override = part[5]
		root.add_child(node)
	return root

## Every mesh under `node` drawn see-through (placement's preview), by the instances' own transparency.
static func see_through(node: Node, amount := 0.4) -> void:
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		(child as GeometryInstance3D).transparency = amount
		(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
