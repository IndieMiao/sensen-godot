class_name FishingPanel
extends CanvasLayer

signal closed
signal opened(site: String)
signal cast_started

var session: FarmSession
var site_id := ""
var site_spec: Dictionary = {}
var landing := Vector3.ZERO
var phase := "ready"
var busy := false
var model: Dictionary = {}
var inputs := ""
var held := false
var _suppress_next_click := false
var _accumulator := 0.0
var _interrupted := false
var _farm_id := ""
var _cast_sequence := -1
var _notice_heading: Label
var _notice_kind := "normal"
var _notice_tween: Tween
var _status: Label
var _title: Label
var _guide: Label
var _primary: Button
var _close_button: Button
var _gauge: Control
var _root: Control
var _safe: SafeAreaMargin
var _message_card: PanelContainer
var _world_anchor := Vector2.ZERO

func _ready() -> void:
	layer = 30
	GameUi.register_modal(self)
	# Transparent input shield prevents world actions; it does not dim the scene.
	var shield := Control.new()
	shield.name = "FishingInputShield"
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shield)
	_safe = SafeAreaMargin.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.theme = GameUi.theme()
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_root)
	_title = GameUi.label("", 14, GameUi.INK)
	_title.add_theme_color_override("font_shadow_color", GameUi.PAPER)
	_title.add_theme_constant_override("shadow_offset_x", 1)
	_title.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(_title)
	_close_button = GameUi.button("x", "", L10n.text("Stop fishing"))
	_close_button.name = "CloseFishing"
	_close_button.pressed.connect(close)
	_root.add_child(_close_button)
	_message_card = PanelContainer.new()
	_message_card.name = "FishingNotice"
	_message_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A one-line notice can be shorter than the large panel's two 32px corners.
	# Use the compact skin with the same text padding so its slices never overlap.
	var notice_style := GameUi.panel_style(8)
	notice_style.set_content_margin_all(12)
	_message_card.add_theme_stylebox_override("panel", notice_style)
	_root.add_child(_message_card)
	_status = GameUi.label("", 14, GameUi.INK)
	_status.name = "FishingStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var message_column := VBoxContainer.new()
	message_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_column.add_theme_constant_override("separation", 5)
	_message_card.add_child(message_column)
	_notice_heading = GameUi.label("", 19, GameUi.BLUE)
	_notice_heading.name = "FishingOutcome"
	_notice_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_heading.hide()
	message_column.add_child(_notice_heading)
	message_column.add_child(_status)
	_guide = GameUi.label("", 12, GameUi.INK)
	_guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide.add_theme_color_override("font_shadow_color", GameUi.PAPER)
	_guide.add_theme_constant_override("shadow_offset_y", 1)
	_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_guide)
	_gauge = preload("res://scenes/fishing/fishing_gauge.gd").new()
	_gauge.name = "FishingGauge"
	_root.add_child(_gauge)
	_primary = preload("res://scenes/fishing/fishing_action.gd").new()
	_primary.name = "FishingAction"
	_primary.theme_type_variation = &"AccentButton"
	_primary.icon = GameUi.icon("fish")
	_primary.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_primary.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	_primary.expand_icon = true
	_primary.clip_text = true
	_primary.add_theme_constant_override("icon_max_width", 26)
	_primary.add_theme_font_size_override("font_size", 14)
	_primary.button_down.connect(func():
		_suppress_next_click = phase == "playing"
		if phase == "playing": held = true)
	_primary.button_up.connect(func(): held = false)
	_primary.mouse_exited.connect(func(): held = false)
	_primary.pressed.connect(_action)
	_root.add_child(_primary)
	# Wrapped text can report a tall minimum before its first width allocation.
	# Refit after the container resolves the text so old height cannot cover the water.
	_message_card.minimum_size_changed.connect(_fit.call_deferred)
	_root.resized.connect(_fit)
	_fit.call_deferred()
	hide()

func _fit() -> void:
	if _root == null: return
	var area := _root.size
	var diameter := 84.0
	_primary.size = Vector2.ONE * diameter
	_primary.position = Vector2((area.x - diameter) * 0.5, area.y - diameter - clampf(area.y * 0.09, 48, 74)).round()
	_close_button.size = Vector2(44, 44)
	_close_button.position = Vector2(area.x - 44, 0)
	_title.position = Vector2(4, 12)
	_title.size = Vector2(maxf(1, area.x - 60), 24)
	_guide.size = Vector2(area.x, 20)
	_guide.position = Vector2(0, _primary.position.y - 26)
	var width := minf(278, area.x - 8)
	_message_card.size = Vector2(width, 0)
	_message_card.position = Vector2((area.x - width) * 0.5, clampf(area.y * 0.23, 76, 176))
	_gauge.size = Vector2(64, clampf(area.y * 0.28, 142, 210))
	_place_gauge()

func anchor_gauge(screen_point: Vector2) -> void:
	_world_anchor = screen_point
	_place_gauge()

func _place_gauge() -> void:
	if not _gauge or not _root: return
	var anchor := _world_anchor - _root.global_position
	if _world_anchor.is_zero_approx(): anchor = _root.size * Vector2(0.32, 0.46)
	var top := maxf(62, _message_card.position.y + _message_card.get_combined_minimum_size().y + 18) if _message_card.visible else 62.0
	var bottom := maxf(62, _guide.position.y - _gauge.size.y - 24)
	_gauge.position = Vector2(clampf(anchor.x - _gauge.size.x - 28, 2, maxf(2, _root.size.x - _gauge.size.x)),
		clampf(anchor.y - _gauge.size.y * 0.55, minf(top, bottom), bottom))

func open(value: FarmSession, target: String, water_target := Vector3.INF, site_override: Dictionary = {}) -> void:
	if busy or value == null: return
	session = value
	site_id = target
	site_spec = FishingModel.site(target, site_override).duplicate(true)
	landing = water_target if water_target.is_finite() else FishingModel.default_target(target, FishingModel.stand(target, site_spec), site_spec)
	_farm_id = session.farm_id
	_cast_sequence = -1
	_interrupted = false
	phase = "ready"
	model = {}
	_gauge.model = {}
	_gauge.queue_redraw()
	_title.text = L10n.text(str(site_spec.name))
	_guide.text = L10n.text("Tap to cast · tap again when a fish bites")
	_show_notice(L10n.text("Cast when you are ready."))
	show()
	_refresh_button()
	opened.emit(target)

func _refresh_button() -> void:
	if not _primary: return
	_close_button.disabled = busy
	_primary.set("progress", float(model.get("progress", 0)) if phase == "playing" else 0.0)
	_primary.set("pulling", false)
	_primary.queue_redraw()
	_primary.disabled = busy or phase == "waiting"
	if session and (session.offline or session.has_unconfirmed_command()) and not busy:
		_primary.disabled = false
		_primary.text = L10n.text("Retry")
	else:
		_primary.text = L10n.text({"ready": "Cast", "casting": "Cast", "waiting": "Wait", "hook": "Hook",
			"playing": "Reel", "settling": "Saving", "result": "Again", "error": "Retry"}.get(phase, "Cast line"))
	if phase == "settling" and model.get("outcome") == "escaped": _primary.text = L10n.text("Reeling in")
	_gauge.set("feedback_active", phase == "playing")
	_gauge.visible = phase in ["playing", "settling"] and not model.is_empty()
	_message_card.visible = phase != "playing" or int(model.get("step", 0)) < 40
	_guide.text = L10n.text("Hold to reel · release to ease") if phase == "playing" else L10n.text("Tap to cast · tap again when a fish bites")
	_guide.visible = phase in ["ready", "playing"]
	_fit.call_deferred()

func _action() -> void:
	if _suppress_next_click:
		_suppress_next_click = false
		return
	if busy or phase == "playing" or session == null: return
	if session.offline or session.has_unconfirmed_command():
		busy = true
		_refresh_button()
		var accepted := await session.refresh()
		busy = false
		if not is_inside_tree(): return
		phase = "ready" if accepted else "error"
		var result: Dictionary = session.state.get("fishing", {}).get("last", {})
		if accepted and _active().is_empty() and int(result.get("sequence", -2)) == _cast_sequence:
			phase = "result"
			_show_result(result)
		elif accepted: _show_notice(L10n.text("Cast when you are ready."))
		else: _show_error(session.last_error_code)
		_refresh_button()
	elif phase == "hook": await _hook()
	elif phase in ["ready", "result", "error"]: await _cast()

func _sequence() -> int:
	return int(session.state.get("fishing", {}).get("sequence", 0))

func _active() -> Dictionary:
	var value = session.state.get("fishing", {}).get("active")
	return value if value is Dictionary else {}

func _send(type: String, extra: Dictionary = {}) -> bool:
	busy = true
	held = false
	_refresh_button()
	var payload := {"sequence": _sequence()}
	payload.merge(extra)
	var accepted := await session.send(type, payload)
	busy = false
	if not is_inside_tree(): return false
	if session.farm_id != _farm_id:
		hide()
		closed.emit()
		return false
	if not accepted:
		_show_error(session.last_error_code)
	_refresh_button()
	return accepted

func _cast() -> void:
	if not CharacterModel.has_fishing_rod(session.state):
		_show_error("FISHING_ROD_REQUIRED")
		_refresh_button()
		return
	_interrupted = false
	if not _active().is_empty():
		if not await _send("cancel_fishing"): return
	if _interrupted: return
	model = {}
	_cast_sequence = _sequence() + 1
	phase = "casting"
	_show_notice(L10n.text("Casting..."))
	cast_started.emit()
	if not await _send("cast_fishing", {"site_id": site_id, "target": [landing.x, landing.z]}): return
	if _interrupted:
		await _cancel("interrupted")
		return
	phase = "waiting"
	model = {}
	_gauge.model = {}
	_gauge.queue_redraw()
	_show_notice(L10n.text("Watch the float. Tap when a fish bites!"))
	_refresh_button()

func _hook() -> void:
	if not await _send("hook_fishing"): return
	if _interrupted:
		await _cancel("interrupted")
		return
	var active := _active()
	if active.is_empty():
		_show_error("FISHING_CHANGED")
		_refresh_button()
		return
	model = FishingModel.initial(int(active.seed))
	inputs = ""
	_accumulator = 0
	phase = "playing"
	var id := str(active.fish_id)
	_gauge.bar_size = float(FishingModel.data().tiers[str(int(FishingModel.fish(id).tier))].bar_size)
	_gauge.fish_texture = ItemCatalog.texture(id)
	_show_notice(FishingModel.tier_name(id) + " · " + L10n.text("Keep the fish inside the green bar."))
	_refresh_button()

func _process(dt: float) -> void:
	if not visible or session == null or busy: return
	if _farm_id != session.farm_id:
		hide()
		closed.emit()
		return
	if phase in ["waiting", "hook"]:
		var active := _active()
		if active.is_empty():
			_show_error("FISHING_CHANGED")
			_refresh_button()
			return
		if session.server_now() > int(active.hook_until):
			await _cancel("missed")
		elif session.server_now() >= int(active.bite_at) and phase != "hook":
			phase = "hook"
			_show_notice(L10n.text("A bite! Tap to hook the fish!"))
			Input.vibrate_handheld(80)
			_refresh_button()
	elif phase == "playing":
		if dt > 0.5:
			await _cancel("interrupted")
			return
		_accumulator += dt
		var active := _active()
		if active.is_empty():
			_show_error("FISHING_CHANGED")
			_refresh_button()
			return
		var tier: Dictionary = FishingModel.data().tiers[str(int(FishingModel.fish(str(active.fish_id)).tier))]
		var step_s := float(FishingModel.data().step_ms) / 1000.0
		while _accumulator >= step_s and model.outcome == "playing":
			_accumulator -= step_s
			inputs += "1" if held else "0"
			FishingModel.step(model, held, tier)
		_gauge.model = model
		_gauge.queue_redraw()
		_message_card.visible = int(model.get("step", 0)) < 40
		_primary.set("progress", float(model.progress))
		_primary.set("pulling", held)
		_primary.queue_redraw()
		if model.outcome != "playing":
			phase = "settling"
			if model.outcome == "escaped": _show_notice(L10n.text("Reeling in the empty line…"), L10n.text("Fish escaped"), "failed")
			else: _show_notice(L10n.text("Saving..."))
			if await _send("finish_fishing", {"inputs": inputs}):
				phase = "result"
				_show_result(session.state.get("fishing", {}).get("last", {}))
			_refresh_button()

func _result_text(result: Dictionary) -> String:
	if result.get("outcome") != "caught": return L10n.text("The fish escaped. Try another cast.")
	var id := str(result.get("fish_id", ""))
	var text := L10n.format_text("%s · %s +1\nSell value: %d coins", [ItemCatalog.name_of(id), FishingModel.tier_name(id), int(FishingModel.fish(id).price)])
	if result.get("overflow", false): text += "\n" + L10n.text("Bag full: your fish is safe in overflow.")

	return text

func _cancel(reason := "stopped") -> void:
	held = false
	phase = "result"
	if reason == "missed":
		_show_notice(L10n.text("Missed the bite. Tap Hook when the float dips."), L10n.text("Fish escaped"), "failed")
	elif reason == "interrupted":
		_show_notice(L10n.text("Return to the water and cast again."), L10n.text("Fishing interrupted"), "failed")
	else: _show_notice(L10n.text("Fishing stopped. Your saved catches are safe."))
	if not _active().is_empty():
		if session.offline or session.has_unconfirmed_command():
			_show_error(session.last_error_code)
			_refresh_button()
			return
		if not await _send("cancel_fishing"): return
	_refresh_button()

func _show_result(result: Dictionary) -> void:
	if result.get("outcome") == "caught":
		_show_notice(_result_text(result), L10n.text("Fish caught!"), "caught")
	elif result.get("outcome") == "cancelled":
		_show_notice(L10n.text("Fishing stopped. Your saved catches are safe."))
	else:
		_show_notice(L10n.text("No fish this time. Tap Again to try another cast."), L10n.text("Fish escaped"), "failed")
		Input.vibrate_handheld(100)

func _show_error(code: String) -> void:
	phase = "error"
	if session and (session.offline or session.has_unconfirmed_command()):
		_show_notice(L10n.text("Connection interrupted. Tap Retry to check this cast."), L10n.text("Checking your catch"), "failed")
	elif code == "FISHING_TIMING":
		_show_notice(L10n.text("This cast timed out. Cast again."), L10n.text("Fish escaped"), "failed")
	else: _show_notice(error_text(code), L10n.text("Fishing did not finish"), "failed")

func _show_notice(text: String, heading := "", kind := "normal") -> void:
	_status.text = text
	_notice_heading.text = heading
	_notice_heading.visible = not heading.is_empty()
	var accent := GameUi.BLUE
	if kind == "failed":
		accent = GameUi.CORAL
	elif kind == "caught":
		accent = GameUi.GREEN
	_notice_heading.add_theme_color_override("font_color", accent)
	if kind != _notice_kind:
		if _notice_tween and _notice_tween.is_valid(): _notice_tween.kill()
		_message_card.modulate.a = 0.5
		_notice_tween = create_tween()
		_notice_tween.tween_property(_message_card, "modulate:a", 1.0, 0.18)
	_notice_kind = kind
	_fit.call_deferred()

func close() -> void:
	if busy: return
	await _cancel()
	hide()
	closed.emit()

func interrupt() -> void:
	if not visible: return
	_interrupted = true
	held = false
	if not busy: _cancel("interrupted")

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]: interrupt()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventScreenTouch and not event.pressed: held = false
	if event is InputEventMouseButton and not event.pressed: held = false

static func error_text(code: String) -> String:
	match code:
		"FISHING_ROD_REQUIRED": return L10n.text("Equip a fishing rod on the character page first.")
		"FISHING_LOCATION": return L10n.text("Stand near the water and reconnect to the area before casting.")
		"FISHING_TIMING": return L10n.text("The fish escaped. Try another cast.")
		"FISHING_CHANGED", "FISHING_ACTIVE", "FISHING_INPUT": return L10n.text("This cast has ended. Check the result, then cast again.")
	return SessionPanel.error_text(code)
