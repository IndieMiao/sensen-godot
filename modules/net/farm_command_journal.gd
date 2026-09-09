class_name FarmCommandJournal
extends RefCounted
## Save before sending so a process exit cannot lose an in-flight idempotency key.

const DEFAULT_DIRECTORY := "user://pending_farm_commands"

var path := ""
var scope := ""
var error := OK

func _init(directory: String, endpoint: String, installation_digest: String, player_id: String, farm_id: String) -> void:
	scope = JSON.stringify([endpoint.trim_suffix("/"), installation_digest, player_id, farm_id]).sha256_text()
	path = directory.path_join(scope + ".json")

func read_command() -> Dictionary:
	error = OK
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = FileAccess.get_open_error()
		return {}
	var record = JSON.parse_string(file.get_as_text())
	file.close()
	if not record is Dictionary or record.get("format") != 1 or record.get("scope") != scope \
			or not _valid_command(record.get("command")):
		error = ERR_FILE_CORRUPT
		return {}
	return record.command.duplicate(true)

func write_command(command: Dictionary) -> bool:
	error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK: return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		error = FileAccess.get_open_error()
		return false
	file.store_string(JSON.stringify({"format": 1, "scope": scope, "command": command}))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK: return false
	error = DirAccess.rename_absolute(temporary, path)
	return error == OK

func clear() -> bool:
	error = DirAccess.remove_absolute(path) if FileAccess.file_exists(path) else OK
	return error == OK

static func _valid_command(command: Variant) -> bool:
	if not command is Dictionary: return false
	var key = command.get("idempotency_key")
	var base = command.get("base_version")
	return key is String and key.length() == 32 and key.is_valid_hex_number() \
		and (base is int or base is float) and base >= 0 and base == floor(base) \
		and command.get("type") is String and not command.type.is_empty() \
		and command.get("payload") is Dictionary
