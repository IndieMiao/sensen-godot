extends RefCounted
const CoreObstacles = preload("res://modules/dynamic_farm/farm_core_obstacles.gd")
const OuterGroves = preload("res://modules/dynamic_farm/farm_outer_groves.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const Art = preload("res://modules/farm/farm_art.gd")
const RECIPE_PATH := "res://assets/dynamic_farm/499-art-recipe.json"
const INVENTORY_PATH := "res://assets/dynamic_farm/499-art-inventory.json"
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
const Palette = preload("res://modules/dynamic_farm/farm_palette.gd")
const Kit = preload("res://modules/dynamic_farm/parcel_fieldkit.gd")
const CHUNK_CELLS := 32

## xorshift32: fixed integer operations, seeded with the first 32 bits of the recipe SHA256.
class FixedRandom:
	var value: int
	func _init(seed_hex: String) -> void:
		value = seed_hex.substr(0,8).hex_to_int()
		if value == 0: value = 0x6d2b79f5
	func next() -> int:
		value = (value ^ (value << 13)) & 0xffffffff
		value = (value ^ (value >> 17)) & 0xffffffff
		value = (value ^ (value << 5)) & 0xffffffff
		return value
	func unit() -> float:
		return float(next()) / 4294967296.0

static func plan(data: Dictionary, walk: RefCounted) -> Dictionary:
	var recipe = JSON.parse_string(FileAccess.get_file_as_string(RECIPE_PATH))
	var inventory = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY_PATH))
	if not recipe is Dictionary or not inventory is Dictionary:
		return {"ok": false, "error": "The farm scenery recipe is unavailable."}
	var assets := {}
	for item in inventory.assets:
		assets[item.id] = item
	var pool: Array[Vector2i] = []
	for cell: Dictionary in data.cells:
		var at := Vector2i(cell.x,cell.y)
		if cell.zone == "extension" and not data.protected.has(at):
			pool.append(at)
	pool.sort_custom(func(a: Vector2i,b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var outer_spec: Dictionary = recipe.outer_groves
	var palette: Array = outer_spec.grove.tree_weights.keys() + [outer_spec.grove.young_pine_id] \
		+ outer_spec.rock_pile.main_ids + outer_spec.rock_pile.companion_ids
	for role: String in recipe.roles: palette.append_array(recipe.roles[role].ids)
	for asset: String in palette:
		if not assets.has(asset):
			return {"ok": false, "error": "The farm scenery palette is incomplete."}
	# Walk budget: the groves may move reserved cells, and cells the fitted profiles
	# close, around the previous approved layout's, never add to them.
	var reference := {"layout":[], "roles":{}}
	var reference_walk := Walk.new(data)
	for role: String in outer_spec.reference_roles:
		_scatter(reference, data, reference_walk, recipe, outer_spec.reference_art_version, role, assets, pool)
	Shade.enforce_budget(reference, data, reference_walk)
	var rngs := {}
	for stream: String in ["grove", "pile", "clump"]:
		rngs[stream] = FixedRandom.new((data.seed_hex + "|" + str(recipe.art_version) + "|" + stream).sha256_text())
	var fit := float(inventory.collision_fit_fraction)
	var lost_budget := OuterGroves.lost_cells(reference_walk, reference.layout, assets, fit)
	var outer := OuterGroves.plan(walk, assets, recipe, pool, reference_walk.reserved.size(), lost_budget, fit, rngs)
	var core_rng := FixedRandom.new((data.block_id + "|" + str(recipe.core_obstacles.version)).sha256_text())
	var core := CoreObstacles.plan(data, walk, assets, recipe.core_obstacles, core_rng)
	return {"ok":true,"core_obstacles":core,"layout":outer.layout,"roles":outer.roles,"outer":outer.summary,
		"art_version":recipe.art_version,"eligible_cells":pool.size(),"layout_sha256":outer.layout_sha256,"recipe":recipe}

## The previous approved per-role scatter (art 499-v2-schema4), kept verbatim as the walk
## budget reference. Only its solid roles are replayed, onto a separate walker.
static func _scatter(planned: Dictionary, data: Dictionary, walk: RefCounted, recipe: Dictionary, art_version: String,
		role: String, assets: Dictionary, pool: Array[Vector2i]) -> void:
	var spec: Dictionary = recipe.roles[role]
	var wanted := mini(int(spec.cap_per_farm), pool.size() / int(spec.cells_per_candidate))
	var rng := FixedRandom.new((data.seed_hex + "|" + art_version + "|" + role).sha256_text())
	var seen_visual := {}
	for item: Dictionary in planned.layout: seen_visual[walk.cell_at(item.transform.origin)] = true
	var accepted := 0
	var attempts := 0
	var anchor := Vector2i.ZERO
	while accepted < wanted and attempts < int(recipe.placement.max_candidate_attempts_per_role) and not pool.is_empty():
		if attempts % 8 == 0:
			anchor = pool[rng.next() % pool.size()]
		var at := anchor + Vector2i(int(rng.next()%7)-3, int(rng.next()%7)-3)
		attempts += 1
		if not data.by_cell.has(at) or data.by_cell[at].zone != "extension" or data.protected.has(at):
			continue
		var point: Vector3 = walk.point(at)
		# Place tall pieces in the rear half for the approved 43/14.5 opening composition.
		if role == "tree" and point.dot(Vector3(0.25,0,0.968)) > 0:
			continue
		var ids: Array = spec.ids
		var pick: int = rng.next() % ids.size()
		if role == "tree" and rng.unit() < 0.7:
			pick = rng.next() % 2
		var asset: String = ids[pick]
		var record: Dictionary = assets[asset]
		var low: Array = record.bounds_godot_m[0]
		var high: Array = record.bounds_godot_m[1]
		var box := AABB(Vector3(low[0],low[1],low[2]),Vector3(high[0]-low[0],high[1]-low[1],high[2]-low[2]))
		var scale_value := lerpf(0.85,1.0,rng.unit())
		var yaw := rng.unit() * TAU
		point += Vector3((rng.unit()-0.5)*0.3,0,(rng.unit()-0.5)*0.3)
		var transform := Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale_value),point)
		var world_box: AABB = transform * box
		var center_cell: Vector2i = walk.cell_at(point)
		if seen_visual.has(center_cell):
			continue
		var footprint: Array[Vector2i] = walk.try_box(world_box, bool(record.collision_proxy.solid))
		if footprint.is_empty():
			continue
		seen_visual[center_cell] = true
		planned.layout.append({"asset":asset,"role":role,"transform":transform,"box":world_box,
			"solid":bool(record.collision_proxy.solid),"shadow":bool(spec.cast_shadow_flag),"cells":footprint})
		accepted += 1
	planned.roles[role] = {"target":wanted,"accepted":accepted,"attempts":attempts,"rejected":attempts-accepted}

## The batch an instance is drawn in: its model's colour variant within a 32-cell
## chunk. EdgeDecor budgets its new batches with the same key.
static func batch_key(palette: Dictionary, asset: String, origin: Vector3, cell_m: float) -> String:
	return "%s#%d:%d:%d" % [asset, Palette.pick(palette, asset, origin),
		floori(origin.x/(CHUNK_CELLS*cell_m)), floori(origin.z/(CHUNK_CELLS*cell_m))]

## `recipe` is the plan's (`plan().recipe`), so a load reads the recipe file once;
## only a caller without it falls back to reading the file.
## `bind`: false draws the art without adding walk profiles (a redraw of props already bound).
## `proxies` lines up with planned.layout (null where unbound), so a cleared prop can be released.
static func build(planned: Dictionary, walk: RefCounted, recipe: Variant = null, bind := true) -> Dictionary:
	var root := Node3D.new()
	root.name = "DynamicScenery"
	var cell_m: float = walk.cell_m
	if not recipe is Dictionary: recipe = planned.get("recipe")
	if not recipe is Dictionary: recipe = JSON.parse_string(FileAccess.get_file_as_string(RECIPE_PATH))
	var palette: Dictionary = recipe.get("prop_palette", {}) if recipe is Dictionary else {}
	var batches := {}
	var triangles := 0
	var unique := {}
	for item: Dictionary in planned.layout:
		var p: Vector3 = item.transform.origin
		var variant := Palette.pick(palette, item.asset, p)
		var replacement: String = Kit.TYPES.get(item.asset, "") if variant >= 0 else ""
		var key := batch_key(palette, item.asset, p, cell_m)
		# New shapes share a batch across colourways; per-instance autumn tint costs no draw.
		if replacement != "": key = "%s:%d:%d" % [replacement,floori(p.x/(64*cell_m)),floori(p.z/(64*cell_m))]
		if not batches.has(key): batches[key] = {"asset":item.asset,"variant":variant,"shadow":item.shadow and item.role == "tree","transforms":[],"tints":[],"replacement":replacement}
		batches[key].transforms.append(item.transform)
		if replacement != "":
			var tint := Color.WHITE
			if replacement in ["Linden", "OrchardElm"]:
				tint = [Color(0.82,1,0.86),Color.WHITE,Color(1.04,0.87,0.66),Color(1.08,0.54,0.35)][clampi(variant,0,3)]
			batches[key].tints.append(tint)
		unique[item.asset] = item.triangles
	for key: String in batches:
		var batch: Dictionary = batches[key]
		var mesh := Kit.mesh(batch.replacement) if batch.replacement != "" else Palette.mesh(palette, batch.asset, batch.variant)
		if mesh == null:
			root.free()
			return {"ok":false,"error":"A farm scenery asset could not be loaded."}
		if batch.replacement != "":
			var n: int = mesh.surface_get_array_index_len(0) if mesh is ArrayMesh else 0
			if n <= 0: n = mesh.surface_get_array_len(0)
			unique[batch.asset] = n / 3
		triangles += unique[batch.asset] * batch.transforms.size()
		var node := Art.batch(batch.asset,batch.transforms,batch.shadow,PackedColorArray(batch.tints))
		node.multimesh.mesh = mesh
		root.add_child(node)
	# Bind final rendered instances, after budget pruning. All layers go through
	# this path; a placement role cannot override the model's collision policy.
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY_PATH))
	var wire: StandardMaterial3D
	if Engine.get_main_loop().debug_collisions_hint:
		wire = StandardMaterial3D.new()
		wire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wire.no_depth_test = true # Precisely fitted shapes would otherwise be hidden inside the art.
		wire.albedo_color = Color("00e5ff")
		wire.render_priority = 127
	var profiles := {}
	for record: Dictionary in catalog.assets: profiles[record.id] = record.collision_proxy
	var proxies := []
	for item: Dictionary in planned.layout:
		proxies.append(null)
		if not bind: continue
		var proxy := Proxy.new(profiles[item.asset], item.transform, catalog.collision_fit_fraction)
		proxies[-1] = proxy
		walk.add_prop(proxy)
		if wire != null and proxy.solid:
			var outline := MeshInstance3D.new()
			outline.mesh = proxy.debug_wire()
			outline.material_override = wire
			outline.transform = proxy.pose
			outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(outline)
	var unique_triangles := 0
	for count: int in unique.values(): unique_triangles += count
	return {"ok":true,"root":root,"instances":planned.layout.size(),"batches":batches.size(),
		"placed_triangles":triangles,"unique_triangles":unique_triangles,"proxies":proxies}
