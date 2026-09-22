class_name NextStep
extends RefCounted
## 「点一块地它自己知道该做什么」的决策表，纯函数，和服务端状态机一一对应：
##   不在状态里（荒地）→ till；tilled → sow；sown → water；growing 且熟 → harvest；
##   growing 未熟 → 没事可做（返回 ""）。
##
## 空字典即荒地：自由格子种田下未开垦的格根本不进状态，这是稀疏存储在客户端的全部体现。

const COMMAND := {
	"till": "till_cells", "sow": "sow_cells",
	"water": "water_cells", "harvest": "harvest_cells", "clear": "clear_plot",
}
const VERB_ING := {"till": "Tilling", "sow": "Sowing", "water": "Watering", "harvest": "Harvesting", "clear": "Clearing"}
static var _economy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/economy.json"))

static func step_for(slot: Dictionary, now_ms: int) -> String:
	match str(slot.get("state", "")):
		"": return "till"          # 不在状态里 = 还没开垦的地
		"tilled": return "sow"
		"sown": return "water"
		"growing":
			var ra = slot.get("ready_at")
			return "harvest" if ra != null and int(ra) <= now_ms else ""
	return ""


## 干活时的现在进行时，播种带作物名。
static func doing_label(action: String, crop := "", field_condition := "sunny") -> String:
	match action:
		"sow": return L10n.format_text("Sowing %s…", CropInfo.name_of(crop))
		"water": return L10n.text("Watering…")
	return L10n.format_text("%s…", str(VERB_ING.get(action, action.capitalize())))

## 一颗种子还有几颗可播：先用绑定的（章节送的），再用买的。
static func seeds_of(inventory: Dictionary, crop: String) -> int:
	var lot: Dictionary = (inventory.get("seeds", {}) as Dictionary).get(crop, {})
	return int(lot.get("bought", 0)) + int(lot.get("bound", 0))

static func seed_lot(inventory: Dictionary, crop: String) -> String:
	var lot: Dictionary = (inventory.get("seeds", {}) as Dictionary).get(crop, {})
	return "bound" if int(lot.get("bound", 0)) > 0 else "bought"

static func sowing_options(cells: Dictionary, state: Dictionary, unlocked: Array) -> Dictionary:
	# 教学期的「只给 6 株萝卜」限制随教学一同退役：能种什么由解锁决定，种多少由地决定。
	return {"crops": unlocked, "room": cells.size()}

## 整片田现在最该做的一件事。返回 {action, cells: Array[String], label, enabled, crop}。
## 优先级：能收的先收（有产出）→ 待照料（否则不长）→ 能播就播 → 翻土 → 清理 → 卖菜 → 等。
## `action` 为 "stall" 表示该去摊位；"" 表示没事可做。
static func bulk(cells: Dictionary, now_ms: int, state: Dictionary, selected_crop: String,
		unlocked_crops: Array, prefer_selected := false) -> Dictionary:
	if JourneyProgress.active(state): state = state.merged({"cells": cells}, true)
	var by_step := {"harvest": [], "water": [], "sow": [], "till": []}
	var growing_unripe := 0
	var first_batch := _first_harvest_pending(state)
	var sowing := sowing_options(cells, state, unlocked_crops)
	var ids := cells.keys()
	ids.sort()
	for id in ids:
		var step := step_for(cells[id], now_ms)
		if step.is_empty():
			if str(cells[id].get("state", "")) == "growing":
				growing_unripe += 1
			continue
		by_step[step].append(id)
	var inventory: Dictionary = state.get("inventory", {})
	if not by_step.harvest.is_empty():
		return _mk("harvest", by_step.harvest, L10n.format_text("Harvest %d %s", [by_step.harvest.size(), _plots(by_step.harvest.size())]))
	if not by_step.water.is_empty():
		return _mk("water", by_step.water,
			L10n.format_text("Water %d %s", [by_step.water.size(), _plots(by_step.water.size())]))
	if prefer_selected and JourneyProgress.active(state) and not first_batch \
			and sowing.crops.has(selected_crop) and not by_step.sow.is_empty():
		var count := mini(by_step.sow.size(), mini(int(sowing.room), seeds_of(inventory, selected_crop)))
		if count > 0:
			var selected := _mk("sow", by_step.sow.slice(0, count), L10n.format_text("Sow %d %s", [count, CropInfo.name_of(selected_crop)]))
			selected.crop = selected_crop
			return selected
	if JourneyProgress.active(state) and (not str(state.journey.get("tracked_project", "")).is_empty() \
			or not JourneyGatherings.planned(state).is_empty() or not JourneyRequests.tracked(state).is_empty()):
		var goal := JourneyProgress.tracked_goal(state, now_ms)
		if not goal.is_empty():
			if goal.place == "farm" and goal.get("action") == "stall":
				var buy := _mk("stall", [], str(goal.hint))
				buy.crop = goal.crop
				return buy
			if goal.get("action") == "wait": goal = JourneyProgress._gather_goal(state)
			if goal.place != "farm":
				return _explore(goal)
	if JourneyProgress.active(state):
		var meal := JourneyProgress.first_meal_goal(state)
		if not meal.is_empty():
			return _explore(meal)
	if JourneyProgress.active(state) and first_batch:
		if growing_unripe > 0:
			var goal := JourneyProgress.next_goal(state)
			return _explore(goal)
	if JourneyProgress.active(state) and growing_unripe > 0 and JourneyProgress.needed_crop(state, cells).is_empty():
		var goal := JourneyProgress.next_goal(state)
		return _explore(goal)
	if not by_step.sow.is_empty():
		var crop := _crop_with_seeds(inventory, selected_crop, sowing.crops)
		var needed := JourneyProgress.needed_crop(state, cells) if JourneyProgress.active(state) else ""
		if not needed.is_empty() and seeds_of(inventory, needed) > 0: crop = needed
		var room := int(sowing.room)
		if not crop.is_empty() and room > 0:
			var n := mini(by_step.sow.size(), seeds_of(inventory, crop))
			n = mini(n, room)
			if crop == needed: n = mini(n, 1)
			var r := _mk("sow", by_step.sow.slice(0, n), L10n.format_text("Sow %d %s", [n, CropInfo.name_of(crop)]))
			r.crop = crop
			return r
	if not by_step.till.is_empty():
		return _mk("till", by_step.till, L10n.format_text("Till %d %s", [by_step.till.size(), _plots(by_step.till.size())]))
	if JourneyProgress.active(state):
		var goal := JourneyProgress.next_goal(state)
		if not by_step.sow.is_empty() and _crop_with_seeds(inventory, selected_crop, sowing.crops).is_empty() and not sowing.crops.is_empty():
			var crop := JourneyProgress.needed_crop(state, cells)
			if crop.is_empty(): crop = selected_crop if sowing.crops.has(selected_crop) else str(sowing.crops[0])
			goal = JourneyProgress._crop_goal(state, crop, 1, now_ms)
			if goal.get("action") == "stall":
				var buy := _mk("stall", [], str(goal.hint))
				buy.crop = crop
				return buy
		if goal.place == "farm": goal = JourneyProgress._gather_goal(state)
		return _explore(goal)
	var total := _sellable_produce(state)
	if total > 0:
		return _mk("stall", [], L10n.format_text("Sell %d at the stall", total))
	# D0's lettuce belongs to the post-harvest batch; planting it early delays that chapter fact.
	if first_batch and growing_unripe > 0:
		var waiting := _mk("", [], L10n.text("First harvest is growing"))
		waiting.enabled = false
		return waiting
	if not by_step.sow.is_empty():
		return _mk("stall", [], L10n.text("Buy seeds at the stall"))
	if growing_unripe > 0:
		var r := _mk("", [], L10n.text("Crops are growing"))
		r.enabled = false
		return r
	var done := _mk("", [], L10n.text("All done for today"))
	done.enabled = false
	return done

static func _explore(goal: Dictionary) -> Dictionary:
	var result := _mk("explore", [], str(goal.label))
	result.place = goal.place
	if goal.has("target"): result.target = goal.target
	if goal.has("surface"): result.surface = goal.surface
	return result

static func _sellable_produce(state: Dictionary) -> int:
	var produce: Dictionary = state.get("inventory", {}).get("produce", {})
	var reserved: Dictionary = state.get("engineering", {}).get("reserved", {})
	var room := maxi(0, int(_economy.get("stall_budget_per_day", 0)) - int(state.get("stall", {}).get("settled", 0)))
	var total := 0
	for crop in CropInfo.ORDER:
		var price := CropInfo.unit_price(crop)
		if price <= 0: continue
		var available := maxi(0, int(produce.get(crop, 0)) - int(reserved.get(crop, 0)))
		var sellable := mini(available, room / price)
		total += sellable
		room -= sellable * price
	return total

static func _first_harvest_pending(state: Dictionary) -> bool:
	if int((state.get("clock", {}) as Dictionary).get("chapter_index", -1)) != 0:
		return false
	var chapters = state.get("chapters", [])
	if chapters is Array and not chapters.is_empty() and chapters[0] is Dictionary:
		var flags = chapters[0].get("step_flags", {})
		if flags is Dictionary and flags.get("first_harvest") is bool and flags.first_harvest:
			return false
	return ((state.get("xp", {}) as Dictionary).get("first_harvest_crops", []) as Array).is_empty()

static func _crop_with_seeds(inventory: Dictionary, selected: String, unlocked: Array) -> String:
	if unlocked.has(selected) and seeds_of(inventory, selected) > 0:
		return selected
	for c in CropInfo.ORDER:
		if unlocked.has(c) and seeds_of(inventory, c) > 0:
			return c
	return ""

static func _plots(n: int) -> String:
	return L10n.text("plot" if n == 1 else "plots")

static func _mk(action: String, cells: Array, label: String) -> Dictionary:
	return {"action": action, "cells": cells, "label": label, "enabled": true, "crop": ""}
