extends Node3D
## Art-only scene. The host owns selection, network, identity, claims and return routing.
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
const House = preload("res://modules/dynamic_farm/farm_house.gd")
const Art = preload("res://modules/farm/farm_art.gd")
const Placement = preload("res://scenes/dynamic_farm/house_placement.gd")
const SPEED := 3.75

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
# The owner's parcel farm save (args.parcel: enter / place_house, C-31 shapes); null in the art preview.
var _parcel: RefCounted
var _farm := {}
var _house: Node3D
var _build: UiCommandButton
var _placement: Placement
var _sending := false

func setup(args: Dictionary) -> void:
	_args = args.duplicate(true)

func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_resized)
	if _args.get("preview_only") != true or not _args.get("farm") is Dictionary:
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
	var art := Scenery.build(_plan,_walk)
	if not art.ok:
		_fail(art.error)
		return
	_props = art.root
	add_child(_props)
	# Separate batches outside extension occupancy and shadow budgets; stones, bushes
	# and saplings still block through the shared model-fitted profiles (Q-16).
	var core_art := Scenery.build(_plan.core_obstacles, _walk)
	if not core_art.ok:
		_fail(core_art.error)
		return
	core_art.root.name = "CoreObstacles"
	add_child(core_art.root)
	_setup_world()
	_shade = Shade.new()
	add_child(_shade)
	_shade.setup(_ground,_props,_plan,_data,_walk)
	if bool(_args.get("edge_decor_preview",false)):
		_edge_plan=EdgeDecor.plan(_data,_walk,_plan)
		var edge_art:=Scenery.build(_edge_plan,_walk)
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
	if _args.get("parcel") is RefCounted:
		_parcel = _args.parcel
		_parcel.enter(_on_entered)

## The owner's farm on opening (the welcome gift arrives with the first entry only).
func _on_entered(reply: Dictionary) -> void:
	if _failed or not reply.get("ok", false): return
	_farm = reply.farm
	if _farm.get("house") is Dictionary and _house == null: _build_house(_farm.house)
	_refresh_build()

func blueprints() -> int:
	return int((_farm.get("bag", {}) as Dictionary).get(House.BLUEPRINT, 0))

func house_state() -> Variant:
	return _farm.get("house")

func _refresh_build() -> void:
	_build.visible = _parcel != null and _house == null and _placement == null and blueprints() > 0

func begin_house_placement() -> void:
	if not _build.visible: return
	_movement = Vector2.ZERO
	_controls.reset()
	_controls.process_mode = Node.PROCESS_MODE_DISABLED
	var solid := {}
	var taken := House.blocked(_plan.core_obstacles.layout, _farm, solid)
	var walk_blocked: Dictionary = solid.merged(_walk.reserved)
	var start = House.nearest(_data, _walk.cell_at(_actor.position), taken, walk_blocked)
	_placement = Placement.new()
	add_child(_placement)
	_placement.setup(_data, _walk, _camera, _canvas, taken, walk_blocked,
		start if start != null else _walk.cell_at(_actor.position) - Vector2i.ONE)
	_placement.confirmed.connect(_on_place_confirmed)
	_placement.cancelled.connect(end_house_placement)
	_refresh_build()
	_play("idle")
	_focus = House.center(_walk, _placement.at)
	_overview = false
	_place_camera()

func end_house_placement() -> void:
	if _placement == null: return
	_placement.queue_free()
	_placement = null
	_sending = false
	_controls.process_mode = Node.PROCESS_MODE_INHERIT
	_controls.reset()
	_refresh_build()

func _on_place_confirmed(at: Vector2i, rotation_steps: int) -> void:
	if _sending: return
	_sending = true
	_parcel.place_house(at.x, at.y, rotation_steps, _on_placed)

func _on_placed(reply: Dictionary) -> void:
	_sending = false
	if reply.get("farm") is Dictionary: _farm = reply.farm
	if reply.get("ok", false) and _farm.get("house") is Dictionary:
		end_house_placement()
		_build_house(_farm.house)
	elif str(reply.get("code", "")) != "CELL_OCCUPIED" or _placement == null:
		end_house_placement()
	_refresh_build()

## The built cottage and its wall profile (C-19's model-fitted walking); a player standing on the new walls steps out.
func _build_house(house: Dictionary) -> void:
	var at := House.at_of(house)
	var turns := int(house.get("rotation", 0))
	_house = Node3D.new()
	_house.name = "House"
	_house.transform = House.transform(_walk, at, turns)
	_house.add_child(Art.instance(House.ASSET))
	add_child(_house)
	var proxy := House.proxy(_walk, at, turns)
	_walk.add_prop(proxy)
	if get_tree().debug_collisions_hint:
		var wire := MeshInstance3D.new()
		wire.mesh = proxy.debug_wire()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.albedo_color = Color("00e5ff")
		wire.material_override = material
		wire.transform = proxy.pose
		add_child(wire)
	if _actor != null and not _walk.clear_position(_walk.position):
		_walk.position = _step_out(_walk.position)
		_actor.position = _walk.position
		_focus = _actor.position
		_place_camera()

## The nearest clear point to `from`, searched in rings of 0.1 m.
func _step_out(from: Vector3) -> Vector3:
	for ring in range(1, 40):
		for k in 32:
			var p := from + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 32.0) * ring * 0.1
			if _walk.clear_position(p): return p
	return _walk.point(_data.spawn)

func _setup_world() -> void:
	var env := Environment.new()
	var clouds := ShaderMaterial.new()
	clouds.shader = SKY_SHADER
	env.sky = Sky.new()
	env.sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky.sky_material = clouds
	env.background_mode = Environment.BG_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.79,0.88,0.94)
	env.ambient_light_energy = 0.42
	_environment = WorldEnvironment.new()
	_environment.environment = env
	add_child(_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Shade.SUN_DEGREES
	sun.light_color = Color(1,0.96,0.87)
	sun.light_energy = 1.1
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
	if not _ready_sent:
		if _avatar_loaded and _shade.complete:
			_ready_sent = true
			_summary.shadows = _shade.metrics.duplicate(true)
			_summary.ready_ms = Time.get_ticks_msec() - _started_ms
			preview_ready.emit(_summary.duplicate(true))
		elif Time.get_ticks_msec() - _started_ms > 15000:
			_fail("The farm preview could not finish loading.")
		return
	if not _focused or _placement != null: return
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
	if _actor.position.distance_to(previous) > 0.0001:
		_actor.look_at(_actor.position+direction,Vector3.UP)
		_play("run")
	else:
		_play("idle")
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
	var hint := _label("Art preview · Walk and explore",12)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_bottom = -12
	hint.offset_top = -34
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(hint)
	_build = UiCommandButton.new("Build Cottage", UiCommandButton.Kind.PRIMARY)
	_build.theme = UiKit.theme()
	_build.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build.offset_left = -90
	_build.offset_right = 90
	_build.offset_top = -92
	_build.offset_bottom = -44
	_build.visible = false
	_build.activated.connect(begin_house_placement)
	_canvas.add_child(_build)

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("314637"))
	return label

func _request_back() -> void:
	if _back_sent: return
	_back_sent = true
	end_house_placement()
	_movement = Vector2.ZERO
	_controls.reset()
	back_requested.emit()

func is_back_navigation_locked() -> bool:
	_request_back()
	return true

func suspend() -> void:
	_suspended = true
	end_house_placement()
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
