class_name P0Session
extends Node
## P0 connection to the local P0 server (server/tools/p0_server.ts, /v1/p0/*).
## Server URL: user://p0_server.txt (one line) → else http://127.0.0.1:3110/v1 (Android: adb reverse tcp:3110 tcp:3110).
## Player id: user://p0_player.txt, created once. Between responses the view is projected locally (energy ticks, crop timers).

signal state_changed(view: Dictionary, events: Array)
signal refused(code: String, detail: Dictionary, cmd: Dictionary)
## cmd is the command that never reached the server ({} for state refreshes and dev calls).
signal connection_failed(message: String, cmd: Dictionary)
## A keyed UI command was accepted for sending / has its result (ok, refusal code or "network").
signal command_started(key: String)
signal command_settled(key: String, ok: bool, code: String)

const DEFAULT_URL := "http://127.0.0.1:3110/v1"
const REFRESH_S := 30.0

var base_url := DEFAULT_URL
var player_id := ""
var view: Dictionary = {}
## Where the player is (P0Runtime sets it on attach / detach): home, pond, outpost, mine, map or "" when unknown.
## Sent beside each command for Rest's 2 h away rule (q(41)); never part of the command or its dedupe key.
var space := ""
var busy := false
var _queue: Array = []        # {cmd, key} sent while a request was in flight (reel / collect must never be dropped)
var _inflight := {}           # the {cmd, key} on the wire; {} for state refreshes and dev calls
## Tests replace the HTTP call: transport.call(method, path, body, cmd), then answer with _finish().
var transport := Callable()
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

## The read also says where the player is, so entering a space counts even before the first command (q(41)).
func refresh() -> void:
	_request(HTTPClient.METHOD_GET, "/p0/state" + ("?space=" + space.uri_encode() if space != "" else ""), {}, {})

## World actions send without a key and are never dropped. UI commands pass a key (ui_key) and are ignored
## while the same key is on the wire or queued, so double taps on Buy / Sell submit once (WP7-B F-08 §2).
func send(cmd: Dictionary, key := "") -> bool:
	if key != "" and (str(_inflight.get("key", "")) == key or _queue.any(func(q): return q.key == key)):
		return false
	var entry := {cmd = cmd, key = key, space = space}   # the space the player issued it from, even if it waits in the queue
	if key != "": command_started.emit(key)
	if busy: _queue.append(entry)
	else: _post(entry)
	return true

## Dedupe key for a UI command: its full content, so Sell one and Sell all stay distinct.
static func ui_key(cmd: Dictionary) -> String:
	return JSON.stringify(cmd, "", true)

## Every command carries the state version the client saw; the server refuses a mismatch as stale_state,
## so a retry after a lost response cannot apply twice.
func _post(entry: Dictionary) -> void:
	_inflight = entry
	var body: Dictionary = (entry.cmd as Dictionary).duplicate()
	if view.has("seq"): body["expect_seq"] = int(view.seq)
	if str(entry.get("space", "")) != "": body["space"] = str(entry.space)
	_request(HTTPClient.METHOD_POST, "/p0/commands", body, entry.cmd)

func dev_skip(minutes: int) -> void:
	_request(HTTPClient.METHOD_POST, "/p0/dev/skip", {"minutes": minutes}, {})

func _request(method: int, path: String, body: Dictionary, cmd: Dictionary) -> void:
	busy = true
	if transport.is_valid():
		transport.call(method, path, body, cmd)
		return
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(_on_done.bind(http, cmd))
	var headers := PackedStringArray(["x-p0-player: " + player_id, "content-type: application/json"])
	var err := http.request(base_url + path, headers, method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if err != OK:
		http.queue_free()
		_finish(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray(), cmd)

func _on_done(result: int, code: int, _h: PackedStringArray, raw: PackedByteArray, http: HTTPRequest, cmd: Dictionary) -> void:
	http.queue_free()
	_finish(result, code, raw, cmd)

## One response, in order: handle it while still busy (so commands sent from signal handlers queue behind
## the ones already waiting), settle its key, then send the next queued command with the fresh seq.
func _finish(result: int, code: int, raw: PackedByteArray, cmd: Dictionary) -> void:
	var entry := _inflight
	_inflight = {}
	var outcome := _handle(result, code, raw, cmd)
	busy = false
	if outcome.network:
		# Later UI commands were based on what the player saw before the failure: drop them.
		for q in _queue.filter(func(q): return q.key != ""): command_settled.emit(q.key, false, "network")
		_queue = _queue.filter(func(q): return q.key == "")
	if str(entry.get("key", "")) != "": command_settled.emit(entry.key, outcome.ok, outcome.code)
	if not busy and not _queue.is_empty(): _post(_queue.pop_front())

func _handle(result: int, code: int, raw: PackedByteArray, cmd: Dictionary) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 0:
		connection_failed.emit("Can't reach the farm server", cmd)
		return {ok = false, code = "network", network = true}
	var data = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		connection_failed.emit("Unexpected server reply", cmd)
		return {ok = false, code = "network", network = true}
	if data.has("state"):
		view = data.state
		_received_ms = Time.get_ticks_msec()
	if bool(data.get("ok", false)):
		state_changed.emit(view, data.get("events", []))
		return {ok = true, code = "", network = false}
	refused.emit(str(data.get("code", "")), data.get("detail", {}), cmd)
	if data.has("state"): state_changed.emit(view, [])
	return {ok = false, code = str(data.get("code", "")), network = false}

## P0 prototype entry: a user://p0_boot marker (adb run-as touch files/p0_boot) or SENSEN_P0=1 on desktop.
static func boot_wanted() -> bool:
	return FileAccess.file_exists("user://p0_boot") or OS.get_environment("SENSEN_P0") == "1" or OS.has_feature("p0")

static func _read_line(path: String, fallback: String) -> String:
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path).strip_edges()
		if text != "": return text
	return fallback
