class_name PartCache
extends RefCounted

var max_bytes: int = 64 * 1024 * 1024

var _entries: Dictionary = {}  # id -> {res: Resource, bytes: int, tick: int}
var _total := 0
var _tick := 0

func get_part(id: String) -> Resource:
	var e = _entries.get(id)
	if e == null:
		return null
	_tick += 1
	e.tick = _tick
	return e.res

func put(id: String, res: Resource, bytes: int) -> void:
	if _entries.has(id):
		_total -= _entries[id].bytes
	_tick += 1
	_entries[id] = {"res": res, "bytes": bytes, "tick": _tick}
	_total += bytes
	_evict_over_budget(id)

func _evict_over_budget(keep_id: String) -> void:
	while _total > max_bytes and _entries.size() > 1:
		var oldest_id := ""
		var oldest_tick := _tick + 1
		for k in _entries:
			if k == keep_id:
				continue
			if _entries[k].tick < oldest_tick:
				oldest_tick = _entries[k].tick
				oldest_id = k
		if oldest_id == "":
			break
		_total -= _entries[oldest_id].bytes
		_entries.erase(oldest_id)

func clear() -> void:
	_entries.clear()
	_total = 0

func total_bytes() -> int:
	return _total

static func estimate_resource_bytes(res_path: String) -> int:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return 1024
	var n := int(f.get_length())
	f.close()
	return maxi(n, 1024)
