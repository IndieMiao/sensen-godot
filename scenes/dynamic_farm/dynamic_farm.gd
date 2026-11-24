extends Node3D
## Art scene; with `own_parcel` it also farms the owner's parcel (ParcelFarming, C-34).
## The host owns selection, network, identity, claims and return routing.
signal preview_ready(summary: Dictionary)
signal preview_error(message: String)
signal back_requested

const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Ground = preload("res://modules/dynamic_farm/farm_mesh.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const EdgeDecor = preload("res://modules/dynamic_farm/farm_edge_decor.gd")
const CameraRules = preload("res://modules/farm/farm_camera.gd")
const Cliff = preload("res://modules/dynamic_farm/island_cliff.gd")
const SKY_SHADER = preload("res://modules/dynamic_farm/island_sky.gdshader")
const Controls = preload("res://scenes/dynamic_farm/dynamic_controls.gd")
const MergedAssembler = preload("res://modules/avatar/assembly/assembler_merged.gd")
const Farming = preload("res://scenes/dynamic_farm/parcel_farming.gd")
const LocalFarmStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const RemoteFarmStore = preload("res://modules/dynamic_farm/parcel_farm_remote_store.gd")
## Development only: keep the own-parcel farm on the device instead of the C-31 server.
const LOCAL_SAVE_SETTING := "sensen/dynamic_farm/local_farm_save"
const SPEED := 3.75
## Background cloud drift in screen widths per second; negative drifts left. A group
## crosses a 1080-pixel-wide screen in about 100 s.
const CLOUD_DRIFT := 0.01

var _args := {}
var _data := {}
var _walk: RefCounted
var _ground: Node3D
var _props: Node3D
var _plan := {}
var _edge_plan := {}
var _shade: Node
var _actor: Node3D
var _rig: Node3D
var _camera: Camera3D
var _environment: WorldEnvironment
var _clouds: ShaderMaterial
var _cloud_drift := 0.0
var _saved_environment: Environment
var _canvas: CanvasLayer
var _controls: Control
var _title: Label
var _status: Label
var _movement := Vector2.ZERO
var _focus := Vector3.ZERO
var _zoom := 1.0
var _normal_size := 7.2
var _avatar_loaded := false
var _ready_sent := false
var _failed := false
var _back_sent := false
var _suspended := false
var _focused := true
var _overview := false
var _started_ms := 0
var _clip := ""
var _summary := {}
var _hint: Label
var _farming: Node3D
var _facing := Vector3.BACK

func setup(args: Dictionary) -> void:
	_args = args.duplicate(true)

func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_resized)
	if (_args.get("preview_only") != true and _args.get("own_parcel") != true) or not _args.get("farm") is Dictionary:
		_fail("This farm preview could not be opened.")
		return
	_data = Data.decode(_args.farm)
	if not _data.ok:
		_fail(_data.error)
		return
	if _args.get("dataset") != _data.dataset_version or _args.get("block_id") != _data.block_id:
		_fail("The selected farm has changed. Please select it again.")
		return
	_walk = Walk.new(_data)
	if not _walk.clear_position(_walk.position):
		_fail("This farm has no safe arrival point.")
		return
	_plan = Scenery.plan(_data,_walk)
	if not _plan.ok:
		_fail(_plan.error)
		return
	Shade.enforce_budget(_plan,_data,_walk)
	_ground = Ground.build(_data,_walk,_plan.recipe,true,Shade.can_widen(_plan,_data,_walk),
		1.0 if bool(_args.get("original_slope_material",false)) else 0.65)
	add_child(_ground)
	var art := Scenery.build(_plan,_walk,_plan.recipe)
	if not art.ok:
		_fail(art.error)
		return
	_props = art.root
	add_child(_props)
	# Separate batches outside extension occupancy and shadow budgets; stones, bushes
	# and trees still block through the shared model-fitted profiles (Q-16).
	var core_art := Scenery.build(_plan.core_obstacles, _walk, _plan.recipe)
	if not core_art.ok:
		_fail(core_art.error)
		return
	core_art.root.name = "CoreObstacles"
	add_child(core_art.root)
	if _args.get("own_parcel") == true:
		_farming = Farming.new()
		_farming.name = "ParcelFarming"
		add_child(_farming)
	_setup_world()
	_shade = Shade.new()
	add_child(_shade)
	_shade.setup(_ground,_props,_plan,_data,_walk)
	if bool(_args.get("edge_decor_preview",false)):
		_edge_plan=EdgeDecor.plan(_data,_walk,_plan)
		var edge_art:=Scenery.build(_edge_plan,_walk,_plan.recipe)
		if not edge_art.ok:
			_fail(edge_art.error)
			return
		edge_art.root.name="EdgeDecorPreview"
		add_child(edge_art.root)
	_actor = Node3D.new()
	_actor.name = "PreviewPlayer"
	_actor.position = _walk.position
	add_child(_actor)
	var avatar := get_tree().root.get_node_or_null("Avatar")
	if avatar == null or avatar.get("loader") == null:
		_fail("The player appearance service is unavailable.")
		return
	_rig = avatar.create_rig()
	_rig.assembler = MergedAssembler.new()
	_rig.rotation.y = PI
	_rig.config_applied.connect(_on_avatar_ready,CONNECT_ONE_SHOT)
	_rig.part_load_failed.connect(func(_slot,_part,_error): _fail("The player appearance could not be loaded."))
	_actor.add_child(_rig)
	for child in _rig.get_children():
		if child.get_script() == preload("res://modules/avatar/assembly/rig_activity.gd"):
			child.reduced_distance = 50
			child.sleep_distance = 80
	avatar.follow_saved_outfit(_rig)
	_focus = _actor.position
	_place_camera()
	_facing = Vector3(_camera.global_basis.z.x, 0, _camera.global_basis.z.z).normalized()
	if _farming != null:
		var store = _args.get("farm_store")
		if not store is RefCounted or not store.has_method("enter") or not store.has_method("send"):
			var net := get_tree().root.get_node_or_null("Net")
			if bool(ProjectSettings.get_setting(LOCAL_SAVE_SETTING, false)): store = LocalFarmStore.new(_data.block_id)
			else: store = RemoteFarmStore.new(net.client if net != null else null, _data.block_id, _data.dataset_version)
		_farming.setup(_data, _walk, {"plan": _plan.core_obstacles, "root": core_art.root, "proxies": core_art.proxies, "recipe": _plan.recipe}, store, _canvas)
		_hint.hide()
	_title.text = _data.address if not _data.address.is_empty() else _data.name
	_status.text = "Core %d · Walk-only %d" % [_data.counts.core,_data.counts.extension]
	_summary = {"schema":4,"dataset":_data.dataset_version,"block_id":_data.block_id,
		"core_cells":_data.counts.core,"extension_cells":_data.counts.extension,
		"protected_cells":_data.protected.size(),"reserved_placement_cells":_walk.reserved.size(),
		"art_version":_plan.art_version,"layout_sha256":_plan.layout_sha256,
		"roles":_plan.roles,"instances":art.instances,"batches":art.batches,
		"placed_triangles":art.placed_triangles,"unique_triangles":art.unique_triangles,
		"shadow_budget_rejected":_plan.shadow_budget_rejected,"island_backdrop":true,
		"seed_hex":_data.seed_hex,"generator_version":_data.generator_version,
		"camera":{"pitch":43.0,"yaw":14.5,"keep_width":true},
		"source_origin":[_data.origin.x,_data.origin.y]}
	_summary.core_obstacles = {"roles":_plan.core_obstacles.roles, "instances":core_art.instances,
		"batches":core_art.batches, "placed_triangles":core_art.placed_triangles,
		"layout_sha256":_plan.core_obstacles.layout_sha256}
	_summary.outer = _plan.outer.duplicate()
	_summary.outer.reserved_cells = _walk.reserved.size()
	_summary.bank = _ground.get_meta("bank_metrics",{})
	_summary.slope_material={"clearing_linear_gain":_ground.get_meta("slope_material_linear_gain"),
		"batches":_ground.get_meta("slope_batches")}
	_summary.edge_decor={"enabled":not _edge_plan.is_empty(),"instances":_edge_plan.get("layout",[]).size(),
		"triangles":_edge_plan.get("triangles",0),"batches":_edge_plan.get("batches",0),
		"layout_sha256":_edge_plan.get("layout_sha256",""),"covered_cells":_edge_plan.get("covered_cells",0),
		"perimeter_cells":_edge_plan.get("perimeter_cells",0),"clusters":_edge_plan.get("clusters",[]).size()}

func _setup_world() -> void:
	var env := Environment.new()
	_clouds = ShaderMaterial.new()
	_clouds.shader = SKY_SHADER
	env.sky = Sky.new()
	env.sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky.sky_material = _clouds
	env.background_mode = Environment.BG_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.84,0.88,0.90)
	env.ambient_light_energy = 0.42
	_environment = WorldEnvironment.new()
	_environment.environment = env
	add_child(_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Shade.SUN_DEGREES
	sun.light_color = Color(1,0.95,0.84)
	sun.light_energy = 1.12
	sun.shadow_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	sun.shadow_opacity = 0.58
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 0.0
	sun.directional_shadow_fade_start = 1.0
	sun.directional_shadow_pancake_size = 4.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(_camera)
	_camera.make_current()
	_normal_size = CameraRules.close_view_size(get_viewport().get_visible_rect().size) * CameraRules.P0_VIEW_K

func _on_avatar_ready(_config) -> void:
	var merged := _rig.find_children("merged_mesh","MeshInstance3D",true,false)
	if merged.is_empty() or (merged[0] as MeshInstance3D).mesh == null or (merged[0] as MeshInstance3D).mesh.get_surface_count() == 0:
		_fail("The player appearance is incomplete.")
		return
	_avatar_loaded = true
	_play("idle")

func _process(delta: float) -> void:
	if _failed or _suspended or _walk == null: return
	if _clouds != null:
		_cloud_drift += CLOUD_DRIFT * delta
		_clouds.set_shader_parameter("drift", _cloud_drift)
	if not _ready_sent:
		if _avatar_loaded and _shade.complete:
			_ready_sent = true
			_summary.shadows = _shade.metrics.duplicate(true)
			_summary.ready_ms = Time.get_ticks_msec() - _started_ms
			preview_ready.emit(_summary.duplicate(true))
			# Only once the scene is up: building it stalls the main thread for seconds, and an
			# HTTP request started during that stall times out (V-123).
			if _farming != null: _farming.enter()
		elif Time.get_ticks_msec() - _started_ms > 15000:
			_fail("The farm preview could not finish loading.")
		return
	if not _focused: return
	var dt := clampf(delta,0,0.1)
	var input := _movement
	input = input.limit_length(1.0)
	var right := _camera.global_basis.x
	right.y = 0
	var forward := -_camera.global_basis.z
	forward.y = 0
	var direction := right.normalized()*input.x-forward.normalized()*input.y
	var previous: Vector3 = _walk.position
	_walk.move(direction*SPEED*dt)
	_actor.position = _walk.position
	var moving := _actor.position.distance_to(previous) > 0.0001
	# Turn toward the stick even when blocked, so the key can target what the player pushes against.
	if not direction.is_zero_approx(): _facing = direction.normalized()
	if moving:
		_actor.look_at(_actor.position+direction,Vector3.UP)
		_play("run")
	else:
		_play("idle")
	if _farming != null:
		_farming.update(dt, _walk.cell_at(_actor.position + _facing * _walk.cell_m * 0.8), moving or not input.is_zero_approx())
	if not _overview:
		var size := get_viewport().get_visible_rect().size
		var safe := Rect2(size*Vector2(0.23,0.26),size*Vector2(0.54,0.48))
		_focus += CameraRules.follow_shift(_camera,_actor.position,safe)
		if input.is_zero_approx(): _focus = _focus.lerp(_actor.position,minf(dt*2.8,1.0))
		_place_camera()

func _place_camera() -> void:
	if _camera == null: return
	_camera.size = _normal_size * _zoom
	CameraRules.place(_camera,_focus)
	CameraRules.fit_ground_depth(_camera, Cliff.LOWEST_Y, 5.0)

func set_review_overview(enabled: bool) -> void:
	# Review-only capture hook. Normal interaction retains the existing player-scale camera.
	if not _ready_sent: return
	_overview = enabled
	_controls.reset()
	if enabled:
		_focus = Vector3.ZERO
		_place_camera()
		var extent: Vector2 = Vector2(_data.grid_size)*_data.cell_m
		var box := AABB(Vector3(-extent.x*0.5,Cliff.LOWEST_Y,-extent.y*0.5),Vector3(extent.x,5.0-Cliff.LOWEST_Y,extent.y))
		var size := get_viewport().get_visible_rect().size
		CameraRules.fit(_camera,box,Rect2(Vector2(20,112),size-Vector2(40,172)))
		CameraRules.fit_ground_depth(_camera,Cliff.LOWEST_Y,5.0)
	else:
		_focus = _actor.position
		_place_camera()

func _play(clip: String) -> void:
	if _rig == null or clip == _clip: return
	_clip = clip
	_rig.play_motion(clip)

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 20
	add_child(_canvas)
	_controls = Controls.new()
	_canvas.add_child(_controls)
	_controls.top_exclusion_y = 102
	_controls.movement_changed.connect(func(value: Vector2): _movement = value)
	_controls.zoom_changed.connect(func(factor: float):
		_zoom = clampf(_zoom*factor,0.8,1.4)
		_overview = false
		_place_camera())
	_controls.tapped.connect(_on_tapped)
	_controls.recenter_requested.connect(func():
		if _actor != null:
			_focus = _actor.position
			_overview = false
			_place_camera())
	var header := PanelContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 12
	header.offset_right = -12
	header.offset_top = 12
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96,0.97,0.93,0.94)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	header.add_theme_stylebox_override("panel",style)
	_canvas.add_child(header)
	var row := HBoxContainer.new()
	header.add_child(row)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(labels)
	_title = _label("Dynamic farm",16)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size.x = 120
	labels.add_child(_title)
	_status = _label("Loading preview…",12)
	labels.add_child(_status)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(64,44)
	back.pressed.connect(_request_back)
	row.add_child(back)
	_hint = _label("Art preview · Walk and explore",12)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_bottom = -12
	_hint.offset_top = -34
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_hint)

## A tap on the ground picks that cell for the main key.
func _on_tapped(at: Vector2) -> void:
	if _farming == null or not _ready_sent or _camera == null: return
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(_camera.project_ray_origin(at), _camera.project_ray_normal(at))
	if hit is Vector3: _farming.pick(_walk.cell_at(hit))

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("314637"))
	return label

func _request_back() -> void:
	if _back_sent: return
	_back_sent = true
	_movement = Vector2.ZERO
	_controls.reset()
	back_requested.emit()

func is_back_navigation_locked() -> bool:
	_request_back()
	return true

func suspend() -> void:
	_suspended = true
	_movement = Vector2.ZERO
	_controls.reset()
	_canvas.visible = false
	visible = false
	if _environment != null:
		_saved_environment = _environment.environment
		_environment.environment = null
	process_mode = Node.PROCESS_MODE_DISABLED

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	_suspended = false
	_back_sent = false
	visible = true
	_canvas.visible = true
	if _environment != null: _environment.environment = _saved_environment
	if _camera != null: _camera.make_current()
	_movement = Vector2.ZERO
	_controls.reset()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_movement = Vector2.ZERO
		if _controls != null: _controls.reset()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true

func _fail(message: String) -> void:
	if _failed: return
	_failed = true
	_movement = Vector2.ZERO
	_status.text = message
	preview_error.emit(message)

func _on_viewport_resized() -> void:
	_normal_size = CameraRules.close_view_size(get_viewport().get_visible_rect().size) * CameraRules.P0_VIEW_K
	if _overview and _ready_sent:
		set_review_overview(true)
	else:
		_place_camera()
