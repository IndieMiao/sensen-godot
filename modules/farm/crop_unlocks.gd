class_name CropUnlocks
extends RefCounted
## 作物解锁章节，读的是与服务端同一份 assets/farm/data/chapters.json（PRD §7.2 L505：
## C 由 D2、H 由 D3；R/L 自 D0）。2026-09-04 真机：种子栏 D0 就能选 Carrot/Chamomile，
## 玩家点了只会收到 CHAPTER_LOCKED——锁着的不该能选。

const PATH := "res://assets/farm/data/chapters.json"
static var _table: Dictionary = {}

static func unlock_chapter(crop: String) -> int:
	if _table.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		var chapters: Array = (parsed as Dictionary).get("chapters", []) if parsed is Dictionary else []
		for ch in chapters:
			for u in (ch as Dictionary).get("unlocks", []):
				if str(u).begins_with("crop_"):
					_table[str(u).trim_prefix("crop_")] = int(ch.index)
		_table["_loaded"] = 1
	return int(_table.get(crop, 0))

static func unlocked(crops: Array, chapter_index: int, state: Dictionary = {}) -> Array:
	if JourneyProgress.active(state): return crops.filter(func(id): return JourneyProgress.crops(state).has(id))
	return crops.filter(func(c): return unlock_chapter(str(c)) <= chapter_index)
