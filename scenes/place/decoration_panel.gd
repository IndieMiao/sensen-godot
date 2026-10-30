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
		heading(L10n.text("Check your arrangement"))
		paragraph(L10n.text("Your last save needs to be checked."))
		var check := GameUi.button("rotate-ccw", L10n.text("Check saved layout"), L10n.text("Reload the saved arrangement"), true)
		check.name = "CheckSavedLayout"
		check.disabled = busy
		check.pressed.connect(reconcile_save)
		append_content(check)
		return
	if _confirm_leave:
		heading(L10n.text("Unsaved arrangement"))
		paragraph(L10n.text("Save this arrangement before leaving?"))
		action("check", L10n.text("Save and continue"), _save_before_leave, DecorationLayout.unlocked(state()), true).name = "SaveAndLeaveDecorations"
		_local_action("x", L10n.text("Discard changes"), L10n.text("Restore the saved arrangement"), _discard_and_leave).name = "DiscardDecorationChanges"
		_local_action("arrow-left", L10n.text("Keep editing"), L10n.text("Return to the arrangement"), _keep_editing).name = "KeepEditingDecorations"
		return
	if compact:
		_render_compact()
		return
	heading(L10n.text("Courtyard pieces"))
	paragraph(L10n.format_text("%d / 6 placed", _draft.size()))
	if not DecorationLayout.unlocked(state()):
		paragraph(L10n.text("Preview only until your first growth purchase."))
	var picker := OptionButton.new()
	picker.name = "DecorationPicker"
	GameUi.register_modal(picker.get_popup())
	picker.custom_minimum_size.y = 44
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.disabled = busy
	var allowed := _allowed_props()
	if allowed.is_empty():
		picker.free()
		paragraph(L10n.text("No courtyard pieces"))
		return
	for id in allowed:
		picker.add_item(_picker_label(str(id)))
		picker.get_popup().set_item_icon_modulate(picker.item_count - 1, GameUi.GREEN if id == selected_prop else GameUi.MUTED)
	if not allowed.has(selected_prop): selected_prop = str(allowed[0])
	picker.selected = allowed.find(selected_prop)
	picker.item_selected.connect(func(index: int): select_prop(str(allowed[index])))
	append_content(picker)
	var existing := DecorationLayout.index_of(_draft, selected_prop)
	if existing < 0:
		_local_action("plus", L10n.text("Place"), L10n.text("Place selected piece"), place_selected, _can_place(selected_prop) and _new_prop_position(selected_prop) != null).name = "PlaceDecoration"
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		append_content(row)
		var moves := [["arrow-left", Vector2i(-1, 0), L10n.text("Move left")], ["chevron-up", Vector2i(0, -1), L10n.text("Move back")],
			["chevron-down", Vector2i(0, 1), L10n.text("Move forward")], ["chevron-right", Vector2i(1, 0), L10n.text("Move right")]]
		for index in moves.size():
			var spec: Array = moves[index]
			var button := GameUi.button(str(spec[0]), "", str(spec[2]))
			button.name = "MoveDecoration%d" % index
			button.custom_minimum_size = Vector2(44, 44)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.disabled = busy or not can_adjust(spec[1])
			button.pressed.connect(func(): adjust(spec[1]))
			row.add_child(button)
		_local_action("minus", L10n.text("Remove"), L10n.text("Remove selected piece"), remove_selected).name = "RemoveDecoration"
		_local_action("rotate-cw", "", L10n.text("Rotate selected piece"), rotate_selected).name = "RotateDecoration"
	var history := HBoxContainer.new()
	history.add_theme_constant_override("separation", 8)
	append_content(history)
	for spec in [["rotate-ccw", L10n.text("Undo"), undo, not _history.is_empty()], ["x", L10n.text("Cancel"), cancel_preview, dirty]]:
		var button := GameUi.button(str(spec[0]), str(spec[1]), str(spec[1]))
		button.name = str(spec[1]) + "Decoration"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = busy or not bool(spec[3])
		button.pressed.connect(spec[2])
		history.add_child(button)
	action("check", L10n.text("Save layout"), save_layout, dirty and DecorationLayout.unlocked(state()), true).name = "SaveDecorations"

func _render_compact() -> void:
	var allowed := _allowed_props()
	if allowed.is_empty():
		paragraph(L10n.text("No courtyard pieces"))
		return
	if not allowed.has(selected_prop): selected_prop = str(allowed[0])
	var picker := OptionButton.new()
	picker.name = "DecorationPicker"
	GameUi.register_modal(picker.get_popup())
	picker.custom_minimum_size.y = 44
	picker.disabled = busy
	for id in allowed: picker.add_item(_picker_label(str(id)))
	picker.selected = allowed.find(selected_prop)
	picker.item_selected.connect(func(index): select_prop(str(allowed[index])))
	append_content(picker)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	append_content(row)
	var placed := DecorationLayout.index_of(_draft, selected_prop) >= 0
	for spec in [["plus", L10n.text("Place selected piece"), place_selected, not placed and _can_place(selected_prop)],
		["rotate-cw", L10n.text("Rotate selected piece"), rotate_selected, placed],
		["rotate-ccw", L10n.text("Undo arrangement"), undo, not _history.is_empty()],
		["minus", L10n.text("Remove selected piece"), remove_selected, placed],
		["x", L10n.text("Cancel arrangement"), cancel_preview, dirty],
		["check", L10n.text("Save layout"), save_layout, dirty and DecorationLayout.unlocked(state())]]:
		var button := GameUi.button(str(spec[0]), "", str(spec[1]), spec[0] == "check")
		button.custom_minimum_size = Vector2(44, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = busy or not bool(spec[3]) or (spec[0] == "check" and (session == null or session.offline))
		button.pressed.connect(spec[2])
		row.add_child(button)

func _managed_inventory() -> bool:
	return JourneyProgress.active(state()) and BagModel.canonical(state())

func _owned_count(id: String) -> int:
	var total := 1 if DecorationLayout.index_of(_baseline, id) >= 0 else 0
	var bag := BagModel.snapshot(state())
	for entry in bag.get("slots", []) + bag.get("overflow", []):
		if entry.get("item_id") == id: total += int(entry.quantity)
	return total

func _allowed_props() -> Array:
	var allowed: Array = ["planter"] if JourneyProgress.active(state()) and not JourneyProgress.unlocked(state(), "decorations") else DecorationLayout.IDS
	if _managed_inventory():
		return allowed.filter(func(id): return _owned_count(str(id)) > 0 or DecorationLayout.index_of(_draft, str(id)) >= 0)
	return allowed

func _can_place(id: String) -> bool:
	return not _managed_inventory() or _owned_count(id) > 0

func _picker_label(id: String) -> String:
	var label := ItemCatalog.name_of(id) if _managed_inventory() else L10n.text(DecorationLayout.name_of(id))
	var placed := DecorationLayout.index_of(_draft, id) >= 0
	if _managed_inventory(): label += " x%d" % maxi(0, _owned_count(id) - (1 if placed else 0))
	if placed: label += " (" + L10n.text("Placed") + ")"
	return label

func _local_action(icon: String, text: String, tooltip: String, callback: Callable, enabled := true) -> Button:
	var button := GameUi.button(icon, text, tooltip)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.disabled = busy or not enabled
	button.pressed.connect(callback)
	append_content(button)
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

func _new_prop_position(id: String) -> Variant:
	return DecorationLayout.first_position(id, _draft, null, state().get("cells", {}))

func place_selected() -> bool:
	if busy or _uncertain() or _confirm_leave or not _can_place(selected_prop): return false
	var q = _new_prop_position(selected_prop)
	if q == null: return false
	return _change(DecorationLayout.with_position(_draft, selected_prop, q))

func place_at(world: Vector3) -> bool:
	if busy or _uncertain() or _confirm_leave or not _can_place(selected_prop) or not is_finite(world.x) or not is_finite(world.z): return false
	var next := DecorationLayout.with_position(_draft, selected_prop, DecorationLayout.quantize(world))
	if not DecorationLayout.is_valid(next):
		if message: message.text = L10n.text("This spot needs more room.")
		return false
	return _change(next)

func can_adjust(delta: Vector2i) -> bool:
	var index := DecorationLayout.index_of(_draft, selected_prop)
	if index < 0: return false
	var q: Array = _draft[index].cell
	return DecorationLayout.is_valid(DecorationLayout.with_position(_draft, selected_prop, Vector2i(int(q[0]), int(q[1])) + delta))

func adjust(delta: Vector2i) -> bool:
	if busy or _uncertain() or _confirm_leave or not can_adjust(delta): return false
	var index := DecorationLayout.index_of(_draft, selected_prop)
	var q: Array = _draft[index].cell
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
	var ok := await command("save_decorations", {"props": preview()}, L10n.text("Layout saved"))
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
				"DECORATION_LOCKED": message.text = L10n.text("Complete your first growth purchase before saving.")
				"INVALID_DECORATION": message.text = L10n.text("This arrangement contains a spot that cannot be used.")
				"DECORATION_OVERLAP": message.text = L10n.text("Leave more room between the pieces.")
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
		message.text = (L10n.text("Layout saved") if not dirty else L10n.text("Saved layout checked. Your preview is retained.")) if ok else L10n.text("Could not connect. Try again.")
		preview_changed.emit(preview())
		refresh()
		if ok and not dirty and _confirm_leave:
			_confirm_leave = false
			navigation_confirmed.emit()
	return ok
