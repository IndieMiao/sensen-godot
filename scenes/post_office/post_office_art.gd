@tool
extends Node3D
## Reusable static room assembly. No player, UI, account, network or save dependencies.
## Lighting belongs to the consuming scene. Art-only review uses a separate script.
const KIT := "res://assets/rooms/post_office/"
var layout: Dictionary
var assets: Dictionary = {}
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
		_add_asset(asset, asset, material)
	for instance in layout.instances:
		_add_asset(assets[instance.asset], instance, material)

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
	if str(asset.name).ends_with("garden"):
		applied = material.duplicate()
		applied.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		applied.cull_mode = BaseMaterial3D.CULL_DISABLED
	if asset.name == "fire":
		applied = material.duplicate()
		applied.emission_enabled = true
		applied.emission = Color("ffb041")
		applied.emission_energy_multiplier = 1.3
		fire = container
	if asset.name == "display_glass":
		applied = material.duplicate()
		applied.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		applied.albedo_color = Color(0.90, 0.97, 1.0, 0.12)
		applied.roughness = 0.14
		applied.cull_mode = BaseMaterial3D.CULL_DISABLED
		_disable_shadows(model)
	_set_material(model, applied)
	if str(asset.name).ends_with("garden"): _disable_shadows(model)
	for c in asset.colliders:
		var body := StaticBody3D.new()
		body.position = _vec(c.at)
		# The authored floorboard top is 8cm above the assembly pivot.
		if asset.name == "room_shell": pass
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
