class_name ResidentPanel
extends SessionPanel

signal resident_selected(resident_id: String)

const PENDING_META := &"pending_resident_command"

var place_id := "nursery"
var selected_resident := ""
var _view := "home"
var _lines: Array = []
var _line_index := 0
var _request_id := ""
var _pending: Dictionary = {}
var _requests: Dictionary = {}
var _relationships: Dictionary = {}

func pending_key() -> StringName:
	return PENDING_META

func _ready() -> void:
	_requests = _read_json("res://assets/farm/data/requests.json").get("requests", {})
	_relationships = _read_json("res://assets/farm/data/relationships.json")
	if session and session.has_meta(PENDING_META):
		_pending = session.get_meta(PENDING_META).duplicate(true)
		selected_resident = str(_pending.get("resident_id", ""))
	super._ready()

func _render() -> void:
	if not _pending.is_empty():
		_render_pending()
		return
	var present := ResidentCast.present(place_id, state())
	if present.is_empty():
		heading("A quiet courtyard")
		paragraph("The restorer arrives in Chapter 6.")
		return
	if not present.has(selected_resident):
		selected_resident = str(present[0])
		_view = "home"
	if present.size() > 1 and _view == "home":
		var selector := HBoxContainer.new()
		selector.add_theme_constant_override("separation", 8)
		content.add_child(selector)
		for id in present:
			var button := GameUi.button("user-round", str(ResidentCast.definition(id).short_name), str(ResidentCast.definition(id).name))
			button.name = "Select_" + str(id)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.theme_type_variation = &"ChoiceSelectedButton" if id == selected_resident else &"ChoiceButton"
			button.disabled = busy
			button.pressed.connect(_select.bind(str(id)))
			selector.add_child(button)
	heading(str(ResidentCast.definition(selected_resident).get("name", "Resident")))
	var resident := _resident()
	paragraph("%s / %d friendship" % [ResidentCast.relationship_stage(resident), int(resident.get("points", 0))])
	match _view:
		"dialogue": _render_dialogue()
		"request": _render_request()
		"gifts": _render_gifts()
		_: _render_home()

func _render_home() -> void:
	var resident := _resident()
	var needs_memory := selected_resident == "bistro_owner" and chapter() == 2 and not _choice().is_empty() and _remembered_choice() != _choice()
	var talk := "Tell me about your harvest" if needs_memory else "Talk"
	action("hand", talk, _talk, true, true).name = "Talk"
	if needs_memory:
		paragraph("Your %s choice is ready to share." % {"gift": "gift", "keep": "saved harvest", "sold": "sale"}.get(_choice(), "harvest"))
	elif str(resident.get("talked_day", "")) == _day():
		paragraph("Already caught up today")
	for id in _requests:
		var request: Dictionary = _requests[id]
		if request.resident != selected_resident or int(request.chapter) > chapter(): continue
		var title := str(_request_text(str(id)).get("title", "Harvest request"))
		if state().get("requests_done", []).has(id):
			paragraph("%s / Delivered" % title)
		else:
			action("shopping-basket", title, _open_request.bind(str(id))).name = "Request_%s" % id
	if chapter() >= 1:
		action("heart", "Bring a gift", _open_gifts, _gifts_left() > 0).name = "Gifts"
		if _gifts_left() == 0: paragraph("Both gifts shared this week")
	else:
		paragraph("Gifts open in Chapter 2")
	if int(resident.get("points", 0)) >= 45 and not bool(resident.get("shared_event_done", false)):
		paragraph("Shared activity still ahead")

func _render_dialogue() -> void:
	if _lines.is_empty():
		_view = "home"
		_render_home()
		return
	paragraph("%d / %d" % [_line_index + 1, _lines.size()])
	var line := GameUi.label(str(_lines[_line_index]), 15)
	line.name = "DialogueLine"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(line)
	if _line_index + 1 < _lines.size():
		_local_action("chevron-right", "Continue", _next_line, true).name = "Continue"
	else:
		_local_action("check", "See you soon", _home, true).name = "FinishDialogue"
	if _line_index > 0:
		_local_action("arrow-left", "Previous", _previous_line).name = "Previous"
	_local_action("x", "Back", _home).name = "Back"

func _render_request() -> void:
	var request: Dictionary = _requests.get(_request_id, {})
	if request.is_empty(): return
	var text := _request_text(_request_id)
	heading(str(text.get("title", "Harvest request")))
	paragraph(str(text.get("intro", "")))
	for crop in request.get("items", {}):
		_ingredient(str(crop), available(str(crop)), int(request.items[crop]))
	for dish in request.get("dishes", {}):
		paragraph("%s / %d available / %d needed" % [_dish_name(str(dish)), int(state().get("inventory", {}).get("dishes", {}).get(dish, 0)), int(request.dishes[dish])])
	paragraph("%d coins%s" % [int(request.get("coins", 0)), " / a personal request" if bool(request.get("personal_story", false)) else ""])
	var done: bool = state().get("requests_done", []).has(_request_id)
	action("shopping-basket", "Delivered" if done else "Deliver basket", _deliver, not done and _can_deliver(request), true).name = "Deliver"
	_local_action("arrow-left", "Back", _home).name = "Back"

func _render_gifts() -> void:
	paragraph(str(ResidentCast.definition(selected_resident).get("gift_clue", "")))
	paragraph("%d gifts left this week" % _gifts_left())
	for crop in _relationships.get("gift_clues", {}).get(selected_resident, []):
		_ingredient(str(crop), available(str(crop)), 1)
		action("heart", "Give 1 %s" % CropInfo.name_of(str(crop)), _give.bind(str(crop)), available(str(crop)) > 0 and _gifts_left() > 0, true).name = "Give_%s" % crop
	_local_action("arrow-left", "Back", _home).name = "Back"

func _render_pending() -> void:
	heading("Checking your visit")
	paragraph("The last reply did not arrive. Your basket is unchanged here until the farm confirms it.")
	_local_action("rotate-ccw", "Check and continue", _retry_pending, true).name = "Retry"

func _ingredient(crop: String, have: int, need: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(GameUi.picture(GameUi.crop_art(crop), 36))
	var label := GameUi.label("%s / %d available / %d needed" % [CropInfo.name_of(crop), have, need], 13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	content.add_child(row)
	var reserved := int(state().get("engineering", {}).get("reserved", {}).get(crop, 0))
	if reserved > 0: paragraph("%d held in the project basket" % reserved)

func _local_action(symbol: String, text: String, callback: Callable, accent := false) -> Button:
	var button := GameUi.button(symbol, text, text, accent)
	button.disabled = busy
	button.pressed.connect(func():
		if not button.disabled: callback.call())
	content.add_child(button)
	return button

func _select(id: String) -> void:
	if busy or not _pending.is_empty(): return
	selected_resident = id
	_view = "home"
	resident_selected.emit(id)
	refresh()

func _home() -> void:
	_view = "home"
	refresh()

func consume_back() -> bool:
	if _view == "home" or not _pending.is_empty(): return false
	_home()
	return true

func _open_request(id: String) -> void:
	_request_id = id
	_view = "request"
	refresh()

func _open_gifts() -> void:
	_view = "gifts"
	refresh()

func _next_line() -> void:
	_line_index = mini(_line_index + 1, _lines.size() - 1)
	refresh()

func _previous_line() -> void:
	_line_index = maxi(0, _line_index - 1)
	refresh()

func _talk() -> void:
	await _perform("talk_to_resident", {"resident_id": selected_resident})

func _give(crop: String) -> void:
	if available(crop) < 1 or _gifts_left() < 1: return
	await _perform("give_gift", {"resident_id": selected_resident, "crop": crop})

func _deliver() -> void:
	if not _can_deliver(_requests.get(_request_id, {})): return
	if state().get("requests_done", []).has(_request_id): return
	await _perform("submit_request", {"request_id": _request_id})

func _perform(type: String, payload: Dictionary) -> void:
	if busy or not _pending.is_empty() or session == null: return
	_pending = {"type": type, "payload": payload.duplicate(), "resident_id": selected_resident,
		"gifts_before": int(_resident().get("gifts_given", 0)), "points_before": int(_resident().get("points", 0)),
		"wallet_before": int(state().get("wallet", 0)), "stage_before": ResidentCast.relationship_stage(_resident())}
	session.set_meta(PENDING_META, _pending.duplicate(true))
	await _send_pending()

func _send_pending() -> void:
	session.last_error_code = ""
	var accepted := await command(str(_pending.type), _pending.payload, "Visit saved")
	if not is_inside_tree(): return
	if accepted:
		_finish_pending()
	elif not session.last_error_code.is_empty() and session.last_error_code not in ["OFFLINE", "TRANSPORT"]:
		_pending.clear()
		session.remove_meta(PENDING_META)
	refresh()

func _retry_pending() -> void:
	if busy or _pending.is_empty() or session == null: return
	busy = true
	message.text = "Checking your farm..."
	refresh()
	var reconciled := await session.refresh()
	busy = false
	if not is_inside_tree(): return
	if not reconciled:
		message.text = "Could not connect. Your delivery is still pending."
		feedback.emit(message.text)
		refresh()
		return
	# A lost response must be reconciled before a new idempotency key can consume another gift.
	if _pending_completed():
		_finish_pending()
	else:
		await _send_pending()
	refresh()

func _pending_completed() -> bool:
	match str(_pending.get("type", "")):
		"give_gift": return int(_resident().get("gifts_given", 0)) > int(_pending.gifts_before)
		"submit_request": return state().get("requests_done", []).has(str(_pending.payload.request_id))
		"talk_to_resident":
			if selected_resident == "bistro_owner" and chapter() == 2 and not _choice().is_empty():
				return _remembered_choice() == _choice()
			return str(_resident().get("talked_day", "")) == _day()
	return false

func _finish_pending() -> void:
	var operation := _pending.duplicate(true)
	_pending.clear()
	session.remove_meta(PENDING_META)
	var change := int(_resident().get("points", 0)) - int(operation.points_before)
	var coins := int(state().get("wallet", 0)) - int(operation.wallet_before)
	var result := []
	if change > 0: result.append("+%d friendship" % change)
	if coins > 0: result.append("+%d coins" % coins)
	var stage := ResidentCast.relationship_stage(_resident())
	if str(operation.stage_before) != stage: result.append(stage)
	message.text = " / ".join(result) if not result.is_empty() else "Good to see you again"
	feedback.emit(message.text)
	match str(operation.type):
		"talk_to_resident": _lines = ResidentCast.dialogue(selected_resident, state())
		"give_gift": _lines = ResidentCast.definition(selected_resident).get("gift_replies", {}).get(str(operation.payload.crop), ["Thank you for thinking of me."]).duplicate()
		"submit_request": _lines = _request_text(str(operation.payload.request_id)).get("reply", ["Thank you for the basket."]).duplicate()
	_line_index = 0
	_view = "dialogue"
	refresh()

func _can_deliver(request: Dictionary) -> bool:
	if request.is_empty() or chapter() < int(request.get("chapter", 99)): return false
	for crop in request.get("items", {}):
		if available(str(crop)) < int(request.items[crop]): return false
	for dish in request.get("dishes", {}):
		if int(state().get("inventory", {}).get("dishes", {}).get(dish, 0)) < int(request.dishes[dish]): return false
	return true

func _resident() -> Dictionary:
	return state().get("residents", {}).get(selected_resident, {})

func _gifts_left() -> int:
	return maxi(0, int(_relationships.get("points", {}).get("clued_gift", {}).get("week_cap", 2)) - int(_resident().get("gifts_given", 0)))

func _day() -> String:
	return str(state().get("clock", {}).get("player_day_id", ""))

func _choice() -> String:
	var choices: Dictionary = state().get("life_choices", {})
	return str(choices.get("2", choices.get(2, "")))

func _remembered_choice() -> String:
	var memories: Dictionary = _resident().get("choice_memories", {})
	return str(memories.get("2", memories.get(2, "")))

func _request_text(id: String) -> Dictionary:
	return ResidentCast.data().get("requests", {}).get(id, {})

static func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func _dish_name(id: String) -> String:
	return {"salad": "Vegetable salad", "tea": "Chamomile tea"}.get(id, id)
