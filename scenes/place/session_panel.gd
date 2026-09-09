class_name SessionPanel
extends VBoxContainer
## A command remains single-flight while the server replaces the shared state.

signal feedback(message: String)

var session: FarmSession
var busy := false
var content: VBoxContainer
var message: Label
var _refresh_queued := false

func setup(value: FarmSession) -> void:
	session = value

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	add_child(content)
	if message == null:
		message = GameUi.label("", 12, GameUi.MUTED)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(message)
	if session:
		session.state_changed.connect(func(_s, _v): refresh())
		session.offline_changed.connect(func(_offline): refresh())
	refresh()

func state() -> Dictionary:
	return session.state if session else {}

func chapter() -> int:
	return int(state().get("clock", {}).get("chapter_index", -1))

func available(crop: String) -> int:
	return maxi(0, int(state().get("inventory", {}).get("produce", {}).get(crop, 0)) - int(state().get("engineering", {}).get("reserved", {}).get(crop, 0)))

func refresh() -> void:
	if _refresh_queued or not is_inside_tree(): return
	_refresh_queued = true
	call_deferred("_rebuild")

func _rebuild() -> void:
	_refresh_queued = false
	if not is_inside_tree() or content == null: return
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_render()
	if session and (session.offline or session.has_unconfirmed_command()):
		var reconnect := GameUi.button("rotate-ccw", "Reconnect" if session.offline else "Check previous action", "Reload your farm")
		reconnect.name = "ReconnectSession"
		reconnect.disabled = busy
		reconnect.pressed.connect(_reconnect)
		content.add_child(reconnect)
	# ScrollContainer cancels a button press once the shared touch gesture starts scrolling.
	for button in content.find_children("*", "BaseButton", true, false):
		(button as BaseButton).mouse_filter = Control.MOUSE_FILTER_PASS

func _reconnect() -> void:
	if busy or session == null: return
	busy = true
	refresh()
	var ok := await session.refresh()
	busy = false
	if not is_inside_tree(): return
	message.text = "Connected" if ok else "Could not connect. Try again."
	refresh()

func _render() -> void:
	pass

func consume_back() -> bool:
	return false

func pending_key() -> StringName:
	return &""

func heading(text: String) -> Label:
	var label := GameUi.label(text, 16)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	return label

func paragraph(text: String) -> Label:
	var label := GameUi.label(text, 13, GameUi.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	return label

func action(symbol: String, text: String, callback: Callable, enabled := true, accent := false) -> Button:
	var button := GameUi.button(symbol, text, text, accent)
	button.disabled = not enabled or busy or session == null or session.offline
	button.pressed.connect(func():
		if not button.disabled: callback.call())
	content.add_child(button)
	return button

func command(type: String, payload: Dictionary, success := "Saved") -> bool:
	if busy or session == null: return false
	if session.offline:
		session.last_error_code = "OFFLINE"
		message.text = error_text("OFFLINE")
		return false
	busy = true
	message.text = "Saving..."
	refresh()
	var ok := await session.send(type, payload, pending_key())
	busy = false
	if not is_inside_tree(): return ok
	message.text = success if ok else error_text(session.last_error_code)
	if not ok and JourneyProgress.active(state()):
		match session.last_error_code:
			"NOT_AVAILABLE", "CHAPTER_LOCKED": message.text = "Complete the earlier step of this project first."
			"INSUFFICIENT_ITEMS": message.text = "More supplies are needed for this activity."
			"DECORATION_LOCKED": message.text = "Make your first planter at the workbench."
	feedback.emit(message.text)
	refresh()
	return ok

static func error_text(code: String) -> String:
	match code:
		"LOCAL_STORAGE": return "Could not save on this device. Free some space, then check the previous action."
		"SESSION_CHANGED": return "The farm connection changed. Reconnect before continuing."
		"PENDING_ACTION": return "Check the previous visit, kitchen, project or trade before changing your basket."
		"DECORATION_LOCKED": return "Complete a growth purchase before saving your courtyard."
		"INVALID_DECORATION": return "Choose a clear spot beside the path."
		"DECORATION_OVERLAP": return "Leave more room between the pieces."
		"OFFLINE", "TRANSPORT": return "Could not connect. Reconnect and try again."
		"INSUFFICIENT_ITEMS": return "Not enough available ingredients. Check your project basket."
		"INSUFFICIENT_FUNDS": return "Not enough coins."
		"CHAPTER_LOCKED", "NOT_AVAILABLE": return "This is not available in your chapter yet."
		"ALREADY_CLAIMED", "REQUEST_DONE": return "Already completed."
		"SLOT_TAKEN": return "This chapter's choice is already saved."
		"LOCKED_CHOICE": return "Your growth purchase is already final."
		"REQUEST_MISMATCH": return "Complete the matching gift or sale first."
		"VERSION_CONFLICT": return "Your farm changed. Try again."
	return "Could not save. Try again."
