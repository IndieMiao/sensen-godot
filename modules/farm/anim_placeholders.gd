class_name AnimPlaceholders
extends RefCounted
## 劳作动画登记表。
##
## rig 自带 idle / run / walk 三条真实 clip；劳作/表情动作先登记为占位，等 Mixamo 重定向
## 管线产出 labour_* / emote_* 真 clip 后自动转正。占位本身不是问题，**悄悄占位**才是：
## 所以规则写成「数据引用的每个动作，要么有真实 clip，要么在登记表里」，新增动作忘了
## 登记会被守卫测试当场打回（方案 D9）。

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

## 仍是占位：既没有同名真 clip，登记条目指向的 clip_id 也还没变成真 clip。
## Mixamo 管线（tools/pipeline/gen_mixamo_clips.gd）把 labour_* 登记进 real_clips 后，
## 对应动作自动"转正"——farm.gd 据此停掉程序化俯身，只播真 clip。
static func is_placeholder(action: String) -> bool:
	if real_clips().has(action):
		return false
	var entry = placeholders().get(action)
	if entry == null:
		return false
	return not real_clips().has(str(entry.get("clip_id", "")))

## 占位时的程序化俯身：真 clip 补齐前，让玩家至少看到「弯下腰在干活」。
## 返回 Tween 供调用方等待或提前 kill。
static func play_fallback(node: Node3D, seconds := 2.0) -> Tween:
	var base := node.rotation
	var tw := node.create_tween()
	tw.tween_property(node, "rotation", base + Vector3(deg_to_rad(22.0), 0, 0), seconds * 0.25)
	tw.tween_interval(seconds * 0.5)
	tw.tween_property(node, "rotation", base, seconds * 0.25)
	return tw

## 挥手占位：绕 Y 轴轻摆两下。真 clip 补齐前，访客至少看得出「打了个招呼」。
static func play_wave_fallback(node: Node3D, seconds := 1.2) -> Tween:
	var base := node.rotation
	var tw := node.create_tween()
	for i in 2:
		tw.tween_property(node, "rotation", base + Vector3(0, deg_to_rad(18.0), 0), seconds * 0.25)
		tw.tween_property(node, "rotation", base - Vector3(0, deg_to_rad(18.0), 0), seconds * 0.25)
	tw.tween_property(node, "rotation", base, 0.05)
	return tw
