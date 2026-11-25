extends RefCounted
## Local stand-in for the C-31 parcel farm save (/v1/parcels/mine/enter and /commands),
## kept on this device until the client talks to the server. It applies the same rules
## with the device clock standing in for server time. Results use the store contract the
## scene reads (await-able like the remote store):
##   {ok, granted?, gift?, farm, farm_version, server_time} or
##   {ok:false, code, index, detail?, farm, farm_version, server_time}.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const DIR := "user://dynamic_farm_local"

var block_id: String
## Milliseconds since the epoch; tests replace it to move time.
var now_ms := func() -> int: return int(Time.get_unix_time_from_system() * 1000.0)
var _path: String

func _init(parcel_block_id: String, directory := DIR) -> void:
	block_id = parcel_block_id
	_path = directory.path_join(block_id.validate_filename() + ".json")

func enter() -> Dictionary:
	var rules := ParcelFarm.rules()
	if rules.is_empty(): return _failure("RULES", 0, {}, ParcelFarm.empty_state(), 0)
	var saved := _load()
	var now: int = now_ms.call()
	var welcomed = ParcelFarm.welcome(rules, saved.farm, now)
	# C-151: the one-off grants the farm has not had yet, in the same write (the server's enter).
	var gift: Dictionary = rules.welcome_gift.duplicate() if welcomed != null else {}
	var granted = ParcelFarm.grant(rules, welcomed if welcomed != null else saved.farm, now)
	if granted != null:
		for id: String in granted.gift: gift[id] = int(gift.get(id, 0)) + int(granted.gift[id])
	var next = granted.state if granted != null else welcomed
	if next == null:
		return {"ok": true, "granted": false, "gift": {}, "farm": saved.farm, "farm_version": saved.version, "server_time": now}
	if not _save(next, saved.version + 1): return _failure("SAVE", 0, {}, saved.farm, saved.version)
	return {"ok": true, "granted": welcomed != null, "gift": gift, "farm": next, "farm_version": saved.version + 1, "server_time": now}

## The farm as saved, without entering it (no welcome gift), like the server's `GET /parcels/mine`.
func read() -> Dictionary:
	if ParcelFarm.rules().is_empty(): return _failure("RULES", 0, {}, ParcelFarm.empty_state(), 0)
	var saved := _load()
	return {"ok": true, "farm": saved.farm, "farm_version": saved.version, "server_time": now_ms.call()}

func send(base_version: int, commands: Array) -> Dictionary:
	var saved := _load()
	var now: int = now_ms.call()
	if base_version != saved.version:
		return _failure("VERSION_CONFLICT", 0, {}, saved.farm, saved.version)
	var outcome := ParcelFarm.apply(ParcelFarm.rules(), saved.farm, commands, now, block_id)
	if not outcome.ok:
		return _failure(outcome.code, outcome.index, outcome.get("detail", {}), saved.farm, saved.version)
	if not _save(outcome.state, saved.version + 1): return _failure("SAVE", 0, {}, saved.farm, saved.version)
	return {"ok": true, "farm": outcome.state, "farm_version": saved.version + 1, "server_time": now}

func _failure(code: String, index: int, detail: Dictionary, farm: Dictionary, version: int) -> Dictionary:
	var result := {"ok": false, "code": code, "index": index, "farm": farm, "farm_version": version,
		"server_time": now_ms.call()}
	if not detail.is_empty(): result.detail = detail
	return result

func _load() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(_path)) if FileAccess.file_exists(_path) else null
	if raw is Dictionary and raw.get("block_id") == block_id and ParcelFarm.whole_in(raw.get("farm_version"), 0, 1 << 30):
		var farm := ParcelFarm.normalize(raw.get("farm"))
		if not farm.is_empty(): return {"farm": farm, "version": int(raw.farm_version)}
	return {"farm": ParcelFarm.empty_state(), "version": 0}

func _save(farm: Dictionary, version: int) -> bool:
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var file := FileAccess.open(_path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"block_id": block_id, "farm_version": version, "farm": farm}))
	file.close()
	return DirAccess.rename_absolute(_path + ".tmp", _path) == OK
