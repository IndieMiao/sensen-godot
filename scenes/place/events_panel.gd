class_name EventsPanel
extends SessionPanel

signal navigation_requested(destination: String, tab: String)
signal photo_requested(summary: Dictionary)

const PENDING_META := &"pending_event_command"
const LAST_EVENT := "wind_and_opening"

var place_id := "nursery"
var _data: Dictionary = {}
var _quota: Dictionary = {"C": 2, "H": 4}
var _view := "home"
var _event_id := ""
var _lines: Array = []
var _line_index := 0
var _gathering := false
var _pending: Dictionary = {}

func pending_key() -> StringName:
	return PENDING_META

func _ready() -> void:
	_data = _read_json("res://assets/farm/data/events.json")
	_quota = _read_json("res://assets/farm/data/economy.json").get("engineering_quota", {"C": 2, "H": 4})
	if chapter() >= 6:
		_event_id = LAST_EVENT
		_view = "event"
	_load_pending()
	super._ready()

func _render() -> void:
	_load_pending()
	if not _pending.is_empty():
		heading(L10n.text("Checking the gathering"))
		paragraph(L10n.text("The last reply did not arrive. Your friends are still here while we check the result."))
		_local_action("rotate-ccw", L10n.text("Check the gathering"), _check_gathering, true).name = "RetryGathering"
		return
	match _view:
		"scene": _render_scene()
		"event": _render_event()
		_: _render_home()

func _render_home() -> void:
	heading(L10n.text("Around the neighbourhood"))
	for event in _data.get("events", []):
		section_card()
		var unlocked := chapter() >= int(event.chapter)
		var button := _local_action(str(event.icon), str(event.title), open_event.bind(str(event.id)))
		button.name = "Event_%s" % event.id
		button.disabled = busy or not unlocked
		paragraph(_event_status(event))

func _render_event() -> void:
	var event := _event()
	if event.is_empty():
		_render_home()
		return
	if _event_id == LAST_EVENT and chapter() >= 6:
		_render_finale()
		_local_action("arrow-left", L10n.text("All neighbourhood stories"), _home).name = "AllEvents"
		return
	heading(str(event.title))
	paragraph(str(event.intro))
	for step in event.get("steps", []):
		if int(step.chapter) <= chapter(): _step_row(str(step.label), fact(str(step.id)))
	var next := _next_step(event)
	if not next.is_empty():
		_local_action("map-pin", str(next.action), _navigate.bind(str(next.destination), str(next.tab)), true).name = "NextEventStep"
	_local_action(str(event.icon), L10n.text("Read the scene"), _start_scene).name = "ReadScene"
	_local_action("arrow-left", L10n.text("All neighbourhood stories"), _home).name = "AllEvents"

func _render_finale() -> void:
	var summary := _summary()
	if not summary.is_empty():
		_render_summary(summary)
		return
	heading(L10n.text("The nursery gathering"))
	for crop in _quota:
		var count := int(state().get("engineering", {}).get("submitted", {}).get(crop, 0))
		_step_row(L10n.format_text("%s / %d of %d delivered", [CropInfo.name_of(str(crop)), mini(count, int(_quota[crop])), int(_quota[crop])]), count >= int(_quota[crop]))
	_step_row(L10n.text("The nursery entrance is ready"), str(state().get("nursery", {}).get("stage", "")) == "built")
	if not _project_ready():
		paragraph(L10n.text("The last materials are still growing. The gathering will wait."))
		_local_action("shopping-basket", L10n.text("Bring the remaining materials"), _navigate.bind("nursery", "project"), true).name = "FinishProject"
	elif not _gathering_done():
		paragraph(L10n.text("The gate is ready, and everyone has arrived at the courtyard."))
		if place_id != "courtyard":
			_local_action("users-round", L10n.text("Meet in the courtyard"), _navigate.bind("courtyard", "events"), true).name = "MeetInCourtyard"
		else:
			action("users-round", L10n.text("Join the gathering"), _start_gathering, true, true).name = "StartGathering"
	else:
		paragraph(L10n.text("The gate is open and the gathering is complete."))
		if _life_choice(6) not in ["gift", "keep", "sold"]:
			paragraph(L10n.text("One last lettuce is waiting for its place in this week's story."))
			_local_action("heart", L10n.text("Choose the last harvest's use"), _navigate.bind(place_id, "choices"), true).name = "LastHarvestChoice"
		else:
			paragraph(L10n.text("Your week is being recorded."))
			_local_action("rotate-ccw", L10n.text("Refresh the week"), _refresh_summary, true).name = "RefreshWeek"

func _render_summary(summary: Dictionary) -> void:
	var variant := str(summary.get("photo_variant", "standard"))
	var ending: Dictionary = _data.get("endings", {}).get(variant, _data.get("endings", {}).get("standard", {}))
	heading(str(ending.get("title", L10n.text("Our first week"))))
	paragraph(str(ending.get("text", L10n.text("The nursery gate is open."))))
	paragraph(L10n.format_text("At the gathering / %d coins / level %d / %d XP", [int(summary.get("wallet", 0)), int(summary.get("level", 1)), int(summary.get("xp", 0))]))
	for id in ResidentCast.ORDER:
		var resident: Dictionary = summary.get("relationships", {}).get(id, {})
		if resident.is_empty(): continue
		var stage := str({"first_sight": L10n.text("First meeting"), "acquainted": L10n.text("Acquainted"), "familiar": L10n.text("Familiar")}.get(str(resident.get("stage", "")), L10n.text("First meeting")))
		paragraph(L10n.format_text("%s / %s", [str(ResidentCast.definition(id).get("name", L10n.text("Resident"))), stage]))
	for id in summary.get("journal_pages", []):
		var page: Dictionary = _data.get("journal_pages", {}).get(str(id), {})
		if page.is_empty(): continue
		heading(str(page.title))
		paragraph(str(page.text))
	var clue := str(_data.get("next_week_clues", {}).get(str(summary.get("next_week_clue", "")), L10n.text("Next week: plan the nursery's next planting beds.")))
	paragraph(clue)
	if place_id == "courtyard":
		_local_action("camera", L10n.text("Gather for a photo"), _request_photo, true).name = "TakePhoto"
	else:
		_local_action("camera", L10n.text("Photograph in the courtyard"), _navigate.bind("courtyard", "events"), true).name = "VisitForPhoto"
	_local_action("book-open", L10n.text("Open the week journal"), _navigate.bind(place_id, "journal")).name = "OpenWeekJournal"

func _render_scene() -> void:
	if _lines.is_empty():
		_view = "event"
		_render_event()
		return
	var line: Dictionary = _lines[_line_index]
	paragraph(L10n.format_text("%d / %d", [_line_index + 1, _lines.size()]))
	heading(str(line.get("speaker", "")))
	var text := paragraph(str(line.get("line", "")))
	text.name = "EventDialogueLine"
	if _line_index + 1 < _lines.size():
		_local_action("chevron-right", L10n.text("Continue"), _next_line, true).name = "ContinueEvent"
	elif _gathering:
		action("sprout", L10n.text("Open the nursery together"), _complete_gathering, _project_ready() and not _gathering_done(), true).name = "CompleteGathering"
	else:
		_local_action("check", L10n.text("Back to the neighbourhood"), _end_scene, true).name = "FinishEventScene"
	if _line_index > 0:
		_local_action("arrow-left", L10n.text("Previous"), _previous_line).name = "PreviousEvent"
	_local_action("x", L10n.text("Back"), _end_scene).name = "BackFromScene"

func _step_row(text: String, done: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := GameUi.picture(GameUi.icon("circle-check" if done else "circle"), 18)
	icon.modulate = GameUi.GREEN if done else GameUi.MUTED
	row.add_child(icon)
	var label := GameUi.label(text, 13, GameUi.INK if done else GameUi.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	append_content(row)

func _local_action(symbol: String, text: String, callback: Callable, accent := false) -> Button:
	var button := GameUi.button(symbol, text, text, accent)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.disabled = busy
	button.pressed.connect(func():
		if not button.disabled: callback.call())
	append_content(button)
	return button

func open_event(id: String) -> void:
	if busy: return
	for event in _data.get("events", []):
		if str(event.id) == id and chapter() >= int(event.chapter):
			_event_id = id
			_view = "event"
			refresh()
			return

func _home() -> void:
	_view = "home"
	refresh()

func _navigate(destination: String, tab: String) -> void:
	if not busy: navigation_requested.emit(destination, tab)

func _start_scene() -> void:
	var event := _event()
	if event.is_empty() or chapter() < int(event.chapter): return
	_lines = event.get("after" if _available_steps_done(event) else "before", []).duplicate(true)
	if _event_id == "a_harvest_remembered" and fact("choice_remembered"):
		_lines.clear()
		var memory := _remembered_choice()
		for line in ResidentCast.definition("bistro_owner").get("choice_replies", {}).get(memory, []):
			_lines.append({"speaker": L10n.text("Bistro host"), "line": str(line)})
	_gathering = false
	_line_index = 0
	_view = "scene"
	refresh()

func _start_gathering() -> void:
	if chapter() < 6 or place_id != "courtyard" or not _project_ready() or _gathering_done(): return
	_lines = _data.get("gathering", []).duplicate(true)
	_gathering = true
	_line_index = 0
	_view = "scene"
	refresh()

func _next_line() -> void:
	_line_index = mini(_line_index + 1, _lines.size() - 1)
	refresh()

func _previous_line() -> void:
	_line_index = maxi(0, _line_index - 1)
	refresh()

func _end_scene() -> void:
	_gathering = false
	_view = "event"
	refresh()

func consume_back() -> bool:
	if busy: return true
	if _view == "scene":
		_end_scene()
		return true
	if _view == "event":
		_home()
		return true
	return false

func _complete_gathering() -> void:
	if busy or session == null or session.offline or not _gathering or _line_index != _lines.size() - 1: return
	if chapter() < 6 or not _project_ready() or _gathering_done(): return
	if not _pending.is_empty(): return
	_pending = {"type": "attend_shared_event", "payload": {"event_id": "nursery_activity"},
		"points_before": int(_keeper().get("points", 0)), "stage_before": ResidentCast.relationship_stage(_keeper())}
	session.set_meta(PENDING_META, _pending.duplicate(true))
	await _send_gathering()

func _send_gathering() -> void:
	var accepted := await command("attend_shared_event", {"event_id": "nursery_activity"}, L10n.text("The nursery gate is open"))
	if not is_inside_tree(): return
	if accepted:
		_finish_gathering()
	elif session.last_error_code == "ALREADY_CLAIMED":
		await _check_gathering()
	elif session.last_error_code not in ["", "OFFLINE", "TRANSPORT"]:
		_clear_pending()
	refresh()

func _check_gathering() -> void:
	if busy or session == null or _pending.is_empty(): return
	busy = true
	message.text = L10n.text("Checking the gathering...")
	refresh()
	var ok := await session.refresh()
	busy = false
	if not is_inside_tree(): return
	if not ok:
		message.text = L10n.text("Could not connect. The gathering is still waiting to be confirmed.")
	elif _gathering_done():
		_finish_gathering()
	elif _project_ready() and chapter() >= 6:
		await _send_gathering()
	else:
		_clear_pending()
		_view = "event"
		_event_id = LAST_EVENT
	refresh()

func _finish_gathering() -> void:
	var points_before := int(_pending.get("points_before", 0))
	var stage_before := str(_pending.get("stage_before", ""))
	_clear_pending()
	var result := [L10n.text("The nursery gate is open")]
	var gain := int(_keeper().get("points", 0)) - points_before
	if gain > 0: result.append(L10n.format_text("+%d friendship", gain))
	var stage := ResidentCast.relationship_stage(_keeper())
	if stage != stage_before: result.append(stage)
	message.text = " / ".join(result)
	feedback.emit(message.text)
	_gathering = false
	_event_id = LAST_EVENT
	_view = "event"
	refresh()

func _refresh_summary() -> void:
	if busy or session == null: return
	busy = true
	refresh()
	var ok := await session.refresh()
	busy = false
	if not is_inside_tree(): return
	message.text = L10n.text("Your week is ready") if ok and not _summary().is_empty() else L10n.text("The week is not ready yet.")
	refresh()

func _request_photo() -> void:
	var summary := _summary()
	if busy or summary.is_empty() or place_id != "courtyard": return
	photo_requested.emit(summary.duplicate(true))

func _clear_pending() -> void:
	_pending.clear()
	if session: session.remove_meta(PENDING_META)

func _load_pending() -> void:
	_pending = session.get_meta(PENDING_META).duplicate(true) if session and session.has_meta(PENDING_META) else {}

func _summary() -> Dictionary:
	return state().get("week_summary", {}) if state().get("week_summary") is Dictionary else {}

func _keeper() -> Dictionary:
	return state().get("residents", {}).get("nursery_keeper", {})

func _gathering_done() -> bool:
	return bool(_keeper().get("shared_event_done", false))

func _project_ready() -> bool:
	if str(state().get("nursery", {}).get("stage", "")) != "built": return false
	for crop in _quota:
		if int(state().get("engineering", {}).get("submitted", {}).get(crop, 0)) < int(_quota[crop]): return false
	return true

func _event() -> Dictionary:
	for event in _data.get("events", []):
		if str(event.id) == _event_id: return event
	return {}

func _event_status(event: Dictionary) -> String:
	if chapter() < int(event.chapter): return L10n.format_text("Chapter %d", (int(event.chapter) + 1))
	if not _available_steps_done(event): return L10n.text("In progress")
	for step in event.get("steps", []):
		if int(step.chapter) > chapter(): return L10n.format_text("Continues in Chapter %d", (int(step.chapter) + 1))
	return L10n.text("Remembered")

func _available_steps_done(event: Dictionary) -> bool:
	for step in event.get("steps", []):
		if int(step.chapter) <= chapter() and not fact(str(step.id)): return false
	return true

func _next_step(event: Dictionary) -> Dictionary:
	for step in event.get("steps", []):
		if int(step.chapter) <= chapter() and not fact(str(step.id)): return step
	return {}

func fact(id: String) -> bool:
	match id:
		"rain_care": return bool(_flags(1).get("rain_care_done", false))
		"first_request": return state().get("requests_done", []).has("d1_bistro_lettuce")
		"harvest_choice": return _life_choice(2) in ["gift", "keep", "sold"]
		"choice_remembered": return fact("harvest_choice") and _remembered_choice() == _life_choice(2)
		"first_salad": return state().get("xp", {}).get("first_recipes", []).has("salad")
		"shared_meal": return bool(state().get("residents", {}).get("bistro_owner", {}).get("shared_event_done", false))
		"nursery_request": return state().get("requests_done", []).has("d3_nursery_basket")
		"visit_return": return bool(_flags(4).get("visit_tutorial_completed", false))
		"first_materials":
			for count in state().get("engineering", {}).get("submitted", {}).values():
				if int(count) > 0: return true
			return false
		"nursery_cleared": return str(state().get("nursery", {}).get("stage", "")) in ["cleared", "built"]
		"wind_care": return bool(_flags(5).get("wind_care_done", false))
		"growth_intent": return state().get("growth_choice", {}).get("intent") in ["tool", "field"]
		"project_complete": return _project_ready()
		"nursery_gathering": return _gathering_done()
	return false

func _flags(index: int) -> Dictionary:
	var chapters: Array = state().get("chapters", [])
	return chapters[index].get("step_flags", {}) if index >= 0 and index < chapters.size() else {}

func _life_choice(index: int) -> String:
	var choices: Dictionary = state().get("life_choices", {})
	return str(choices.get(str(index), choices.get(index, "")))

func _remembered_choice() -> String:
	var memories: Dictionary = state().get("residents", {}).get("bistro_owner", {}).get("choice_memories", {})
	return str(memories.get("2", memories.get(2, "")))

static func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
