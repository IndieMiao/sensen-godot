class_name PresetSnapshots
extends RefCounted
## 随包兜底快照（PRD §11.2）：远端不可用时，D4 所需的两座系统农场仍能访问，不阻塞主线。
## 文件由 server/tools/gen_presets.ts 生成，farm_id 与线上那座相同。

const DIR := "res://assets/farm/presets"

static func _load_all() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [DIR, f]))
		if parsed is Dictionary:
			out.append(parsed)
	out.sort_custom(func(a, b): return str(a.farm_id) < str(b.farm_id))
	return out

## 某城的随包条目，形状与服务端 NearbyEntry 一致。
static func entries(region_id: String) -> Array:
	var out: Array = []
	for s in _load_all():
		if str(s.get("region_id", "")) != region_id:
			continue
		out.append({
			"farm_id": s.farm_id, "avatar_ref": s.get("avatar_ref", "seed:unknown"),
			"nursery_stage": (s.get("nursery", {}) as Dictionary).get("stage", "derelict"),
			"region_id": s.region_id,
		})
	return out

static func snapshot(farm_id: String) -> Dictionary:
	for s in _load_all():
		if str(s.farm_id) == farm_id:
			return s
	return {}
