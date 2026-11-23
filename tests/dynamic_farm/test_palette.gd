extends SceneTree
## C-21 warm palette: only vertex colours of the 13 existing models change. Geometry,
## layouts, collision and walking stay identical; every model colour is mapped; no
## blue (water-like) colour is introduced. Always runs the synthetic fixture parcel
## (core obstacles only, no outer props); optional real parcels: -- <farm.json>...
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const Palette = preload("res://modules/dynamic_farm/farm_palette.gd")
const Art = preload("res://modules/farm/farm_art.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(reason)

func _blue(colour: Color) -> bool:
	return colour.s > 0.3 and colour.h > 0.5 and colour.h < 0.72

func _run() -> void:
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenery.RECIPE_PATH))
	var inventory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenery.INVENTORY_PATH))
	var palette: Dictionary = recipe.prop_palette
	var ids: Array = []
	for item: Dictionary in inventory.assets: ids.append(item.id)
	_check(palette.assets.keys().size() == 13 and ids.all(func(id): return palette.assets.has(id)), "palette covers exactly the 13 inventory models")
	for asset: String in palette.assets:
		var source := Art.mesh_for(asset)
		var original := source.surface_get_arrays(0)
		var seen := {}
		for colour: Color in original[Mesh.ARRAY_COLOR]: seen[colour.linear_to_srgb().to_html(false)] = true
		var variants: Array = palette.assets[asset]
		for index in variants.size():
			var map: Dictionary = variants[index].map
			_check(map.keys().all(func(key): return seen.has(key)), "%s variant %d maps a colour the model lacks" % [asset, index])
			_check(seen.keys().all(func(key): return map.has(key)), "%s variant %d leaves a model colour unmapped" % [asset, index])
			_check(not map.values().any(func(value): return _blue(Color(value))), "%s variant %d adds a water-blue colour" % [asset, index])
			var mesh := Palette.mesh(palette, asset, index)
			_check(mesh == Palette.mesh(palette, asset, index), "%s variant %d is cached" % [asset, index])
			var arrays := mesh.surface_get_arrays(0)
			# Compressed attributes re-encode within float rounding; indices must match exactly.
			var same: bool = arrays[Mesh.ARRAY_INDEX] == original[Mesh.ARRAY_INDEX]
			for slot in Mesh.ARRAY_MAX:
				if slot == Mesh.ARRAY_COLOR or slot == Mesh.ARRAY_INDEX: continue
				if (arrays[slot] == null) != (original[slot] == null): same = false
				elif arrays[slot] != null:
					var a: PackedFloat32Array = _floats(arrays[slot])
					var b: PackedFloat32Array = _floats(original[slot])
					same = same and a.size() == b.size()
					for i in mini(a.size(), b.size()):
						if absf(a[i] - b[i]) > 0.0005: same = false
			_check(same and mesh.get_aabb().is_equal_approx(source.get_aabb()), "%s variant %d changed more than colours" % [asset, index])
			var expected := {}
			for key: String in map: expected[key] = Color(map[key]).srgb_to_linear()
			var recoloured := true
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for i in colours.size():
				var want: Color = expected[original[Mesh.ARRAY_COLOR][i].linear_to_srgb().to_html(false)]
				# Vertex colours are stored as 8-bit channels.
				if maxf(absf(want.r - colours[i].r), maxf(absf(want.g - colours[i].g), absf(want.b - colours[i].b))) > 1.0 / 255.0: recoloured = false
			_check(recoloured, "%s variant %d vertex colours follow its map" % [asset, index])
		var counts := []
		counts.resize(variants.size())
		counts.fill(0)
		for i in 400:
			var at := Vector3(i % 20 * 0.8 + 0.37, 0, -(i / 20) * 0.8 - 0.11)
			var pick := Palette.pick(palette, asset, at)
			_check(pick == Palette.pick(palette, asset, at), "%s pick is repeatable" % asset)
			counts[pick] += 1
		_check(counts.all(func(count): return count > 0), "%s every variant appears over 400 positions: %s" % [asset, counts])
	_check(Palette.pick({}, "wild_pz_tree_20", Vector3.ZERO) == -1 and Palette.mesh({}, "wild_pz_tree_20", -1) == Art.mesh_for("wild_pz_tree_20"), "no palette keeps the original model")
	for key in ["grass_srgb", "grass_warm_srgb", "grass_far_srgb", "core_warm_surface_srgb", "core_grid_srgb"]:
		_check(not _blue(Color(recipe.surface[key])), "ground %s is not water-blue" % key)
	var parcels: Array = [["fixture p-A", Fixture.farm("p-A")]]
	for file in OS.get_cmdline_user_args():
		parcels.append([file, JSON.parse_string(FileAccess.get_file_as_string(file))])
	for parcel: Array in parcels:
		var data := Data.decode(parcel[1])
		_check(data.ok, "invalid parcel: " + parcel[0])
		if not data.ok: continue
		var walk := Walk.new(data)
		var plan := Scenery.plan(data, walk)
		Shade.enforce_budget(plan, data, walk)
		var layout := str(plan.layout) + str(plan.core_obstacles.layout)
		var reserved := walk.reserved.duplicate()
		var art := Scenery.build(plan, walk, plan.recipe)
		var core := Scenery.build(plan.core_obstacles, walk, plan.recipe)
		_check(art.ok and core.ok, "scenery builds")
		_check(str(plan.layout) + str(plan.core_obstacles.layout) == layout and walk.reserved == reserved, "recolouring changed a layout or reservation")
		var instances := 0
		var unknown := 0
		for root: Node in [art.root, core.root]:
			for node: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
				instances += node.multimesh.instance_count
				if node.material_override != Art.material(): unknown += 1
		_check(instances == art.instances + core.instances and unknown == 0, "every instance drawn once with the shared material")
		var again_walk := Walk.new(data)
		var again := Scenery.plan(data, again_walk)
		Shade.enforce_budget(again, data, again_walk)
		var repeat := Scenery.build(again, again_walk, again.recipe)
		var repeat_core := Scenery.build(again.core_obstacles, again_walk, again.recipe)
		# Outer and core props together, so a parcel without outer props is still compared.
		var rows := _signature([art.root, core.root])
		_check(rows.size() == instances and instances > 0, "%s: reopen signature covers every drawn instance (%d rows)" % [parcel[0], rows.size()])
		_check(_signature([repeat.root, repeat_core.root]) == rows, "%s: reopening gives the same colours in the same places" % parcel[0])
		# build() colours from the recipe it is given (plan().recipe), not a fresh file read.
		var plain_recipe: Dictionary = plan.recipe.duplicate()
		plain_recipe.prop_palette = {}
		var plain := Scenery.build(plan.core_obstacles, Walk.new(data), plain_recipe)
		var source_meshes: Array = ids.map(func(id): return Art.mesh_for(id))
		var plain_meshes: Array = plain.root.find_children("*", "MultiMeshInstance3D", true, false).map(func(node): return node.multimesh.mesh)
		var core_meshes: Array = core.root.find_children("*", "MultiMeshInstance3D", true, false).map(func(node): return node.multimesh.mesh)
		_check(not plain_meshes.is_empty() and plain_meshes.all(func(mesh): return source_meshes.has(mesh))
			and not core_meshes.any(func(mesh): return source_meshes.has(mesh)), "%s: build() colours from the recipe it is passed" % parcel[0])
		print("PALETTE_PARCEL ", data.block_id, " instances=", instances, " batches=", art.batches + core.batches, " signature=", "\n".join(rows).sha256_text())
		for root: Node in [art.root, core.root, repeat.root, repeat_core.root, plain.root]: root.free()
	print("DYNAMIC_PALETTE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _floats(values: Variant) -> PackedFloat32Array:
	if values is PackedVector3Array:
		var out := PackedFloat32Array()
		for v: Vector3 in values: out.append_array([v.x, v.y, v.z])
		return out
	if values is PackedVector2Array:
		var out := PackedFloat32Array()
		for v: Vector2 in values: out.append_array([v.x, v.y])
		return out
	return PackedFloat32Array(values)

## One row per drawn instance: position and its model's vertex colours.
func _signature(roots: Array) -> Array[String]:
	var rows: Array[String] = []
	for root: Node in roots:
		for node: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
			var colours := str(node.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]).sha256_text()
			for i in node.multimesh.instance_count:
				rows.append("%s %s" % [node.multimesh.get_instance_transform(i).origin, colours])
	rows.sort()
	return rows
