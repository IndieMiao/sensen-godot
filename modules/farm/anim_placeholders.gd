class_name AnimPlaceholders
extends RefCounted
## 劳作动画登记表。
##
## rig 目前只有 idle / run / walk 三条真实 clip，六条劳作动作全是占位。占位本身不是
## 问题，**悄悄占位**才是：所以规则写成「数据引用的每个动作，要么有真实 clip，要么在
## 登记表里」，新增动作忘了登记会被守卫测试当场打回（方案 D9）。

const TABLE_PATH := "res://assets/avatar/base/anim_placeholders.json"
## 田况 → 必需照料动作，与 assets/farm/data/weather_script.json 的 care_action 同源。
const CARE_ACTION := {"sunny": "water", "rain": "drain", "wind": "shelter"}

static var _table: Dictionary

static func table() -> Dictionary:
	if _table.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
		_table = parsed if parsed is Dictionary else {}
	return _table

static func real_clips() -> Array:
	return table().get("real_clips", [])

static func placeholders() -> Dictionary:
	return table().get("placeholders", {})

## 这个动作已登记（有真 clip 或有占位条目）。
static func is_registered(action: String) -> bool:
	return real_clips().has(action) or placeholders().has(action)

## 该播哪条 clip。占位动作回退到 idle——**播不出来也不能崩**，
## 玩家看到的是站着不动，而不是黑屏或异常。
static func clip_for(action: String) -> String:
	if real_clips().has(action):
		return action
	var entry = placeholders().get(action)
	if entry != null and real_clips().has(str(entry.get("clip_id", ""))):
		return str(entry.clip_id)
	return "idle"

static func is_placeholder(action: String) -> bool:
	return not real_clips().has(action) and placeholders().has(action)

## 占位时的程序化俯身：真 clip 补齐前，让玩家至少看到「弯下腰在干活」。
## 返回 Tween 供调用方等待或提前 kill。
static func play_fallback(node: Node3D, seconds := 2.0) -> Tween:
	var base := node.rotation
	var tw := node.create_tween()
	tw.tween_property(node, "rotation", base + Vector3(deg_to_rad(22.0), 0, 0), seconds * 0.25)
	tw.tween_interval(seconds * 0.5)
	tw.tween_property(node, "rotation", base, seconds * 0.25)
	return tw
