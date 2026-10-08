class_name P0Session
extends Node
## P0 connection to the P0 server (server/tools/p0_server.ts, /v1/p0/*).
## Server URL: user://p0_server.txt (one line) → P0_SERVER_URL → the demo build's res://assets/p0/demo_server.json
## (written by tools/p0/build_demo_apk.sh, never committed) → http://127.0.0.1:3110/v1 (adb reverse tcp:3110 tcp:3110).
## The demo file may also carry the demo access key, sent as x-p0-key (SGODOT-232 D1 / D2).
## Player id: user://p0_player.txt, created once. Between responses the view is projected locally (energy ticks, crop timers).

signal state_changed(view: Dictionary, events: Array)
signal refused(code: String, detail: Dictionary, cmd: Dictionary)
## cmd is the command that never reached the server ({} for state refreshes and dev calls).
signal connection_failed(message: String, cmd: Dictionary)
## A keyed UI command was accepted for sending / has its result (ok, refusal code or "network").
signal command_started(key: String)
signal command_settled(key: String, ok: bool, code: String)
## Every command as it is handed to send(), before it goes out (the guide closes a TipCard the player just acted on).
signal sent(cmd: Dictionary)
## The server turned every request away (q(74), SGODOT-233): "update_required" (HTTP 426, {url}) or "maintenance"
## (HTTP 503, {back_at}: UTC ISO, absent when unknown). Not a network failure: no Didn't go through, no Offline.
signal blocked(code: String, detail: Dictionary)

const DEFAULT_URL := "http://127.0.0.1:3110/v1"
const DEMO_CONFIG := "res://assets/p0/demo_server.json"
const REFRESH_S := 30.0

var base_url := DEFAULT_URL
var access_key := ""
## The build's versionCode, sent as x-p0-version (q(74)): from the demo build's config; 0 sends none (desktop and
## test builds are never turned away for their version).
var version := 0
var player_id := ""
var view: Dictionary = {}
## Where the player is (P0Runtime sets it on attach / detach): home, pond, outpost, mine, map or "" when unknown.
## Sent beside each command for Rest's 2 h away rule (q(41)); never part of the command or its dedupe key.
var space := ""
## The catalog pond inside a pond space (q(36)): the server reads the pond's template from its own table.
var place := ""
## How the player pressed for the next command ("hold" / "tap"), for the observation log (S7): P0Runtime sets a
## callable that says "hold" only for the farm's hold-to-repeat commands. Sent beside the command, like space.
var src_of := Callable()
var busy := false
var _queue: Array = []        # {cmd, key} sent while a request was in flight (reel / collect must never be dropped)
var _inflight := {}           # the {cmd, key} on the wire; {} for state refreshes and dev calls
## Tests replace the HTTP call: transport.call(method, path, body, cmd), then answer with _finish().
var transport := Callable()
var _received_ms := 0
var _refresh_left := REFRESH_S
## UI moments for the observation log (S7): batched, sent apart from commands, dropped when the server is away.
const UI_BATCH := 20
const UI_FLUSH_S := 10.0
var _ui_events: Array = []
var _ui_flush_left := UI_FLUSH_S

func _ready() -> void:
	var demo := demo_config(FileAccess.get_file_as_string(DEMO_CONFIG) if FileAccess.file_exists(DEMO_CONFIG) else "")
	base_url = _read_line("user://p0_server.txt", OS.get_environment("P0_SERVER_URL"))
	if base_url == "": base_url = str(demo.get("url", ""))
	if base_url == "": base_url = DEFAULT_URL
	access_key = str(demo.get("key", ""))
	version = int(demo.get("version", 0))
	player_id = _read_line("user://p0_player.txt", "")
	if player_id == "":
		var bytes := Crypto.new().generate_random_bytes(10)
		player_id = "p0-" + bytes.hex_encode()
		var f := FileAccess.open("user://p0_player.txt", FileAccess.WRITE)
		if f: f.store_line(player_id)
	report({"kind": "session_start"})
	# Deferred: P0Runtime adds the session before P0Ui, and an immediate failure would toast on a UI not built yet.
	refresh.call_deferred()

func _process(dt: float) -> void:
	_ui_flush_left -= dt
	if _ui_flush_left <= 0.0 or _ui_events.size() >= UI_BATCH: _flush_ui()
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
	var query := ("?space=" + space.uri_encode() if space != "" else "") + ("&place=" + place.uri_encode() if space != "" and place != "" else "")
	_request(HTTPClient.METHOD_GET, "/p0/state" + query, {}, {})

## World actions send without a key and are never dropped. UI commands pass a key (ui_key) and are ignored
## while the same key is on the wire or queued, so double taps on Buy / Sell submit once (WP7-B F-08 §2).
func send(cmd: Dictionary, key := "") -> bool:
	if key != "" and (str(_inflight.get("key", "")) == key or _queue.any(func(q): return q.key == key)):
		return false
	sent.emit(cmd)
	var src := str(src_of.call()) if src_of.is_valid() else ""
	var entry := {cmd = cmd, key = key, space = space, place = place, src = src}   # where and how it was issued, even if it waits
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
	if str(entry.get("place", "")) != "": body["place"] = str(entry.place)
	if str(entry.get("src", "")) != "": body["src"] = str(entry.src)
	_request(HTTPClient.METHOD_POST, "/p0/commands", body, entry.cmd)

## A UI moment for the observation log: {kind = "tip_shown", key = "sow"} and the like (server keeps known kinds only).
func report(event: Dictionary) -> void:
	_ui_events.append(event)
	if _ui_events.size() >= UI_BATCH: _flush_ui()

## Fire and forget: the log never blocks or reorders commands, and a failed send is simply dropped.
func _flush_ui() -> void:
	_ui_flush_left = UI_FLUSH_S
	if _ui_events.is_empty(): return
	var body := {"events": _ui_events.slice(0, UI_BATCH)}
	_ui_events = _ui_events.slice(UI_BATCH)
	if transport.is_valid():
		transport.call(HTTPClient.METHOD_POST, "/p0/telemetry", body, {"type": "telemetry"})
		return
	if not is_inside_tree(): return
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	# _headers(): the demo key too, or a deployed server (P0_ACCESS_KEYS) would refuse every report with 401
	if http.request(base_url + "/p0/telemetry", _headers(), HTTPClient.METHOD_POST, JSON.stringify(body)) != OK: http.queue_free()

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
	var err := http.request(base_url + path, _headers(), method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
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
	var block := blocked_reply(result, code, raw)
	if not block.is_empty():
		blocked.emit(str(block.code), block)
		return {ok = false, code = str(block.code), network = true}   # what waits behind it is dropped, like a failure
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

## The server's whole-screen refusals (q(74)): 426 {code: "update_required", url} and 503 {code: "maintenance",
## back_at}. Both the status and the body's code must match, so a proxy's plain 503 stays a network failure.
static func blocked_reply(result: int, code: int, raw: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS or not code in [426, 503]: return {}
	var data = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY: return {}
	var want := "update_required" if code == 426 else "maintenance"
	return data if str(data.get("code", "")) == want else {}

## P0 prototype entry: a user://p0_boot marker (adb run-as touch files/p0_boot) or SENSEN_P0=1 on desktop.
static func boot_wanted() -> bool:
	return FileAccess.file_exists("user://p0_boot") or OS.get_environment("SENSEN_P0") == "1" or OS.has_feature("p0")

func _headers() -> PackedStringArray:
	var headers := PackedStringArray(["x-p0-player: " + player_id, "content-type: application/json"])
	if access_key != "": headers.append("x-p0-key: " + access_key)
	if version > 0: headers.append("x-p0-version: %d" % version)
	return headers

## The internal demo APK (tools/p0/build_demo_apk.sh) carries DEMO_CONFIG; no other build does, the file is
## written for that export only. The demo is exported as a debug build, so OS.is_debug_build() alone can't tell it
## from a test build (SGODOT-232 D2).
static func is_demo_build() -> bool:
	return FileAccess.file_exists(DEMO_CONFIG)

## The demo build's baked server: {"url": "https://…/v1", "key": "…"}; {} when absent or malformed.
static func demo_config(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text) if text != "" else null
	if not parsed is Dictionary: return {}
	var url := str(parsed.get("url", "")).strip_edges().trim_suffix("/")
	if not (url.begins_with("http://") or url.begins_with("https://")): url = ""
	return {"url": url, "key": str(parsed.get("key", "")).strip_edges(), "version": int(parsed.get("version", 0))}

static func _read_line(path: String, fallback: String) -> String:
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path).strip_edges()
		if text != "": return text
	return fallback
