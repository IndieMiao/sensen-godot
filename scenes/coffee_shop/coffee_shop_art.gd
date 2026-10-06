@tool
extends Node3D
## Art + simple collisions only. All placement is in metres, local floor/mount pivots.
@export_dir var kit_path: String = "res://assets/rooms/coffee_shop"
var _assembled := false

func _ready() -> void:
	if _assembled: return
	_assembled = true
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(kit_path + "/layout.json"))
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

func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _add_asset(asset: Dictionary, placement: Dictionary, material: StandardMaterial3D) -> void:
	var pivot := Node3D.new()
	pivot.name = placement.name
	pivot.position = _vec(placement.position)
	pivot.rotation.y = deg_to_rad(float(placement.yaw_degrees))
	add_child(pivot)
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
	_set_material(model, applied, "glass" in str(asset.name))
	for box: Dictionary in asset.colliders:
		var body := StaticBody3D.new()
		body.position = _vec(box.at)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = _vec(box.size)
		collision.shape = shape
		body.add_child(collision)
		pivot.add_child(body)

func _set_material(node: Node, material: Material, glass: bool) -> void:
	if node is MeshInstance3D:
		node.material_override = material
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if glass: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _set_material(child, material, glass)
