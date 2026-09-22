class_name JourneyStreet
extends Node3D

const NAMES := {"farm": "My farm", "nursery": "Nursery", "bistro": "Bistro", "courtyard": "Courtyard"}
const ICONS := {"farm": "sprout", "nursery": "flower-2", "bistro": "utensils", "courtyard": "hammer"}
const FOLLOW_VIEW_SIZE := 16.0
var session: FarmSession
var layout: JourneyStreets
var cam: Camera3D
var world_env: WorldEnvironment
var environment: Environment
var canvas: CanvasLayer
var ui: Control
var header: VBoxContainer
var header_backdrop: Panel
var dialogue_title: Label
var markers: Control
var status: Label
var objective: Label
var objective_action: Button
var _goal_target := ""
var _destination_goal: Dictionary = {}
var notice: Label
var scenery: Node3D
var objects: Node3D
var commons: Node3D
var gatherings: Node3D
var residents: StreetResidents
var dialogue: PanelContainer
var confirmation: CanvasLayer
var dialogue_scroll: ScrollContainer
var active_panel: SessionPanel
var bag_sheet: BagSheet
var selected_slot := ""
var _commons_key := ""
var _residents_key := ""
var _gatherings_key := "unbuilt"
var selected_gathering := ""
var player: Node3D
var _rig: AvatarRig
var mover: PlayerMover
var hints: PlotHints
var camera_pan := preload("res://modules/farm/scene_pan.gd").new()
var targets: Dictionary = {}
var pending := ""
var busy := false
var fishing_panel: FishingPanel
var fishing_view: FishingPresentation
var _fishing_plan: Dictionary = {}
var _world_key := ""
var _notice_left := 0.0
# Null means no gesture; an empty ID preserves a press on the ground.
var _pressed_target: Variant = null
var _base_size := FOLLOW_VIEW_SIZE
var _camera_center := Vector3(19.2, 0, -19.2)
var _start_place := "farm"
var _start_target := ""
var _request_timber_slot := ""
var _walk_place := ""
var _status_elapsed := 0.0
var visitor_snapshot: Dictionary = {}
var visitor_blueprint: FarmBlueprint
var online: OnlineSpace
var _online_join: Dictionary = {}
var _online_animation := "idle"

func setup(args: Dictionary) -> void:
	_online_join = args.get("online_join", {})
	session = args.get("session", Net.session)
	visitor_snapshot = args.get("visitor_snapshot", {})
	visitor_blueprint = args.get("blueprint")
	if not visitor_snapshot.is_empty():
		# This scene has no authenticated client; all public scenery comes from the visitor DTO.
		session = FarmSession.new(null)
		session.layout_patch_id = str(visitor_snapshot.layout_patch_id)
		session.blueprint_revision = int(visitor_snapshot.blueprint_revision)
		var street: Dictionary = visitor_snapshot.get("street_snapshot", {})
		session.state = {"nursery": visitor_snapshot.get("nursery", {}), "journey": {
			"version": 1, "facts": ["side_path"] if street.get("side_path", false) else [], "unlocks": [],
			"contributions": street.get("contributions", {}), "gathering": {"current": street.get("gathering", "")},
			"exploration": {"round": 0, "collected": []}}}
	_start_place = str(args.get("from", "farm"))
	_start_target = str(args.get("target", ""))
	_request_timber_slot = str(args.get("request_timber_slot", ""))
	_walk_place = str(args.get("walk_place", "bistro" if JourneyStreets.WALK_STOPS.has(_start_target) else ""))

func _ready() -> void:
	if session == null: session = Net.session
	get_viewport().transparent_bg = false
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("bad4b2")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("eef4ef")
	var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	environment.ambient_light_energy = 0.2 if compatibility else 0.4
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.4 if compatibility else 0.8
	sun.shadow_enabled = true
	add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(cam)
	cam.make_current()
	add_child((load("res://modules/ui/opaque_scene_layer.tscn") as PackedScene).instantiate())
	player = Node3D.new()
	player.name = "StreetPlayer"
	add_child(player)
	_rig = Avatar.create_rig()
	_rig.assembler = AvatarAssemblerMerged.new()
	for child in _rig.get_children():
		if child is RigActivity:
			child.reduced_distance = 50
			child.sleep_distance = 80
	player.add_child(_rig)
	_rig.config_applied.connect(func(_config): _play("idle"))
	Avatar.follow_saved_outfit(_rig)
	_build_ui()
	fishing_panel = FishingPanel.new()
	add_child(fishing_panel)
	fishing_panel.opened.connect(_begin_fishing_view)
	fishing_panel.closed.connect(_end_fishing_view)
	confirmation = preload("res://modules/ui/entry_confirmation.gd").new()
	add_child(confirmation)
	camera_pan.radius = 18.0
	camera_pan.min_zoom = 0.65
	camera_pan.max_zoom = 1.6
	camera_pan.tapped.connect(_ground_tap)
	session.state_changed.connect(func(_state, _version): _refresh())
	session.offline_changed.connect(func(_offline): _refresh_status())
	_refresh()
	mover.position = layout.entrances.get(_start_place, layout.entrances.farm)
	player.position = mover.position
	_camera_center = player.position
	_update_camera()
	_sync_markers()
	if not _start_target.is_empty(): select_target(_start_target)
	var live_session: FarmSession = Net.session if not visitor_snapshot.is_empty() else session
	if live_session and live_session.logged_in():
		var args := {} if visitor_snapshot.is_empty() else {"farm_id": str(visitor_snapshot.get("farm_id", ""))}
		args.merge(_online_join, true)
		online = OnlineSpace.attach(self, live_session, "street", args, func(): return mover,
			func(): return _online_animation)

func _build_ui() -> void:
	canvas = CanvasLayer.new()
	add_child(canvas)
	var safe := SafeAreaMargin.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.theme = GameUi.theme()
	canvas.add_child(safe)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(ui)
	header_backdrop = Panel.new()
	header_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_backdrop.add_theme_stylebox_override("panel", GameUi.card_style(false, 8))
	ui.add_child(header_backdrop)
	markers = Control.new()
	markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(markers)
	hints = PlotHints.new()
	hints.cam = cam
	ui.add_child(hints)
	header = VBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 8
	header.offset_right = -8
	header.offset_top = 8
	header.add_theme_constant_override("separation", 4)
	ui.add_child(header)
	header.resized.connect(_update_camera)
	var row := HBoxContainer.new()
	header.add_child(row)
	var back := GameUi.button("arrow-left", "", L10n.text("Back to map"))
	back.pressed.connect(_leave)
	row.add_child(back)
	var title := GameUi.label(JourneyStreets.load_for(session).display_name if visitor_snapshot.is_empty() else L10n.format_text("%s's neighbourhood", SeededOutfit.short_name(str(visitor_snapshot.avatar_ref))), 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(title)
	var overview := GameUi.button("map", "", L10n.text("Whole neighbourhood"))
	overview.pressed.connect(func(): _focus_view(Vector3(19.2, 0, -19.2), 45.0))
	row.add_child(overview)
	if visitor_snapshot.is_empty():
		var bag := GameUi.button("backpack", "", L10n.text("Your bag"))
		bag.name = "OpenBag"
		bag.pressed.connect(_open_bag)
		row.add_child(bag)
	status = GameUi.label("", 12, GameUi.GREEN)
	header.add_child(status)
	var goal_row := HBoxContainer.new()
	header.add_child(goal_row)
	objective = GameUi.label("", 12)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	goal_row.add_child(objective)
	objective_action = GameUi.button("compass", "", L10n.text("Go to current goal"))
	objective_action.name = "ObjectiveAction"
	objective_action.pressed.connect(_act_on_goal)
	goal_row.add_child(objective_action)
	var footer := HBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -48
	ui.add_child(footer)
	for spec in [["map", L10n.text("Neighbourhood map")], ["locate-fixed", L10n.text("Follow my character")], ["sprout", L10n.text("Return to your farm")]]:
		var button := GameUi.button(spec[0], "", spec[1])
		if spec[0] == "sprout" and not visitor_snapshot.is_empty(): button.tooltip_text = L10n.text("Visit Farm")
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(button)
		if spec[0] == "map": button.pressed.connect(_leave)
		elif spec[0] == "sprout": button.pressed.connect(select_target.bind("farm"))
		else: button.pressed.connect(func(): _focus_view(player.position, FOLLOW_VIEW_SIZE))
	notice = GameUi.label("", 13, GameUi.GREEN)
	notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	notice.offset_top = -86
	notice.offset_bottom = -52
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_color_override("font_outline_color", GameUi.PAPER)
	notice.add_theme_constant_override("outline_size", 3)
	ui.add_child(notice)
	var credit := GameUi.label(L10n.text("OpenStreetMap contributors"), 9, GameUi.MUTED)
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	credit.position.y -= 103
	ui.add_child(credit)
	dialogue = PanelContainer.new()
	dialogue.name = "StreetDialogue"
	dialogue.add_theme_stylebox_override("panel", GameUi.panel_style(12))
	GameUi.register_modal(dialogue)
	ui.add_child(dialogue)
	var column := VBoxContainer.new()
	dialogue.add_child(column)
	var dialogue_header := HBoxContainer.new()
	dialogue_header.add_theme_constant_override("separation", 8)
	column.add_child(dialogue_header)
	dialogue_header.add_child(GameUi.picture(GameUi.icon("users-round"), 24))
	dialogue_title = GameUi.label(L10n.text("Residents"), 17)
	dialogue_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dialogue_header.add_child(dialogue_title)
	var close := GameUi.button("x", "", L10n.text("Close conversation"))
	close.pressed.connect(_close_dialogue)
	dialogue_header.add_child(close)
	dialogue_scroll = TouchScrollContainer.new()
	dialogue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialogue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(dialogue_scroll)
	dialogue.hide()
	ui.resized.connect(func(): _update_camera(); _sync_markers())

func _refresh() -> void:
	var key := JSON.stringify([JourneyProgress.fact(session.state, "side_path"), session.state.get("nursery", {})])
	if layout == null or key != _world_key:
		var previous := mover.position if mover else Vector3.ZERO
		layout = JourneyStreets.new(visitor_blueprint if visitor_blueprint else JourneyStreets.load_for(session), JourneyProgress.fact(session.state, "side_path"))
		mover = PlayerMover.new(layout.nav, layout.grid)
		if layout.nav.is_walkable(layout.nav.world_to_cell(previous)): mover.position = previous
		_build_scenery()
		_world_key = key
		_commons_key = ""
		_residents_key = ""
		_gatherings_key = "unbuilt"
	_refresh_commons()
	_refresh_gatherings()
	if objects:
		remove_child(objects)
		objects.queue_free()
	objects = Node3D.new()
	objects.name = "StreetSupplies"
	add_child(objects)
	for child in markers.get_children():
		markers.remove_child(child)
		child.queue_free()
	targets.clear()
	for id in layout.entrances:
		if not visitor_snapshot.is_empty() and id != "farm": continue
		_add_target(id, L10n.text("Visit Farm") if not visitor_snapshot.is_empty() else NAMES[id], ICONS[id], layout.buildings[id] + Vector3(0, 1.5, 0), layout.entrances[id])
	if not visitor_snapshot.is_empty():
		_refresh_status()
		_sync_markers()
		return
	if JourneyGatherings.available(session.state):
		for theme in layout.gatherings:
			var venue: Dictionary = layout.gatherings[theme]
			var spec: Dictionary = JourneyGatherings.themes()[theme]
			_add_target("gathering:" + str(theme), L10n.text("Tea walk") if theme == "garden" else L10n.text("Lantern supper"), str(spec.icon), venue.position + Vector3(0, 1.6, 0), venue.approach)
			targets["gathering:" + str(theme)].gathering = theme
	for slot in residents.moments:
		var actor: Node3D = residents.moments[slot].actor
		_add_target("resident:" + slot, L10n.text(str(ResidentCast.definition(str(actor.name)).name)), "message-circle", actor.position + Vector3(0, 1.8, 0), actor.position)
		targets["resident:" + slot].slot = slot
		if not JourneyGatherings.current(session.state).is_empty():
			targets["resident:" + slot].button.text = ""
			targets["resident:" + slot].button.size = Vector2(44, 44)
	for place in ["nursery", "bistro", "courtyard"]:
		var node := JourneyStreets.street_node(session.state, place)
		var nodes := JourneyProgress.remaining_nodes(session.state, place) if JourneyProgress.street_supplies(session.state, place) else ([] if node.is_empty() else [node])
		for supply in nodes:
			var bundles := JourneyProgress.node_bundles(session.state, supply)
			var pair: Array = layout.walk_caches[supply.id] if JourneyProgress.street_supplies(session.state, place) else layout.caches[place]
			for index in bundles.size():
				var bundle: Dictionary = bundles[index]
				var point: Vector3 = pair[index]
				_resource_pile(point, bundle.materials)
				var height := 1.35 if JourneyProgress.street_supplies(session.state, place) else 0.65
				_add_target(str(bundle.id), JourneyProgress.material_label(bundle.materials), "", point + Vector3(0, height, 0), point)
				targets[bundle.id].bundle = bundle
	_refresh_status()
	_sync_markers()

func _refresh_commons() -> void:
	var key := JSON.stringify(session.state.get("journey", {}).get("contributions", {}))
	if key != _commons_key:
		if commons:
			remove_child(commons)
			commons.queue_free()
		commons = Node3D.new()
		add_child(commons)
		for slot in layout.commons:
			var area := StreetCommons.build(slot, session.state)
			var common: Dictionary = layout.commons[slot]
			area.position = common.position
			area.rotation.y = atan2(-common.facing.x, -common.facing.z)
			commons.add_child(area)
		_commons_key = key
	var cast_key := str(JourneyProgress.fact(session.state, "shared_meal"))
	if cast_key != _residents_key:
		if residents:
			remove_child(residents)
			residents.queue_free()
		residents = StreetResidents.new()
		add_child(residents)
		residents.setup(layout, session.state)
		_residents_key = cast_key
	residents.set_gathering(JourneyGatherings.current(session.state))

func _refresh_gatherings() -> void:
	var key := JourneyGatherings.current(session.state)
	if key == _gatherings_key: return
	if gatherings:
		remove_child(gatherings)
		gatherings.queue_free()
	gatherings = Node3D.new()
	gatherings.name = "StreetGatherings"
	add_child(gatherings)
	for theme in layout.gatherings:
		var venue: Dictionary = layout.gatherings[theme]
		var table := StreetGatherings.build(str(theme), session.state)
		table.position = venue.position
		table.rotation.y = atan2(-venue.facing.x, -venue.facing.z)
		gatherings.add_child(table)
	_gatherings_key = key

func _build_scenery() -> void:
	if scenery:
		remove_child(scenery)
		scenery.queue_free()
	scenery = Node3D.new()
	add_child(scenery)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	PlaceScenery._box(surface, Vector3(80, 0.15, 80), Vector3(19.2, -0.11, -19.2), PlaceScenery.GRASS)
	for road in layout.roads:
		var is_shortcut := road == layout.shortcut
		for index in road.size() - 1:
			var start := road[index]
			var end := road[index + 1]
			var direction := end - start
			var basis := Basis(Vector3.UP, atan2(direction.x, direction.z))
			PlaceScenery._box(surface, Vector3(2.55, 0.06, direction.length()), (start + end) * 0.5 + Vector3(0, 0.005, 0), PlaceScenery.STONE, basis)
			PlaceScenery._box(surface, Vector3(1.85, 0.02, direction.length()), (start + end) * 0.5 + Vector3(0, 0.042, 0), Color("87ad8c") if is_shortcut else Color("93a3a6"), basis)
		for point in road: PlaceScenery._cylinder(surface, 1.28, 0.05, point, PlaceScenery.STONE, Vector3.ONE, 16)
	for pair in layout.all_caches():
		for point in pair: PlaceScenery._cylinder(surface, 0.85, 0.03, point + Vector3(0, 0.035, 0), PlaceScenery.STONE, Vector3.ONE, 16)
	for id in layout.buildings:
		var position: Vector3 = layout.buildings[id]
		if id == "farm":
			var art = preload("res://modules/farm/farm_art.gd")
			scenery.add_child(art.instance("house_" + art.style_for(layout.source.region_id, layout.source.layout_patch_id), position, 1.5))
		else:
			var miniature := PlaceScenery.build(id, session.state)
			miniature.position = position
			miniature.scale = Vector3.ONE * 0.4
			scenery.add_child(miniature)
	for id in FishingModel.data().sites:
		if FishingModel.site(id).space == "street": scenery.add_child(FishingWater.build(id))
	var tree_surface := SurfaceTool.new()
	tree_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(2, 39, 4):
		for z in range(2, 39, 4):
			var point := Vector3(x, 0, -z)
			if FishingModel.water_at("street", point, 1.5): continue
			if layout.road_distance(point) < 2.7: continue
			if layout.buildings.values().any(func(p): return p.distance_to(point) < 4): continue
			if layout.all_caches().any(func(pair): return pair[0].distance_to(point) < 2 or pair[1].distance_to(point) < 2): continue
			if layout.commons.values().any(func(common): return common.position.distance_to(point) < 3.6): continue
			if layout.gatherings.values().any(func(venue): return venue.position.distance_to(point) < 3.8): continue
			PlaceScenery._tree(tree_surface, point, 0.75 + float((x + z) % 3) * 0.15)
	scenery.add_child(_mesh(surface, "NeighbourhoodRoads"))
	scenery.add_child(_mesh(tree_surface, "NeighbourhoodTrees"))

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

func _resource_pile(point: Vector3, materials: Dictionary) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if int(materials.get("wood", 0)) > 0:
		for i in 3: PlaceScenery._beam(surface, point + Vector3(-0.36, 0.12 + i * 0.1, -0.12), point + Vector3(0.36, 0.12 + i * 0.1, 0.13), 0.12, PlaceScenery.WOOD)
	if int(materials.get("stone", 0)) > 0:
		for i in 3: PlaceScenery._oval(surface, Vector3(0.3, 0.25, 0.25), point + Vector3(-0.3 + i * 0.26, 0.18, 0.4), PlaceScenery.STONE.darkened(0.2))
	if int(materials.get("fiber", 0)) > 0:
		for i in 5: PlaceScenery._beam(surface, point + Vector3(-0.3 + i * 0.15, 0, 0.3), point + Vector3(-0.4 + i * 0.18, 0.85, 0.35), 0.04, PlaceScenery.LEAF)
	objects.add_child(_mesh(surface, "ResourceBundle"))

func _add_target(id: String, text: String, icon: String, world: Vector3, approach: Vector3) -> void:
	var label := GameUi.button(icon, text.replace(" + ", "\n"), text)
	label.name = "StreetTarget_" + id
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(44, 44)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", GameUi.INK)
	label.add_theme_color_override("icon_normal_color", GameUi.BLUE)
	for style in ["normal", "hover", "pressed", "disabled"]: label.add_theme_stylebox_override(style, GameUi.card_style(false, 5))
	markers.add_child(label)
	label.size = label.get_combined_minimum_size()
	targets[id] = {"button": label, "world": world, "approach": approach, "text": text}
	label.pressed.connect(select_target.bind(id))

func _sync_markers() -> void:
	if not layout or not ui: return
	var area := _world_area()
	for id in targets:
		var target: Dictionary = targets[id]
		if target.has("slot"):
			var actor: Node3D = residents.moments[target.slot].actor
			target.world = actor.position + Vector3(0, 1.8, 0)
			target.body = actor.position + Vector3(0, 1.35, 0)
		var button: Button = target.button
		var point := cam.unproject_position(target.world) - ui.global_position
		button.position = point - button.size * 0.5
		button.visible = not dialogue.visible and area.encloses(button.get_rect()) and not cam.is_position_behind(target.world)
		button.modulate.a = 0.9 if target.world.distance_to(player.position + Vector3(0, 1, 0)) > 1.4 else 0.5
		button.disabled = busy or session.offline or session.has_unconfirmed_command() or (NAMES.has(id) and id != "farm" and not PlaceCatalog.available(id, session.state))

func _world_area() -> Rect2:
	return Rect2(0, header.size.y + 12, ui.size.x, maxf(1, ui.size.y - header.size.y - 115))

func _update_camera() -> void:
	if cam == null: return
	if header_backdrop and header:
		header_backdrop.size = Vector2(ui.size.x, header.position.y + header.size.y + 8)
	var center := _camera_center + camera_pan.offset
	if dialogue and dialogue.visible and residents.moments.has(selected_slot):
		center = player.position.lerp(residents.moments[selected_slot].actor.position, 0.5)
	elif dialogue and dialogue.visible and not selected_gathering.is_empty():
		center = player.position.lerp(layout.gatherings[selected_gathering].position, 0.5)
	cam.position = center + Vector3(5, 27, 23)
	cam.look_at(center)
	# Keep the same local area visible when headers and controls limit a wide screen.
	var width := get_viewport().get_visible_rect().size.x
	cam.size = _base_size * maxf(1, width / _world_area().size.y) / camera_pan.zoom
	cam.v_offset = 0
	if dialogue:
		var height := minf(410, ui.size.y * 0.50)
		var dialogue_width := minf(620, ui.size.x)
		dialogue.position = Vector2((ui.size.x - dialogue_width) * 0.5, maxf(header.size.y + 16, ui.size.y - height - 100))
		dialogue.size = Vector2(maxf(1, dialogue_width), maxf(1, ui.size.y - dialogue.position.y - 100))
		if dialogue.visible:
			var top := header.global_position.y + header.size.y + 12
			var bottom := dialogue.global_position.y - 12
			cam.size = maxf(12, width * 3.5 / maxf(1, bottom - top))
			var point := cam.unproject_position(center + Vector3(0, 0.85, 0))
			cam.v_offset = ((top + bottom) * 0.5 - point.y) * cam.size / width
	if notice:
		notice.offset_bottom = -56
		notice.offset_top = -56 - maxf(34, notice.get_minimum_size().y)

func _focus_view(center: Vector3, view_size: float) -> void:
	_camera_center = center
	_base_size = view_size
	camera_pan.reset()
	_update_camera()
	_sync_markers()

func _current_goal() -> Dictionary:
	if not _walk_place.is_empty() and JourneyProgress.street_supplies(session.state, _walk_place):
		var nodes := JourneyProgress.remaining_nodes(session.state, _walk_place)
		if not nodes.is_empty():
			nodes.sort_custom(func(a, b): return mover.position.distance_squared_to(layout.walk_caches[a.id][0]) < mover.position.distance_squared_to(layout.walk_caches[b.id][0]))
			return JourneyProgress.resource_goal(session.state, nodes[0], str(nodes[0].id), str(JourneyStreets.WALK_STOPS[nodes[0].id]))
	return JourneyProgress.next_goal(JourneyProgress.goal_state(session), session.server_now())

func _refresh_status() -> void:
	if not visitor_snapshot.is_empty():
		status.text = L10n.text("Visiting neighbourhood")
		objective.get_parent().hide()
		return
	status.text = L10n.format_text("%d coins / %d wood / %d stone / %d reeds", [session.state.get("wallet", 0), JourneyProgress.material(session.state, "wood"), JourneyProgress.material(session.state, "stone"), JourneyProgress.material(session.state, "fiber")])
	var effect_status := CharacterModel.action_status(session.state, "gather_bonus")
	if not effect_status.is_empty(): status.text += "\n" + effect_status
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var goal := _current_goal()
	_goal_target = _goal_target_id(goal)
	if pending.is_empty():
		objective.text = JourneyProgress.goal_label(goal)
	else: objective.text = str(targets.get(pending, {}).get("text", L10n.text("Following the path")))
	if session.offline: objective.text = L10n.text("Waiting for connection")
	var walking := mover != null and (mover.is_moving() or not pending.is_empty())
	objective_action.icon = GameUi.icon("x" if walking else "compass")
	objective_action.tooltip_text = L10n.text("Stop walking") if walking else L10n.text("Go to current goal")
	objective_action.disabled = busy or dialogue.visible or (not walking and (session.offline or session.has_unconfirmed_command() or _goal_target.is_empty()))

func _goal_target_id(goal: Dictionary) -> String:
	if goal.has("resident"):
		var slot = StreetCommons.RESIDENTS.find_key(str(goal.resident))
		if slot != null and targets.has("resident:" + str(slot)): return "resident:" + str(slot)
	var target := str(goal.get("target", ""))
	if targets.has(target): return target
	var place := str(goal.get("place", ""))
	return place if targets.has(place) else ""

func _act_on_goal() -> void:
	if busy or dialogue.visible: return
	if mover.is_moving() or not pending.is_empty():
		mover.stop()
		pending = ""
		_destination_goal = {}
		_refresh_status()
		return
	if session.offline or session.has_unconfirmed_command(): return
	var goal := _current_goal()
	select_target(_goal_target_id(goal), goal)

func select_target(id: String, goal: Dictionary = {}) -> void:
	_fishing_plan = {}
	if fishing_panel and fishing_panel.visible: return
	if not visitor_snapshot.is_empty() and id != "farm": return
	if busy or dialogue.visible or confirmation.visible or not targets.has(id) or session.offline or session.has_unconfirmed_command(): return
	if NAMES.has(id) and id != "farm" and not PlaceCatalog.available(id, session.state):
		_message(L10n.text("First harvest opens the bistro"))
		return
	mover.grid = residents.navigation(residents.positions(), mover.position)
	if targets[id].has("slot"):
		var actor: Node3D = residents.moments[targets[id].slot].actor
		var found := false
		for point in residents.nearby(actor.position, 3):
			if point.distance_to(actor.position) < 1.0 or point.distance_to(actor.position) > 1.8: continue
			if not mover.grid.point_path(mover.position, point).is_empty():
				targets[id].approach = point
				found = true
				break
		if not found:
			_message(L10n.text("The path is busy. Try again in a moment."))
			return
	var accepted := mover.set_target_position(targets[id].approach)
	hints.destination(targets[id].approach, accepted, mover.remaining_path())
	if accepted:
		pending = id
		_destination_goal = goal.duplicate(true) if NAMES.has(id) and goal.get("place") == id else {}
		_refresh_status()
	else: _message(L10n.text("That path is not reachable"))

func _ground_tap(screen: Vector2) -> void:
	if fishing_panel and fishing_panel.visible: return
	if busy or dialogue.visible or confirmation.visible or session.offline or session.has_unconfirmed_command() or not _world_area().has_point(screen - ui.global_position): return
	var id: String = _pick_target(screen) if _pressed_target == null else str(_pressed_target)
	if not id.is_empty():
		select_target(id)
		return
	var point = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	if not point is Vector3: return
	for water_id in FishingModel.data().sites:
		if FishingModel.site(water_id).space == "street" and FishingModel.contains(water_id, point):
			_go_fishing(water_id, point)
			return
	_fishing_plan = {}
	pending = ""
	_destination_goal = {}
	mover.grid = residents.navigation(residents.positions(), mover.position)
	var accepted := mover.set_target_position(point)
	hints.destination(point, accepted, mover.remaining_path())
	_refresh_status()
	if not accepted: _message(L10n.text("That spot is not reachable"))

func _pick_target(screen: Vector2) -> String:
	if dialogue.visible or not _world_area().has_point(screen - ui.global_position): return ""
	var nearest := 30.0
	var id := ""
	for key in targets:
		var target: Dictionary = targets[key]
		var button: Button = target.button
		if button.disabled: continue
		var distance := screen.distance_to(button.get_global_rect().get_center()) if button.visible else INF
		if target.has("body") and not cam.is_position_behind(target.body):
			var body := cam.unproject_position(target.body)
			if _world_area().has_point(body - ui.global_position):
				distance = minf(distance, screen.distance_to(body))
		if target.has("gathering") and button.visible:
			var table: Vector3 = layout.gatherings[target.gathering].position + Vector3(0, 0.9, 0)
			distance = minf(distance, screen.distance_to(cam.unproject_position(table)))
		if distance < nearest:
			nearest = distance
			id = key
	return id

func _process(dt: float) -> void:
	if not mover: return
	if fishing_panel and fishing_panel.visible:
		mover.stop()
		return
	if online and online.travel_busy:
		_update_camera()
		return
	if online and online.session: mover.speed = CharacterModel.current(online.session.state, "move_speed")
	elif session: mover.speed = CharacterModel.current(session.state, "move_speed")
	_status_elapsed += dt
	if _status_elapsed >= 1.0:
		_status_elapsed = 0.0
		_refresh_status()
	camera_pan.step(dt, cam)
	var holding_resident: bool = camera_pan.active() and targets.get(_pressed_target, {}).has("slot")
	residents.step(dt, mover.is_moving() or not pending.is_empty() or busy or dialogue.visible or holding_resident, player.position)
	mover.step(dt)
	player.position = mover.position
	if not _fishing_plan.is_empty() and not mover.is_moving():
		var plan := _fishing_plan
		_fishing_plan = {}
		if player.position.distance_to(plan.origin) < 0.3:
			camera_pan.cancel()
			_play("idle")
			fishing_panel.open(online.session if online else session, plan.site, plan.target)
			return
	if mover.is_moving():
		_rig.rotation.y = atan2(mover.facing.x, mover.facing.z)
		_play("run")
		if not camera_pan.active(): _camera_center = _camera_center.lerp(player.position, 1.0 - exp(-3 * dt))
	elif not busy:
		_play("idle")
		if not pending.is_empty():
			var id := pending
			pending = ""
			_arrive(id)
			if not is_inside_tree(): return
	_update_camera()
	_sync_markers()
	hints.world_rect = _world_area()
	hints.update_motion(mover.is_moving(), mover.remaining_path(), dt)
	_notice_left = maxf(0, _notice_left - dt)
	notice.visible = _notice_left > 0

func _go_fishing(id: String, clicked: Vector3) -> void:
	var own_session: FarmSession = online.session if online else session
	if own_session == null or own_session.offline or own_session.has_unconfirmed_command(): return
	if not CharacterModel.has_fishing_rod(own_session.state):
		_message(L10n.text("Equip a fishing rod on the character page first."))
		return
	pending = ""
	_destination_goal = {}
	mover.grid = residents.navigation(residents.positions(), mover.position)
	_fishing_plan = FishingModel.plan(id, mover.position, clicked, mover.grid)
	if _fishing_plan.is_empty():
		_message(L10n.text("Can't reach that spot"))
		return
	_fishing_plan.site = id
	var accepted := mover.set_target_position(_fishing_plan.origin)
	hints.destination(_fishing_plan.origin, accepted, mover.remaining_path())
	if not accepted: _fishing_plan = {}

func _begin_fishing_view(_site: String) -> void:
	_end_fishing_view()
	fishing_view = FishingPresentation.new()
	add_child(fishing_view)
	fishing_view.configure(fishing_panel, player, _rig, cam, [ui, online.hud if online else null])

func _end_fishing_view() -> void:
	if is_instance_valid(fishing_view): fishing_view.finish()
	fishing_view = null

func _arrive(id: String) -> void:
	if not targets.has(id): return
	if not visitor_snapshot.is_empty() and id != "farm": return
	if targets[id].has("gathering"):
		_show_gathering(str(targets[id].gathering))
		return
	if targets[id].has("slot"):
		var slot := str(targets[id].slot)
		_show_dialogue(slot)
		await active_panel.command("talk_to_resident", {"resident_id": StreetCommons.RESIDENTS[slot]}, "")
		return
	if NAMES.has(id):
		var goal := _destination_goal
		_destination_goal = {}
		camera_pan.cancel()
		mover.stop()
		confirmation.ask(L10n.text("Farm") if not visitor_snapshot.is_empty() else str(NAMES[id]))
		var enter: bool = await confirmation.answered
		if not enter: return
		if not visitor_snapshot.is_empty():
			var farm_snapshot := visitor_snapshot
			if has_meta("party_travel"):
				var response := await Net.snapshot(str(visitor_snapshot.farm_id))
				if not is_inside_tree(): return
				if not response.ok:
					_message(L10n.text("Ask the owner to allow party farm visits"))
					return
				farm_snapshot = response.snapshot
			AppRouter.open_instance(AppRouter.FARM, {"visitor": true, "snapshot": farm_snapshot, "blueprint": visitor_blueprint,
				"online_join": {"channel": int(online.join_args.get("channel", 1)) if online else 1}})
			return
		if id == "farm":
			AppRouter.open_instance(AppRouter.FARM, {"session": session,
				"seed_crop": str(goal.get("crop", "")) if goal.get("action") == "stall" else "", "target": str(goal.get("target", ""))})
		else: AppRouter.open_instance(AppRouter.PLACE, {"session": session, "place_id": id, "target": str(goal.get("target", ""))})
		return
	var bundle: Dictionary = targets[id].bundle
	var materials: Dictionary = bundle.materials
	var round_id := int(session.state.journey.exploration.round)
	busy = true
	_play("labour_till" if materials.has("stone") else ("labour_sow" if materials.has("fiber") else "labour_clear"))
	await get_tree().create_timer(CharacterModel.gather_seconds(session.state, CharacterModel.resource_kind(materials))).timeout
	var accepted := await session.send("collect_resource", {"node_id": bundle.node, "round": round_id, "choice": bundle.choice})
	busy = false
	var result := "+" + JourneyProgress.material_label(materials)
	var effect_status := CharacterModel.action_status(session.state, "gather_bonus")
	if not effect_status.is_empty(): result += "\n" + effect_status
	_message(result if accepted else SessionPanel.error_text(session.last_error_code))
	_refresh()

func _show_dialogue(slot: String) -> void:
	camera_pan.cancel()
	mover.stop()
	pending = ""
	selected_slot = slot
	selected_gathering = ""
	var actor: Node3D = residents.moments[slot].actor
	var toward := player.position - actor.position
	actor.rotation.y = atan2(toward.x, toward.z)
	_rig.rotation.y = atan2(-toward.x, -toward.z)
	if active_panel:
		dialogue_scroll.remove_child(active_panel)
		active_panel.queue_free()
	var panel := JourneyActivityPanel.new()
	active_panel = panel
	panel.target = "resident:" + str(StreetCommons.RESIDENTS[slot])
	dialogue_title.text = L10n.text(str(ResidentCast.definition(str(StreetCommons.RESIDENTS[slot])).name))
	panel.prefer_timber_only = _request_timber_slot == slot
	panel.place_id = "street"
	active_panel.setup(session)
	panel.contribution_completed.connect(_contribution_completed)
	panel.resident_interaction_completed.connect(_resident_interaction_completed)
	panel.goal_requested.connect(_gathering_destination)
	panel.requests_requested.connect(_open_requests)
	panel.destination_requested.connect(func(id):
		_close_dialogue()
		if not dialogue.visible: select_target(id))
	dialogue_scroll.add_child(active_panel)
	dialogue_scroll.scroll_vertical = 0
	dialogue.show()
	_refresh_status()
	_sync_markers()

func _show_gathering(theme: String) -> void:
	dialogue_title.text = L10n.text(str(JourneyGatherings.themes()[theme].name))
	camera_pan.cancel()
	mover.stop()
	pending = ""
	selected_slot = ""
	selected_gathering = theme
	if active_panel:
		dialogue_scroll.remove_child(active_panel)
		active_panel.queue_free()
	var panel := JourneyGatheringPanel.new()
	panel.theme_id = theme
	panel.setup(session)
	panel.goal_requested.connect(_gathering_destination)
	panel.hosted.connect(func(_id):
		var text := panel.message.text
		_close_dialogue()
		_message(text))
	panel.packed.connect(func():
		_close_dialogue()
		_message(panel.message.text))
	active_panel = panel
	dialogue_scroll.add_child(panel)
	dialogue_scroll.scroll_vertical = 0
	dialogue.show()
	_refresh_status()
	_sync_markers()

func _gathering_destination(goal: Dictionary) -> void:
	_close_dialogue()
	if dialogue.visible: return
	_walk_place = ""
	_request_timber_slot = str(goal.get("change_request", ""))
	select_target(_goal_target_id(goal), goal)

func _close_dialogue() -> void:
	if active_panel and active_panel.busy: return
	dialogue.hide()
	selected_slot = ""
	selected_gathering = ""
	_refresh_status()
	_update_camera()
	_sync_markers()

func _resident_interaction_completed(resident_id: String) -> void:
	var slot = StreetCommons.RESIDENTS.find_key(resident_id)
	if slot == null or not residents.moments.has(slot): return
	var message := active_panel.message.text
	_close_dialogue()
	var moment: ResidentMoment = residents.moments[slot]
	moment.start(moment.actor.position, player.position)
	_message(message)

func _contribution_completed(slot: String, effect: String) -> void:
	_close_dialogue()
	_refresh_commons()
	residents.respond(slot)
	_message(StreetCommons.progress(session.state, effect) + " / " + str(active_panel.message.text))

func _message(text: String) -> void:
	notice.text = text
	notice.show()
	_notice_left = 5

func _play(id: String) -> void:
	_online_animation = id
	_rig.play_motion(id)

func _input(event: InputEvent) -> void:
	if fishing_panel and fishing_panel.visible: return
	if online and (online.travel_busy or is_instance_valid(online.panel)): return
	if bag_sheet and bag_sheet.visible: return
	if dialogue.visible or confirmation.visible: return
	if camera_pan.handle(event, cam):
		if not camera_pan.active() or camera_pan.dragged or camera_pan.multi: _pressed_target = null
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if fishing_panel and fishing_panel.visible: return
	if online and (online.travel_busy or is_instance_valid(online.panel)): return
	if bag_sheet and bag_sheet.visible: return
	if busy or dialogue.visible or confirmation.visible: return
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION):
		_pressed_target = _pick_target(event.position)
	if camera_pan.handle(event, cam, true): get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pressed_target = null
		camera_pan.cancel()

func is_back_navigation_locked() -> bool:
	if fishing_panel and fishing_panel.visible:
		fishing_panel.close()
		return true
	if online and online.consume_back(): return true
	if bag_sheet and bag_sheet.consume_back(): return true
	if confirmation.visible:
		confirmation.dismiss(false)
		return true
	if dialogue.visible:
		_close_dialogue()
		return true
	if busy or session.has_unconfirmed_command(): return true
	if mover.is_moving():
		mover.stop()
		pending = ""
		_refresh_status()
		return true
	return false

func _leave() -> void:
	if not is_back_navigation_locked(): AppRouter.pop_instance()

func _open_bag() -> void:
	if busy or confirmation.visible or (active_panel and active_panel.busy): return
	_close_dialogue()
	pending = ""
	mover.stop()
	camera_pan.cancel()
	_pressed_target = null
	if bag_sheet == null:
		bag_sheet = BagSheet.new()
		bag_sheet.setup(session)
		ui.add_child(bag_sheet)
	bag_sheet.open()

func _open_requests() -> void:
	_open_bag()
	if bag_sheet and bag_sheet.visible: bag_sheet.active.select_page("requests")

func suspend() -> void:
	_end_fishing_view()
	if fishing_panel:
		fishing_panel.interrupt()
		fishing_panel.hide()
	if online: online.suspend()
	_pressed_target = null
	camera_pan.cancel()
	process_mode = Node.PROCESS_MODE_DISABLED
	hide()
	canvas.hide()
	cam.current = false
	world_env.environment = null

func resume() -> void:
	if online: online.resume()
	get_viewport().transparent_bg = false
	process_mode = Node.PROCESS_MODE_INHERIT
	show()
	canvas.show()
	world_env.environment = environment
	cam.make_current()
	_refresh()

func party_travel_ready() -> bool:
	return not (fishing_panel and fishing_panel.visible) and not busy and not session.has_unconfirmed_command()
