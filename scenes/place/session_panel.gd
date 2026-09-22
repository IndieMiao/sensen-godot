class_name SessionPanel
extends VBoxContainer
## A command remains single-flight while the server replaces the shared state.

signal feedback(message: String)

var session: FarmSession
var busy := false
var content: VBoxContainer
var message: Label
var _refresh_queued := false
var _section: VBoxContainer

func setup(value: FarmSession) -> void:
	session = value

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
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
	_section = null
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_render()
	if session and (session.offline or session.has_unconfirmed_command()):
		var reconnect := GameUi.button("rotate-ccw", L10n.text("Reconnect") if session.offline else L10n.text("Check previous action"), L10n.text("Reload your farm"))
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
	message.text = L10n.text("Connected") if ok else L10n.text("Could not connect. Try again.")
	refresh()

func _render() -> void:
	pass

func consume_back() -> bool:
	return false

func pending_key() -> StringName:
	return &""

func section_card(selected := false) -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = "ActivityCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", GameUi.card_style(selected, 12))
	content.add_child(card)
	_section = VBoxContainer.new()
	_section.add_theme_constant_override("separation", 9)
	card.add_child(_section)
	return _section

func heading(text: String) -> Label:
	section_card()
	var label := GameUi.label(text, 17)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_section.add_child(label)
	return label

func append_content(node: Control) -> void:
	(_section if is_instance_valid(_section) else content).add_child(node)

func ingredient_card(texture: Texture2D, text: String, have: int, need: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(66, 0)
	card.add_theme_stylebox_override("panel", GameUi.card_style(false, 7))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	card.add_child(column)
	var art := GameUi.picture(texture, 30)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(art)
	var title := GameUi.label(text, 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var amount := GameUi.label("%d / %d" % [have, need], 14, GameUi.GREEN if have >= need else GameUi.CORAL)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(amount)
	return card

func paragraph(text: String) -> Label:
	var label := GameUi.label(text, 14, GameUi.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	append_content(label)
	return label

func action(symbol: String, text: String, callback: Callable, enabled := true, accent := false) -> Button:
	var button := GameUi.button(symbol, text, text, accent)
	button.custom_minimum_size.y = 46
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.disabled = not enabled or busy or session == null or session.offline
	button.pressed.connect(func():
		if not button.disabled: callback.call())
	append_content(button)
	return button

func command(type: String, payload: Dictionary, success := "Saved") -> bool:
	if busy or session == null: return false
	if session.offline:
		session.last_error_code = "OFFLINE"
		message.text = error_text("OFFLINE")
		return false
	busy = true
	message.text = L10n.text("Saving...")
	refresh()
	var ok := await session.send(type, payload, pending_key())
	busy = false
	if not is_inside_tree(): return ok
	message.text = success if ok else error_text(session.last_error_code)
	if not ok and JourneyProgress.active(state()):
		match session.last_error_code:
			"NOT_AVAILABLE", "CHAPTER_LOCKED": message.text = L10n.text("Complete the earlier step of this project first.")
			"INSUFFICIENT_ITEMS": message.text = L10n.text("More supplies are needed for this activity.")
			"DECORATION_LOCKED": message.text = L10n.text("Make your first planter at the workbench.")
	feedback.emit(message.text)
	refresh()
	return ok

static func error_text(code: String) -> String:
	match code:
		"WORK_COOLDOWN": return L10n.text("The current main hand is still recovering. Try again shortly.")
		"FISHING_ROD_REQUIRED": return L10n.text("Equip a fishing rod on the character page first.")
		"BAG_FULL": return L10n.text("Your bag is full. Merge stacks, use items or free a slot.")
		"BAG_CHANGED": return L10n.text("Your bag changed. Select the item again.")
		"INVALID_BAG_ACTION": return L10n.text("This item cannot be moved or used that way.")
		"EFFECT_ACTIVE": return L10n.text("This meal effect is still active. No item was consumed.")
		"EQUIPMENT_OWNED": return L10n.text("You already own this equipment.")
		"LOCAL_STORAGE": return L10n.text("Could not save on this device. Free some space, then check the previous action.")
		"SESSION_CHANGED": return L10n.text("The farm connection changed. Reconnect before continuing.")
		"PENDING_ACTION": return L10n.text("Check the previous visit, kitchen, project or trade before changing your basket.")
		"DECORATION_LOCKED": return L10n.text("Complete a growth purchase before saving your courtyard.")
		"INVALID_DECORATION": return L10n.text("Choose a clear spot beside the path.")
		"DECORATION_OVERLAP": return L10n.text("Leave more room between the pieces.")
		"OFFLINE", "TRANSPORT": return L10n.text("Could not connect. Reconnect and try again.")
		"INVALID_FARM_TERRAIN": return L10n.text("The farm terrain could not be verified. Retry loading it.")
		"INSUFFICIENT_ITEMS": return L10n.text("Not enough available ingredients. Check your project basket.")
		"INSUFFICIENT_FUNDS": return L10n.text("Not enough coins.")
		"CHAPTER_LOCKED", "NOT_AVAILABLE": return L10n.text("This is not available in your chapter yet.")
		"ALREADY_CLAIMED", "REQUEST_DONE": return L10n.text("Already completed.")
		"SLOT_TAKEN": return L10n.text("This chapter's choice is already saved.")
		"LOCKED_CHOICE": return L10n.text("Your growth purchase is already final.")
		"REQUEST_MISMATCH": return L10n.text("Complete the matching gift or sale first.")
		"VERSION_CONFLICT": return L10n.text("Your farm changed. Try again.")
	return L10n.text("Could not save. Try again.")
