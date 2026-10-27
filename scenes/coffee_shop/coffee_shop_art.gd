@tool
extends Node3D
## Art + simple collisions only. All placement is in metres, local floor/mount pivots.
@export_dir var kit_path: String = "res://assets/rooms/coffee_shop"
var _assembled := false
var module_count := 0
var material_overrides: Dictionary = {}
var merged_sources: Dictionary = {}   # module name → the render batch it is merged into
var _modules: Dictionary = {}   # module name → its asset (file, colliders)

func _ready() -> void:
	if _assembled: return
	_assembled = true
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(kit_path + "/layout.json"))
	material_overrides = layout.get("material_overrides", {})
	for batch: Dictionary in layout.get("render_batches", []):
		for source_name: String in batch.sources: merged_sources[source_name] = str(batch.name)
	var material := StandardMaterial3D.new()
	material.resource_name = "SharedShopAtlas"
	material.albedo_texture = load(kit_path + "/room_albedo_ao.png")
	material.roughness = .86
	material.metallic_specular = .22
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var assets: Dictionary = {}
	for asset: Dictionary in layout.assets:
		assets[asset.name] = asset
		_add_asset(asset, asset, material)
	for placement: Dictionary in layout.instances:
		_add_asset(assets[placement.asset], placement, material)
	module_count = layout.assets.size() + layout.instances.size()
	if layout.has("shared_plants"):
		_add_shared_plants(layout.shared_plants)
	for box: Dictionary in layout.get("boundaries", []):
		_add_box(self, box)
	for batch: Dictionary in layout.get("render_batches", []):
		var model := (load(batch.file) as PackedScene).instantiate()
		model.name = batch.name
		add_child(model)
		var applied := material.duplicate() as StandardMaterial3D
		if batch.material == "plants":
			applied.albedo_texture = load("res://assets/rooms/_shared/plants/room_albedo_ao.png")
			applied.cull_mode = BaseMaterial3D.CULL_DISABLED
			applied.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			applied.alpha_scissor_threshold = .45
		if batch.material == "glass":
			applied.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			applied.albedo_color.a = .08
			applied.cull_mode = BaseMaterial3D.CULL_DISABLED
		_set_material(model, applied, batch.material == "glass")
		if not batch.cast_shadow: _disable_shadows(model)

func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _add_asset(asset: Dictionary, placement: Dictionary, material: StandardMaterial3D) -> void:
	_modules[str(placement.name)] = asset
	var pivot := Node3D.new()
	pivot.name = placement.name
	pivot.position = _vec(placement.position)
	pivot.rotation.y = deg_to_rad(float(placement.yaw_degrees))
	add_child(pivot)
	if merged_sources.has(placement.name):
		for box: Dictionary in asset.colliders: _add_box(pivot, box)
		return
	var packed := load(kit_path + "/" + asset.file) as PackedScene
	if packed == null:
		push_error("Missing shop module: " + asset.file)
		return
	var model := packed.instantiate()
	pivot.add_child(model)
	var applied := material
	if "glass" in str(asset.name):
		applied = StandardMaterial3D.new()
		applied.resource_name = "SoftShopGlass"
		applied.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		applied.albedo_color = Color(.76,.89,.86,.14)
		applied.roughness = .40
		applied.metallic_specular = .25
		applied.cull_mode = BaseMaterial3D.CULL_DISABLED
	if material_overrides.has(asset.name):
		var settings: Dictionary = material_overrides[asset.name]
		applied = applied.duplicate()
		applied.roughness = settings.get("roughness", applied.roughness)
		applied.metallic = settings.get("metallic", applied.metallic)
		if settings.has("alpha"): applied.albedo_color.a = settings.alpha
		if settings.has("emission"):
			applied.emission_enabled = true
			if settings.get("emission_use_atlas", false): applied.emission_texture = applied.albedo_texture
			applied.emission = Color(settings.emission)
			applied.emission_energy_multiplier = float(settings.get("emission_energy", 1.0))
			_disable_shadows(model)
		if settings.get("unshaded", false):
			applied.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_disable_shadows(model)
	_set_material(model, applied, "glass" in str(asset.name))
	for box: Dictionary in asset.colliders:
		_add_box(pivot, box)

## Takes a module out of the picture (SGODOT-351: the card room hides the tavern's `TAVERN` sign, 不知火舞 351 e38e8e85,
## 上官婉儿 on it): its pivot is hidden, and when a render batch merged it, the batch's triangles that are the module's
## own — every corner on one of its placed vertices, to the millimetre — are cut out, its shadow with them. All of them
## or none: a count that is not the module's own triangle count (the batch rebuilt since) warns and leaves the batch
## whole. Returns the triangles cut.
func hide_module(module: String) -> int:
	var pivot := get_node_or_null(NodePath(module)) as Node3D
	if pivot == null or not _modules.has(module): return 0
	pivot.visible = false
	if not merged_sources.has(module): return 0
	var own := []
	var model := (load(kit_path + "/" + str(_modules[module].file)) as PackedScene).instantiate()
	_surfaces(model, pivot.transform, own)
	model.free()
	var keys := {}
	var want := 0
	for e in own:
		for v in e.vertices: keys[_mm(e.xf * v)] = true
		want += e.index.size() / 3
	return _cut(str(merged_sources[module]), keys, AABB(), want, module)

## Cuts from a render batch the triangles wholly inside box (this art's metres) — a piece of a merged module that is
## not a module of its own (上官婉儿 on 351: the bracket left on the tavern's wall once its sign is hidden). All `want`
## of them or none, as hide_module.
func hide_box(batch: String, box: AABB, want: int) -> int:
	return _cut(batch, {}, box, want, "box %s" % box)

## A triangle goes when all three of its corners do — on one of keys (millimetre vertices), or with no keys inside box,
## in this art's space: each vertex is placed and asked once, each triangle only reads the three answers.
## Each cut is made once per session: the batch's meshes it made are kept by the mesh they were cut from and what was
## cut, so the room opened again takes them as they are (亚瑟 on #523: the pass costs some 30 ms on a desktop).
static var _cut_cache: Dictionary = {}   # "<kit>|<batch>|<batch file>|<cuts so far>|<what>" → {meshes: {mesh path: ArrayMesh}, hit}

func _cut(batch_name: String, keys: Dictionary, box: AABB, want: int, what: String) -> int:
	var batch := get_node_or_null(NodePath(batch_name)) as Node3D
	if batch == null: return 0
	# the kit and batch first (亚瑟 on #523: a batch node not made from a scene has no scene_file_path)
	var key := "%s|%s" % [str(batch.get_meta("cuts", "%s|%s|%s" % [kit_path, batch_name, batch.scene_file_path])), what]
	if _cut_cache.has(key):
		var done: Dictionary = _cut_cache[key]
		for path in done.meshes: (batch.get_node(NodePath(path)) as MeshInstance3D).mesh = done.meshes[path]
		batch.set_meta("cuts", key)
		return int(done.hit)
	var t0 := Time.get_ticks_usec()
	var cut := []
	var hit := 0
	_surfaces(batch, batch.transform, cut)
	for e in cut:
		var xf: Transform3D = e.xf
		var vs: PackedVector3Array = e.vertices
		var out := PackedByteArray()
		out.resize(vs.size())
		var by_key := not keys.is_empty()
		for v in vs.size():
			var at := xf * vs[v]
			out[v] = 1 if (keys.has(_mm(at)) if by_key else box.has_point(at)) else 0
		var idx: PackedInt32Array = e.index
		var keep := PackedInt32Array()
		keep.resize(idx.size())
		var k := 0
		for i in range(0, idx.size(), 3):
			if out[idx[i]] == 1 and out[idx[i + 1]] == 1 and out[idx[i + 2]] == 1: continue
			keep[k] = idx[i]; keep[k + 1] = idx[i + 1]; keep[k + 2] = idx[i + 2]
			k += 3
		keep.resize(k)
		e["keep"] = keep
		hit += (idx.size() - k) / 3
	if hit != want:
		push_warning("%s: %d of %s's %d triangles found in %s, the batch left whole" % [kit_path, hit, what, want, batch_name])
		return 0
	var meshes := {}
	for e in cut:
		var mi: MeshInstance3D = e.node
		if not meshes.has(mi): meshes[mi] = ArrayMesh.new()
		var arrays: Array = mi.mesh.surface_get_arrays(e.surface)
		arrays[Mesh.ARRAY_INDEX] = e.keep
		(meshes[mi] as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)   # no LODs: a room's batch is near
		(meshes[mi] as ArrayMesh).surface_set_material(e.surface, mi.mesh.surface_get_material(e.surface))
	var done := {}
	for mi in meshes:
		(mi as MeshInstance3D).mesh = meshes[mi]
		done[str(batch.get_path_to(mi))] = meshes[mi]
	_cut_cache[key] = {"meshes": done, "hit": hit}
	batch.set_meta("cuts", key)
	# 亚瑟 on #523: a one-off pass at the room's load, timed for the low-end phones
	print("%s: %d triangles of %s cut from %s in %d us" % [kit_path, hit, what, batch_name, Time.get_ticks_usec() - t0])
	return hit

static func _mm(v: Vector3) -> Vector3i:
	return Vector3i((v * 1000.0).round())

## Every indexed triangle surface under node (an unindexed one skipped): {node, surface, xf (to this art's space), vertices, index}.
static func _surfaces(node: Node, xf: Transform3D, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			if a[Mesh.ARRAY_INDEX] == null or (a[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty(): continue   # 亚瑟: unindexed, not ours
			out.append({"node": node, "surface": s, "xf": xf, "vertices": a[Mesh.ARRAY_VERTEX], "index": a[Mesh.ARRAY_INDEX]})
	for c in node.get_children():
		if c is Node3D: _surfaces(c, xf * (c as Node3D).transform, out)

func _set_material(node: Node, material: Material, glass: bool) -> void:
	if node is MeshInstance3D:
		node.material_override = material
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if glass: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _set_material(child, material, glass)

func _add_box(parent: Node3D, box: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = str(box.get("name", "Collider"))
	body.position = _vec(box.at)
	body.rotation_degrees = _vec(box.get("rotation_degrees", [0,0,0]))
	var collision := CollisionShape3D.new()
	if box.has("points"):
		var shape := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for point: Array in box.points: points.append(_vec(point))
		shape.points = points
		collision.shape = shape
	else:
		var shape := BoxShape3D.new()
		shape.size = _vec(box.size)
		collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

func _add_shared_plants(placements: Array) -> void:
	var plant_material := StandardMaterial3D.new()
	plant_material.resource_name = "SharedBotanicalAtlas"
	plant_material.albedo_texture = load("res://assets/rooms/_shared/plants/room_albedo_ao.png")
	plant_material.roughness = .86
	plant_material.metallic_specular = .22
	plant_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plant_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	plant_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	plant_material.alpha_scissor_threshold = .45
	for placement: Dictionary in placements:
		var pivot := Node3D.new()
		pivot.name = placement.name
		pivot.position = _vec(placement.position)
		pivot.rotation_degrees = _vec(placement.rotation_degrees)
		pivot.scale = _vec(placement.scale)
		add_child(pivot)
		if merged_sources.has(placement.name):
			for box: Dictionary in placement.colliders: _add_box(pivot, box)
			module_count += 1
			continue
		var model := (load(placement.file) as PackedScene).instantiate()
		pivot.add_child(model)
		_set_material(model, plant_material, false)
		# Outside garden is scenery; it must not block the window's sunlight.
		if str(placement.name).begins_with("GardenBeyond") or str(placement.name) == "WindowGardenLow":
			_disable_shadows(model)
		for box: Dictionary in placement.colliders: _add_box(pivot, box)
		module_count += 1

func _disable_shadows(node: Node) -> void:
	if node is MeshInstance3D: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _disable_shadows(child)
