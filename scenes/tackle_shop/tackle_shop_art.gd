@tool
extends Node3D
## SGODOT-214 reusable art. Gameplay placement consumes layout anchors separately.
const KIT := "res://assets/rooms/tackle_shop/"
var layout: Dictionary
var assets: Dictionary = {}

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(KIT + "layout.json"))
	for asset in layout.assets:
		assets[asset.name] = asset
		_add_asset(asset, asset)
	for placement in layout.instances:
		_add_asset(assets[placement.asset], placement)
	for spec in layout.get("local_lights", []):
		var light := OmniLight3D.new()
		light.name = spec.name
		light.position = _vec(spec.position)
		light.light_color = Color(spec.color)
		light.light_energy = float(spec.energy)
		light.omni_range = float(spec.range)
		light.omni_attenuation = float(spec.get("attenuation", 1.6))
		light.shadow_enabled = false
		add_child(light)
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
		# Imported surfaces retain their own opaque/glass materials and shared atlas.
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if not asset.get("cast_shadow", true):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for index in asset.get("colliders", []).size():
		var c: Dictionary = asset.colliders[index]
		var body := StaticBody3D.new()
		body.name = "Collider_%02d" % index
		body.position = _vec(c.at)
		body.rotation_degrees = _vec(c.get("rotation", [0, 0, 0]))
		var volume: Shape3D
		if c.get("kind", "box") == "cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = float(c.radius)
			cylinder.height = float(c.height)
			volume = cylinder
		else:
			var box := BoxShape3D.new()
			box.size = _vec(c.size)
			volume = box
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		shape.shape = volume
		body.add_child(shape)
		container.add_child(body)
