class_name JourneyPlace
extends Node3D

const NAV_ORIGIN := Vector3(-5, 0, 4)
const RESIDENT_CLEARANCE := 0.5
var place_id := "nursery"
var initial_target := ""
var session: FarmSession
var cam: Camera3D
var world_env: WorldEnvironment
var environment: Environment
var canvas: CanvasLayer
var header_backdrop: Panel
var header: VBoxContainer
var ui: Control
var marker_layer: Control
var panel: PanelContainer
var panel_scroll: ScrollContainer
var active_panel: SessionPanel
var feedback: Label
var status: Label
var objective: Label
var follow_goal: Button
var _tracked_target := ""
var scenery: Node3D
var cast: Node3D
var objects: Node3D
var decorations: Node3D
var player: Node3D
var rig: AvatarRig
var mover: PlayerMover
var nav: FarmBlueprint
var targets: Dictionary = {}
var pending_target := ""
var selected_target := ""
var display_project := ""
var _display_plan: Dictionary = {}
var display_done: Button
var farm_return: Button
var _farm_hint_elapsed := 0.0
var world_notice: PanelContainer
var world_notice_label: Label
var _world_notice_left := 0.0
var busy := false
var _world_key := ""
var _nav_props_key := ""
var _scenery_key := ""
var _cast_key := ""
var _decorations_key := ""
var _pointer := -2
var _press := Vector2.ZERO
# Null means no gesture; an empty ID preserves a press on the ground.
var _pressed_target: Variant = null
var _dragged := false
var _drag_prop := false
var _drag_last := Vector2.ZERO
var camera_pan := preload("res://modules/farm/scene_pan.gd").new()
var ground_feedback: PlotHints
var _pending_destination := Callable()
var meal_moment: ResidentMoment
var served_dish: MeshInstance3D
var served_recipe := ""
var _meal_left := 0.0
var served_target := "table"
var resident_moments: Dictionary = {}
var resident_activities: Dictionary = {}
var _meal_residents: Array[String] = []
var _activity_wait := 8.0
var _activity_index := 0

func _ready() -> void:
	_build_world()
	_build_ui()
	camera_pan.tapped.connect(_ground_tap)
	session.state_changed.connect(_changed)
	session.offline_changed.connect(func(_offline): _refresh())
	_refresh()
	if not initial_target.is_empty(): select_target.call_deferred(initial_target)

func _build_world() -> void:
	get_viewport().transparent_bg = false
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("dcebd4")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("eef4ef")
	environment.ambient_light_energy = 0.65
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.shadow_enabled = true
	add_child(light)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 10.8
	cam.position = Vector3(3, 13, 12)
	add_child(cam)
	cam.look_at(Vector3(0, 0, 0.5))
	cam.make_current()
	add_child((load("res://modules/ui/opaque_scene_layer.tscn") as PackedScene).instantiate())
	_build_navigation()
	player = Node3D.new()
	player.name = "Player"
	add_child(player)
	rig = Avatar.create_rig()
	rig.assembler = AvatarAssemblerMerged.new()
	for child in rig.get_children():
		if child is RigActivity:
			child.reduced_distance = 50
			child.sleep_distance = 80
	player.add_child(rig)
	rig.config_applied.connect(func(_config): _play("idle"))
	rig.apply_config(Avatar.load_outfit())
	player.position = mover.position + NAV_ORIGIN

func _build_navigation() -> void:
	var previous := mover.position if mover else Vector3(5, 0, -0.4)
	nav = _navigation_blueprint(_resident_positions())
	nav.anchors = {"spawn": nav.world_to_cell(previous)}
	if not nav.is_walkable(nav.anchors.spawn): nav.anchors.spawn = Vector2i(12, 2)
	mover = PlayerMover.new(nav, BlueprintGrid.new(nav))
	if nav.is_walkable(nav.world_to_cell(previous)): mover.position = previous

func _resident_positions(exclude := "") -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for id in ResidentCast.present(place_id, session.state):
		if id == exclude: continue
		var actor := cast.get_node_or_null(NodePath(str(id))) as Node3D if is_instance_valid(cast) else null
		positions.append(actor.position if actor else ResidentCast.journey_position(place_id, str(id)))
	return positions

func _navigation_blueprint(residents: Array[Vector3]) -> FarmBlueprint:
	var blueprint := FarmBlueprint.new()
	var harvest_positions: Array[Vector3] = []
	for id in JourneyProgress.data().discoveries:
		if JourneyProgress.data().discoveries[id].place != place_id: continue
		for choice in JourneyProjects.discovery_choices(str(id), session.state): harvest_positions.append(choice.position)
	var terrace_open := place_id == "bistro" and JourneyProgress.project_complete(session.state, "terrace")
	var terrace_posts := place_id == "bistro" and JourneyProgress.project_stage(session.state, "terrace") > 0
	blueprint.grid = Vector2i(25, 20)
	blueprint.cell_m = 0.4
	blueprint.masks = {"walkable": []}
	for z in blueprint.grid.y:
		var row := ""
		for x in blueprint.grid.x:
			var p := blueprint.cell_to_world(Vector2i(x, z)) + NAV_ORIGIN
			var blocked := p.z < -0.1 or p.x * p.x / 25.0 + p.z * p.z / 16.0 > 0.98
			if terrace_open \
					and p.x > 0.25 and p.x < 3.95 and p.z > -2.75 and p.z < -0.1:
				blocked = false
			if place_id == "nursery" and p.x > 3.5 and p.z < 0.95:
				blocked = not (JourneyProgress.fact(session.state, "side_path") and p.x > 3.95 and p.x < 4.7 and p.z > -1.85)
			if absf(absf(p.x) - 3.1) < 0.75 and absf(p.z - 1.65) < 0.45: blocked = true
			if place_id == "nursery" and absf(p.x + 1.55) < 0.9 and absf(p.z - 1) < 0.5: blocked = true
			if place_id == "bistro":
				for table_z in [0.3, -1.65]:
					if absf(p.x - 2.0) < 0.8 and absf(p.z - table_z) < 0.65: blocked = true
					for chair_x in [1.19, 2.81]:
						if absf(p.x - chair_x) < 0.43 and absf(p.z - table_z) < 0.45: blocked = true
				if terrace_posts:
					for post_x in [1.0, 3.0]:
						if Vector2(p.x - post_x, p.z + 2.15).length() < 0.28: blocked = true
			if place_id == "courtyard": blocked = blocked or (absf(p.x) > 1.3 and absf(p.x) < 3.1 and p.z < 0.85)
			for resident in residents:
				if p.distance_to(resident) < RESIDENT_CLEARANCE: blocked = true
			if place_id == "courtyard":
				for prop in DecorationLayout.saved(session.state):
					if p.distance_to(DecorationLayout.world_position(prop)) < 0.55: blocked = true
			if JourneyProgress.fact(session.state, "planter_crafted"):
				for id in JourneyProgress.data().discoveries:
					if JourneyProgress.data().discoveries[id].place == place_id \
							and p.distance_to(JourneyProjects.discovery_position(str(id))) < 0.7: blocked = true
			for position in harvest_positions:
				if Vector2(p.x - position.x, p.z - position.z).length() < 0.42: blocked = true
			for id in JourneyProgress.data().projects:
				if JourneyProgress.data().projects[id].place != place_id: continue
				var items := JourneyProgress.display_items(session.state, str(id))
				for slot in items.size():
					if not str(items[slot]).is_empty() and p.distance_to(JourneyProjects.display_position(str(id), slot)) < 0.38:
						blocked = true
			row += "0" if blocked else "1"
		blueprint.masks.walkable.append(row)
	return blueprint

func _build_ui() -> void:
	canvas = CanvasLayer.new()
	add_child(canvas)
	header_backdrop = Panel.new()
	header_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := GameUi.surface(Color(0.988, 0.996, 0.98, 0.94), 0, 0)
	backdrop.set_border_width_all(0)
	header_backdrop.add_theme_stylebox_override("panel", backdrop)
	var safe := SafeAreaMargin.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.theme = GameUi.theme()
	canvas.add_child(safe)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(ui)
	ui.add_child(header_backdrop)
	ui.resized.connect(_layout)
	marker_layer = Control.new()
	marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(marker_layer)
	ground_feedback = PlotHints.new()
	ground_feedback.name = "GroundFeedback"
	ground_feedback.cam = cam
	ground_feedback.path_origin = NAV_ORIGIN
	ui.add_child(ground_feedback)
	header = VBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ui.add_child(header)
	header.resized.connect(_layout)
	var row := HBoxContainer.new()
	header.add_child(row)
	var back := GameUi.button("arrow-left", "", "Return")
	back.pressed.connect(_leave)
	row.add_child(back)
	var title := GameUi.label(str(PlaceCatalog.find(place_id).name), 17)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	display_done = GameUi.button("check", "", "Finish arranging")
	display_done.visible = false
	display_done.pressed.connect(_finish_display)
	row.add_child(display_done)
	var bag := GameUi.button("backpack", "", "Neighbourhood supplies")
	bag.pressed.connect(func(): _show_panel("board"))
	row.add_child(bag)
	status = GameUi.label("", 13, GameUi.GREEN)
	header.add_child(status)
	objective = GameUi.label("", 13)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var goal_row := HBoxContainer.new()
	header.add_child(goal_row)
	goal_row.add_child(objective)
	follow_goal = GameUi.button("compass", "", "Go to current goal")
	follow_goal.name = "FollowGoal"
	follow_goal.pressed.connect(_follow_goal)
	goal_row.add_child(follow_goal)
	panel = PanelContainer.new()
	panel.visible = false
	ui.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var close_row := HBoxContainer.new()
	col.add_child(close_row)
	feedback = GameUi.label("", 12, GameUi.GREEN)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_row.add_child(feedback)
	var close := GameUi.button("x", "", "Close")
	close.pressed.connect(_close_panel)
	close_row.add_child(close)
	panel_scroll = ScrollContainer.new()
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel_scroll)
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -48
	ui.add_child(footer)
	farm_return = GameUi.button("sprout", "My farm", "Return to your farm")
	farm_return.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	farm_return.clip_text = true
	farm_return.pressed.connect(_go_farm)
	footer.add_child(farm_return)
	var map_button := GameUi.button("map", "", "Neighbourhood map")
	map_button.pressed.connect(_go_map)
	footer.add_child(map_button)
	world_notice = PanelContainer.new()
	world_notice.name = "WorldResult"
	world_notice.theme_type_variation = &"ToastPanel"
	world_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_notice.visible = false
	world_notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	world_notice.offset_top = -128
	world_notice.offset_bottom = -56
	ui.add_child(world_notice)
	world_notice_label = GameUi.label("", 13, GameUi.PAPER)
	world_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	world_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	world_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	world_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_notice.add_child(world_notice_label)
	call_deferred("_layout")

func _layout() -> void:
	if panel == null: return
	var viewport_size := get_viewport().get_visible_rect().size
	_update_camera()
	var compact_editor := active_panel is DecorationPanel and not (active_panel as DecorationPanel)._confirm_leave
	var object_actions := selected_target.begins_with("display:") or selected_target.begins_with("project_") \
		or selected_target == "resident" or selected_target.begins_with("resident:")
	var h := minf(190 if compact_editor else 290, ui.size.y * (0.44 if object_actions else 0.39))
	if selected_target == "workbench" and JourneyProgress.fact(session.state, "planter_crafted"):
		h = minf(310, ui.size.y * 0.49)
	panel.position = Vector2(0, ui.size.y - h - 56)
	panel.size = Vector2(ui.size.x, h)
	header_backdrop.position = -ui.global_position
	header_backdrop.size = Vector2(viewport_size.x, header.global_position.y + header.size.y + 8)
	_sync_markers()

func _update_camera() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	cam.size = maxf(10.8, viewport_size.x / maxf(viewport_size.y, 1) * 12.5) / camera_pan.zoom
	cam.position = Vector3(3, 13, 12) + camera_pan.offset

func _changed(_state: Dictionary, _version: int) -> void:
	call_deferred("_refresh")

func _refresh() -> void:
	if not is_inside_tree(): return
	var plan := JourneyWorkshop.planned(session.state)
	if plan != _display_plan:
		# Recovery can confirm a plan without replaying the panel's success callback.
		_display_plan = plan.duplicate(true)
		display_project = ""
		display_done.hide()
	_refresh_farm_hint()
	status.text = "%d coins / %d wood / %d stone / %d reeds%s" % [int(session.state.wallet), int(session.state.journey.wood), JourneyProgress.material(session.state, "stone"), JourneyProgress.material(session.state, "fiber"), " / Offline" if session.offline else ""]
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh_goal()
	var key := JSON.stringify([session.state.journey, session.state.get("decorations", []), session.state.nursery, session.state.inventory.dishes])
	if key == _world_key: return
	_world_key = key
	var prop_key := JSON.stringify(session.state.get("decorations", []))
	var navigation_key := JSON.stringify([prop_key, session.state.journey.get("workshop", {}).get("displays", {}),
		JourneyProgress.fact(session.state, "planter_crafted"), JourneyProgress.fact(session.state, "side_path"),
		session.state.journey.facts.filter(func(fact): return str(fact).begins_with("discovery_")),
		JourneyProgress.unlocked(session.state, "crop_H"), ResidentCast.present(place_id, session.state)])
	if navigation_key != _nav_props_key:
		_nav_props_key = navigation_key
		_build_navigation()
	for old in [objects]:
		if is_instance_valid(old):
			remove_child(old)
			old.queue_free()
	for button in marker_layer.get_children():
		marker_layer.remove_child(button)
		button.queue_free()
	targets.clear()
	var scenery_key := JSON.stringify(session.state.nursery)
	if not is_instance_valid(scenery) or scenery_key != _scenery_key:
		_scenery_key = scenery_key
		if is_instance_valid(scenery):
			remove_child(scenery)
			scenery.queue_free()
		scenery = PlaceScenery.build(place_id, session.state, true)
		add_child(scenery)
	var cast_key := JSON.stringify(ResidentCast.present(place_id, session.state))
	if not is_instance_valid(cast) or cast_key != _cast_key:
		_cast_key = cast_key
		if is_instance_valid(cast):
			remove_child(cast)
			cast.queue_free()
		cast = ResidentCast.build(place_id, session.state)
		add_child(cast)
		meal_moment = null
		resident_moments.clear()
		resident_activities.clear()
		_meal_residents.clear()
		for actor in cast.get_children(): resident_moments[str(actor.name)] = ResidentMoment.new(actor, NAV_ORIGIN)
		_build_navigation()
	objects = Node3D.new()
	add_child(objects)
	var decorations_key := JSON.stringify([prop_key, JourneyProgress.fact(session.state, "planter_planted")])
	if not is_instance_valid(decorations) or decorations_key != _decorations_key:
		_decorations_key = decorations_key
		if is_instance_valid(decorations):
			remove_child(decorations)
			decorations.queue_free()
		decorations = DecorationLayout.build(DecorationLayout.saved(session.state), "", JourneyProgress.fact(session.state, "planter_planted")) if place_id == "courtyard" else Node3D.new()
		add_child(decorations)
	for resident in cast.get_children():
		var id := "resident" if resident.name == JourneyActivityPanel.RESIDENTS[place_id] else "resident:" + str(resident.name)
		_add_target(id, "Talk" if id == "resident" else "Talk to " + str(ResidentCast.definition(str(resident.name)).name), "message-circle",
			resident.position + Vector3(0, 2.96, 0), resident.position + Vector3(-0.2, 0, 0.85))
		targets[id].resident = str(resident.name)
		targets[id].body = resident.position + Vector3(0, 1.35, 0)
	for node in JourneyProgress.remaining_nodes(session.state, place_id):
		if JourneyProgress.street_supplies(session.state, place_id): continue
		var bundles := JourneyProgress.node_bundles(session.state, node)
		for bundle in bundles:
			var pos := Vector3(float(bundle.position[0]), 0, float(bundle.position[1]))
			_resource_pile(pos, bundle.materials)
			var approach := Vector3(4.2, 0, 0.1) if str(bundle.id) == "side_path" else pos - pos.normalized() * 0.65
			var label := JourneyProgress.material_label(bundle.materials)
			_add_target(str(bundle.id), ("Take " if bundles.size() > 1 else "Gather ") + label, "axe", pos + Vector3(0, 0.45, 0), approach)
			targets[bundle.id].bundle = bundle
			if bundles.size() > 1:
				targets[bundle.id].badge = false
				targets[bundle.id].body = pos + Vector3(0, 0.55, 0)
				_add_target_caption(str(bundle.id), label.replace(" + ", "\n"))
	var trail: String = {"nursery": "woodland", "bistro": "gardens", "courtyard": "riverside"}[place_id]
	if JourneyProgress.route_ready(session.state, trail) or JourneyProgress.street_supplies(session.state, place_id):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pos := Vector3(3.65, 0, 2.7)
		PlaceScenery._box(surface, Vector3(0.09, 0.9, 0.09), pos + Vector3(0, 0.45, 0), PlaceScenery.WOOD)
		PlaceScenery._box(surface, Vector3(0.65, 0.3, 0.08), pos + Vector3(0, 0.85, 0), PlaceScenery.GREEN)
		objects.add_child(_mesh(surface, "TrailSign"))
		var trail_name := str(JourneyProgress.route_for(session.state, place_id).name) if JourneyProgress.street_supplies(session.state, place_id) else str(JourneyProgress.data().routes[trail].name)
		_add_target("trail", trail_name, "route", pos + Vector3(0, 1.15, 0), pos - pos.normalized() * 0.7)
	for id in JourneyProgress.data().projects:
		var spec: Dictionary = JourneyProgress.data().projects[id]
		if spec.place != place_id: continue
		var project := JourneyProjects.build(str(id), session.state)
		objects.add_child(project)
		var display := Node3D.new()
		display.name = "Handmade_" + str(id)
		objects.add_child(display)
		var items := JourneyProgress.display_items(session.state, str(id))
		for index in items.size():
			var item := str(items[index])
			var preview := JourneyWorkshop.preview_item(session.state, str(id), index) if item.is_empty() else ""
			if item.is_empty() and preview.is_empty() and display_project != str(id): continue
			var visual_item := item if not item.is_empty() else preview
			var piece := DecorationLayout._prop(visual_item) if not visual_item.is_empty() else _display_pad()
			if not preview.is_empty():
				var material := piece.material_override as StandardMaterial3D
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color.a = 0.45
				piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				piece.set_meta("planned_item", preview)
			piece.name = "Display_%d_%s" % [index, items[index]]
			piece.position = JourneyProjects.display_position(str(id), index)
			piece.scale = Vector3.ONE * 0.7
			display.add_child(piece)
			var label := str(JourneyProgress.data().workshop.recipes[item].name) if not item.is_empty() else "Empty display %d" % (index + 1)
			if not preview.is_empty(): label = "Planned " + str(JourneyProgress.data().workshop.recipes[preview].name)
			var target_id := "display:%s:%d" % [id, index]
			_add_target(target_id, label, "plus" if preview.is_empty() else "hammer", piece.position + Vector3(0, 0.3, 0), piece.position + Vector3(-signf(piece.position.x) * 0.85, 0, 0.55))
			targets[target_id].body = piece.position + Vector3(0, 0.3, 0)
			targets[target_id].badge = item.is_empty()
		_add_target("project_" + str(id), str(spec.name), "sprout" if id == "seedbeds" else "hammer", project.position + Vector3(0, 1.1, 0), project.position + Vector3(0, 0, 1.5))
		if id == "terrace" and JourneyProgress.project_complete(session.state, "terrace"):
			targets.project_terrace.approach = _reachable_approach(Vector3(2, 0, -0.65))
	if JourneyProgress.fact(session.state, "planter_crafted"):
		for id in JourneyProgress.data().discoveries:
			var spec: Dictionary = JourneyProgress.data().discoveries[id]
			if spec.place != place_id: continue
			var discovery := JourneyProjects.build_discovery(str(id), session.state)
			objects.add_child(discovery)
			_add_target("discovery_" + str(id), str(spec.name), "sprout" if JourneyProgress.fact(session.state, "discovery_" + str(id)) else "compass",
				discovery.position + Vector3(0, 1.05, 0), discovery.position + Vector3(0, 0, 1.05))
			if JourneyProgress.discovery_harvest_ready(session.state, str(id)):
				targets["discovery_" + str(id)].badge = false
				for choice in JourneyProjects.discovery_choices(str(id), session.state):
					var pos: Vector3 = choice.position
					var label := JourneyProgress.discovery_reward_label(choice.reward)
					_add_target(str(choice.id), "Take %s / one harvest this trail" % label, "sprout", pos + Vector3(0, 1.05, 0), pos + Vector3(0, 0, 0.8))
					targets[choice.id].harvest = choice
					targets[choice.id].body = pos + Vector3(0, 0.45, 0)
					targets[choice.id].badge = false
					_add_target_caption(str(choice.id), label.replace(" + ", "\n").replace(" seeds", "\nseeds"))
	if place_id == "nursery":
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		if JourneyProgress.fact(session.state, "workbench"):
			PlaceScenery._blueprint_table(surface, Vector3(-1.55, 0, 1.0))
		else:
			PlaceScenery._box(surface, Vector3(1.5, 0.12, 0.8), Vector3(-1.55, 0.24, 1), PlaceScenery.WOOD)
			PlaceScenery._beam(surface, Vector3(-2.1, 0.1, 1.4), Vector3(-1.3, 0.4, 0.65), 0.12, PlaceScenery.WOOD)
		objects.add_child(_mesh(surface, "Workbench"))
		_add_target("workbench", "Workbench", "hammer", Vector3(-1.55, 0.95, 1), Vector3(-1.55, 0, 1.95))
		_build_side_path()
	elif place_id == "bistro":
		_add_target("counter", "Prepare a meal", "utensils", Vector3(-1.1, 1, -0.7), Vector3(-1.1, 0, 0.6))
		_add_target("table", "Share a meal", "heart", Vector3(2, 1, 0.3), Vector3(2, 0, 1.35))
		var dishes: Dictionary = session.state.inventory.dishes
		if int(dishes.get("salad", 0)) + int(dishes.get("tea", 0)) > 0:
			var dish_mesh := _dish_mesh("salad" if int(dishes.get("salad", 0)) > 0 else "tea", "PreparedDish")
			dish_mesh.position = Vector3(-0.85, 0.96, -0.35)
			objects.add_child(dish_mesh)
	else:
		_add_target("planter", "Your courtyard", "move", Vector3(-2.7, 0.8, 2.4), Vector3(-1.7, 0, 2.8))
	_add_target("exit", "Street exit", "map", Vector3(1.05, 1.45, 3.7), Vector3(0.4, 0, 3.5))
	_refresh_goal()
	_sync_markers()

func _mesh(surface: SurfaceTool, object_name: String) -> MeshInstance3D:
	surface.index()
	var mesh := MeshInstance3D.new()
	mesh.name = object_name
	mesh.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	mesh.material_override = material
	return mesh

func _display_pad() -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	PlaceScenery._cylinder(surface, 0.43, 0.035, Vector3.ZERO, PlaceScenery.PAPER)
	return _mesh(surface, "EmptyDisplay")

func _build_side_path() -> void:
	var opened := JourneyProgress.fact(session.state, "side_path")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step in 7:
		PlaceScenery._box(surface, Vector3(0.85, 0.025, 0.36), Vector3(4.25, 0.015, 0.95 - step * 0.43), PlaceScenery.STONE)
	for side in [3.85, 4.78]:
		PlaceScenery._box(surface, Vector3(0.1, 0.7, 0.1), Vector3(side, 0.35, 0.55), PlaceScenery.WOOD)
	if not opened:
		for height in [0.28, 0.55]:
			PlaceScenery._box(surface, Vector3(0.95, 0.12, 0.13), Vector3(4.3, height, 0.55), PlaceScenery.WOOD)
		_add_target("path", "Garden side path", "route", Vector3(4.25, 0.85, 0.55), Vector3(4.2, 0, 1.2))
	else:
		PlaceScenery._box(surface, Vector3(0.08, 1.0, 0.08), Vector3(3.85, 0.5, -0.9), PlaceScenery.WOOD)
		PlaceScenery._box(surface, Vector3(0.7, 0.25, 0.08), Vector3(3.85, 0.9, -0.9), PlaceScenery.GREEN)
		_add_target("path", "Courtyard via side path", "route", Vector3(3.85, 1.45, -0.9), Vector3(4.2, 0, -1.5))
	objects.add_child(_mesh(surface, "GardenSidePath"))

func _log_pile(pos: Vector3) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		PlaceScenery._beam(surface, pos + Vector3(-0.32, 0.12 + i * 0.10, -0.12), pos + Vector3(0.34, 0.12 + i * 0.1, 0.13), 0.12, PlaceScenery.WOOD)
	objects.add_child(_mesh(surface, "Timber"))

func _resource_pile(pos: Vector3, materials: Dictionary) -> void:
	if int(materials.get("wood", 0)) > 0: _log_pile(pos)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if materials.has("stone"):
		for i in 3: PlaceScenery._oval(surface, Vector3(0.28, 0.24, 0.24), pos + Vector3(-0.34 + i * 0.26, 0.18, 0.35), PlaceScenery.STONE.darkened(0.2))
	elif materials.has("fiber"):
		for i in 5: PlaceScenery._beam(surface, pos + Vector3(-0.3 + i * 0.15, 0, 0.3), pos + Vector3(-0.4 + i * 0.18, 0.85, 0.35), 0.04, PlaceScenery.LEAF)
	else: return
	objects.add_child(_mesh(surface, "Supplies"))

func _reachable_approach(approach: Vector3) -> Vector3:
	var cell := nav.world_to_cell(approach - NAV_ORIGIN)
	# An empty cell can still be isolated between furniture and a resident.
	if mover.grid.point_path(mover.position, nav.cell_to_world(cell)).is_empty():
		var closest := INF
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				var candidate := cell + Vector2i(dx, dz)
				var distance := Vector2(dx, dz).length_squared()
				if nav.is_walkable(candidate) and distance < closest:
					if mover.grid.point_path(mover.position, nav.cell_to_world(candidate)).is_empty(): continue
					closest = distance
					approach = nav.cell_to_world(candidate) + NAV_ORIGIN
	else:
		approach = nav.cell_to_world(cell) + NAV_ORIGIN
	return approach

func _add_target(id: String, label: String, icon: String, world: Vector3, approach: Vector3) -> void:
	approach = _reachable_approach(approach)
	var button := GameUi.button("", "", label)
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.name = "Target_" + id
	button.custom_minimum_size = Vector2(44, 44)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var badge := Panel.new()
	badge.name = "Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(8, 8)
	badge.size = Vector2(28, 28)
	var style := GameUi.surface(GameUi.PAPER, 0, 14)
	style.shadow_color = Color(0.1, 0.2, 0.15, 0.14)
	style.shadow_size = 2
	badge.add_theme_stylebox_override("panel", style)
	button.add_child(badge)
	var symbol := GameUi.picture(GameUi.icon(icon), 16)
	symbol.self_modulate = GameUi.INK
	symbol.position = Vector2(6, 6)
	symbol.size = Vector2(16, 16)
	badge.add_child(symbol)
	badge.self_modulate = GameUi.MINT if id == _tracked_target else Color.WHITE
	button.mouse_entered.connect(func(): badge.modulate = GameUi.MINT)
	button.mouse_exited.connect(func(): badge.modulate = Color.WHITE)
	button.pressed.connect(func(): select_target(id))
	marker_layer.add_child(button)
	# Resolve the scene theme before sizing; the project theme has larger padding.
	button.size = Vector2(44, 44)
	targets[id] = {"world": world, "body": world - Vector3(0, 0.45, 0), "approach": approach, "button": button, "label": label, "badge": true}

func _add_target_caption(id: String, text: String) -> void:
	var caption := GameUi.label(text, 11)
	caption.name = "BundleLabel_" + id
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_outline_color", GameUi.PAPER)
	caption.add_theme_constant_override("outline_size", 5)
	marker_layer.add_child(caption)
	caption.size = caption.get_combined_minimum_size()
	targets[id].caption = caption

func _sync_markers() -> void:
	if cam == null or not cam.is_inside_tree() or ui == null or ui.size.y < header.size.y + 100: return
	var head := cam.unproject_position(player.position + Vector3(0, 1.0, 0)) - marker_layer.global_position
	var area := Rect2(0, header.size.y + 8, ui.size.x, ui.size.y - header.size.y - 64)
	for id in targets:
		var target: Dictionary = targets[id]
		if target.has("resident"):
			var actor := cast.get_node_or_null(NodePath(str(target.resident))) as Node3D
			if actor:
				target.world = actor.position + Vector3(0, 2.96, 0)
				target.body = actor.position + Vector3(0, 1.35, 0)
		var button: Button = target.button
		var anchor := cam.unproject_position(target.world) - marker_layer.global_position
		button.position = anchor - button.size * 0.5
		button.modulate.a = lerpf(0.38, 0.86, smoothstep(14, 65, anchor.distance_to(head)))
		var in_mode := display_project.is_empty() or str(id).begins_with("display:" + display_project + ":")
		var serving: bool = id == served_target and _meal_left > 0
		if target.has("resident"):
			var activity := str(resident_activities.get(str(target.resident), ""))
			button.tooltip_text = str(target.label) + (": " + activity if not activity.is_empty() else "")
		button.visible = bool(target.badge) and not serving and in_mode and not panel.visible and area.encloses(button.get_rect()) and not cam.is_position_behind(target.world)
		button.disabled = busy or session.offline or session.has_unconfirmed_command()
		button.get_node("Badge").self_modulate = GameUi.MINT if id == _tracked_target or id == _pressed_target else Color.WHITE
		if target.has("caption"):
			var caption: Label = target.caption
			caption.position = anchor - Vector2(caption.size.x * 0.5, caption.size.y)
			caption.modulate.a = button.modulate.a
			caption.visible = in_mode and not panel.visible and area.encloses(caption.get_rect()) and not cam.is_position_behind(target.world)

func select_target(id: String) -> bool:
	if busy or not targets.has(id) or session.offline or session.has_unconfirmed_command(): return false
	_close_panel()
	if panel.visible: return false
	_build_navigation()
	var target: Dictionary = targets[id]
	if target.has("resident"):
		var actor := cast.get_node_or_null(NodePath(str(target.resident))) as Node3D
		if actor: target.approach = actor.position + Vector3(-0.2, 0, 0.85)
	target.approach = _reachable_approach(target.approach)
	var cell := nav.world_to_cell(target.approach - NAV_ORIGIN)
	if not mover.set_target_cell(cell):
		ground_feedback.destination(target.approach, false, [])
		objective.text = "That spot is not reachable"
		return false
	pending_target = id
	ground_feedback.destination(nav.cell_to_world(cell) + NAV_ORIGIN, true, mover.remaining_path())
	objective.text = str(target.label)
	return true

func _process(dt: float) -> void:
	_farm_hint_elapsed += dt
	if _farm_hint_elapsed >= 1.0: _refresh_farm_hint()
	if _world_notice_left > 0:
		_world_notice_left = maxf(0, _world_notice_left - dt)
		world_notice.visible = _world_notice_left > 0
	if mover == null: return
	if busy or (panel.visible and not active_panel is DecorationPanel): camera_pan.cancel()
	camera_pan.step(dt, cam)
	_update_camera()
	mover.step(dt)
	player.position = mover.position + NAV_ORIGIN
	if mover.is_moving():
		rig.rotation.y = atan2(mover.facing.x, mover.facing.z)
		_play("run")
	elif not busy:
		_play("idle")
		if not pending_target.is_empty():
			var id := pending_target
			pending_target = ""
			_arrived(id)
			# Arriving at the exit can remove this scene during the current frame.
			if not is_inside_tree(): return
	_step_meal(dt)
	_sync_markers()
	ground_feedback.world_rect = Rect2(0, header.size.y + 8, ui.size.x, ui.size.y - header.size.y - 64)
	ground_feedback.visible = not panel.visible
	ground_feedback.update_motion(mover.is_moving(), mover.remaining_path(), dt)

func _refresh_farm_hint() -> void:
	_farm_hint_elapsed = 0.0
	if farm_return == null or session == null: return
	var hint := JourneyProgress.farm_hint(JourneyProgress.goal_state(session), session.server_now())
	farm_return.text = "My farm" if hint.is_empty() else "My farm: " + hint
	if pending_target.is_empty(): _refresh_goal()

func _refresh_goal() -> void:
	if objective == null or follow_goal == null: return
	var goal := JourneyProgress.next_goal(JourneyProgress.goal_state(session), session.server_now())
	objective.text = JourneyProgress.goal_label(goal)
	follow_goal.visible = not goal.is_empty() and (goal.get("surface") == "street" or goal.get("place") != place_id or targets.has(str(goal.get("target", ""))))
	follow_goal.disabled = busy or session.offline or session.has_unconfirmed_command()
	_tracked_target = str(goal.get("target", "")) if goal.get("place") == place_id and goal.get("surface") != "street" else ""
	for id in targets:
		var badge := targets[id].button.get_node_or_null("Badge") as Panel
		if badge: badge.self_modulate = GameUi.MINT if id == _tracked_target else Color.WHITE

func _follow_goal() -> void:
	_go_goal(JourneyProgress.next_goal(JourneyProgress.goal_state(session), session.server_now()))

func _go_goal(goal: Dictionary) -> void:
	if goal.is_empty() or busy or session.offline or session.has_unconfirmed_command(): return
	if goal.get("surface") == "street": _go_place("street", str(goal.get("target", "")))
	elif goal.place == "farm": _go_farm(str(goal.get("crop", "")) if goal.get("action") == "stall" else "")
	elif goal.place != place_id: _go_place(str(goal.place), str(goal.get("target", "")))
	elif goal.has("target"):
		if _prepare_destination(_go_goal.bind(goal)): select_target(str(goal.target))

func _play(id: String) -> void:
	var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(id) and ap.current_animation != id: ap.play(id)

func _arrived(id: String) -> void:
	if not targets.has(id): return
	if id == "exit":
		_go_street()
		return
	if id == "path" and JourneyProgress.fact(session.state, "side_path"):
		_go_place("courtyard")
		return
	var direction: Vector3 = targets[id].world - player.position
	rig.rotation.y = atan2(direction.x, direction.z)
	if id.begins_with("project_") or id.begins_with("discovery_") or id.begins_with("display:") or id.begins_with("resident:") or id in ["resident", "workbench", "counter", "table", "path", "planter", "board", "trail"]:
		var resident_id := str(targets[id].get("resident", ""))
		if not resident_id.is_empty():
			var resident := cast.get_node(NodePath(resident_id)) as Node3D
			var toward := player.position - resident.position
			resident.rotation.y = atan2(toward.x, toward.z)
		_show_panel(id)
		if not resident_id.is_empty() and active_panel:
			await active_panel.command("talk_to_resident", {"resident_id": resident_id}, "")
		return
	busy = true
	var round_id := int(session.state.journey.exploration.round)
	var target: Dictionary = targets[id]
	var harvest: Dictionary = target.get("harvest", {})
	var bundle: Dictionary = target.get("bundle", {})
	var materials: Dictionary = harvest.reward.materials if not harvest.is_empty() else bundle.materials
	_play("labour_harvest" if not harvest.is_empty() else ("labour_till" if materials.has("stone") else ("labour_sow" if materials.has("fiber") else "labour_clear")))
	await get_tree().create_timer(0.9).timeout
	var accepted := await session.send("harvest_journey_discovery", {"discovery": harvest.discovery, "choice": harvest.choice, "round": round_id}) if not harvest.is_empty() \
		else await session.send("collect_resource", {"node_id": bundle.node, "round": round_id, "choice": bundle.choice})
	busy = false
	if not is_inside_tree(): return
	_play("idle")
	if accepted:
		world_notice_label.text = "+" + (JourneyProgress.discovery_reward_label(harvest.reward) if not harvest.is_empty() else JourneyProgress.material_label(materials))
		_world_notice_left = 4.0
		world_notice.show()
	else:
		_show_panel("discovery_" + str(harvest.discovery) if not harvest.is_empty() else "board")
		feedback.text = SessionPanel.error_text(session.last_error_code)
	_refresh()

func _show_panel(id: String) -> void:
	if busy or (active_panel and active_panel.busy): return
	if active_panel is DecorationPanel and (active_panel as DecorationPanel).request_leave(): return
	world_notice.hide()
	_world_notice_left = 0
	pending_target = ""
	mover.stop()
	if active_panel:
		panel_scroll.remove_child(active_panel)
		active_panel.queue_free()
	selected_target = id
	var activity := JourneyActivityPanel.new()
	activity.target = id
	activity.place_id = place_id
	activity.message = feedback
	activity.setup(session)
	activity.arrangement_requested.connect(_arrange)
	activity.display_arrangement_requested.connect(_arrange_display)
	activity.display_plan_changed.connect(_finish_display)
	activity.destination_requested.connect(_go_place)
	activity.target_requested.connect(select_target)
	activity.goal_requested.connect(_go_goal)
	activity.world_action_completed.connect(_world_action)
	activity.meal_served.connect(_meal_served)
	activity.terrace_served.connect(_meal_served.bind("project_terrace"))
	active_panel = activity
	panel_scroll.add_child(activity)
	feedback.text = ""
	panel_scroll.scroll_vertical = 0
	panel.show()
	_layout()
	_sync_markers()

func _arrange_display(project: String) -> void:
	_close_panel()
	if panel.visible: return
	display_project = project
	display_done.show()
	_world_key = ""
	_refresh()

func _finish_display() -> void:
	_close_panel()
	if panel.visible: return
	display_project = ""
	display_done.hide()
	_world_key = ""
	_refresh()

func _go_place(id: String, target_id := "") -> void:
	if not _prepare_destination(_go_place.bind(id, target_id)): return
	var shared_session := session
	while AppRouter.instance_depth() > 0: AppRouter.pop_instance()
	if id == "street": AppRouter.push_instance(AppRouter.STREET, {"session": shared_session, "from": place_id, "target": target_id, "walk_place": "" if target_id.begins_with("gathering:") else place_id})
	else: AppRouter.push_instance(AppRouter.PLACE, {"place_id": id, "session": shared_session, "target": target_id})

func _world_action(id: String) -> void:
	var result := feedback.text
	_close_panel()
	_refresh()
	if not result.is_empty() and not panel.visible:
		world_notice_label.text = result
		_world_notice_left = 6.0
		world_notice.show()
	var project := objects.get_node_or_null("Project_" + id.trim_prefix("project_")) as Node3D
	if id.begins_with("discovery_"): project = objects.get_node_or_null("Discovery_" + id.trim_prefix("discovery_")) as Node3D
	if id == "counter": project = objects.get_node_or_null("PreparedDish") as Node3D
	if id.begins_with("display:"):
		var parts := id.split(":")
		var item := str(JourneyProgress.display_items(session.state, str(parts[1]))[int(parts[2])])
		project = objects.get_node_or_null("Handmade_%s/Display_%d_%s" % [parts[1], int(parts[2]), item]) as Node3D
	if project:
		var resting_scale := project.scale
		project.scale = resting_scale * Vector3(0.92, 0.75, 0.92)
		create_tween().tween_property(project, "scale", resting_scale, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _dish_mesh(dish: String, object_name: String) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	PlaceScenery._cylinder(surface, 0.3, 0.025, Vector3.ZERO, PlaceScenery.PAPER)
	if dish == "salad":
		PlaceScenery._oval(surface, Vector3(0.45, 0.14, 0.38), Vector3(0, 0.09, 0), PlaceScenery.GREEN)
		for offset in [Vector3(-0.12, 0.16, 0.03), Vector3(0.06, 0.15, -0.07), Vector3(0.1, 0.16, 0.1)]:
			PlaceScenery._cylinder(surface, 0.055, 0.035, offset, PlaceScenery.CORAL)
	else:
		PlaceScenery._cylinder(surface, 0.14, 0.21, Vector3(0, 0.1, 0), PlaceScenery.CORAL)
		PlaceScenery._cylinder(surface, 0.11, 0.01, Vector3(0, 0.21, 0), PlaceScenery.WOOD.darkened(0.2))
	return _mesh(surface, object_name)

func _meal_served(dish: String, target := "table") -> void:
	if place_id != "bistro" or dish not in ["salad", "tea"]: return
	if is_instance_valid(served_dish):
		remove_child(served_dish)
		served_dish.queue_free()
	served_recipe = dish
	served_target = target
	served_dish = _dish_mesh(dish, "ServedMeal")
	served_dish.position = Vector3(2, 0.96, -1.65 if target == "project_terrace" else 0.3)
	add_child(served_dish)
	_meal_left = 8.0
	for moment in resident_moments.values(): moment.finish()
	_meal_residents.clear()
	_activity_wait = 8.0
	var host := cast.get_node_or_null("bistro_owner") as Node3D
	if host:
		meal_moment = resident_moments.bistro_owner
		meal_moment.start(Vector3(0.7, 0.04, -0.7) if target == "project_terrace" else Vector3(0.6, 0.04, 1.6), served_dish.position)
		_meal_residents.append("bistro_owner")
		resident_activities.bistro_owner = "Sharing " + dish
	if target == "project_terrace" and resident_moments.has("nursery_keeper"):
		var guest: ResidentMoment = resident_moments.nursery_keeper
		guest.start(Vector3(3.55, 0.04, -0.65), served_dish.position)
		_meal_residents.append("nursery_keeper")
		resident_activities.nursery_keeper = "Sharing " + dish

func _meal_route(destination: Vector3) -> PlayerMover:
	return _resident_route(destination, meal_moment)

func _resident_route(destination: Vector3, moment: ResidentMoment) -> PlayerMover:
	if moment == null or not is_instance_valid(moment.actor): return null
	var blockers := _resident_positions(str(moment.actor.name))
	blockers.append(player.position)
	var blueprint := _navigation_blueprint(blockers)
	var start := moment.actor.position - NAV_ORIGIN
	start.y = 0
	blueprint.anchors = {"spawn": blueprint.world_to_cell(start)}
	if not blueprint.is_walkable(blueprint.anchors.spawn): return null
	var movement := PlayerMover.new(blueprint, BlueprintGrid.new(blueprint))
	movement.position = start
	var goal := destination - NAV_ORIGIN
	goal.y = 0
	if movement.set_target_position(goal): return movement
	# Wait for the exact home position to clear; returning must not drift each meal.
	if moment.phase == "returning": return null
	var candidates: Array[Vector3] = []
	var cell := blueprint.world_to_cell(goal)
	for z in range(-2, 3):
		for x in range(-2, 3): candidates.append(blueprint.cell_to_world(cell + Vector2i(x, z)))
	candidates.sort_custom(func(a, b): return a.distance_squared_to(goal) < b.distance_squared_to(goal))
	for point in candidates:
		if movement.set_target_position(point): return movement
	return null

func _resident_step_clear(from: Vector3, to: Vector3, actor: Node3D) -> bool:
	var blockers := _resident_positions(str(actor.name))
	blockers.append(player.position)
	for point in blockers:
		var nearest := Geometry3D.get_closest_point_to_segment(point, from, to)
		if nearest.distance_to(point) < RESIDENT_CLEARANCE: return false
	return true

func _step_meal(dt: float) -> void:
	if _meal_left > 0:
		_meal_left = maxf(0, _meal_left - dt)
		if is_instance_valid(served_dish): served_dish.visible = _meal_left > 0
		if _meal_left == 0:
			for id in _meal_residents:
				if resident_moments.has(id): resident_moments[id].finish()
	var holding_resident: bool = camera_pan.active() and targets.get(_pressed_target, {}).has("resident")
	var paused := mover.is_moving() or not pending_target.is_empty() or busy or panel.visible or not display_project.is_empty() or holding_resident
	var active := false
	for id in resident_moments:
		var moment: ResidentMoment = resident_moments[id]
		moment.step(dt, paused, _resident_route.bind(moment), _resident_step_clear.bind(moment.actor))
		if moment.active(): active = true
		else: resident_activities.erase(id)
	if _meal_left > 0 or active or paused: return
	_meal_residents.clear()
	_activity_wait -= dt
	if _activity_wait > 0: return
	_activity_wait = 8.0
	var activities := ResidentCast.activities(place_id, session.state)
	if activities.is_empty(): return
	var activity: Dictionary = activities[_activity_index % activities.size()]
	_activity_index += 1
	var moment: ResidentMoment = resident_moments.get(activity.resident)
	if moment == null: return
	moment.start(activity.point, activity.facing, activity.animation, activity.seconds)
	resident_activities[activity.resident] = activity.label

func _arrange() -> void:
	if active_panel:
		panel_scroll.remove_child(active_panel)
		active_panel.queue_free()
	var editor := DecorationPanel.new()
	editor.compact = true
	editor.message = feedback
	editor.setup(session)
	editor.preview_changed.connect(_preview_decorations)
	editor.navigation_confirmed.connect(_arrangement_confirmed)
	editor.navigation_cancelled.connect(func():
		_pending_destination = Callable()
		_layout())
	active_panel = editor
	panel_scroll.add_child(editor)
	feedback.text = ""
	panel_scroll.scroll_vertical = 0
	_layout()

func _arrangement_confirmed() -> void:
	var destination := _pending_destination
	_pending_destination = Callable()
	_close_panel()
	if not panel.visible and destination.is_valid(): destination.call_deferred()

func _preview_decorations(props: Array) -> void:
	if decorations:
		remove_child(decorations)
		decorations.queue_free()
	decorations = DecorationLayout.build(props, (active_panel as DecorationPanel).selected_prop if active_panel is DecorationPanel else "", JourneyProgress.fact(session.state, "planter_planted"))
	add_child(decorations)

func _close_panel() -> void:
	if active_panel and active_panel.busy: return
	if active_panel is DecorationPanel and (active_panel as DecorationPanel).dirty:
		if (active_panel as DecorationPanel).request_leave():
			_layout()
			return
	panel.hide()
	selected_target = ""
	_sync_markers()

func _input(event: InputEvent) -> void:
	if _drag_prop:
		if event is InputEventScreenTouch and event.pressed and event.index != _pointer:
			# A second finger changes the gesture to a pinch, canceling the draft move.
			(active_panel as DecorationPanel).end_drag(true)
			camera_pan.begin(_pointer, _drag_last)
			camera_pan.begin(event.index, event.position)
			_drag_prop = false
			_pointer = -2
			get_viewport().set_input_as_handled()
		elif (event is InputEventScreenDrag and event.index == _pointer) or (event is InputEventMouseMotion and _pointer == -1):
			_dragged = _dragged or _press.distance_to(event.position) > 12
			_drag_last = event.position
			if _dragged: _move_prop_drag(event.position)
			get_viewport().set_input_as_handled()
		elif (event is InputEventScreenTouch and event.index == _pointer and not event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _pointer == -1):
			(active_panel as DecorationPanel).end_drag(event is InputEventScreenTouch and event.canceled)
			_drag_prop = false
			_pointer = -2
			get_viewport().set_input_as_handled()
		return
	if camera_pan.handle(event, cam):
		if not camera_pan.active() or camera_pan.dragged or camera_pan.multi: _pressed_target = null
		_update_camera()
		_sync_markers()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if busy or (panel.visible and not active_panel is DecorationPanel): return
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION):
		_press = event.position
		_drag_last = event.position
		_dragged = false
		_begin_prop_drag(event.position)
		if _drag_prop:
			camera_pan.cancel()
			_pointer = event.index if event is InputEventScreenTouch else -1
			get_viewport().set_input_as_handled()
			return
		_pressed_target = _pick_target(event.position)
	if camera_pan.handle(event, cam, true):
		_update_camera()
		_sync_markers()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pressed_target = null
		camera_pan.cancel()
		if _drag_prop and active_panel is DecorationPanel:
			(active_panel as DecorationPanel).end_drag(true)
		_drag_prop = false
		_pointer = -2

func _begin_prop_drag(screen: Vector2) -> void:
	_drag_prop = false
	if active_panel is DecorationPanel and panel.visible:
		var point = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
		if point is Vector3:
			_drag_prop = (active_panel as DecorationPanel).pick_at(point)
			if _drag_prop: (active_panel as DecorationPanel).begin_drag()

func _move_prop_drag(screen: Vector2) -> void:
	if not _drag_prop or not active_panel is DecorationPanel or not panel.visible: return
	if panel.get_global_rect().has_point(screen): return
	var point = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	if point is Vector3: (active_panel as DecorationPanel).place_at(point)

func _ground_tap(screen: Vector2) -> void:
	if busy or session.offline or session.has_unconfirmed_command(): return
	if screen.y < header.global_position.y + header.size.y + 8 or screen.y > ui.global_position.y + ui.size.y - 55: return
	var point = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	if not point is Vector3: return
	if active_panel is DecorationPanel and panel.visible:
		var editor := active_panel as DecorationPanel
		if not editor.pick_at(point): editor.place_at(point)
		return
	if panel.visible: return
	var hit: String = _pick_target(screen) if _pressed_target == null else str(_pressed_target)
	if not hit.is_empty():
		select_target(hit)
		return
	pending_target = ""
	_build_navigation()
	var reachable := mover.set_target_position(point - NAV_ORIGIN)
	ground_feedback.destination(point, reachable, mover.remaining_path())
	if not reachable: objective.text = "Can't reach that spot"

func _pick_target(screen: Vector2) -> String:
	var nearest := 28.0
	var hit := ""
	for id in targets:
		var button: Button = targets[id].button
		if not button.visible or button.disabled: continue
		if button.get_global_rect().has_point(screen):
			var distance := button.get_global_rect().get_center().distance_to(screen)
			if distance < nearest:
				nearest = distance
				hit = id
	for id in targets:
		if not display_project.is_empty() and not str(id).begins_with("display:" + display_project + ":"): continue
		if cam.is_position_behind(targets[id].body): continue
		var projected := cam.unproject_position(targets[id].body)
		var distance := projected.distance_to(screen)
		if distance < nearest:
			nearest = distance
			hit = id
	return hit

func is_back_navigation_locked() -> bool:
	if busy or (active_panel and active_panel.busy): return true
	if panel.visible:
		if active_panel is DecorationPanel and (active_panel as DecorationPanel).consume_back(): return true
		_close_panel()
		return true
	if not display_project.is_empty():
		_finish_display()
		return true
	return false

func _leave() -> void:
	if not is_back_navigation_locked(): AppRouter.pop_instance()

func _go_street() -> void:
	if not _prepare_destination(_go_street): return
	var shared_session := session
	var departure := place_id
	# A physical exit resumes the walk that brought the player here.
	while AppRouter.instance_depth() > 0:
		var street := AppRouter.top_instance() as JourneyStreet
		if street and street.session == shared_session: return
		AppRouter.pop_instance()
	AppRouter.push_instance(AppRouter.STREET, {"session": shared_session, "from": departure})

func _go_map() -> void:
	if not _prepare_destination(_go_map): return
	while AppRouter.instance_depth() > 0: AppRouter.pop_instance()

func _go_farm(seed_crop := "") -> void:
	if not _prepare_destination(_go_farm.bind(seed_crop)): return
	while AppRouter.instance_depth() > 0: AppRouter.pop_instance()
	AppRouter.push_instance(AppRouter.FARM, {"session": session, "seed_crop": seed_crop})

func _prepare_destination(destination := Callable()) -> bool:
	if busy or (active_panel and active_panel.busy): return false
	_pending_destination = destination if active_panel is DecorationPanel and (active_panel as DecorationPanel).dirty else Callable()
	_close_panel()
	return not panel.visible

func suspend() -> void:
	_pressed_target = null
	camera_pan.cancel()
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	canvas.hide()
	cam.current = false
	world_env.environment = null

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	canvas.show()
	world_env.environment = environment
	cam.make_current()
	_refresh()
