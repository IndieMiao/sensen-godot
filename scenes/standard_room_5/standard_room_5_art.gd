@tool
extends Node3D
## Reusable static room assembly. No player, UI, account, network or save dependencies.
## Lighting belongs to the consuming scene. Art-only review uses a separate script.
const KIT := "res://assets/rooms/standard_room_5/"
var layout: Dictionary
var assets: Dictionary = {}
var fire: Node3D
var variant_materials: Dictionary = {}

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(KIT + "layout.json"))
	_setup_room()

func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _setup_room() -> void:
	var atlas := load(KIT + "room_albedo_ao.png") as Texture2D
	var material := StandardMaterial3D.new()
	material.resource_name = "SharedRoomAtlas"
	material.albedo_texture = atlas
	material.roughness = .80
	material.metallic_specular = .28
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for asset in layout.assets:
		assets[asset.name] = asset
		_add_asset(asset, asset, material)
	for instance in layout.instances:
		_add_asset(assets[instance.asset], instance, material)
	var plant_material := load("res://assets/rooms/_shared/plants/material.tres") as StandardMaterial3D
	for plant in layout.get("shared_plants", []):
		var container := Node3D.new()
		container.name = plant.name
		container.position = _vec(plant.position)
		container.rotation_degrees = _vec(plant.rotation_degrees)
		container.scale = _vec(plant.scale)
		add_child(container)
		var model := (load("res://assets/rooms/_shared/plants/" + str(plant.file)) as PackedScene).instantiate()
		container.add_child(model)
		_set_material(model, plant_material)
		# R2 library uses small leaves and alpha-scissor cutouts. Keep their
		# shadows disabled per the shared budget standard (pots included).
		_disable_shadows(model)
		for c in plant.get("colliders", []):
			var body := StaticBody3D.new(); body.position = _vec(c.at)
			var shape := BoxShape3D.new(); shape.size = _vec(c.size)
			var collision := CollisionShape3D.new(); collision.shape = shape
			body.add_child(collision); container.add_child(body)

func _add_asset(asset: Dictionary, placement: Dictionary, material: StandardMaterial3D) -> void:
	var container := Node3D.new()
	container.name = placement.name
	container.position = _vec(placement.position)
	container.scale = _vec(placement.get("scale", [1.0, 1.0, 1.0]))
	container.rotation.y = deg_to_rad(float(placement.yaw_degrees))
	add_child(container)
	var scene := load(KIT + asset.file) as PackedScene
	if scene == null:
		push_error("Missing room asset: " + asset.file)
		return
	var model := scene.instantiate() as Node3D
	container.add_child(model)
	var applied := material
	if str(asset.name).ends_with("garden"):
		applied = material.duplicate()
		applied.albedo_texture = load(KIT + "window_landscape.png")
		applied.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		applied.cull_mode = BaseMaterial3D.CULL_DISABLED
	if asset.name == "fire":
		applied = material.duplicate()
		applied.albedo_texture = load(KIT + "fire_gradient.png")
		applied.albedo_color = Color("ffc487")
		applied.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		applied.emission_enabled = true
		applied.emission = Color("ff841f")
		applied.emission_texture = applied.albedo_texture
		applied.emission_energy_multiplier = .22
		fire = container
	var variant := "garden" if str(asset.name).ends_with("garden") else "fire" if asset.name == "fire" else "plain"
	if variant_materials.has(variant): applied = variant_materials[variant]
	else: variant_materials[variant] = applied
	_set_material(model, applied)
	if str(asset.name).ends_with("garden"): _disable_shadows(model)
	if asset.name in ["fire", "daisy_jug", "window_daisies", "counter_board"]: _disable_shadows(model)
	for c in asset.colliders:
		var body := StaticBody3D.new()
		body.position = _vec(c.at)
		var shape := BoxShape3D.new()
		shape.size = _vec(c.size)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		container.add_child(body)

func set_bench_door_open(open: bool) -> void:
	var door := get_node_or_null("green_door") as Node3D
	if door: door.rotation.y = deg_to_rad(float(layout.door.open_yaw_degrees)) if open else 0.0

func _set_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for child in node.get_children(): _set_material(child, mat)

func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _disable_shadows(child)
