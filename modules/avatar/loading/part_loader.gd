class_name PartLoader
extends Node

signal load_finished(request_id: int, part_id: String, resource: Resource)
signal load_failed(request_id: int, part_id: String, err: int)

var catalog: PartCatalog
var cache: PartCache
var content_repo: ContentRepo = ContentRepo.new()

var _next_id := 1
var _by_path: Dictionary = {}   # res_path -> {part_id: String, waiters: Array[int]}
var _cancelled: Dictionary = {} # request_id -> true

func request_part(part_id: String) -> int:
	var rid := _next_id
	_next_id += 1
	var meta = catalog.part(part_id) if catalog else null
	if meta == null:
		call_deferred("_fail", rid, part_id, ERR_DOES_NOT_EXIST)
		return rid
	var avail := content_repo.ensure_available(part_id)
	if avail != OK:
		call_deferred("_fail", rid, part_id, avail)
		return rid
	if cache:
		var hit := cache.get_part(part_id)
		if hit != null:
			call_deferred("_deliver", rid, part_id, hit)
			return rid
	if _by_path.has(meta.res_path):
		_by_path[meta.res_path].waiters.append(rid)
		return rid
	var err := ResourceLoader.load_threaded_request(meta.res_path)
	if err != OK:
		call_deferred("_fail", rid, part_id, err)
		return rid
	_by_path[meta.res_path] = {"part_id": part_id, "waiters": [rid]}
	set_process(true)
	return rid

func cancel(request_id: int) -> void:
	_cancelled[request_id] = true

func _process(_delta: float) -> void:
	if _by_path.is_empty():
		set_process(false)
		return
	for path in _by_path.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var entry = _by_path[path]
		_by_path.erase(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var res := ResourceLoader.load_threaded_get(path)
			if cache:
				cache.put(entry.part_id, res, PartCache.estimate_resource_bytes(path))
			for rid in entry.waiters:
				_deliver(rid, entry.part_id, res)
		else:
			for rid in entry.waiters:
				_fail(rid, entry.part_id, ERR_CANT_ACQUIRE_RESOURCE)

func _deliver(rid: int, part_id: String, res: Resource) -> void:
	if _cancelled.erase(rid):
		return
	load_finished.emit(rid, part_id, res)

func _fail(rid: int, part_id: String, err: int) -> void:
	if _cancelled.erase(rid):
		return
	load_failed.emit(rid, part_id, err)
