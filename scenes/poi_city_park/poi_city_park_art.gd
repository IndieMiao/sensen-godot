@tool
extends Node3D
## SGODOT-320 art-only kit. No room service, movement or gameplay integration.
const KIT = "res://assets/rooms/poi_city_park/"
var assembled = false
var atlas: StandardMaterial3D
var water: ShaderMaterial
var backdrop: StandardMaterial3D
var layout: Dictionary

func vec(a): return Vector3(a[0], a[1], a[2])

func _process(_delta):
	if not assembled: return
	var camera = get_viewport().get_camera_3d()
	var card = get_node_or_null("village_backdrop")
	if camera == null or card == null: return
	var toward_camera = camera.global_basis.z
	toward_camera.y = 0
	if toward_camera.length_squared() < .001: return
	toward_camera = toward_camera.normalized()
	card.position = -toward_camera*6.1
	card.rotation.y = atan2(toward_camera.x, toward_camera.z)

func _ready():
	if assembled: return
	assembled = true
	layout = JSON.parse_string(FileAccess.get_file_as_string(KIT + "layout.json"))
	atlas = StandardMaterial3D.new()
	atlas.resource_name = "N5_Shared_2048_Atlas"
	atlas.albedo_texture = load(KIT + "room_albedo_ao.png")
	atlas.roughness = .9
	atlas.metallic_specular = .18
	atlas.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	backdrop = atlas.duplicate()
	backdrop.resource_name = "N5_Backdrop_Same_Atlas"
	backdrop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop.cull_mode = BaseMaterial3D.CULL_DISABLED
	water = water_material()
	var assets = {}
	for spec in layout.assets:
		assets[spec.name] = spec
		if not spec.get("review_only", false): add_module(spec, spec)
	for placement in layout.instances:
		add_module(assets[placement.asset], placement)
	for box in layout.boundaries: add_box(self, box)
	for point in layout.local_lights:
		var lamp = OmniLight3D.new()
		lamp.name = "ParkLanternLight"
		lamp.position = vec(point.position)
		lamp.light_color = Color(point.color)
		lamp.light_energy = point.energy
		lamp.omni_range = point.range
		lamp.shadow_enabled = false
		add_child(lamp)
	for point in layout.anchors:
		var marker = Marker3D.new()
		marker.name = point.name
		marker.position = vec(point.position)
		marker.rotation_degrees.y = point.yaw_degrees
		for key in ["module", "size", "approach", "pitch_degrees", "width_m"]:
			if point.has(key): marker.set_meta(key, point[key])
		add_child(marker)

func add_module(spec, placement):
	var pivot = Node3D.new()
	pivot.name = placement.name
	pivot.position = vec(placement.position)
	pivot.rotation_degrees.y = placement.yaw_degrees
	pivot.scale = vec(placement.get("scale", [1, 1, 1]))
	add_child(pivot)
	var model = load(KIT + spec.file).instantiate()
	pivot.add_child(model)
	var material = water if spec.material == "pond_water" else backdrop if spec.material == "backdrop" else atlas
	var meshes = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D: meshes.push_front(model)
	for node in meshes:
		node.material_override = material
		if not spec.cast_shadow: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for box in spec.colliders: add_box(pivot, box)
	return pivot

func add_box(parent, box):
	var body = StaticBody3D.new()
	body.name = box.get("name", "ArtCollider")
	body.position = vec(box.at)
	body.rotation_degrees.y = box.get("yaw_degrees", 0)
	var shape = BoxShape3D.new()
	shape.size = vec(box.size)
	var collision = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

func water_material():
	var material = ShaderMaterial.new()
	material.resource_name = "N5_Existing_Pond_Water"
	material.shader = preload("res://modules/ponds/pond_water.gdshader")
	material.set_shader_parameter("ripple_field", preload("res://assets/ponds/art/pond_ripple_field.png"))
	material.set_shader_parameter("surface_flow", preload("res://assets/farm/art/water/surface_flow.png"))
	material.set_shader_parameter("caustics", preload("res://assets/ponds/art/caustic_web.png"))
	# Constant shallow stone-bed inputs suit the two tiny stone basins. Animation,
	# caustics and light response are all supplied by the unchanged pond shader.
	material.set_shader_parameter("pond_shore", constant_texture(Color(.4, .4, .4, 1)))
	material.set_shader_parameter("basin_bed", constant_texture(Color(.48, .52, .43, .14)))
	material.set_shader_parameter("fish_paths", PackedVector4Array([Vector4(-100, -100, .1, .1), Vector4(-100, -100, .1, .1), Vector4(-100, -100, .1, .1)]))
	material.set_shader_parameter("has_foam_contact", false)
	material.set_shader_parameter("foam_strength", 0.0)
	material.set_shader_parameter("sun_direction", Vector3(-.45, .82, -.35))
	return material

func constant_texture(color):
	var image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
