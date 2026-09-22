class_name CellPredictor
extends RefCounted
## 薄预测器：只预测**格子状态跃迁**，让手势有即时反馈；不预测钱、XP、关系、成熟时刻。
##
## 为什么不算 ready_at（方案 §3 D4）：成熟时刻由服务端按作物时长与教学特例决定，
## 客户端连作物表都不该有权威副本。所以 water_cells 预测到 `growing` 就停手，
## `ready_at` 留 null，作物渲染在阶段 0 等服务端回包填真值——「动作已登记」是真的，
## 「还剩多久」不装懂。
##
## 与 server/src/domain/handlers/farming.ts 的状态机逐条对齐：
##   wild → cleared → tilled → sown → growing →（成熟后收获）→ tilled
## **成熟是派生量**：`ready_at != null and ready_at <= now`，从不入状态。

const STATES := ["wild", "cleared", "tilled", "sown", "growing"]
## 预测器只认这五条；其余命令一律不预测。
const PREDICTED := ["till_cells", "clear_plot", "sow_cells", "water_cells", "harvest_cells"]

## 权威副本（服务端最后一次回包）。
var cells: Dictionary = {}
var version := -1
## 预测叠加层：cell_id → CellSlot 字典。渲染读 view()，不读 cells。
var _overlay: Dictionary = {}
var _pending: Array = []

var _cultivable: Dictionary = {}   ## cell_id → true

func _init(p_cells: Dictionary = {}, p_cultivable: Array = []) -> void:
	cells = p_cells.duplicate(true)
	for id in p_cultivable:
		_cultivable[str(id)] = true

static func from_blueprint(bp: FarmBlueprint, p_cells: Dictionary = {}) -> CellPredictor:
	var cultivable: Array = []
	for y in bp.grid.y:
		for x in bp.grid.x:
			if bp.mask_has("cultivable", Vector2i(x, y)):
				cultivable.append("%d,%d" % [x, y])
	return CellPredictor.new(p_cells, cultivable)

## 这格能不能动：地面属性说可开垦就行。渐进解锁随自由格子种田退役。
func is_unlocked(id: String) -> bool:
	return _cultivable.has(id)

## 渲染用的视图：权威副本叠上未确认的预测。
func view() -> Dictionary:
	var out := cells.duplicate(true)
	for id in _overlay:
		var slot: Dictionary = _overlay[id]
		if slot.is_empty():
			out.erase(id)        # 预测的铲平：格子回到荒地
		else:
			out[id] = slot.duplicate(true)
	return out

func pending() -> Array:
	return _pending.duplicate(true)

func has_pending() -> bool:
	return not _pending.is_empty()

## 派生成熟：ready_at 已由服务端写入且已到点。
func is_ripe(slot: Dictionary, now_ms: int) -> bool:
	var ra = slot.get("ready_at")
	return ra != null and int(ra) <= now_ms

func ripe_cells(now_ms: int) -> Array:
	var out: Array = []
	var v := view()
	for id in v:
		if is_ripe(v[id], now_ms):
			out.append(id)
	out.sort()
	return out

## 试着预测一条命令。返回 {ok, error, cells}；`ok == false` 时不留任何痕迹——
## 本地就判定不合法的动作根本不发，合法性存疑的交给服务端回 422 说明原因。
func predict(type: String, payload: Dictionary, now_ms: int) -> Dictionary:
	if not PREDICTED.has(type):
		return {"ok": false, "error": "NOT_PREDICTED", "cells": {}}
	var ids := _ids(payload)
	var gate := _gate(ids)
	if gate != "":
		return {"ok": false, "error": gate, "cells": {}}
	var v := view()
	var changed := {}
	for id in ids:
		var slot: Dictionary = (v.get(id, {}) as Dictionary).duplicate(true)
		var step := _step(type, payload, slot, now_ms)
		if step.has("error"):
			return {"ok": false, "error": step.error, "cells": {}}
		changed[id] = step.slot
	for id in changed:
		if (changed[id] as Dictionary).is_empty():
			# 铲平：格子回到荒地，也就是从状态里消失。
			_overlay[id] = {}
		else:
			_overlay[id] = changed[id]
	_pending.append({"type": type, "payload": payload, "cell_ids": ids})
	return {"ok": true, "error": "", "cells": changed}

## 只判合法性、不写叠加层：人物走到地头之前先知道这一下会不会被拒。
func check(type: String, payload: Dictionary, now_ms: int) -> Dictionary:
	if not PREDICTED.has(type):
		return {"ok": false, "error": "NOT_PREDICTED"}
	var ids := _ids(payload)
	var gate := _gate(ids)
	if gate != "":
		return {"ok": false, "error": gate}
	var v := view()
	for id in ids:
		var step := _step(type, payload, (v.get(id, {}) as Dictionary).duplicate(true), now_ms)
		if step.has("error"):
			return {"ok": false, "error": step.error}
	return {"ok": true, "error": ""}

## 服务端回包：**整体覆盖**，不做 diff 合并——漂移一律服务端为准（方案 §3 D4）。
func commit(server_cells: Dictionary, p_version: int) -> void:
	cells = server_cells.duplicate(true)
	version = p_version
	_overlay.clear()
	_pending.clear()

## 命令被拒：丢掉全部预测，回到权威副本。
func rollback() -> void:
	_overlay.clear()
	_pending.clear()

func _ids(payload: Dictionary) -> Array:
	var raw = payload.get("cell_ids", [])
	var out: Array = []
	for id in raw:
		out.append(str(id))
	return out

func _gate(ids: Array) -> String:
	if ids.is_empty():
		return "EMPTY"
	var seen := {}
	for id in ids:
		if seen.has(id):
			return "DUPLICATE_CELL"
		seen[id] = true
		if not _cultivable.has(id):
			return "CELL_NOT_CULTIVABLE"
	return ""

## 逐条复刻 server/src/domain/handlers/farming.ts 的状态跃迁。两边必须一字不差，
## 否则玩家会看到「本地变了、服务端拒绝、又弹回去」的闪烁。
func _step(type: String, payload: Dictionary, slot: Dictionary, now_ms: int) -> Dictionary:
	match type:
		"till_cells":
			# 空槽（荒地）才能开垦；已经开垦过的地再点一次是 WRONG_STATE。
			if not str(slot.get("state", "")).is_empty():
				return {"error": "WRONG_STATE"}
			slot = {"state": "tilled", "crop": null, "watered_at": null, "ready_at": null}
		"clear_plot":
			if str(slot.get("state", "")) != "tilled":
				return {"error": "WRONG_STATE"}
			slot = {}   # 铲平：格子从状态里消失，回到荒地
		"sow_cells":
			if str(slot.get("state", "")) != "tilled":
				return {"error": "WRONG_STATE"}
			slot = {"state": "sown", "crop": str(payload.get("crop", "")),
				"watered_at": null, "ready_at": null}
		"water_cells":
			if str(slot.get("state", "")) != "sown":
				return {"error": "WRONG_STATE"}
			slot.state = "growing"
			slot.watered_at = now_ms
			slot.ready_at = null   # 时长归服务端；渲染停在阶段 0 等真值
		"harvest_cells":
			if not is_ripe(slot, now_ms):
				return {"error": "NOT_RIPE"}
			slot = {"state": "tilled", "crop": null, "watered_at": null, "ready_at": null}
	return {"slot": slot}
