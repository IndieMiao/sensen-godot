class_name JourneyMap
extends Control

signal place_requested(id: String)
signal farm_requested()
signal street_requested(target_id: String)

const OFFSETS := {"farm": Vector3.ZERO, "nursery": Vector3(-105, 0, -105),
	"bistro": Vector3(105, 0, -65), "courtyard": Vector3(0, 0, 135)}
var state: Dictionary = {}
var fallback := false
var points: Dictionary = {}
var buttons: Dictionary = {}
var labels: Dictionary = {}
var status_labels: Dictionary = {}
var _area := Rect2()
var streets: JourneyStreets
var _roads: Array[PackedVector2Array] = []
var _walk_buttons: Dictionary = {}
var _gathering_buttons: Dictionary = {}

func configure(blueprint: FarmBlueprint) -> void:
	streets = JourneyStreets.new(blueprint)

func _project_street(point: Vector3, camera: Camera3D, origin: Vector3) -> Vector2:
	if not fallback: return camera.unproject_position(origin + (point - streets.entrances.farm) * streets.map_scale) - global_position
	var factor := minf((_area.size.x - 100) / 38.4, (_area.size.y - 100) / 38.4)
	return _area.get_center() + Vector2(point.x - 19.2, point.z + 19.2) * factor

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for id in OFFSETS:
		var b := Button.new()
		b.name = "Place_" + str(id)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(80, 54)
		b.size = b.custom_minimum_size
		for style in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		b.pressed.connect(func():
			if id == "farm": farm_requested.emit()
			else: place_requested.emit(id))
		add_child(b)
		buttons[id] = b
		var badge := Panel.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(24, 0)
		badge.size = Vector2(32, 32)
		badge.add_theme_stylebox_override("panel", GameUi.surface(Color(GameUi.PAPER, 0.76), 0, 16))
		b.add_child(badge)
		var art := GameUi.picture(GameUi.icon({"farm": "sprout", "nursery": "flower-2", "bistro": "utensils", "courtyard": "hammer"}[id]), 16)
		art.modulate = GameUi.GREEN
		art.position = Vector2(8, 8)
		badge.add_child(art)
		var label := GameUi.label("My farm" if id == "farm" else str(id).capitalize(), 11)
		label.position = Vector2(0, 34)
		label.size = Vector2(80, 18)
		label.add_theme_color_override("font_shadow_color", Color(GameUi.PAPER, 0.9))
		label.add_theme_constant_override("shadow_outline_size", 3)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_child(label)
		labels[id] = label
		var status := GameUi.label("", 10)
		status.name = "Status_" + str(id)
		status.position = Vector2(-12, 51)
		status.size = Vector2(104, 16)
		status.add_theme_color_override("font_shadow_color", Color(GameUi.PAPER, 0.95))
		status.add_theme_constant_override("shadow_outline_size", 4)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(status)
		status_labels[id] = status

func activate_at(screen: Vector2) -> bool:
	var chosen: Button
	var distance := INF
	for button: Button in buttons.values() + _walk_buttons.values() + _gathering_buttons.values():
		if not button.visible or button.disabled or button.modulate.a < 0.2: continue
		if not button.get_global_rect().has_point(screen): continue
		var d := screen.distance_to(button.get_global_rect().get_center())
		if d < distance:
			distance = d
			chosen = button
	if chosen == null: return false
	chosen.pressed.emit()
	return true

func sync(camera: Camera3D, origin: Vector3, area: Rect2, farm_state: Dictionary, use_fallback: bool, now_ms := -1) -> void:
	state = farm_state
	fallback = use_fallback
	_area = area
	points.clear()
	_roads.clear()
	if streets:
		for road in streets.roads:
			var line := PackedVector2Array()
			for point in road: line.append(_project_street(point, camera, origin))
			_roads.append(line)
	var tracked := JourneyProgress.tracked_goal(state, now_ms)
	var farm_hint := JourneyProgress.farm_hint(state, now_ms)
	for id in OFFSETS:
		var world: Vector3 = origin + (streets.offset_for(id) if streets else OFFSETS[id])
		var point: Vector2
		if streets:
			point = _project_street(streets.entrances[id], camera, origin)
		elif fallback:
			var positions := {"nursery": Vector2(0, 0.08), "bistro": Vector2(1, 0.08), "farm": Vector2(0.5, 0.5), "courtyard": Vector2(0.5, 0.94)}
			point = area.position + Vector2(68, 38) + positions[id] * (area.size - Vector2(136, 76))
		else:
			point = camera.unproject_position(world) - global_position
		points[id] = point
		var b: Button = buttons[id]
		b.visible = fallback or (area.has_point(point) and not camera.is_position_behind(world))
		if not b.visible: continue
		b.position = point - Vector2(40, 16)
		var edge := minf(minf(point.x - area.position.x, area.end.x - point.x), minf(point.y - area.position.y, area.end.y - point.y))
		b.modulate.a = 1.0 if fallback else smoothstep(0, 40, edge)
		b.disabled = id != "farm" and not PlaceCatalog.available(id, state)
		labels[id].modulate.a = 0.5 if b.disabled else 0.9
		labels[id].add_theme_color_override("font_color", GameUi.GREEN if tracked.get("place") == id else GameUi.INK)
		status_labels[id].text = str(tracked.hint) if tracked.get("place") == id else (farm_hint if id == "farm" else JourneyProgress.place_hint(state, str(id)))
		b.tooltip_text = labels[id].text + ": " + (status_labels[id].text if not status_labels[id].text.is_empty() else "Growing & harvesting")
	for button in _walk_buttons.values(): button.hide()
	for button in _gathering_buttons.values(): button.hide()
	if streets and JourneyGatherings.available(state):
		for theme in JourneyGatherings.themes():
			var spec: Dictionary = JourneyGatherings.themes()[theme]
			if not _gathering_buttons.has(theme):
				var button := GameUi.button(str(spec.icon), "", str(spec.name))
				button.name = "Gathering_" + str(theme)
				button.mouse_filter = Control.MOUSE_FILTER_IGNORE
				button.custom_minimum_size = Vector2(44, 44)
				button.size = Vector2(44, 44)
				for style in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
				button.pressed.connect(func(): street_requested.emit("gathering:" + str(theme)))
				add_child(button)
				_gathering_buttons[theme] = button
			var button: Button = _gathering_buttons[theme]
			button.position = _project_street(streets.gatherings[theme].position, camera, origin) - Vector2(22, 22)
			button.visible = area.encloses(button.get_rect())
			button.modulate = GameUi.GREEN if JourneyGatherings.planned(state) == theme or JourneyGatherings.current(state) == theme else Color(GameUi.INK, 0.7)
	if streets:
		for node in JourneyProgress.remaining_nodes(state):
			if not JourneyProgress.street_supplies(state, str(node.place)): continue
			var id := str(node.id)
			if not _walk_buttons.has(id):
				var button := Button.new()
				button.name = "WalkStop_" + id
				button.mouse_filter = Control.MOUSE_FILTER_IGNORE
				button.custom_minimum_size = Vector2(44, 44)
				button.size = Vector2(44, 44)
				for style in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
				var badge := Panel.new()
				badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				badge.position = Vector2(10, 10)
				badge.size = Vector2(24, 24)
				badge.add_theme_stylebox_override("panel", GameUi.surface(Color(GameUi.PAPER, 0.65), 0, 12))
				button.add_child(badge)
				var art := GameUi.picture(GameUi.icon("axe"), 16)
				art.position = Vector2(4, 4)
				art.modulate = GameUi.GREEN
				badge.add_child(art)
				button.pressed.connect(func(): street_requested.emit(id))
				add_child(button)
				_walk_buttons[id] = button
			var button: Button = _walk_buttons[id]
			var center: Vector3 = (streets.walk_caches[id][0] + streets.walk_caches[id][1]) * 0.5
			var point := _project_street(center, camera, origin)
			button.position = point - Vector2(22, 22)
			button.tooltip_text = str(JourneyStreets.WALK_STOPS[id]) + ": " + JourneyProgress.material_label(JourneyProgress.node_materials(state, node))
			button.visible = area.encloses(button.get_rect()) and (fallback or not camera.is_position_behind(origin + (center - streets.entrances.farm) * streets.map_scale))
			button.disabled = false
	queue_redraw()

func _draw() -> void:
	if points.size() != 4: return
	if fallback:
		draw_rect(Rect2(Vector2.ZERO, size), Color("d9e7d3"))
	if fallback and not streets:
		for pair in [["farm", "nursery"], ["farm", "bistro"], ["farm", "courtyard"], ["courtyard", "bistro"]]:
			draw_line(points[pair[0]], points[pair[1]], Color("f5f7f2"), 12, true)
			draw_line(points[pair[0]], points[pair[1]], Color("8b9e98"), 2, true)
	var bounds := PackedVector2Array([_area.position, Vector2(_area.end.x, _area.position.y), _area.end, Vector2(_area.position.x, _area.end.y)])
	for road in _roads:
		for segment in Geometry2D.intersect_polyline_with_polygon(road, bounds):
			if fallback: draw_polyline(segment, Color("f5f7f2"), 10, true)
			draw_polyline(segment, Color(GameUi.MUTED, 0.4), 1.5, true)
	var path_open := JourneyProgress.fact(state, "side_path")
	for segment in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([points.nursery, points.courtyard]), bounds):
		for index in range(segment.size() - 1):
			if path_open: draw_line(segment[index], segment[index + 1], Color(GameUi.GREEN, 0.55), 2, true)
			else: draw_dashed_line(segment[index], segment[index + 1], Color(GameUi.MUTED, 0.45), 1.5, 6)
