class_name DecorationPanel
extends SessionPanel

signal preview_changed(props: Array)
signal navigation_confirmed
signal navigation_cancelled

const PENDING_META := "pending_decoration_command"
var dirty := false
var selected_prop := "bench"
var _draft: Array = []
var _baseline: Array = []
var _history: Array = []
var _confirm_leave := false
var compact := false
var _drag_active := false
var _drag_origin: Array = []

func pending_key() -> StringName:
	return PENDING_META

func setup(value: FarmSession) -> void:
	super.setup(value)
	_baseline = DecorationLayout.saved(state())
	_draft = _baseline.duplicate(true)
	if JourneyProgress.active(state()): selected_prop = "planter"
	if session and session.has_meta(PENDING_META):
		_draft = session.get_meta(PENDING_META).get("props", _baseline).duplicate(true)
	dirty = _draft != _baseline

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	super._ready()
	if session: session.state_changed.connect(_server_changed)
	preview_changed.emit(_draft.duplicate(true))

func preview() -> Array:
	return _draft.duplicate(true)

func _server_changed(_state: Dictionary, _version: int) -> void:
	_baseline = DecorationLayout.saved(state())
	if not dirty and not busy:
		_draft = _baseline.duplicate(true)
		preview_changed.emit(preview())
	elif not busy:
		dirty = _draft != _baseline
	refresh()

func _render() -> void:
	if _uncertain():
		heading("Check your arrangement")
		paragraph("Your last save needs to be checked.")
		var check := GameUi.button("rotate-ccw", "Check saved layout", "Reload the saved arrangement", true)
		check.name = "CheckSavedLayout"
		check.disabled = busy
		check.pressed.connect(reconcile_save)
		content.add_child(check)
		return
	if _confirm_leave:
		heading("Unsaved arrangement")
		paragraph("Save this arrangement before leaving?")
		action("check", "Save and continue", _save_before_leave, DecorationLayout.unlocked(state()), true).name = "SaveAndLeaveDecorations"
		_local_action("x", "Discard changes", "Restore the saved arrangement", _discard_and_leave).name = "DiscardDecorationChanges"
		_local_action("arrow-left", "Keep editing", "Return to the arrangement", _keep_editing).name = "KeepEditingDecorations"
		return
	if compact:
		_render_compact()
		return
	heading("Courtyard pieces")
	paragraph("%d / 6 placed" % _draft.size())
	if not DecorationLayout.unlocked(state()):
		paragraph("Preview only until your first growth purchase.")
	var picker := OptionButton.new()
	picker.name = "DecorationPicker"
	picker.custom_minimum_size.y = 44
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.disabled = busy
	for id in DecorationLayout.IDS:
		if JourneyProgress.active(state()) and not JourneyProgress.unlocked(state(), "decorations") and id != "planter": continue
		var placed := DecorationLayout.index_of(_draft, str(id)) >= 0
		picker.add_item(DecorationLayout.name_of(str(id)) + (" (placed)" if placed else ""))
		picker.get_popup().set_item_icon_modulate(picker.item_count - 1, GameUi.GREEN if id == selected_prop else GameUi.MUTED)
	var allowed := ["planter"] if JourneyProgress.active(state()) and not JourneyProgress.unlocked(state(), "decorations") else DecorationLayout.IDS
	if not allowed.has(selected_prop): selected_prop = "planter"
	picker.selected = allowed.find(selected_prop)
	picker.item_selected.connect(func(index: int): select_prop(str(allowed[index])))
	content.add_child(picker)
	var existing := DecorationLayout.index_of(_draft, selected_prop)
	if existing < 0:
		_local_action("plus", "Place", "Place selected piece", place_selected, DecorationLayout.first_position(selected_prop, _draft) != null).name = "PlaceDecoration"
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		content.add_child(row)
		var moves := [["arrow-left", Vector2i(-1, 0), "Move left"], ["chevron-up", Vector2i(0, -1), "Move back"],
			["chevron-down", Vector2i(0, 1), "Move forward"], ["chevron-right", Vector2i(1, 0), "Move right"]]
		for index in moves.size():
			var spec: Array = moves[index]
			var button := GameUi.button(str(spec[0]), "", str(spec[2]))
			button.name = "MoveDecoration%d" % index
			button.custom_minimum_size = Vector2(44, 44)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.disabled = busy or not can_adjust(spec[1])
			button.pressed.connect(func(): adjust(spec[1]))
			row.add_child(button)
		_local_action("minus", "Remove", "Remove selected piece", remove_selected).name = "RemoveDecoration"
		_local_action("rotate-cw", "", "Rotate selected piece", rotate_selected).name = "RotateDecoration"
	var history := HBoxContainer.new()
	history.add_theme_constant_override("separation", 8)
	content.add_child(history)
	for spec in [["rotate-ccw", "Undo", undo, not _history.is_empty()], ["x", "Cancel", cancel_preview, dirty]]:
		var button := GameUi.button(str(spec[0]), str(spec[1]), str(spec[1]))
		button.name = str(spec[1]) + "Decoration"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = busy or not bool(spec[3])
		button.pressed.connect(spec[2])
		history.add_child(button)
	action("check", "Save layout", save_layout, dirty and DecorationLayout.unlocked(state()), true).name = "SaveDecorations"

func _render_compact() -> void:
	var allowed: Array = ["planter"] if JourneyProgress.active(state()) and not JourneyProgress.unlocked(state(), "decorations") else DecorationLayout.IDS
	if not allowed.has(selected_prop): selected_prop = str(allowed[0])
	var picker := OptionButton.new()
	picker.name = "DecorationPicker"
	picker.custom_minimum_size.y = 44
	picker.disabled = busy
	for id in allowed: picker.add_item(DecorationLayout.name_of(str(id)))
	picker.selected = allowed.find(selected_prop)
	picker.item_selected.connect(func(index): select_prop(str(allowed[index])))
	content.add_child(picker)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	content.add_child(row)
	var placed := DecorationLayout.index_of(_draft, selected_prop) >= 0
	for spec in [["plus", "Place selected piece", place_selected, not placed],
		["rotate-cw", "Rotate selected piece", rotate_selected, placed],
		["rotate-ccw", "Undo arrangement", undo, not _history.is_empty()],
		["minus", "Remove selected piece", remove_selected, placed],
		["x", "Cancel arrangement", cancel_preview, dirty],
		["check", "Save layout", save_layout, dirty and DecorationLayout.unlocked(state())]]:
		var button := GameUi.button(str(spec[0]), "", str(spec[1]), spec[0] == "check")
		button.custom_minimum_size = Vector2(44, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = busy or not bool(spec[3]) or (spec[0] == "check" and (session == null or session.offline))
		button.pressed.connect(spec[2])
		row.add_child(button)

func _local_action(icon: String, text: String, tooltip: String, callback: Callable, enabled := true) -> Button:
	var button := GameUi.button(icon, text, tooltip)
	button.disabled = busy or not enabled
	button.pressed.connect(callback)
	content.add_child(button)
	return button

func select_prop(id: String) -> void:
	if busy or _uncertain() or _confirm_leave or not DecorationLayout.IDS.has(id): return
	selected_prop = id
	preview_changed.emit(preview())
	refresh()

func pick_at(world: Vector3) -> bool:
	if busy or _uncertain() or _confirm_leave: return false
	var nearest := 0.6
	var id := ""
	for prop in _draft:
		var distance := Vector2(world.x, world.z).distance_to(Vector2(DecorationLayout.world_position(prop).x, DecorationLayout.world_position(prop).z))
		if distance < nearest:
			nearest = distance
			id = str(prop.prop_id)
	if id.is_empty(): return false
	select_prop(id)
	return true

func place_selected() -> bool:
	if busy or _uncertain() or _confirm_leave: return false
	var q = DecorationLayout.first_position(selected_prop, _draft)
	if q == null: return false
	return _change(DecorationLayout.with_position(_draft, selected_prop, q))

func place_at(world: Vector3) -> bool:
	if busy or _uncertain() or _confirm_leave or not is_finite(world.x) or not is_finite(world.z): return false
	var next := DecorationLayout.with_position(_draft, selected_prop, DecorationLayout.quantize(world))
	if not DecorationLayout.is_valid(next):
		if message: message.text = "This spot needs more room."
		return false
	return _change(next)

func can_adjust(delta: Vector2i) -> bool:
	var index := DecorationLayout.index_of(_draft, selected_prop)
	if index < 0: return false
	var q: Array = _draft[index].offset_q
	return DecorationLayout.is_valid(DecorationLayout.with_position(_draft, selected_prop, Vector2i(int(q[0]), int(q[1])) + delta))

func adjust(delta: Vector2i) -> bool:
	if busy or _uncertain() or _confirm_leave or not can_adjust(delta): return false
	var index := DecorationLayout.index_of(_draft, selected_prop)
	var q: Array = _draft[index].offset_q
	return _change(DecorationLayout.with_position(_draft, selected_prop, Vector2i(int(q[0]), int(q[1])) + delta))

func remove_selected() -> void:
	if busy or _uncertain() or _confirm_leave: return
	var index := DecorationLayout.index_of(_draft, selected_prop)
	if index < 0: return
	var next := preview()
	next.remove_at(index)
	_change(next)

func rotate_selected() -> bool:
	if busy or _uncertain() or _confirm_leave: return false
	var next := preview()
	var index := DecorationLayout.index_of(next, selected_prop)
	if index < 0: return false
	next[index].rotation_q = (int(next[index].get("rotation_q", 0)) + 1) % 4
	return _change(DecorationLayout.canonical(next))

func _change(next: Array) -> bool:
	if next == _draft or not DecorationLayout.is_valid(next): return false
	if not _drag_active:
		_history.append(preview())
		if _history.size() > 50: _history.pop_front()
	_draft = next.duplicate(true)
	dirty = _draft != _baseline
	if message: message.text = ""
	preview_changed.emit(preview())
	refresh()
	return true

func begin_drag() -> void:
	if _drag_active or busy or _uncertain() or _confirm_leave: return
	_drag_active = true
	_drag_origin = preview()

func end_drag(canceled := false) -> void:
	if not _drag_active: return
	_drag_active = false
	if _draft != _drag_origin:
		if canceled:
			_draft = _drag_origin.duplicate(true)
			dirty = _draft != _baseline
			preview_changed.emit(preview())
		else:
			_history.append(_drag_origin.duplicate(true))
			if _history.size() > 50: _history.pop_front()
	_drag_origin.clear()
	refresh()

func undo() -> void:
	if busy or _uncertain() or _confirm_leave or _history.is_empty(): return
	_draft = _history.pop_back()
	dirty = _draft != _baseline
	preview_changed.emit(preview())
	refresh()

func cancel_preview() -> void:
	if busy or _uncertain(): return
	_baseline = DecorationLayout.saved(state())
	_draft = _baseline.duplicate(true)
	_history.clear()
	dirty = false
	if message: message.text = ""
	preview_changed.emit(preview())
	refresh()

func save_layout() -> bool:
	if busy or _uncertain() or not dirty or session == null or session.offline or not DecorationLayout.unlocked(state()): return false
	if not DecorationLayout.is_valid(_draft): return false
	session.set_meta(PENDING_META, {"props": preview(), "uncertain": false})
	var ok := await command("save_decorations", {"props": preview()}, "Layout saved")
	if ok:
		session.remove_meta(PENDING_META)
		_baseline = DecorationLayout.saved(state())
		_draft = _baseline.duplicate(true)
		_history.clear()
		dirty = false
	elif session.offline or session.last_error_code in ["", "TRANSPORT"]:
		session.set_meta(PENDING_META, {"props": preview(), "uncertain": true})
	else:
		session.remove_meta(PENDING_META)
	if is_inside_tree():
		if not ok:
			match session.last_error_code:
				"DECORATION_LOCKED": message.text = "Complete your first growth purchase before saving."
				"INVALID_DECORATION": message.text = "This arrangement contains a spot that cannot be used."
				"DECORATION_OVERLAP": message.text = "Leave more room between the pieces."
			feedback.emit(message.text)
		preview_changed.emit(preview())
		refresh()
	return ok

func _uncertain() -> bool:
	return session != null and session.has_meta(PENDING_META) and bool(session.get_meta(PENDING_META).get("uncertain", false))

func request_leave() -> bool:
	if busy or _uncertain():
		refresh()
		return true
	if not dirty: return false
	_confirm_leave = true
	refresh()
	return true

func consume_back() -> bool:
	if _confirm_leave and not busy and not _uncertain():
		_keep_editing()
		return true
	return request_leave()

func _keep_editing() -> void:
	if busy or _uncertain(): return
	_confirm_leave = false
	navigation_cancelled.emit()
	refresh()

func _discard_and_leave() -> void:
	if busy or _uncertain(): return
	cancel_preview()
	_confirm_leave = false
	navigation_confirmed.emit()

func _save_before_leave() -> void:
	if await save_layout():
		_confirm_leave = false
		if is_inside_tree(): navigation_confirmed.emit()

func _reconnect() -> void:
	if _uncertain(): await reconcile_save()
	else: await super._reconnect()

func reconcile_save() -> bool:
	if busy or session == null or not _uncertain(): return false
	busy = true
	refresh()
	var ok := await session.refresh()
	busy = false
	if ok:
		session.remove_meta(PENDING_META)
		_baseline = DecorationLayout.saved(state())
		dirty = _draft != _baseline
		if not dirty: _history.clear()
	if is_inside_tree():
		message.text = ("Layout saved" if not dirty else "Saved layout checked. Your preview is retained.") if ok else "Could not connect. Try again."
		preview_changed.emit(preview())
		refresh()
		if ok and not dirty and _confirm_leave:
			_confirm_leave = false
			navigation_confirmed.emit()
	return ok
