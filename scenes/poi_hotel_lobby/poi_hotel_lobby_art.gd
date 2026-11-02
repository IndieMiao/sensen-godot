@tool
extends Node3D
## Reusable N1 art, shared architecture, local fixtures and collision. No environment/camera/UI.
const KIT := "res://assets/rooms/poi_hotel_lobby/"
const PLANTS := "res://assets/rooms/_shared/plants/"
var layout: Dictionary
var assets := {}
var _materials := {}

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(KIT + "layout.json"))
	var shell = load(layout.shared_shell).instantiate()
	shell.name = "SharedHallShell"
	shell.atlas_path = layout.shell_atlas
	add_child(shell)
	# Native P0 anchor visibility addresses module nodes directly under the art root.
	for child in shell.get_children():
		if child is Marker3D: child.queue_free()
		else: child.reparent(self)
	shell.queue_free()
	for row in layout.assets:
		assets[row.name] = row
		_add_asset(row, row)
	for row in layout.instances: _add_asset(assets[row.asset], row)
	for row in layout.shared_plants:
		var holder := Node3D.new()
		holder.name = row.name
		holder.position = _vec(row.position)
		holder.rotation_degrees.y = float(row.yaw_degrees)
		add_child(holder)
		var plant = load(PLANTS + row.file).instantiate()
		holder.add_child(plant)
		for mesh in plant.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = load(PLANTS + "material.tres")
			mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_collider(holder, {"kind": "cylinder", "at": [0, 1.0, 0], "radius": row.collision_radius, "height": 2.0}, "PotCollision")
	for row in layout.local_lights: _light(row)
	var fire = load(layout.shared_fire.scene).instantiate()
	fire.name = "SharedHearthFire"
	for key in ["flame_height", "flame_count", "spark_count", "light_energy", "light_range"]: fire.set(key, layout.shared_fire[key])
	fire.emission_box = _vec(layout.shared_fire.emission_box)
	fire.position = _vec(layout.shared_fire.position)
	fire.rotation_degrees.y = float(layout.shared_fire.yaw_degrees)
	add_child(fire)
	for row in layout.anchors:
		var marker := Marker3D.new()
		marker.name = row.name
		marker.position = _vec(row.position)
		marker.rotation_degrees.y = float(row.get("yaw_degrees", 0))
		marker.set_meta("module", row.module)
		if row.has("size"): marker.set_meta("size", row.size)
		if row.has("stand"): marker.set_meta("stand", row.stand)
		for key in ["role", "pitch_degrees", "orthographic_width", "near", "far"]:
			if row.has(key): marker.set_meta(key, row[key])
		add_child(marker)

func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _add_asset(asset: Dictionary, row: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = row.name
	holder.position = _vec(row.position)
	holder.rotation_degrees.y = float(row.yaw_degrees)
	add_child(holder)
	var model = load(KIT + asset.file).instantiate()
	holder.add_child(model)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if str(asset.name) in ["green_rug", "cowhide_rug"] or str(mesh.name) == "Artwork":
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(surface) as StandardMaterial3D
			assert(original != null)
			if not _materials.has(original.resource_name):
				var material := original.duplicate() as StandardMaterial3D
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false
				_materials[original.resource_name] = material
			mesh.set_surface_override_material(surface, _materials[original.resource_name])
	for index in asset.colliders.size(): _collider(holder, asset.colliders[index], "Collider_%02d" % index)

func _collider(parent: Node3D, row: Dictionary, node_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = _vec(row.at)
	var shape: Shape3D
	if row.get("kind", "box") == "cylinder":
		var cylinder := CylinderShape3D.new()
		cylinder.radius = float(row.radius)
		cylinder.height = float(row.height)
		shape = cylinder
	else:
		var box := BoxShape3D.new()
		box.size = _vec(row.size)
		shape = box
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)

func _light(row: Dictionary) -> void:
	var light: Light3D
	if row.kind == "spot":
		var spot := SpotLight3D.new()
		spot.spot_range = float(row.range)
		spot.spot_angle = float(row.angle_degrees)
		spot.spot_attenuation = 1.1
		spot.spot_angle_attenuation = 1.2
		spot.basis = Basis.looking_at(_vec(row.target) - _vec(row.position), Vector3.FORWARD)
		light = spot
	else:
		var omni := OmniLight3D.new()
		omni.omni_range = float(row.range)
		omni.omni_attenuation = 1.5
		light = omni
	light.name = row.name
	light.position = _vec(row.position)
	light.light_color = Color(row.color)
	light.light_energy = float(row.energy)
	light.light_specular = .25
	light.shadow_enabled = false
	add_child(light)
