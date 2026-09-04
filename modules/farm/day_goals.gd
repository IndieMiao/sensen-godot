class_name DayGoals
extends RefCounted
## 第一天的目标清单，客户端按状态算（服务端的章节推进是 G3 的内容，目前没有任何东西把章节
## 标成 done）。每条对应第 0 章 min_facts 里的一步：first_harvest / next_batch_sown_and_cared，
## 中间补上清理→翻土→播种→照料，让玩家知道下一步在哪。

static func evaluate(state: Dictionary, cells: Dictionary) -> Array:
	var xp: Dictionary = state.get("xp", {})
	var inv: Dictionary = state.get("inventory", {})
	var produce: Dictionary = inv.get("produce", {})
	var states := []
	for id in cells:
		states.append(str((cells[id] as Dictionary).get("state", "")))
	var any := func(list: Array) -> bool:
		for s in states:
			if list.has(s):
				return true
		return false
	var harvested: bool = (xp.get("first_harvest_crops", []) as Array).size() > 0
	# 收过就意味着前面每一步都做过——服务端只记「首次清理的格」和「首次收获的作物」两类事实。
	var cleared_any: bool = harvested or (xp.get("first_clear_cells", []) as Array).size() > 0 \
		or any.call(["cleared", "tilled", "sown", "growing"])
	var tilled_any: bool = harvested or any.call(["tilled", "sown", "growing"])
	var sown_any: bool = harvested or any.call(["sown", "growing"])
	var cared_any: bool = harvested or any.call(["growing"])
	var sold: bool = int((state.get("stall", {}) as Dictionary).get("settled", 0)) > 0 \
		or not (state.get("sales_facts", {}) as Dictionary).is_empty()
	var produce_total := 0
	for c in produce:
		produce_total += int(produce[c])
	var next_batch: bool = harvested and any.call(["growing"])
	var fc := str((state.get("clock", {}) as Dictionary).get("field_condition", "sunny"))
	return [
		{"id": "clear", "label": "Clear a plot", "done": cleared_any},
		{"id": "till", "label": "Till it", "done": tilled_any},
		{"id": "sow", "label": "Sow a radish", "done": sown_any},
		{"id": "care", "label": "%s it" % NextStep.care_verb(fc), "done": cared_any},
		{"id": "harvest", "label": "Harvest a radish", "done": harvested},
		{"id": "sell", "label": "Sell at the stall", "done": sold},
		{"id": "next", "label": "Sow next batch", "done": next_batch},
	]

static func done_count(goals: Array) -> int:
	var n := 0
	for g in goals:
		if bool(g.done):
			n += 1
	return n
