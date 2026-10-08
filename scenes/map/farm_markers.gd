class_name FarmMarkers
extends Control
## City portraits/selected actors stay at geographic anchors. Legacy maps retain clusters.
signal focused(farm_id: String)
signal cluster_focused(farm_ids: Array)
const MARKER_SIZE := Vector2(88, 28)
const CLUSTER_DISTANCE := 80.0
const MINIATURE_OFFSET := Vector2(106, -24)
const MINIATURE_SCALE := 0.195
const MINIATURE_HALF_WIDTH := 54.0
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
var city_mode := false:
	set(value):
		if city_mode == value: return
		city_mode = value
		if not value:
			for id in _pin_tweens:
				if _pin_tweens[id] is Tween: (_pin_tweens[id] as Tween).kill()
			_pin_tweens.clear()
			_pin_anim.clear()
			for id in _buttons:
				var button: Button = _buttons[id]
				button.scale = Vector2.ONE
				_avatar_targets[id].scale = Vector2.ONE
				button.mouse_filter = Control.MOUSE_FILTER_STOP
				_avatar_targets[id].mouse_filter = Control.MOUSE_FILTER_STOP
				_avatar_targets[id].size = Vector2(70, 92)
				for portrait in _avatar_targets[id].get_children():
					portrait.position = Vector2(17, 46)
					portrait.show()
				button.custom_minimum_size = MARKER_SIZE
				button.size = MARKER_SIZE
				button.get_child(0).offset_top = 4
				button.get_child(0).offset_bottom = -3
				_owner_labels[id].add_theme_font_size_override("font_size", 11)
				for state in ["normal", "hover", "pressed", "focus"]:
					button.remove_theme_stylebox_override(state)
			_city_styled.clear()
var _city_styled := {}
var expanded_avatar_id := ""
## 城市模式玩家 pin 打包：上帧在位者带 8px 死区防闪烁；被折叠者计入幸存者的 +N。
const CITY_PACK_MARGIN := 8.0
var _city_shown_last: Dictionary = {}
## pin 显隐动画状态：id -> {on, pop}；出现果冻弹入、消失快速缩没（与 POI 一致）。
var _pin_anim: Dictionary = {}
var _pin_tweens: Dictionary = {}
## 城市地图当前 zoom（宿主每帧喂入）：视野最大时玩家 pin 放大到 1.3 倍。
var city_zoom := 16.0
## 城市模式投影（宿主喂入 geo_to_screen：pitch=0 时是精确 Mercator）。未设置时用相机投影。
var projector: Callable
## 国家/省级视野（宿主喂入）：只显示自己，且用 2D 头像代替 3D 全身。
var low_detail := false

func _pin_zoom_boost() -> float:
	return lerpf(1.3, 1.0, clampf((city_zoom - 11.0) / 4.0, 0.0, 1.0))

func _set_pin_shown(id: String, on: bool) -> void:
	if not _pin_anim.has(id):
		# put() 创建的按钮默认可见；以城市打包记录为准初始化，别信 Button 现状。
		var was := _city_shown_last.has(id)
		_pin_anim[id] = {"on": was, "pop": 1.0 if was else 0.0}
	var state: Dictionary = _pin_anim[id]
	var target: Button = _avatar_targets[id]
	var label: Button = _buttons[id]
	if bool(state.on) == on:
		# 状态没变也要纠正可见性：首次进入城市模式时按钮还带着 put() 的默认可见。
		target.visible = on or float(state.pop) > 0.0
		label.visible = target.visible
		return
	state.on = on
	if _pin_tweens.get(id) is Tween: (_pin_tweens[id] as Tween).kill()
	# 围绕地理锚点缩放：热区的锚点在底部中心，名牌的锚点在其上方 6px。
	target.pivot_offset = Vector2(target.size.x * 0.5, target.size.y - 2)
	label.pivot_offset = Vector2(label.size.x * 0.5, -6.0)
	var apply := func(value: float):
		state.pop = value
		target.scale = Vector2.ONE * maxf(0.001, value * _pin_zoom_boost())
		label.scale = target.scale
	if not on and float(state.pop) <= 0.0:
		target.visible = false
		label.visible = false
		return
	var tween := create_tween()
	_pin_tweens[id] = tween
	if on:
		target.visible = true
		label.visible = true
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_method(apply, float(state.pop), 1.0, 0.22)
	else:
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_method(apply, float(state.pop), 0.0, 0.12)
		tween.tween_callback(func():
			target.visible = false
			label.visible = false)

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
	avatar_target.name = "MapPlayer_" + id.validate_node_name()
	avatar_target.size = Vector2(70, 92)
	avatar_target.tooltip_text = L10n.format_text("Select %s", owner_name)
	avatar_target.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus"]:
		avatar_target.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	avatar_target.pressed.connect(_on_marker_pressed.bind(id))
	add_child(avatar_target)
	_avatar_targets[id] = avatar_target
	if not own:
		var portrait := MapPortrait.new()
		portrait.config = SeededOutfit.config_for(avatar_ref)
		avatar_target.add_child(portrait)
		portrait.position = Vector2(17, 46)
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

## A map mark (plan §9.5.2) on a farm's pin, e.g. P0's ✓ on the homestead when a Stall Board request can be
## handed in: hangs at the top-left of the farm's avatar target, follows its visibility; null clears it.
func set_mark(id: String, mark: Control) -> void:
	var target: Control = _avatar_targets.get(id)
	if target == null:
		if mark: mark.queue_free()
		return
	var old := target.get_node_or_null("MapMark")
	if old: old.queue_free()
	if mark == null: return
	mark.name = "MapMark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the pin takes the tap (LOCK-11)
	mark.position = Vector2(-6, -6)
	target.add_child(mark)

## 国家/省级视野下自己不画 3D 全身，改用与其他玩家同款的 2D 头像（跟随换装保存）。
func _add_self_portrait(target: Button) -> void:
	var portrait := MapPortrait.new()
	portrait.config = Avatar.load_outfit()
	target.add_child(portrait)
	Avatar.outfit_saved.connect(portrait.set_outfit)

## 该玩家 pin 当前画好的头像贴图；真头像还没渲染完成时返回 null（占位图不算）。
func portrait_texture(id: String) -> Texture2D:
	var target = _avatar_targets.get(id)
	if target == null: return null
	for child in target.get_children():
		if child is MapPortrait and not child._shown_key.is_empty() and child._shown_key == child._desired_key:
			return child.portrait.texture
	return null

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
		if _pin_tweens.get(id) is Tween: (_pin_tweens[id] as Tween).kill()
		_pin_tweens.erase(id)
		_pin_anim.erase(id)
		_buttons[id].queue_free()
		_badges[id].queue_free()
		_avatar_targets[id].queue_free()
		_buttons.erase(id)
		_badges.erase(id)
		_avatar_targets.erase(id)
		_owner_labels.erase(id)
		_city_styled.erase(id)
	if not points.has(selected_id): selected_id = ""
	if not points.has(expanded_avatar_id): expanded_avatar_id = ""
	expanded_ids = expanded_ids.filter(func(id): return points.has(id))

func _toggle_cluster(id: String) -> void:
	if expanded_ids.has(id): expanded_ids.clear()
	else: expanded_ids = _clusters.get(id, [id]).duplicate()
	cluster_focused.emit(expanded_ids.duplicate())

func _on_marker_pressed(id: String) -> void:
	focused.emit(id)

func sync(cam: Camera3D, lat: float, lng: float, visible_area: Rect2) -> void:
	if city_mode:
		_sync_city(cam, lat, lng)
		return
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
	if projected.has(selected_id):
		projected[selected_id] = _selected_layout_anchor(projected[selected_id], visible_area)
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
		b.position = anchor + Vector2(-b.size.x * 0.5, 12)
		b.position.x = clampf(b.position.x, visible_area.position.x, visible_area.end.x - b.size.x)
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
			miniature.scale = Vector3.ONE * unit * MINIATURE_SCALE
			miniature.show_farm(id, points[id].bp.region_id, points[id].bp.layout_patch_id, int(points[id].get("plots", 9)))
	for id in _buttons:
		_buttons[id].visible = visible_farm_ids.has(id)
		_avatar_targets[id].visible = visible_farm_ids.has(id)
		_badges[id].visible = visible_badges.has(id)
	if not _show_ring: miniature.hide()
	queue_redraw()

func _sync_city(cam: Camera3D, lat: float, lng: float) -> void:
	visible_farm_ids.clear()
	world_positions.clear()
	_clusters.clear()
	expanded_ids.clear()
	_show_ring = false
	miniature.hide()
	var area := Rect2(-global_position, get_viewport_rect().size).grow(140)
	var ids := points.keys()
	ids.sort()
	# 打包顺序：3D 的自己永不被盖 > 展开全身者 > 选中者 > 其余（id 稳定序）。
	# 锚点绝不挪动：重叠的 pin 整个折叠，计入幸存者名牌的 +N；被折叠的玩家
	# 仍然在附近农场主面板里可选。
	for priority in [selected_id, expanded_avatar_id, "self"]:
		if ids.has(priority):
			ids.erase(priority)
			ids.push_front(priority)
	var occupied: Array = []
	var pile: Dictionary = {}
	var shown_now: Dictionary = {}
	var anchors: Dictionary = {}
	for id in ids:
		var ll: Vector2 = points[id].center
		var world := MapGeoMath.geo_to_world(ll.x, ll.y, lat, lng)
		var projected = projector.call(ll.x, ll.y) if projector.is_valid() else (null if cam.is_position_behind(world) else cam.unproject_position(world))
		var anchor: Vector2 = (projected as Vector2) - global_position if projected != null else Vector2(-1e6, -1e6)
		world_positions[id] = world
		anchors[id] = anchor
		var target: Button = _avatar_targets[id]
		var label: Button = _buttons[id]
		if not _city_styled.has(id):
			_city_styled[id] = true
			label.custom_minimum_size = Vector2(66, 20)
			label.size = label.custom_minimum_size
			_owner_labels[id].add_theme_font_size_override("font_size", 9)
			label.get_child(0).offset_top = 1
			label.get_child(0).offset_bottom = -1
			for state in ["normal", "hover", "pressed", "focus"]:
				label.add_theme_stylebox_override(state, CityMapView.marker_style())
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badges[id].visible = false
		var full_body: bool = (id == "self" or id == expanded_avatar_id) and not low_detail
		if id == "self" and low_detail and target.get_child_count() == 0: _add_self_portrait(target)
		target.size = Vector2(70, 130) if full_body else Vector2(44, 44)
		var boost := _pin_zoom_boost()
		var rect := Rect2(anchor - Vector2(target.size.x * 0.5, target.size.y - 2), target.size).merge(
			Rect2(anchor + Vector2(-label.size.x * 0.5, 6), label.size)).grow((boost - 1.0) * 22.0)
		var placed: bool = projected != null and area.has_point(anchor) and (id == "self" or not low_detail)
		if placed and not (id == "self" or id == expanded_avatar_id or id == selected_id):
			var probe := rect.grow(-CITY_PACK_MARGIN if _city_shown_last.has(id) else CITY_PACK_MARGIN)
			for pair in occupied:
				if (pair[0] as Rect2).intersects(probe):
					placed = false
					pile[pair[1]] = int(pile.get(pair[1], 0)) + 1
					break
		if placed:
			occupied.append([rect, id])
			shown_now[id] = true
			target.position = anchor - Vector2(target.size.x * 0.5, target.size.y - 2)
			for portrait in target.get_children():
				portrait.visible = not full_body
				portrait.position = Vector2(4, 4)
			label.position = anchor + Vector2(-label.size.x * 0.5, 6)
			visible_farm_ids.append(id)
			# 在位 pin 每帧应用 zoom 放大系数（动画进行中的由 tween 内部乘算）。
			if not (_pin_tweens.get(id) is Tween and (_pin_tweens[id] as Tween).is_running()):
				target.pivot_offset = Vector2(target.size.x * 0.5, target.size.y - 2)
				label.pivot_offset = Vector2(label.size.x * 0.5, -6.0)
				var steady_pop := float((_pin_anim.get(id, {}) as Dictionary).get("pop", 1.0))
				target.scale = Vector2.ONE * maxf(0.001, steady_pop * boost)
				label.scale = target.scale
		_set_pin_shown(id, placed)
		# 国家级：自己只留头像，名牌会压在城市气泡上。
		if low_detail and id == "self": label.visible = false
		if id == "self" and self_label_yields: label.visible = false   # under an outpost label (C30)
	for id in visible_farm_ids:
		var entry: Dictionary = points[id]
		var owner := str(entry.owner_name) if str(entry.avatar_ref).is_empty() else SeededOutfit.short_name(str(entry.avatar_ref))
		# 折叠数量的 +N 不能被省略号吃掉：带后缀时名牌加宽并保持锚点居中。
		var label: Button = _buttons[id]
		label.custom_minimum_size.x = 96.0 if pile.has(id) else 66.0
		label.size = Vector2(label.custom_minimum_size.x, 20)
		label.position.x = (anchors[id] as Vector2).x - label.size.x * 0.5
		_owner_labels[id].text = L10n.text(owner) + (" +%d" % int(pile[id]) if pile.has(id) else "")
	_city_shown_last = shown_now
	# Deterministic paint order; selecting never relocates neighbouring portraits.
	if visible_farm_ids.has(selected_id):
		move_child(_avatar_targets[selected_id], -1)
		move_child(_buttons[selected_id], -1)
	queue_redraw()

## The player's own label has given way to an outpost label (CityMapView._yield_own_label): it stays hidden until
## they part.
var self_label_yields := false

## The player's own name label as drawn (local space) while their pin is shown in the city; an empty rect otherwise.
## The label is scaled about its pivot by the zoom boost (1.3 at z11): the whole drawn rect counts (不知火舞 on #83).
func self_label_rect() -> Rect2:
	if not city_mode or low_detail or not visible_farm_ids.has("self") or not _buttons.has("self"): return Rect2()
	var label: Button = _buttons["self"]
	var s := maxf(label.scale.x, _pin_zoom_boost())   # never less than the steady boost, even mid-pop
	return Rect2(label.position + label.pivot_offset * (1.0 - s), label.size * s)

func yield_self_label(on: bool) -> void:
	self_label_yields = on
	if _buttons.has("self") and _avatar_targets.has("self"):
		(_buttons["self"] as Button).visible = (_avatar_targets["self"] as Control).visible and not low_detail and not on

## City-mode screen footprints of players (local space): the city POI layer
## packs its markers around people so artwork never buries an avatar's pin.
func blocker_rects() -> Array:
	var result: Array = []
	if not city_mode: return result
	for id in visible_farm_ids:
		var target: Control = _avatar_targets[id]
		var rect := Rect2(target.position, target.size)
		if (id == "self" or id == expanded_avatar_id) and not low_detail:
			# The full-body 3D actor draws wider and taller than its tap target.
			rect = rect.grow_individual(26, 84, 26, 0)
		result.append(rect.merge(Rect2(_buttons[id].position, _buttons[id].size)))
	return result

func activate_at(screen: Vector2) -> bool:
	var ids := visible_farm_ids.duplicate()
	if city_mode:
		ids.reverse()
		if ids.has(selected_id):
			ids.erase(selected_id)
			ids.push_front(selected_id)
	for id in ids:
		if _badges[id].visible and _badges[id].get_global_rect().has_point(screen):
			_toggle_cluster(id)
			return true
		if _avatar_targets[id].get_global_rect().has_point(screen) or _buttons[id].get_global_rect().has_point(screen):
			_on_marker_pressed(id)
			return true
	return false

func _selected_layout_anchor(anchor: Vector2, area: Rect2) -> Vector2:
	# Reserve space for the owner and farm together, so the farm never changes sides.
	var right := maxf(area.position.x + 44, area.end.x - MINIATURE_OFFSET.x - MINIATURE_HALF_WIDTH)
	var bottom := maxf(area.position.y + 100, area.end.y - 84)
	return Vector2(clampf(anchor.x, area.position.x + 44, right),
		clampf(anchor.y, area.position.y + 100, bottom))

func _model_anchor(anchor: Vector2, projected: Dictionary, area: Rect2) -> Vector2:
	var best := anchor + MINIATURE_OFFSET
	var best_score := INF
	for offset_y in [-24.0, 12.0, 48.0, 84.0, -60.0, -96.0]:
		var candidate := Vector2(anchor.x + MINIATURE_OFFSET.x,
			clampf(anchor.y + offset_y, area.position.y + 62, maxf(area.position.y + 62, area.end.y - 24)))
		var bounds := Rect2(candidate - Vector2(MINIATURE_HALF_WIDTH, 62), Vector2(108, 86))
		var score := absf(offset_y - MINIATURE_OFFSET.y) * 0.01
		for id in projected:
			if not _clusters.has(id): continue
			score += bounds.intersection(Rect2(projected[id] - Vector2(44, 100), Vector2(88, 144))).get_area()
			if _clusters[id].size() > 1:
				var badge: Button = _badges[id]
				score += bounds.intersection(Rect2(projected[id] + Vector2(-badge.size.x * 0.5, 46), badge.size)).get_area()
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
