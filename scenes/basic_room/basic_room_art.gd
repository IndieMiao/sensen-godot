@tool
extends Node3D
## Reusable room assembly. No player, UI, account, network or save dependencies.
## The benchmark supplies lighting and the existing avatar controller separately.
const KIT := "res://assets/rooms/basic_room/"
var layout: Dictionary
var assets: Dictionary = {}
@export var hearth_light_path: NodePath
var fire: Node3D

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
		if asset.name != "fire": _add_asset(asset, asset, material)
	for instance in layout.instances:
		if instance.asset != "fire": _add_asset(assets[instance.asset], instance, material)
	_add_fire()

func _add_asset(asset: Dictionary, placement: Dictionary, material: StandardMaterial3D) -> void:
	var container := Node3D.new()
	container.name = placement.name
	container.position = _vec(placement.position)
	container.rotation.y = deg_to_rad(float(placement.yaw_degrees))
	add_child(container)
	var scene := load(KIT + asset.file) as PackedScene
	if scene == null:
		push_error("Missing room asset: " + asset.file)
		return
	var model := scene.instantiate() as Node3D
	container.add_child(model)
	var applied := material
	if asset.name == "window_garden":
		applied = material.duplicate()
		applied.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		applied.cull_mode = BaseMaterial3D.CULL_DISABLED
	_set_material(model, applied)
	if asset.name == "window_garden": _disable_shadows(model)
	for c in asset.colliders:
		var body := StaticBody3D.new()
		body.position = _vec(c.at)
		# The authored floorboard top is 8cm above the assembly pivot.
		if asset.name == "room_shell" and float(c.at[1]) < 0: body.position.y += .08
		var shape := BoxShape3D.new()
		shape.size = _vec(c.size)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		container.add_child(body)
	if asset.name == "floor_plant":
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.height = .45
		shape.radius = .22
		collision.shape = shape
		collision.position.y = .225
		body.add_child(collision)
		container.add_child(body)

func _set_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for child in node.get_children(): _set_material(child, mat)

func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _disable_shadows(child)

func _add_fire() -> void:
	fire = preload("res://assets/rooms/_shared/fx/fx_hearth_fire.tscn").instantiate()
	fire.name = "fire"
	fire.position = _vec(layout.fire_position)
	fire.emission_box = Vector3(.18, .005, .035)
	fire.flame_height = .42
	fire.flame_count = 16
	fire.spark_count = 4
	fire.light_energy = .72
	fire.flicker_strength = .0486
	# The benchmark creates HearthGlow first. Other hosts can supply their lamp path.
	var lamp := get_node_or_null(hearth_light_path) as OmniLight3D if not hearth_light_path.is_empty() else get_node_or_null("../HearthGlow") as OmniLight3D
	if lamp:
		# Resolve from the not-yet-parented effect through this room root.
		fire.light_path = NodePath("../" + str(get_path_to(lamp)))
	else:
		# Standalone art retains the same single Basic Room lamp at fire_position.
		lamp = OmniLight3D.new()
		lamp.name = "HearthGlow"
		lamp.position = _vec(layout.fire_position)
		lamp.light_color = Color("ff9b35")
		lamp.omni_range = 1.25
		lamp.omni_attenuation = 1.6
		lamp.shadow_enabled = false
		add_child(lamp)
		fire.light_path = NodePath("../HearthGlow")
	add_child(fire)
	# fire_position is the retained light anchor. Seat emitter geometry at the
	# original fire.glb pivot (fuel bed) without moving that public FX root/lamp.
	var fuel_offset := _vec(assets.fire.position) - fire.position
	for emitter in fire.get_children():
		if emitter is GPUParticles3D: emitter.position += fuel_offset
