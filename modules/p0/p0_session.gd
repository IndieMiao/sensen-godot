class_name P0Session
extends Node
## P0 connection to the local P0 server (server/tools/p0_server.ts, /v1/p0/*).
## Server URL: user://p0_server.txt (one line) → else http://127.0.0.1:3110/v1 (Android: adb reverse tcp:3110 tcp:3110).
## Player id: user://p0_player.txt, created once. Between responses the view is projected locally (energy ticks, crop timers).

signal state_changed(view: Dictionary, events: Array)
signal refused(code: String, detail: Dictionary, cmd: Dictionary)
## cmd is the command that never reached the server ({} for state refreshes and dev calls).
signal connection_failed(message: String, cmd: Dictionary)

const DEFAULT_URL := "http://127.0.0.1:3110/v1"
const REFRESH_S := 30.0

var base_url := DEFAULT_URL
var player_id := ""
var view: Dictionary = {}
var busy := false
var _queue: Array = []        # commands sent while a request was in flight (reel / collect must never be dropped)
var _received_ms := 0
var _refresh_left := REFRESH_S

func _ready() -> void:
	base_url = _read_line("user://p0_server.txt", OS.get_environment("P0_SERVER_URL"))
	if base_url == "": base_url = DEFAULT_URL
	player_id = _read_line("user://p0_player.txt", "")
	if player_id == "":
		var bytes := Crypto.new().generate_random_bytes(10)
		player_id = "p0-" + bytes.hex_encode()
		var f := FileAccess.open("user://p0_player.txt", FileAccess.WRITE)
		if f: f.store_line(player_id)
	refresh()

func _process(dt: float) -> void:
	_refresh_left -= dt
	if _refresh_left <= 0.0 and not busy:
		_refresh_left = REFRESH_S
		refresh()

## The server view advanced to "now" on the client clock.
func current() -> Dictionary:
	if view.is_empty(): return view
	return P0Logic.project(view, float(Time.get_ticks_msec() - _received_ms))

func refresh() -> void:
	_request(HTTPClient.METHOD_GET, "/p0/state", {}, {})

func send(cmd: Dictionary) -> void:
	if busy:
		_queue.append(cmd)
		return
	_request(HTTPClient.METHOD_POST, "/p0/commands", cmd, cmd)

func dev_skip(minutes: int) -> void:
	_request(HTTPClient.METHOD_POST, "/p0/dev/skip", {"minutes": minutes}, {})

func _request(method: int, path: String, body: Dictionary, cmd: Dictionary) -> void:
	busy = true
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(_on_done.bind(http, cmd))
	var headers := PackedStringArray(["x-p0-player: " + player_id, "content-type: application/json"])
	var err := http.request(base_url + path, headers, method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if err != OK:
		busy = false
		http.queue_free()
		connection_failed.emit("Can't reach the farm server", cmd)

func _on_done(result: int, code: int, _h: PackedStringArray, raw: PackedByteArray, http: HTTPRequest, cmd: Dictionary) -> void:
	busy = false
	http.queue_free()
	if not _queue.is_empty():
		var next: Dictionary = _queue.pop_front()
		_request(HTTPClient.METHOD_POST, "/p0/commands", next, next)
		_handle(result, code, raw, cmd)
		return
	_handle(result, code, raw, cmd)

func _handle(result: int, code: int, raw: PackedByteArray, cmd: Dictionary) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 0:
		connection_failed.emit("Can't reach the farm server", cmd)
		return
	var data = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		connection_failed.emit("Unexpected server reply", cmd)
		return
	if data.has("state"):
		view = data.state
		_received_ms = Time.get_ticks_msec()
	if bool(data.get("ok", false)):
		state_changed.emit(view, data.get("events", []))
	else:
		refused.emit(str(data.get("code", "")), data.get("detail", {}), cmd)
		if data.has("state"): state_changed.emit(view, [])

## P0 prototype entry: a user://p0_boot marker (adb run-as touch files/p0_boot) or SENSEN_P0=1 on desktop.
static func boot_wanted() -> bool:
	return FileAccess.file_exists("user://p0_boot") or OS.get_environment("SENSEN_P0") == "1" or OS.has_feature("p0")

static func _read_line(path: String, fallback: String) -> String:
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path).strip_edges()
		if text != "": return text
	return fallback
