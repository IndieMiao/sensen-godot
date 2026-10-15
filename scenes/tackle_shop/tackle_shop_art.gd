@tool
extends Node3D
## SGODOT-214 reusable art. Gameplay placement consumes layout anchors separately.
const KIT := "res://assets/rooms/tackle_shop/"
var layout: Dictionary
var assets: Dictionary = {}
var materials: Dictionary = {}

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(KIT + "layout.json"))
	var plain := StandardMaterial3D.new()
	plain.resource_name = "TackleRoomSharedAtlas"
	plain.albedo_texture = load(KIT + "room_albedo_ao.png")
	plain.roughness = .80
	plain.metallic_specular = .28
	plain.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	materials.plain = plain
	var glass := plain.duplicate() as StandardMaterial3D
	glass.resource_name = "TackleFishbowlGlass"
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(1, 1, 1, .075)
	glass.roughness = .20
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	materials.glass = glass
	for asset in layout.assets:
		assets[asset.name] = asset
		_add_asset(asset, asset)
	for placement in layout.instances:
		_add_asset(assets[placement.asset], placement)
	for anchor in layout.anchors:
		var marker := Marker3D.new()
		marker.name = anchor.name
		marker.position = _vec(anchor.position)
		marker.rotation.y = deg_to_rad(float(anchor.get("yaw_degrees", 0)))
		marker.set_meta("module", anchor.module)
		if anchor.has("size"): marker.set_meta("size", anchor.size)
		add_child(marker)

func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _add_asset(asset: Dictionary, placement: Dictionary) -> void:
	var container := Node3D.new()
	container.name = placement.name
	container.position = _vec(placement.position)
	container.rotation.y = deg_to_rad(float(placement.yaw_degrees))
	container.scale = _vec(placement.get("scale", [1, 1, 1]))
	add_child(container)
	var model := (load(KIT + asset.file) as PackedScene).instantiate()
	container.add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		node.material_override = materials[asset.get("material", "plain")]
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if not asset.get("cast_shadow", true):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in asset.colliders:
		var body := StaticBody3D.new()
		body.position = _vec(c.at)
		body.rotation_degrees = _vec(c.get("rotation", [0, 0, 0]))
		var box := BoxShape3D.new()
		box.size = _vec(c.size)
		var shape := CollisionShape3D.new()
		shape.shape = box
		body.add_child(shape)
		container.add_child(body)
