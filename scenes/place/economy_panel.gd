class_name EconomyPanel
extends SessionPanel

signal gift_requested(resident_id: String)

var section := "supplies"
var _economy: Dictionary = _table("economy")
var _chapters: Array = _table("chapters").get("chapters", [])
var _recipes: Dictionary = _table("recipes")
var _requests: Dictionary = _table("requests").get("requests", {})

func pending_key() -> StringName:
	return &"pending_economy_command"

static func _table(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/%s.json" % id))

func set_section(value: String) -> void:
	section = value
	refresh()

func _render() -> void:
	if session and session.has_meta("pending_economy_command"):
		heading(L10n.text("Confirming your last change"))
		paragraph(L10n.text("The connection ended before the result arrived."))
		action("rotate-ccw", L10n.text("Check saved action"), _check_saved).name = "CheckSavedAction"
		return
	if session and session.has_meta("pending_resident_command"):
		var pending: Dictionary = session.get_meta("pending_resident_command")
		heading(L10n.text("Resident interaction pending"))
		action("user-round", L10n.text("Check resident interaction"), func(): gift_requested.emit(str(pending.get("resident_id", "nursery_keeper")))).name = "CheckResidentAction"
		return
	match section:
		"choices": _render_choices()
		"project": _render_project()
		"growth": _render_growth()
		_: _render_supplies()

func command(type: String, payload: Dictionary, success := "Saved") -> bool:
	if busy or session == null: return false
	if session.has_meta("pending_economy_command"):
		await _check_saved()
		return false
	if session.has_meta("pending_resident_command"): return false
	if session.offline: return await super.command(type, payload, success)
	# Keep an uncertain transaction across tabs and scene returns until its owner state is reloaded.
	session.set_meta("pending_economy_command", {"type": type, "payload": payload.duplicate(true)})
	var ok := await super.command(type, payload, success)
	if ok or session.last_error_code != "TRANSPORT": session.remove_meta("pending_economy_command")
	refresh()
	return ok

func _check_saved() -> void:
	if busy or session == null: return
	busy = true
	refresh()
	var ok := await session.refresh()
	busy = false
	if ok: session.remove_meta("pending_economy_command")
	if not is_inside_tree(): return
	message.text = L10n.text("Farm synced") if ok else L10n.text("Could not connect. Try again.")
	feedback.emit(message.text)
	refresh()

func _render_supplies() -> void:
	heading(L10n.text("Supplies & support"))
	paragraph(L10n.format_text("%d coins", int(state().get("wallet", 0))))
	var tutorial: Dictionary = _requests.get("d0_tutorial_buyback", {})
	var bought_back: bool = state().get("requests_done", []).has("d0_tutorial_buyback")
	var count := int(tutorial.get("items", {}).get("R", 3))
	paragraph(L10n.format_text("First harvest basket: %d / %d radishes", [mini(available("R"), count), count]))
	action("shopping-basket", L10n.text("First basket delivered") if bought_back else L10n.format_text("Deliver %d radishes - +%d coins", [count, int(tutorial.get("coins", 30))]),
		func(): command("submit_request", {"request_id": "d0_tutorial_buyback"}, L10n.text("First harvest delivered")),
		not bought_back and available("R") >= count).name = "TutorialBuyback"
	append_content(HSeparator.new())
	var pack: Dictionary = _economy.seedling_pack
	var used: Array = state().get("seedling_packs", {}).get("days", [])
	paragraph(L10n.format_text("Seedling support: %d / %d packs remaining", [maxi(0, int(pack.week_cap) - used.size()), int(pack.week_cap)]))
	action("sprout", L10n.format_text("Claim %d radish seedlings", int(pack.contents.R)),
		func(): command("claim_seedling_pack", {}, L10n.text("Radish seedlings received")), can_claim_pack()).name = "SeedlingPack"
	if not can_claim_pack():
		paragraph(L10n.text("Available when your seed store and harvest basket are empty and coins run out."))
	var seeds: Dictionary = state().get("inventory", {}).get("seeds", {})
	var bound: Array[String] = []
	for crop in CropInfo.ORDER:
		var qty := int(seeds.get(crop, {}).get("bound", 0))
		if qty > 0: bound.append(L10n.format_text("%d %s", [qty, CropInfo.name_of(crop)]))
	if not bound.is_empty(): paragraph(L10n.format_text("Chapter seedlings: %s\nPlant before the next chapter opens.", ", ".join(bound)))
	if chapter() >= _unlock_chapter("kitchen"):
		append_content(HSeparator.new())
		var buyback: Dictionary = _recipes.buyback
		var history: Dictionary = state().get("buyback", {})
		var tea := int(state().get("inventory", {}).get("dishes", {}).get(str(buyback.dish), 0))
		var used_today := str(history.get("day", "")) == _day() and int(history.get("sold", 0)) >= int(buyback.per_player_day)
		var used_week := int(history.get("week_total", 0)) >= int(buyback.per_week)
		action("shopping-bag", L10n.text("Tea collected") if used_week else L10n.format_text("Tea buyback - +%d coins", int(buyback.coins)),
			func(): command("sell_to_buyback_box", {"qty": 1}, L10n.text("Tea collected")), tea > 0 and not used_today and not used_week).name = "TeaBuyback"
	for id in _economy.subsidies:
		var subsidy: Dictionary = _economy.subsidies[id]
		if chapter() < int(subsidy.chapter): continue
		var received: bool = state().get("subsidies_claimed", []).has(id)
		var ready: bool = id != "nursery_built" or str(state().get("nursery", {}).get("stage", "")) == "built"
		var label := L10n.text("Weather story") if id == "weather_story" else L10n.text("Nursery completion")
		action("coins", L10n.format_text("%s received", label) if received else L10n.format_text("%s - +%d coins", [label, int(subsidy.coins)]),
			func(): command("claim_subsidy", {"subsidy_id": id}, L10n.format_text("%s support received", label)), not received and ready).name = "Subsidy_" + str(id)

func can_claim_pack() -> bool:
	var pack: Dictionary = _economy.seedling_pack
	var used: Array = state().get("seedling_packs", {}).get("days", [])
	if used.has(_day()) or used.size() >= int(pack.week_cap): return false
	var cheapest := 2147483647
	for crop in CropInfo.ORDER: cheapest = mini(cheapest, CropInfo.seed_price(crop))
	if int(state().get("wallet", 0)) >= cheapest: return false
	var inventory: Dictionary = state().get("inventory", {})
	for crop in CropInfo.ORDER:
		var seed: Dictionary = inventory.get("seeds", {}).get(crop, {})
		if int(seed.get("bought", 0)) + int(seed.get("bound", 0)) > 0: return false
	for group in [inventory.get("produce", {}), inventory.get("dishes", {}), state().get("engineering", {}).get("reserved", {})]:
		for value in group.values():
			if int(value) > 0: return false
	for cell in state().get("cells", {}).values():
		if str(cell.get("state", "")) in ["sown", "growing"]: return false
	return chapter() >= 0

func _render_choices() -> void:
	heading(L10n.text("Today's harvest"))
	var day := chapter()
	if day < 0 or day >= _chapters.size() or not _chapters[day].has("life_choice_crop"):
		paragraph(L10n.text("Your first harvest belongs in the nursery basket and the roadside stall."))
		return
	var crop := str(_chapters[day].life_choice_crop)
	var selected = _chapter_value(state().get("life_choices", {}), day)
	var art := GameUi.picture(GameUi.crop_art(crop), 56)
	art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	append_content(art)
	paragraph(L10n.format_text("%s - %d available", [CropInfo.name_of(crop), available(crop)]))
	if selected != null:
		var labels := {"gift": L10n.text("Shared with a resident"), "keep": L10n.text("Set aside for next week"), "sold": L10n.text("Sold at the roadside stall")}
		action("check", str(labels.get(str(selected), L10n.text("Choice saved"))), func(): pass, false).name = "ChoiceSaved"
		return
	var facts: Dictionary = state().get("sales_facts", {})
	var gifted := int((_chapter_value(facts, -day - 1, {}) as Dictionary).get(crop, 0)) > 0
	var sold := int((_chapter_value(facts, day, {}) as Dictionary).get(crop, 0)) > 0
	var recipient := "nursery_keeper" if day == 1 else ("restorer" if day >= 5 else "bistro_owner")
	if gifted:
		action("heart", L10n.text("Remember my gift"), func(): _resolve(day, "gift"), true, true).name = "ChoiceGift"
	else:
		action("heart", L10n.format_text("Share 1 %s", CropInfo.name_of(crop)), func(): gift_requested.emit(recipient), available(crop) > 0).name = "ChoiceGift"
	action("shopping-basket", L10n.text("Set aside 1 for next week"), func(): _resolve(day, "keep"), available(crop) > 0).name = "ChoiceKeep"
	var room := maxi(0, int(_economy.stall_budget_per_day) - int(state().get("stall", {}).get("settled", 0)))
	action("coins", L10n.text("Remember my sale") if sold else L10n.format_text("Sell 1 - +%d coins", CropInfo.unit_price(crop)),
		func(): _sell_choice(day, crop), sold or (available(crop) > 0 and room >= CropInfo.unit_price(crop))).name = "ChoiceSell"
	if not sold and room < CropInfo.unit_price(crop): paragraph(L10n.text("Today's stall budget is full. Your harvest stays in your basket."))

func _resolve(day: int, choice: String) -> bool:
	return await command("resolve_life_choice", {"chapter": day, "choice": choice}, L10n.text("Harvest choice saved"))

func _sell_choice(day: int, crop: String) -> void:
	if busy: return
	# A sale can succeed while its follow-up choice fails; the saved fact resumes without selling twice.
	var facts: Dictionary = _chapter_value(state().get("sales_facts", {}), day, {})
	if int(facts.get(crop, 0)) < 1:
		var sold := await command("sell_at_stall", {"items": [{"kind": "produce", "id": crop, "qty": 1}]}, L10n.text("Harvest sold"))
		if not sold or not is_inside_tree(): return
	await _resolve(day, "sold")

func _render_project() -> void:
	heading(L10n.text("Nursery project"))
	var nursery: Dictionary = state().get("nursery", {})
	paragraph(str({"derelict": L10n.text("Waiting for a new beginning"), "cleared": L10n.text("The entrance is clear"), "built": L10n.text("The nursery is ready")}.get(str(nursery.get("stage", "derelict")), L10n.text("Nursery entrance"))))
	var unlocked := chapter() >= _unlock_chapter("engineering_basket")
	if not unlocked: paragraph(L10n.format_text("Project basket opens in Chapter %d", (_unlock_chapter("engineering_basket") + 1)))
	var reserve_all := {}
	var submit_all := {}
	for crop in _economy.engineering_quota:
		section_card()
		var progress := project_status(str(crop))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(GameUi.picture(GameUi.crop_art(str(crop)), 40))
		var text := GameUi.label(L10n.format_text("%s\n%d / %d delivered - %d reserved", [CropInfo.name_of(str(crop)), progress.submitted, progress.quota, progress.reserved]), 13)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		append_content(row)
		var bar := ProgressBar.new()
		bar.max_value = progress.quota
		bar.value = progress.submitted
		bar.show_percentage = false
		bar.custom_minimum_size.y = 6
		append_content(bar)
		var controls := HBoxContainer.new()
		controls.add_theme_constant_override("separation", 8)
		append_content(controls)
		var minus := GameUi.button("minus", "", L10n.format_text("Return 1 %s to your basket", CropInfo.name_of(str(crop))))
		minus.name = "Withdraw_" + str(crop)
		minus.disabled = not unlocked or busy or session == null or session.offline or int(progress.reserved) <= 0
		minus.pressed.connect(func():
			if not minus.disabled: command("withdraw_engineering", {"items": {crop: 1}}, L10n.text("Material returned; nursery completion may take longer")))
		controls.add_child(minus)
		var count := GameUi.label(L10n.format_text("%d available", available(str(crop))), 12, GameUi.MUTED)
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		controls.add_child(count)
		var plus := GameUi.button("plus", "", L10n.format_text("Reserve 1 %s", CropInfo.name_of(str(crop))))
		plus.name = "Reserve_" + str(crop)
		plus.disabled = not unlocked or busy or session == null or session.offline or int(progress.to_reserve) <= 0
		plus.pressed.connect(func():
			if not plus.disabled: command("reserve_engineering", {"items": {crop: 1}}, L10n.text("Material reserved")))
		controls.add_child(plus)
		if int(progress.to_reserve) > 0: reserve_all[crop] = int(progress.to_reserve)
		var can_submit := mini(int(progress.reserved), maxi(0, int(progress.quota) - int(progress.submitted)))
		if can_submit > 0: submit_all[crop] = can_submit
	action("shopping-basket", L10n.text("Reserve available materials"), func(): command("reserve_engineering", {"items": reserve_all}, L10n.text("Materials reserved")), unlocked and not reserve_all.is_empty()).name = "ReserveAll"
	action("check", L10n.text("Deliver reserved materials"), func(): command("submit_engineering", {"items": submit_all}, L10n.text("Nursery materials delivered")), unlocked and not submit_all.is_empty(), true).name = "SubmitAll"
	paragraph(L10n.text("Reserved crops stay out of sales, gifts and recipes."))
	if chapter() >= _unlock_chapter("nursery_appearance"):
		append_content(HSeparator.new())
		heading(L10n.text("Entrance style"))
		for appearance in ["a", "b"]:
			var selected: bool = nursery.get("appearance") == appearance
			var label := L10n.text("Garden arch") if appearance == "a" else L10n.text("Painted gate")
			action("check" if selected else "sprout", label, func(): command("choose_nursery_appearance", {"appearance": appearance}, L10n.text("Entrance style saved")), not selected, selected).name = "Appearance_" + appearance

func project_status(crop: String) -> Dictionary:
	var engineering: Dictionary = state().get("engineering", {})
	var quota := int(_economy.engineering_quota.get(crop, 0))
	var reserved := int(engineering.get("reserved", {}).get(crop, 0))
	var submitted := int(engineering.get("submitted", {}).get(crop, 0))
	return {"quota": quota, "reserved": reserved, "submitted": submitted,
		"to_reserve": mini(available(crop), maxi(0, quota - reserved - submitted))}

func _render_growth() -> void:
	heading(L10n.text("Your next step"))
	var wallet := int(state().get("wallet", 0))
	paragraph(L10n.format_text("%d coins", wallet))
	var growth: Dictionary = state().get("growth_choice", {})
	var purchased = growth.get("purchase")
	var unlocked := chapter() >= _unlock_chapter("growth_choice")
	if not unlocked: paragraph(L10n.format_text("Growth choices open in Chapter %d", (_unlock_chapter("growth_choice") + 1)))
	for choice in ["tool", "field"]:
		var chosen: bool = growth.get("intent") == choice
		var name := L10n.text("Row tools") if choice == "tool" else L10n.text("Fourth garden bed")
		var cost := growth_cost(choice)
		append_content(HSeparator.new())
		heading(name)
		if choice == "tool":
			paragraph(L10n.format_text("%d coins\nTend a whole row with one touch. Each plot keeps its usual pace and yield.", cost))
		else:
			var field_price := int(_economy.growth_choice.field.price)
			paragraph(L10n.format_text("%d bed + %d seeds = %d coins\nThree more plots, already tilled. Includes 3 seeds of each crop.", [field_price, cost - field_price, cost]))
		if purchased != null:
			action("check" if purchased == choice else "circle", L10n.text("Purchased") if purchased == choice else L10n.text("Available in a later season"), func(): pass, false).name = "Growth_" + choice
		else:
			action("check" if chosen else "circle", L10n.text("Selected") if chosen else L10n.text("Choose ") + name,
				func(): command("set_growth_intent", {"choice": choice}, L10n.text("Growth choice saved")), unlocked and not chosen, chosen).name = "Growth_" + choice
			if chosen:
				action("coins", L10n.format_text("Buy - %d coins", cost), func(): _purchase(choice), unlocked and wallet >= cost, true).name = "Purchase_" + choice
				if wallet < cost: paragraph(L10n.format_text("%d more coins needed. Your choice is saved.", (cost - wallet)))
	if purchased == null: paragraph(L10n.text("Your first purchase locks this week's growth route."))

func growth_cost(choice: String) -> int:
	var price := int(_economy.growth_choice[choice].price)
	if choice == "field":
		for crop in _economy.growth_choice.field.seed_basket:
			price += int(_economy.growth_choice.field.seed_basket[crop]) * CropInfo.seed_price(str(crop))
	return price

func _purchase(choice: String) -> void:
	await command("purchase_growth_choice", {"choice": choice, "transaction_id": Crypto.new().generate_random_bytes(16).hex_encode()}, L10n.text("Growth purchase complete"))

func _unlock_chapter(unlock: String) -> int:
	for item in _chapters:
		if item.get("unlocks", []).has(unlock): return int(item.index)
	return 99

func _day() -> String:
	return str(state().get("clock", {}).get("player_day_id", ""))

static func _chapter_value(values: Dictionary, index: int, fallback = null):
	return values.get(str(index), values.get(index, fallback))
