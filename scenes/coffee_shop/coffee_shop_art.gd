@tool
extends Node3D
## Art + simple collisions only. All placement is in metres, local floor/mount pivots.
@export_dir var kit_path: String = "res://assets/rooms/coffee_shop"
var _assembled := false
var module_count := 0
var material_overrides: Dictionary = {}
var merged_sources: Dictionary = {}

func _ready() -> void:
	if _assembled: return
	_assembled = true
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(kit_path + "/layout.json"))
	material_overrides = layout.get("material_overrides", {})
	for batch: Dictionary in layout.get("render_batches", []):
		for source_name: String in batch.sources: merged_sources[source_name] = true
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
