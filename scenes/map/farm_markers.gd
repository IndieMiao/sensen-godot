class_name FarmMarkers
extends Control
## Screen-space clusters keep co-located owners identifiable and every farm selectable.
signal focused(farm_id: String)
signal cluster_focused(farm_ids: Array)
const MARKER_SIZE := Vector2(88, 28)
const CLUSTER_DISTANCE := 80.0
const FarmArt = preload("res://modules/farm/farm_art.gd")
var points := {}
var selected_id := "":
	set(value):
		if selected_id == value: return
		selected_id = value
		_show_ring = false
		if is_instance_valid(miniature): miniature.hide()
		queue_redraw()
var visible_farm_ids: Array = []
var _buttons := {}
var _badges := {}
var _avatar_targets := {}
var _owner_labels := {}
var _clusters := {}
var _selected_anchor := Vector2.ZERO
var _show_ring := false
var miniature: Node3D
var expanded_ids: Array = []
var world_positions := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if miniature == null:
		miniature = preload("res://scenes/map/farm_map_model.gd").new()
		add_child(miniature)
	miniature.hide()

func _exit_tree() -> void:
	if is_instance_valid(miniature) and miniature.get_parent() != self: miniature.queue_free()

func put(id: String, bp: FarmBlueprint, owner_name: String, own := false, avatar_ref := "") -> void:
	points[id] = {"center": bp.overlay.center, "bp": bp, "own": own, "owner_name": owner_name, "avatar_ref": avatar_ref}
	if _buttons.has(id): return
	var avatar_target := Button.new()
	avatar_target.size = Vector2(70, 92)
	avatar_target.tooltip_text = L10n.format_text("Select %s", owner_name)
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
	b.tooltip_text = L10n.format_text("Select %s", owner_name)
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
	var label := GameUi.label(owner_name, 11)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	_owner_labels[id] = label
	_buttons[id] = b
	var badge := GameUi.button("users-round", "", "Choose a farm at this location")
	badge.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	badge.custom_minimum_size = Vector2(54, 36)
	badge.size = badge.custom_minimum_size
	badge.add_theme_font_size_override("font_size", 11)
	badge.visible = false
	badge.name = "Cluster_" + id
	badge.pressed.connect(_toggle_cluster.bind(id))
	add_child(badge)
	_badges[id] = badge

func refresh_language() -> void:
	for id in points:
		var entry: Dictionary = points[id]
		var owner := str(entry.owner_name) if str(entry.avatar_ref).is_empty() else SeededOutfit.short_name(str(entry.avatar_ref))
		_owner_labels[id].text = owner
		var hint := L10n.format_text("Select %s", owner)
		_buttons[id].tooltip_text = hint
		_avatar_targets[id].tooltip_text = hint

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
		_owner_labels.erase(id)
	if not points.has(selected_id): selected_id = ""
	expanded_ids = expanded_ids.filter(func(id): return points.has(id))

func _toggle_cluster(id: String) -> void:
	if expanded_ids.has(id): expanded_ids.clear()
	else: expanded_ids = _clusters.get(id, [id]).duplicate()
	cluster_focused.emit(expanded_ids.duplicate())

func _on_marker_pressed(id: String) -> void:
	focused.emit(id)

func sync(cam: Camera3D, lat: float, lng: float, visible_area: Rect2) -> void:
	visible_farm_ids.clear()
	world_positions.clear()
	_clusters.clear()
	_show_ring = false
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
		if expanded_ids.has(id):
			_clusters[id] = [id]
			continue
		var representative := ""
		for existing in _clusters:
			if expanded_ids.has(existing): continue
			if (projected[existing] as Vector2).distance_to(projected[id]) < CLUSTER_DISTANCE:
				representative = str(existing)
				break
		if representative.is_empty(): _clusters[id] = [id]
		else: _clusters[representative].append(id)
	var expanded := expanded_ids.filter(func(id): return projected.has(id))
	if expanded.size() > 1:
		var center := Vector2.ZERO
		for id in expanded: center += projected[id]
		center /= expanded.size()
		for index in expanded.size():
			var offset := Vector2((index % 3 - (mini(3, expanded.size()) - 1) * 0.5) * 96, floori(index / 3.0) * 130)
			var point: Vector2 = center + offset
			point.x = clampf(point.x, visible_area.position.x + 46, visible_area.end.x - 46)
			point.y = clampf(point.y, visible_area.position.y + 96, visible_area.end.y - 48)
			projected[expanded[index]] = point
	var visible_badges: Array = []
	for id in _clusters:
		var anchor: Vector2 = projected[id]
		var world = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(anchor + global_position), cam.project_ray_normal(anchor + global_position))
		if world is Vector3: world_positions[id] = world
		var b: Button = _buttons[id]
		_avatar_targets[id].position = anchor - Vector2(35, 92)
		_avatar_targets[id].position.x = clampf(_avatar_targets[id].position.x, visible_area.position.x, visible_area.end.x - 70)
		_avatar_targets[id].visible = true
		b.visible = true
		b.position = anchor + Vector2(-MARKER_SIZE.x * 0.5, 12)
		b.position.x = clampf(b.position.x, visible_area.position.x, visible_area.end.x - MARKER_SIZE.x)
		b.theme_type_variation = &"ChoiceSelectedButton" if id == selected_id else &"ChoiceButton"
		visible_farm_ids.append(id)
		if _clusters[id].size() > 1 or (expanded.size() > 1 and id == expanded[0]):
			var badge: Button = _badges[id]
			var is_expanded: bool = expanded.has(id)
			badge.text = str(expanded.size() if is_expanded else _clusters[id].size())
			badge.icon = GameUi.icon("chevron-up" if is_expanded else "users-round")
			badge.position = anchor + Vector2(-badge.size.x * 0.5, 46)
			badge.position.x = clampf(badge.position.x, visible_area.position.x, visible_area.end.x - badge.size.x)
			badge.visible = true
			visible_badges.append(id)
			move_child(badge, -1)
		if id == selected_id:
			_selected_anchor = anchor
			_show_ring = true
			var base: Vector3 = world_positions.get(id, Vector3.ZERO)
			var distance := cam.global_position.distance_to(base)
			var unit := maxf(distance / 16.7, 0.001)
			var model_anchor := _model_anchor(anchor, projected, visible_area)
			var model_world = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(model_anchor + global_position), cam.project_ray_normal(model_anchor + global_position))
			miniature.position = model_world if model_world is Vector3 else base
			miniature.scale = Vector3.ONE * unit * 0.26
			miniature.show_farm(id, points[id].bp.region_id, points[id].bp.layout_patch_id, int(points[id].get("plots", 9)))
	for id in _buttons:
		_buttons[id].visible = visible_farm_ids.has(id)
		_avatar_targets[id].visible = visible_farm_ids.has(id)
		_badges[id].visible = visible_badges.has(id)
	if not _show_ring: miniature.hide()
	queue_redraw()

func _model_anchor(anchor: Vector2, projected: Dictionary, area: Rect2) -> Vector2:
	var best := anchor
	var best_score := INF
	for offset in [Vector2(96, 0), Vector2(-96, 0), Vector2(0, 135), Vector2(96, 135), Vector2(-96, 135), Vector2(0, -150)]:
		var candidate: Vector2 = anchor + offset
		candidate.x = clampf(candidate.x, area.position.x + 72, area.end.x - 72)
		candidate.y = clampf(candidate.y, area.position.y + 82, area.end.y - 32)
		var bounds := Rect2(candidate - Vector2(72, 82), Vector2(144, 114))
		var score: float = offset.length() * 0.01
		for id in projected:
			if not _clusters.has(id): continue
			var actor := Rect2(projected[id] - Vector2(44, 100), Vector2(88, 144))
			score += bounds.intersection(actor).get_area()
			if _clusters[id].size() > 1 or (not expanded_ids.is_empty() and id == expanded_ids[0]):
				var badge_size: Vector2 = _badges[id].size
				var badge_rect := Rect2(projected[id] + Vector2(-badge_size.x * 0.5, 46), badge_size)
				score += bounds.intersection(badge_rect).get_area()
		if score < best_score:
			best_score = score
			best = candidate
	return best

func _draw() -> void:
	if not _show_ring: return
	var ring := PackedVector2Array()
	for i in 49:
		var angle := TAU * i / 48.0
		ring.append(_selected_anchor + Vector2(cos(angle) * 23, sin(angle) * 9))
	draw_colored_polygon(ring, Color(GameUi.GOLD, 0.24))
	draw_polyline(ring, GameUi.GOLD, 3, true)
