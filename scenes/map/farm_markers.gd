class_name FarmMarkers
extends Control
## Screen-space clusters keep co-located owners identifiable and every farm selectable.
signal focused(farm_id: String)
signal cluster_focused(farm_ids: Array)
const MARKER_SIZE := Vector2(80, 62)
const CLUSTER_DISTANCE := 80.0
var points := {}
var selected_id := "self"
var visible_farm_ids: Array = []
var _buttons := {}
var _badges := {}
var _avatar_targets := {}
var _clusters := {}
var _selected_anchor := Vector2.ZERO
var _show_ring := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func put(id: String, bp: FarmBlueprint, owner_name: String, own := false) -> void:
	points[id] = {"center": bp.overlay.center, "bp": bp, "own": own}
	if _buttons.has(id): return
	var avatar_target := Button.new()
	avatar_target.size = Vector2(70, 92)
	avatar_target.tooltip_text = "Select %s" % owner_name
	avatar_target.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus"]:
		avatar_target.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	avatar_target.pressed.connect(_on_marker_pressed.bind(id))
	add_child(avatar_target)
	_avatar_targets[id] = avatar_target
	var b := Button.new()
	b.custom_minimum_size = MARKER_SIZE
	b.size = b.custom_minimum_size
	b.theme_type_variation = &"ChoiceButton"
	b.tooltip_text = "Select %s" % owner_name
	b.pressed.connect(_on_marker_pressed.bind(id))
	add_child(b)
	var row := VBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4
	row.offset_right = -4
	row.offset_top = 4
	row.offset_bottom = -3
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var image := TextureRect.new()
	var path := FarmBlueprint.asset_path(bp.layout_patch_id, bp.revision).get_base_dir() + "/preview.png"
	image.texture = load(path) if ResourceLoader.exists(path) else null
	image.custom_minimum_size = Vector2(34, 34)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(image)
	var label := GameUi.label(owner_name, 11)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	_buttons[id] = b
	var badge := GameUi.button("users-round", "", "Choose a farm at this location")
	badge.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	badge.custom_minimum_size = Vector2(54, 36)
	badge.size = badge.custom_minimum_size
	badge.add_theme_font_size_override("font_size", 11)
	badge.visible = false
	badge.pressed.connect(func(): cluster_focused.emit(_clusters.get(id, [id]).duplicate()))
	add_child(badge)
	_badges[id] = badge

func remove_missing(ids: Array) -> void:
	for id in points.keys():
		if id == "self" or ids.has(id): continue
		points.erase(id)
		_buttons[id].queue_free()
		_badges[id].queue_free()
		_avatar_targets[id].queue_free()
		_buttons.erase(id)
		_badges.erase(id)
		_avatar_targets.erase(id)
	if not points.has(selected_id): selected_id = "self"

func _on_marker_pressed(id: String) -> void:
	focused.emit(id)
	if _clusters.get(id, []).size() > 1:
		cluster_focused.emit(_clusters[id].duplicate())

func sync(cam: Camera3D, lat: float, lng: float, visible_area: Rect2) -> void:
	visible_farm_ids.clear()
	_clusters.clear()
	_show_ring = false
	for id in _buttons:
		_buttons[id].visible = false
		_badges[id].visible = false
		_avatar_targets[id].visible = false
	var ids := points.keys()
	ids.sort()
	for priority in ["self", selected_id]:
		if ids.has(priority):
			ids.erase(priority)
			ids.push_front(priority)
	var projected := {}
	for id in ids:
		var ll: Vector2 = points[id].center
		var world := MapGeoMath.geo_to_world(ll.x, ll.y, lat, lng)
		var p := cam.unproject_position(world) - global_position
		if not cam.is_position_behind(world) and visible_area.has_point(p):
			projected[id] = p
	for id in projected:
		var representative := ""
		for existing in _clusters:
			if (projected[existing] as Vector2).distance_to(projected[id]) < CLUSTER_DISTANCE:
				representative = str(existing)
				break
		if representative.is_empty(): _clusters[id] = [id]
		else: _clusters[representative].append(id)
	for id in _clusters:
		var anchor: Vector2 = projected[id]
		var b: Button = _buttons[id]
		_avatar_targets[id].position = anchor - Vector2(35, 92)
		_avatar_targets[id].visible = true
		b.visible = true
		b.position = anchor + Vector2(-MARKER_SIZE.x * 0.5, 12)
		b.position.x = clampf(b.position.x, visible_area.position.x, visible_area.end.x - MARKER_SIZE.x)
		b.theme_type_variation = &"ChoiceSelectedButton" if id == selected_id else &"ChoiceButton"
		visible_farm_ids.append(id)
		if _clusters[id].size() > 1:
			var badge: Button = _badges[id]
			badge.text = str(_clusters[id].size())
			badge.position = b.position + Vector2(MARKER_SIZE.x - 24, -28)
			badge.position.x = minf(badge.position.x, visible_area.end.x - badge.size.x)
			badge.visible = true
		if id == selected_id:
			_selected_anchor = anchor
			_show_ring = true
	queue_redraw()

func _draw() -> void:
	if not _show_ring: return
	var ring := PackedVector2Array()
	for i in 49:
		var angle := TAU * i / 48.0
		ring.append(_selected_anchor + Vector2(cos(angle) * 23, sin(angle) * 9))
	draw_colored_polygon(ring, Color(GameUi.GOLD, 0.24))
	draw_polyline(ring, GameUi.GOLD, 3, true)
