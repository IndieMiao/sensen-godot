class_name PartLoader
extends Node

signal load_finished(request_id: int, part_id: String, resource: Resource)
signal load_failed(request_id: int, part_id: String, err: int)

var catalog: PartCatalog
var cache: PartCache
var content_repo: ContentRepo = ContentRepo.new()

var _next_id := 1
var _by_path: Dictionary = {}   # res_path -> {waiters: Array[{rid: int, part_id: String}]}
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
		_by_path[meta.res_path].waiters.append({"rid": rid, "part_id": part_id})
		return rid
	if AppRouter.sync_loads:   # Compatibility: threaded loads never finished there (0.3.3 h1); loaded here, delivered as one
		var res := load(meta.res_path)
		if res == null:
			call_deferred("_fail", rid, part_id, ERR_CANT_ACQUIRE_RESOURCE)
			return rid
		if cache: cache.put(part_id, res, PartCache.estimate_resource_bytes(meta.res_path))
		call_deferred("_deliver", rid, part_id, res)
		return rid
	var err := ResourceLoader.load_threaded_request(meta.res_path)
	if err != OK:
		call_deferred("_fail", rid, part_id, err)
		return rid
	_by_path[meta.res_path] = {"waiters": [{"rid": rid, "part_id": part_id}]}
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
				var cached_parts: Dictionary = {}
				for w in entry.waiters:
					if not cached_parts.has(w.part_id):
						cache.put(w.part_id, res, PartCache.estimate_resource_bytes(path))
						cached_parts[w.part_id] = true
			for w in entry.waiters:
				_deliver(w.rid, w.part_id, res)
		else:
			# 取走失败的加载令牌，释放引擎内部句柄（否则 ObjectDB 泄漏）
			var _discard := ResourceLoader.load_threaded_get(path)
			for w in entry.waiters:
				_fail(w.rid, w.part_id, ERR_CANT_ACQUIRE_RESOURCE)

func _deliver(rid: int, part_id: String, res: Resource) -> void:
	if _cancelled.erase(rid):
		return
	load_finished.emit(rid, part_id, res)

func _fail(rid: int, part_id: String, err: int) -> void:
	if _cancelled.erase(rid):
		return
	load_failed.emit(rid, part_id, err)
