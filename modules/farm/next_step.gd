class_name NextStep
extends RefCounted
## 「点一块田它自己知道该做什么」的决策表，纯函数，和服务端状态机一一对应：
##   wild → clear；cleared → till；tilled → sow；sown → care；growing 且熟 → harvest；
##   growing 未熟 → 没事可做（返回 ""）。
## 玩家不需要理解工具，只需要理解「这块地接下来会变成什么」。

const COMMAND := {
	"clear": "clear_cells", "till": "till_cells", "sow": "sow_cells",
	"care": "apply_care", "harvest": "harvest_cells",
}
const CARE_VERB := {"sunny": "Water", "rain": "Drain", "wind": "Shelter"}
const VERB_ING := {"clear": "Clearing", "till": "Tilling", "sow": "Sowing", "care": "Tending", "harvest": "Harvesting"}

static func step_for(slot: Dictionary, now_ms: int) -> String:
	match str(slot.get("state", "")):
		"wild": return "clear"
		"cleared": return "till"
		"tilled": return "sow"
		"sown": return "care"
		"growing":
			var ra = slot.get("ready_at")
			return "harvest" if ra != null and int(ra) <= now_ms else ""
	return ""

## 照料动词按田况：晴浇水、雨疏水、风加固。
static func care_verb(field_condition: String) -> String:
	return str(CARE_VERB.get(field_condition, "Tend"))

## 干活时的现在进行时，播种带作物名。
static func doing_label(action: String, crop := "", field_condition := "sunny") -> String:
	match action:
		"sow": return "Sowing %s…" % CropInfo.name_of(crop)
		"care": return "%sing…" % care_verb(field_condition).trim_suffix("e")
	return "%s…" % str(VERB_ING.get(action, action.capitalize()))

## 一颗种子还有几颗可播：先用绑定的（章节送的），再用买的。
static func seeds_of(inventory: Dictionary, crop: String) -> int:
	var lot: Dictionary = (inventory.get("seeds", {}) as Dictionary).get(crop, {})
	return int(lot.get("bought", 0)) + int(lot.get("bound", 0))

static func seed_lot(inventory: Dictionary, crop: String) -> String:
	var lot: Dictionary = (inventory.get("seeds", {}) as Dictionary).get(crop, {})
	return "bound" if int(lot.get("bound", 0)) > 0 else "bought"

## 整片田现在最该做的一件事。返回 {action, cells: Array[String], label, enabled, crop}。
## 优先级：能收的先收（有产出）→ 待照料（否则不长）→ 能播就播 → 翻土 → 清理 → 卖菜 → 等。
## `action` 为 "stall" 表示该去摊位；"" 表示没事可做。
static func bulk(cells: Dictionary, now_ms: int, state: Dictionary, selected_crop: String,
		unlocked_crops: Array) -> Dictionary:
	var by_step := {"harvest": [], "care": [], "sow": [], "till": [], "clear": []}
	var growing_unripe := 0
	var ids := cells.keys()
	ids.sort()
	for id in ids:
		var step := step_for(cells[id], now_ms)
		if step.is_empty():
			if str(cells[id].get("state", "")) == "growing":
				growing_unripe += 1
			continue
		by_step[step].append(id)
	var fc := str((state.get("clock", {}) as Dictionary).get("field_condition", "sunny"))
	var inventory: Dictionary = state.get("inventory", {})
	if not by_step.harvest.is_empty():
		return _mk("harvest", by_step.harvest, "Harvest %d %s" % [by_step.harvest.size(), _plots(by_step.harvest.size())])
	if not by_step.care.is_empty():
		return _mk("care", by_step.care, "%s %d %s" % [care_verb(fc), by_step.care.size(), _plots(by_step.care.size())])
	if not by_step.sow.is_empty():
		var crop := _crop_with_seeds(inventory, selected_crop, unlocked_crops)
		if not crop.is_empty():
			var n := mini(by_step.sow.size(), seeds_of(inventory, crop))
			var r := _mk("sow", by_step.sow.slice(0, n), "Sow %d %s" % [n, CropInfo.name_of(crop)])
			r.crop = crop
			return r
	if not by_step.till.is_empty():
		return _mk("till", by_step.till, "Till %d %s" % [by_step.till.size(), _plots(by_step.till.size())])
	if not by_step.clear.is_empty():
		return _mk("clear", by_step.clear, "Clear %d %s" % [by_step.clear.size(), _plots(by_step.clear.size())])
	var produce: Dictionary = inventory.get("produce", {})
	var total := 0
	for c in produce:
		total += int(produce[c])
	if total > 0:
		return _mk("stall", [], "Sell %d at the stall" % total)
	if not by_step.sow.is_empty():
		return _mk("stall", [], "Buy seeds at the stall")
	if growing_unripe > 0:
		var r := _mk("", [], "Crops are growing")
		r.enabled = false
		return r
	var done := _mk("", [], "All done for today")
	done.enabled = false
	return done

static func _crop_with_seeds(inventory: Dictionary, selected: String, unlocked: Array) -> String:
	if unlocked.has(selected) and seeds_of(inventory, selected) > 0:
		return selected
	for c in CropInfo.ORDER:
		if unlocked.has(c) and seeds_of(inventory, c) > 0:
			return c
	return ""

static func _plots(n: int) -> String:
	return "plot" if n == 1 else "plots"

static func _mk(action: String, cells: Array, label: String) -> Dictionary:
	return {"action": action, "cells": cells, "label": label, "enabled": true, "crop": ""}
