class_name KitchenPanel
extends SessionPanel

const PENDING_META := &"pending_kitchen_command"
const RECIPE_ORDER := ["salad", "tea"]
const DISH_NAMES := {"salad": "Vegetable salad", "tea": "Chamomile tea"}
const SHARED_LINES := [
	{"speaker": "Bistro host", "line": "Look at the colours in this bowl. A carrot and a lettuce, both from your own beds."},
	{"speaker": "Nursery keeper", "line": "I will set three places. The nursery basket can wait a moment while we share the first taste."},
	{"speaker": "Bistro host", "line": "Here is to your first salad, and to many more meals around this table."},
]

var section := "kitchen"
var _recipes: Dictionary = {}
var _xp: Dictionary = {}
var _pending: Dictionary = {}
var _ambiguous := false
var _shared_step := -1
var _journal_filter := "all"
var _result_recipe := ""

func pending_key() -> StringName:
	return PENDING_META

func _ready() -> void:
	_recipes = _read_json("res://assets/farm/data/recipes.json").get("recipes", {})
	_xp = _read_json("res://assets/farm/data/xp.json")
	_load_pending()
	super._ready()

func _render() -> void:
	_load_pending()
	if section == "journal":
		_render_journal()
		return
	if not _pending.is_empty():
		_render_pending()
		return
	if chapter() < 3:
		heading(L10n.text("The kitchen opens in Chapter 4"))
		paragraph(L10n.text("The bistro host is getting the table ready."))
		return
	if _shared_step >= 0:
		_render_shared()
		return
	if not _result_recipe.is_empty():
		var result := _picture_row(GameUi.dish_art(_result_recipe), L10n.format_text("%s ready", _dish_name(_result_recipe)), L10n.format_text("%d in your basket", _dish_count(_result_recipe)), 44)
		result.name = "CookingResult"
	if _first_recipe("salad") and not _shared_done():
		action("users-round", L10n.text("Set the table together"), _open_shared, true, true).name = "SharedCooking"
	elif _shared_done():
		paragraph(L10n.text("First meal shared with the bistro host"))
	for id in RECIPE_ORDER:
		_render_recipe(id)
		if id != RECIPE_ORDER.back(): content.add_child(HSeparator.new())

func _render_recipe(id: String) -> void:
	var recipe: Dictionary = _recipes.get(id, {})
	var subtitle := L10n.format_text("%d prepared", _dish_count(id))
	if _first_recipe(id): subtitle += L10n.text(" / In your journal")
	else: subtitle += L10n.text(" / First recipe")
	_picture_row(GameUi.dish_art(id), _dish_name(id), subtitle, 56)
	for crop in recipe.get("inputs", {}):
		var reserved := int(state().get("engineering", {}).get("reserved", {}).get(crop, 0))
		var label := L10n.format_text("%d available / %d needed", [available(str(crop)), int(recipe.inputs[crop])])
		if reserved > 0: label += L10n.format_text(" / %d reserved", reserved)
		_picture_row(GameUi.crop_art(str(crop)), CropInfo.name_of(str(crop)), label, 32)
	var title := L10n.text("Make salad") if id == "salad" else L10n.text("Brew tea")
	action("utensils", title, _cook.bind(id), _can_cook(id), true).name = "Cook_%s" % id
	if chapter() >= 5 and id == "salad" and not state().get("requests_done", []).has("d5_restorer_salads"):
		paragraph(L10n.format_text("The restorer's lunch: %d / 2 salads prepared", mini(2, _dish_count(id))))

func _render_shared() -> void:
	if _shared_done():
		_shared_step = -1
		paragraph(L10n.text("Your first meal together is in the journal."))
		return
	var step: Dictionary = SHARED_LINES[_shared_step]
	_picture_row(GameUi.dish_art("salad"), L10n.text("Our first meal"), L10n.format_text("%d / %d", [_shared_step + 1, SHARED_LINES.size()]), 44)
	heading(str(step.speaker))
	var line := paragraph(str(step.line))
	line.name = "SharedCookingLine"
	if _shared_step + 1 < SHARED_LINES.size():
		_local_action("chevron-right", L10n.text("Continue"), _continue_shared, true).name = "ContinueShared"
	else:
		action("heart", L10n.text("Share the first meal"), _complete_shared, _first_recipe("salad"), true).name = "CompleteShared"
	if _shared_step > 0:
		_local_action("arrow-left", L10n.text("Previous"), _previous_shared).name = "PreviousShared"
	_local_action("x", L10n.text("Back to recipes"), _close_shared).name = "BackToRecipes"

func _render_pending() -> void:
	heading(L10n.text("Checking the kitchen"))
	if _ambiguous:
		paragraph(L10n.text("Your basket changed while the reply was missing. No extra portion has been made."))
		var recipe := str(_pending.get("payload", {}).get("recipe", "salad"))
		_picture_row(GameUi.dish_art(recipe), _dish_name(recipe), L10n.format_text("%d in your basket", _dish_count(recipe)), 44)
		_local_action("check", L10n.text("Keep current basket"), _accept_reconciled, true).name = "KeepBasket"
	else:
		paragraph(L10n.text("The last reply did not arrive. Check the result before making another portion."))
		_local_action("rotate-ccw", L10n.text("Check and continue"), _retry_pending, true).name = "RetryKitchen"

func _render_journal() -> void:
	heading(L10n.text("Garden journal"))
	var total := int(state().get("xp", {}).get("total", 0))
	var thresholds: Array = _xp.get("level_thresholds", [0, 40, 80, 120, 160, 220, 290])
	var level := level_of(total, thresholds)
	var progress := paragraph(L10n.format_text("Level %d / %d XP", [level, total]))
	progress.name = "GardenLevel"
	var meter := ProgressBar.new()
	meter.name = "LevelProgress"
	meter.custom_minimum_size.y = 6
	meter.show_percentage = false
	meter.max_value = 1
	meter.value = 1.0 if level == thresholds.size() else clampf(float(total - int(thresholds[level - 1])) / float(int(thresholds[level]) - int(thresholds[level - 1])), 0.0, 1.0)
	content.add_child(meter)
	paragraph(L10n.text("Top garden level this week") if level == thresholds.size() else L10n.format_text("%d XP to level %d", [int(thresholds[level]) - total, level + 1]))
	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation", 2)
	content.add_child(levels)
	for index in thresholds.size():
		var label := GameUi.label(str(index + 1), 12, GameUi.GREEN if index < level else GameUi.MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		levels.add_child(label)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 2)
	content.add_child(filters)
	for filter in [["all", L10n.text("All")], ["first_harvest", "Crops"], ["first_recipe", L10n.text("Food")], ["week", L10n.text("Week")]]:
		var button := GameUi.button("", str(filter[1]), str(filter[1]))
		button.name = "Journal_%s" % filter[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = &"TabSelectedButton" if _journal_filter == filter[0] else &"TabButton"
		button.pressed.connect(_filter_journal.bind(str(filter[0])))
		filters.add_child(button)
	var entries := _journal_entries()
	var shown := 0
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		var kind := str(entry.get("kind", ""))
		if _journal_filter != "all" and kind != _journal_filter and not (_journal_filter == "week" and kind in ["chapter_done", "week_summary"]): continue
		_render_entry(entry)
		shown += 1
	if shown == 0:
		paragraph(L10n.text("Your first memories are still growing.") if entries.is_empty() else L10n.text("No memories in this section yet."))
	if _journal_filter in ["all", "week"]:
		var summary: Dictionary = state().get("week_summary", {}) if state().get("week_summary") is Dictionary else {}
		var pages: Dictionary = _read_json("res://assets/farm/data/events.json").get("journal_pages", {})
		for page in summary.get("journal_pages", []):
			if not page is String: continue
			if pages.has(page):
				heading(str(pages[page].get("title", "")))
				paragraph(str(pages[page].get("text", "")))
			elif not page.contains("_"):
				paragraph(page)

func _render_entry(entry: Dictionary) -> void:
	var kind := str(entry.get("kind", ""))
	var key := str(entry.get("key", ""))
	var texture: Texture2D = GameUi.icon("book-open")
	var title := L10n.text("A garden memory")
	match kind:
		"first_harvest":
			texture = GameUi.crop_art(key)
			title = L10n.format_text("First %s harvest", CropInfo.name_of(key).to_lower())
		"first_recipe":
			texture = GameUi.dish_art(key)
			title = L10n.format_text("First %s", _dish_name(key).to_lower())
		"chapter_done":
			texture = GameUi.icon("circle-check")
			title = L10n.format_text("Chapter %d complete", (int(key) + 1))
		"week_summary":
			title = L10n.text("A week of sharing") if bool(entry.get("life_priority", false)) else L10n.text("A week of growing")
	var detail := str(entry.get("day", L10n.text("Recorded")))
	if bool(entry.get("careful", false)): detail += L10n.text(" / Carefully tended")
	var row := _picture_row(texture, title, detail, 40)
	if kind not in ["first_harvest", "first_recipe"]:
		(row.get_child(0) as TextureRect).modulate = GameUi.GREEN
	row.set_meta("journal_kind", kind)
	row.set_meta("journal_key", key)

func _picture_row(texture: Texture2D, title: String, detail: String, side: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(GameUi.picture(texture, side))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	var label := GameUi.label(title, 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(label)
	var sub := GameUi.label(detail, 12, GameUi.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(sub)
	content.add_child(row)
	return row

func _local_action(symbol: String, title: String, callback: Callable, accent := false) -> Button:
	var button := GameUi.button(symbol, title, title, accent)
	button.disabled = busy
	button.pressed.connect(func():
		if not button.disabled: callback.call())
	content.add_child(button)
	return button

func _cook(recipe: String) -> void:
	if not _can_cook(recipe): return
	await _perform("cook_dish", {"recipe": recipe})

func _open_shared() -> void:
	if not _first_recipe("salad") or _shared_done(): return
	_shared_step = 0
	refresh()

func _continue_shared() -> void:
	_shared_step = mini(_shared_step + 1, SHARED_LINES.size() - 1)
	refresh()

func _previous_shared() -> void:
	_shared_step = maxi(0, _shared_step - 1)
	refresh()

func _close_shared() -> void:
	_shared_step = -1
	refresh()

func consume_back() -> bool:
	if busy: return true
	if _shared_step >= 0:
		_close_shared()
		return true
	return false

func _complete_shared() -> void:
	if _shared_step != SHARED_LINES.size() - 1 or not _first_recipe("salad") or _shared_done(): return
	await _perform("attend_shared_event", {"event_id": "cooking_together"})

func _perform(type: String, payload: Dictionary) -> void:
	_load_pending()
	if busy or not _pending.is_empty() or session == null or session.offline: return
	if session.has_meta("pending_economy_command") or session.has_meta("pending_resident_command"):
		message.text = L10n.text("Finish checking your previous visit first.")
		return
	_pending = {"type": type, "payload": payload.duplicate(true), "version_before": session.version,
		"xp_before": int(state().get("xp", {}).get("total", 0)), "points_before": int(_host().get("points", 0)),
		"stage_before": ResidentCast.relationship_stage(_host()), "dishes_before": state().get("inventory", {}).get("dishes", {}).duplicate(true),
		"first_recipes_before": state().get("xp", {}).get("first_recipes", []).duplicate()}
	session.set_meta(PENDING_META, _pending.duplicate(true))
	await _send_pending()

func _send_pending() -> void:
	session.last_error_code = ""
	var accepted := await command(str(_pending.type), _pending.payload, L10n.text("Kitchen saved"))
	if not is_inside_tree(): return
	if accepted:
		_finish_pending()
	elif session.last_error_code not in ["", "OFFLINE", "TRANSPORT"]:
		_clear_pending()
	refresh()

func _retry_pending() -> void:
	if busy or _pending.is_empty() or session == null: return
	busy = true
	message.text = L10n.text("Checking your basket...")
	refresh()
	var reconciled := await session.refresh()
	busy = false
	if not is_inside_tree(): return
	if not reconciled:
		message.text = L10n.text("Could not connect. Your cooking result is still pending.")
		refresh()
		return
	if _pending_completed():
		_finish_pending()
	elif session.version == int(_pending.version_before):
		await _send_pending()
	elif str(_pending.type) == "attend_shared_event":
		await _send_pending()
	else:
		# Repeated recipes lack a durable counter. A changed farm may have sold the result already.
		_ambiguous = true
	refresh()

func _pending_completed() -> bool:
	if str(_pending.get("type", "")) == "attend_shared_event": return _shared_done()
	var recipe := str(_pending.get("payload", {}).get("recipe", ""))
	return _dish_count(recipe) > int(_pending.get("dishes_before", {}).get(recipe, 0)) or (_first_recipe(recipe) and not _pending.get("first_recipes_before", []).has(recipe))

func _finish_pending() -> void:
	var operation := _pending.duplicate(true)
	_clear_pending()
	var outcome := []
	if str(operation.type) == "cook_dish":
		_result_recipe = str(operation.payload.recipe)
		var made := _dish_count(_result_recipe) - int(operation.dishes_before.get(_result_recipe, 0))
		outcome.append(L10n.format_text("%s ready", _dish_name(_result_recipe)) if made > 0 else L10n.text("Recipe saved in your journal"))
		var xp_gain := int(state().get("xp", {}).get("total", 0)) - int(operation.xp_before)
		if xp_gain > 0: outcome.append(L10n.format_text("+%d XP", xp_gain))
		var thresholds: Array = _xp.get("level_thresholds", [])
		var level := level_of(int(state().get("xp", {}).get("total", 0)), thresholds)
		if level > level_of(int(operation.xp_before), thresholds): outcome.append(L10n.format_text("Level %d", level))
	else:
		_shared_step = -1
		outcome.append(L10n.text("Our first meal, shared"))
		var points := int(_host().get("points", 0)) - int(operation.points_before)
		if points > 0: outcome.append(L10n.format_text("+%d friendship", points))
		var stage := ResidentCast.relationship_stage(_host())
		if stage != str(operation.stage_before): outcome.append(stage)
	message.text = " / ".join(outcome)
	feedback.emit(message.text)
	refresh()

func _accept_reconciled() -> void:
	if not _ambiguous or busy: return
	_clear_pending()
	message.text = L10n.text("Current basket kept.")
	refresh()

func _clear_pending() -> void:
	_pending.clear()
	_ambiguous = false
	if session: session.remove_meta(PENDING_META)

func _load_pending() -> void:
	if session and session.has_meta(PENDING_META):
		_pending = session.get_meta(PENDING_META).duplicate(true)
	else:
		_pending.clear()

func _can_cook(recipe: String) -> bool:
	if chapter() < 3 or not _recipes.has(recipe): return false
	for crop in _recipes[recipe].get("inputs", {}):
		if available(str(crop)) < int(_recipes[recipe].inputs[crop]): return false
	return true

func _dish_count(recipe: String) -> int:
	return int(state().get("inventory", {}).get("dishes", {}).get(recipe, 0))

func _first_recipe(recipe: String) -> bool:
	return state().get("xp", {}).get("first_recipes", []).has(recipe)

func _host() -> Dictionary:
	return state().get("residents", {}).get("bistro_owner", {})

func _shared_done() -> bool:
	return bool(_host().get("shared_event_done", false))

func _journal_entries() -> Array:
	var entries: Array = state().get("handbook", []).duplicate(true)
	for kind in ["first_harvest", "first_recipe"]:
		var source := "first_harvest_crops" if kind == "first_harvest" else "first_recipes"
		for key in state().get("xp", {}).get(source, []):
			if not entries.any(func(entry): return str(entry.get("kind", "")) == kind and str(entry.get("key", "")) == str(key)):
				entries.append({"kind": kind, "key": str(key), "day": L10n.text("Recorded")})
	return entries

func _filter_journal(value: String) -> void:
	_journal_filter = value
	refresh()

static func level_of(total: int, thresholds: Array) -> int:
	var level := 1
	for index in thresholds.size():
		if total >= int(thresholds[index]): level = index + 1
	return level

static func _dish_name(id: String) -> String:
	return str(DISH_NAMES.get(id, id))

static func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
