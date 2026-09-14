extends SubViewportContainer
## One shared, transparent model preview for the currently selected owner.
const Art = preload("res://modules/farm/farm_art.gd")
var viewport: SubViewport
var stage: Node3D
var _key := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	size = Vector2(128, 112)
	viewport = SubViewport.new()
	viewport.size = Vector2i(256, 224)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("edf4e7")
	environment.environment.ambient_light_energy = 0.65
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 0.8
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.8
	viewport.add_child(camera)
	camera.position = Vector3(5, 8, 10)
	camera.look_at(Vector3(0, 0.6, 0.2))
	camera.make_current()

func show_farm(region_id: String, layout_id: String, plots := 9) -> void:
	show_style(Art.style_for(region_id, layout_id), plots)

func show_style(style: String, plots := 9) -> void:
	var key := "%s:%d" % [style, plots]
	if key == _key: return
	_key = key
	if stage:
		viewport.remove_child(stage)
		stage.queue_free()
	stage = build_model(style, plots)
	viewport.add_child(stage)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

static func build_model(style: String, plots := 9) -> Node3D:
	var model := Node3D.new()
	var ground := MeshInstance3D.new()
	var base := CylinderMesh.new()
	base.top_radius = 3.1
	base.bottom_radius = 2.9
	base.height = 0.22
	ground.mesh = base
	ground.position.y = -0.14
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("91b96b")
	ground.material_override = material
	model.add_child(ground)
	model.add_child(Art.instance("house_" + style, Vector3(0, 0, -1.25), 0.8))
	if style == "windmill": model.add_child(Art.instance("windmill_sails", Vector3(0, 1.808, -0.21), 0.8))
	model.add_child(Art.instance("tree_0", Vector3(-2, 0, -0.7), 0.7))
	model.add_child(Art.instance("well", Vector3(2, 0, -0.4), 0.7))
	var columns := 2 if plots == 4 else 3
	for index in mini(plots, 12):
		var point := Vector3((index % columns - (columns - 1) * 0.5) * 1.08, 0, 0.5 + floori(float(index) / columns) * 0.85)
		model.add_child(Art.instance("plot", point, 0.85))
	return model
