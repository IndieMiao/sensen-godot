class_name CropInfo
extends RefCounted
## 作物名字、价格、时长——读与服务端同一份 assets/farm/data/crops.json。
## 客户端**不用它算钱**：显示「+16」只是把服务端会给的数提前写在按钮上，成交额以回包为准。

const PATH := "res://assets/farm/data/crops.json"
const NAMES := {"R": "Radish", "L": "Lettuce", "C": "Carrot", "H": "Chamomile", "T": "Fruit tree"}
const ORDER := ["R", "L", "C", "H", "T"]
static var _table: Dictionary = {}

static func _load() -> Dictionary:
	if _table.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_table = (parsed as Dictionary).get("crops", {}) if parsed is Dictionary else {}
	return _table

static func name_of(crop: String) -> String:
	return L10n.text(str(NAMES.get(crop, crop)))

static func unit_price(crop: String, state: Dictionary = {}) -> int:
	if JourneyProgress.active(state): return int(JourneyProgress.data().crops.get(crop, {}).get("unit_price", 0))
	return int((_load().get(crop, {}) as Dictionary).get("unit_price", 0))

static func seed_price(crop: String) -> int:
	return int((_load().get(crop, {}) as Dictionary).get("seed_price", 0))

static func duration_ms(crop: String, state: Dictionary = {}) -> int:
	if JourneyProgress.active(state): return int(JourneyProgress.data().crops.get(crop, {}).get("duration_ms", 0))
	return int((_load().get(crop, {}) as Dictionary).get("duration_ms", 0))

## 木本作物占住格子并阻挡通行（果树、藤架类）；一年生作物可以直接踩过去。
## 这是「哪些种植能穿越、哪些不能」的唯一判据，与服务端 crops.json 的 woody 同源。
static func is_woody(crop: String) -> bool:
	return bool((_load().get(crop, {}) as Dictionary).get("woody", false))

## 这格是不是被木本作物占着——用来决定要不要在寻路图上把它设成障碍。
static func blocks_movement(slot: Dictionary) -> bool:
	if str(slot.get("state", "")) not in ["sown", "growing"]: return false
	return is_woody(str(slot.get("crop", "")))
