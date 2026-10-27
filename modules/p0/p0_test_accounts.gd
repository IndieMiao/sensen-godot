extends RefCounted
## SGODOT-341 B test accounts (aa0e971b): local device options, never a server reset or a replacement main identity.
## The main p0_player.txt is retained byte-for-byte. A verified backup is required before creating any test id.
## Test ids, outfit keys and UI preferences are separate and survive an in-place application update.

const PREFIX := "g3test-"
const OPTIONS := "p0_test_options.json"
const MAIN := "p0_player.txt"
const BACKUP := "p0_main_identity.backup"
var directory: String
var _options := {}

func _init(dir := "user://") -> void:
	directory = dir.trim_suffix("/") + "/"
	var file := directory + OPTIONS
	if FileAccess.file_exists(file):
		var value = JSON.parse_string(FileAccess.get_file_as_string(file))
		if value is Dictionary: _options = value

func enabled() -> bool: return bool(_options.get("enabled", false))

static func valid_test_id(id: String) -> bool:
	if not id.begins_with(PREFIX) or id.length() != PREFIX.length() + 32: return false
	for c in id.trim_prefix(PREFIX):
		if not c in "0123456789abcdef": return false
	return true

func active_id() -> String:
	var id := str(_options.get("active", ""))
	return id if valid_test_id(id) and not _backup_bytes().is_empty() else ""

func is_test() -> bool: return active_id() != ""

## Latched when a new test account is created. Toggling the next-account option never changes an existing account.
func guide_enabled() -> bool:
	return is_test() and bool(_options.get("active_guide", false))

func set_enabled(on: bool) -> bool:
	var next := _options.duplicate(true)
	next.enabled = on
	return _save(next)

## The app's main identity is created by P0Session as before. Never replace an existing different file with a backup.
func restore_missing_main() -> bool:
	if FileAccess.file_exists(directory + MAIN) and FileAccess.get_file_as_string(directory + MAIN).strip_edges() != "":
		return true
	var backup := _backup_bytes()
	if backup.is_empty(): return not FileAccess.file_exists(directory + BACKUP)
	return _write_atomic(directory + MAIN, backup)

func start_test(main_avatar := "local") -> bool:
	var primary := FileAccess.get_file_as_bytes(directory + MAIN) if FileAccess.file_exists(directory + MAIN) else PackedByteArray()
	if primary.get_string_from_utf8().strip_edges() == "": return false
	var backup := _backup_bytes()
	if FileAccess.file_exists(directory + BACKUP):
		if backup != primary: return false   # no guessing which main account was meant
	elif not _write_atomic(directory + BACKUP, primary): return false
	if _backup_bytes() != primary: return false
	var next := _options.duplicate(true)
	if not is_test(): next.main_avatar = main_avatar
	next.active = PREFIX + Crypto.new().generate_random_bytes(16).hex_encode()
	next.active_guide = enabled()
	return _save(next)

func return_main() -> bool:
	if not restore_missing_main(): return false
	var primary := FileAccess.get_file_as_bytes(directory + MAIN)
	if primary.is_empty() or primary != _backup_bytes(): return false
	var next := _options.duplicate(true)
	next.active = ""
	next.active_guide = false
	return _save(next)

func avatar_id(fallback := "local") -> String:
	return active_id() if is_test() else str(_options.get("main_avatar", fallback))

## The original preference paths are used only on Main. Test profiles cannot clear the main tips/quick-bar stores.
func profile_file(name: String) -> String:
	if not is_test(): return directory + name
	var dir := directory + "p0_test_accounts/" + active_id() + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir + name

func _backup_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(directory + BACKUP) if FileAccess.file_exists(directory + BACKUP) else PackedByteArray()

func _save(next: Dictionary) -> bool:
	if not _write_atomic(directory + OPTIONS, JSON.stringify(next).to_utf8_buffer()): return false
	_options = next
	return true

## Write+flush+readback before atomic rename. On failure the last valid options/identity remain in place.
static func _write_atomic(path: String, bytes: PackedByteArray) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return false
	f.store_buffer(bytes)
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK or FileAccess.get_file_as_bytes(tmp) != bytes:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	var moved := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	return moved == OK and FileAccess.get_file_as_bytes(path) == bytes
