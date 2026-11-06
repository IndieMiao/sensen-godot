@tool
extends Node3D
## Shared POI architecture only. The consuming scene owns lighting and cameras.
const KIT := "res://assets/rooms/_shared/shell_hall/"
@export_file("*.png") var atlas_path := KIT + "hall_albedo_ao.png"
var layout: Dictionary
var assets: Dictionary = {}
var _materials: Dictionary = {}

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(KIT + "layout.json"))
	for asset in layout.assets:
		assets[asset.name] = asset
		_add_asset(asset, asset)
	for placement in layout.instances:
		_add_asset(assets[placement.asset], placement)
	for spec in layout.boundaries:
		_add_collider(self, spec, str(spec.name))
	for spec in layout.anchors:
		var marker := Marker3D.new()
		marker.name = spec.name
		marker.position = _vec(spec.position)
		marker.rotation.y = deg_to_rad(float(spec.get("yaw_degrees", 0)))
		marker.set_meta("module", spec.module)
		if spec.has("size"): marker.set_meta("size", spec.size)
		add_child(marker)

func _vec(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _add_asset(asset: Dictionary, placement: Dictionary) -> void:
	var container := Node3D.new()
	container.name = placement.name
	container.position = _vec(placement.position)
	container.rotation.y = deg_to_rad(float(placement.yaw_degrees))
	add_child(container)
	var model := (load(KIT + asset.file) as PackedScene).instantiate()
	container.add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if not asset.get("cast_shadow", true):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in node.mesh.get_surface_count():
			var original := node.get_active_material(surface) as StandardMaterial3D
			assert(original != null)
			var key := original.resource_name
			if not _materials.has(key):
				var material := original.duplicate() as StandardMaterial3D
				material.albedo_texture = load(atlas_path)
				_materials[key] = material
			node.set_surface_override_material(surface, _materials[key])
	for index in asset.colliders.size():
		_add_collider(container, asset.colliders[index], "Collider_%02d" % index)

func _add_collider(parent: Node3D, spec: Dictionary, node_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = _vec(spec.at)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = _vec(spec.size)
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
