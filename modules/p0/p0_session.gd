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
const TestAccounts := preload("res://modules/p0/p0_test_accounts.gd")
var test_accounts = TestAccounts.new()

var base_url := DEFAULT_URL
var access_key := ""
## The build's versionCode, sent as x-p0-version (q(74)): from the demo build's config; 0 sends none (desktop and
## test builds are never turned away for their version).
var version := 0
var player_id := ""
## The server's view. SGODOT-260 Q3: current() shares its unchanged parts with every caller, so nothing writes into it:
## in the editor and the tests it is made read-only (a write is an error there; exported builds skip the walk).
var view: Dictionary = {}:
	set(v):
		view = v
		if OS.has_feature("editor"): P0Logic.freeze(v)
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
## When the request on the wire left: each reply logs `P0 net: <type> seq <n> <ms> ms <result> <via>` (preview B, 421:
## the per-command time on the US-west line, read from logcat): via `new` / `kept` on P0Line, `http` a request each.
var _sent_ms := 0
var _via := ""
## 421: commands and reads on one connection kept open (P0Line); a request each (P0HttpRequest) when it is off or out.
const P0Line := preload("res://modules/p0/p0_line.gd")
var line: P0Line
## false: never the line, every request a new one (tests that put in their transport after the runtime's first read
## went out: they were written for its failing a few frames on, as P0HttpRequest's does).
var use_line := true
## Tests replace the HTTP call: transport.call(method, path, body, cmd), then answer with _finish().
var transport := Callable()
## Development only (SGODOT-351): the Blackjack's bj_* commands answered locally until the server has them, its table
## laid over every view (P0BlackjackMock; P0_BJ_MOCK=1 or user://p0_bj_mock). null in every build that ships.
var bj_mock: P0BlackjackMock = P0BlackjackMock.new() if P0BlackjackMock.wanted() else null
const _BJ_MOCK_MS := 120   # the reply's round trip, so the page's in-flight states show
var _received_ms := 0
var _refresh_left := REFRESH_S
var _guide_maturity_checked := false
var _expiry_ms := -1.0   # SGODOT-377: P0Logic.next_expiry of the view, -1 once read again (or none)
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
	if not test_accounts.restore_missing_main():
		push_error("P0 test-account main identity backup could not be verified")
		return
	player_id = _read_line("user://p0_player.txt", "")
	if player_id == "":
		var bytes := Crypto.new().generate_random_bytes(10)
		player_id = "p0-" + bytes.hex_encode()
		var f := FileAccess.open("user://p0_player.txt", FileAccess.WRITE)
		if f: f.store_line(player_id)
	if test_accounts.is_test(): player_id = test_accounts.active_id()
	Avatar.user_id = test_accounts.avatar_id(Avatar.user_id)
	report({"kind": "session_start"})
	# Deferred: P0Runtime adds the session before P0Ui, and an immediate failure would toast on a UI not built yet.
	refresh.call_deferred()

func _process(dt: float) -> void:
	_ui_flush_left -= dt
	if _ui_flush_left <= 0.0 or _ui_events.size() >= UI_BATCH: _flush_ui()
	_refresh_guide_maturity(float(Time.get_ticks_msec() - _received_ms))
	_refresh_expired(float(Time.get_ticks_msec() - _received_ms))
	_refresh_left -= dt
	if _refresh_left <= 0.0 and not busy:
		_refresh_left = REFRESH_S
		refresh()

## The server view advanced to "now" on the client clock. SGODOT-260 Q3: one projection per view and millisecond (the
## runtime's frame and every caller in it share it; project is a function of the two); callers read it, never write it.
var _projected: Dictionary = {}
var _projected_of: Dictionary = {}
var _projected_ms := -1
func current() -> Dictionary:
	if view.is_empty(): return view
	var ms := Time.get_ticks_msec() - _received_ms
	if ms != _projected_ms or not is_same(_projected_of, view):
		_projected = P0Logic.project(view, float(ms))
		if OS.has_feature("editor"): P0Logic.freeze(_projected)   # shared by every caller this millisecond (哪吒 on #573)
		_projected_of = view
		_projected_ms = ms
	return _projected

## A locally expired crop may finish an optional guide step without any action. Ask the server once per view;
## a busy command finishes first, and failures fall back to the existing retry/periodic refresh (no frame storm).
func _refresh_guide_maturity(elapsed_ms: float) -> void:
	if _guide_maturity_checked or not P0Guide.guide_on(view): return
	var row = view.guide.get("row", null)
	if row is Dictionary and row.get("countdown") is String and row.get("ready_in") != null and float(row.ready_in) > 0.0 and float(row.ready_in) <= elapsed_ms:
		_guide_maturity_checked = true
		if busy: refresh_after()
		else: refresh()
		return
	for plot in view.get("plots", []):
		if str(plot.get("state", "")) != "growing" or plot.get("ready_in", null) == null: continue
		if float(plot.ready_in) <= 0.0 or float(plot.ready_in) > elapsed_ms: continue
		_guide_maturity_checked = true
		if busy: refresh_after()
		else: refresh()
		return

## SGODOT-377: a resident's next request or a board slot that came due on the projection is the server's to fill: one
## read when the first of them runs out, not the next periodic refresh up to 30 s later.
func _refresh_expired(elapsed_ms: float) -> void:
	if _expiry_ms < 0.0 or elapsed_ms < _expiry_ms: return
	_expiry_ms = -1.0
	if busy: refresh_after()
	else: refresh()

## Pure client-page acknowledgement, sent only on a player confirmation. Keyed like other UI commands, so the
## home build queued behind it uses its reply's seq; revisiting a completed page never acknowledges another step.
func guide_ack(step: String) -> bool:
	if not P0Guide.guide_on(view) or str(view.guide.step) != step: return false
	var cmd := {"type": "guide", "op": "ack", "step": step}
	return send(cmd, ui_key(cmd))

## One more read once the request on the wire is settled (a space entered while it was out: its read must carry it).
var _refresh_queued := false
func refresh_after() -> void:
	_refresh_queued = true

## The read also says where the player is, so entering a space counts even before the first command (q(41)).
func refresh() -> void:
	_refresh_left = REFRESH_S
	_refresh_queued = false
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
	var http := P0HttpRequest.new()   # its wait in live time, not stalls (SGODOT-370)
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	# _headers(): the demo key too, or a deployed server (P0_ACCESS_KEYS) would refuse every report with 401
	if http.send(base_url + "/p0/telemetry", _headers(), HTTPClient.METHOD_POST, JSON.stringify(body)) != OK: http.queue_free()

func dev_skip(minutes: int) -> void:
	_request(HTTPClient.METHOD_POST, "/p0/dev/skip", {"minutes": minutes}, {})

func _request(method: int, path: String, body: Dictionary, cmd: Dictionary) -> void:
	busy = true
	_sent_ms = Time.get_ticks_msec()
	if bj_mock != null and method == HTTPClient.METHOD_POST and str(cmd.get("type", "")).begins_with("bj_"):
		var raw := JSON.stringify(bj_mock.command(cmd, view)).to_utf8_buffer()
		if is_inside_tree(): get_tree().create_timer(_BJ_MOCK_MS / 1000.0).timeout.connect(_finish.bind(HTTPRequest.RESULT_SUCCESS, 200, raw, cmd))
		else: _finish.call_deferred(HTTPRequest.RESULT_SUCCESS, 200, raw, cmd)
		return
	if transport.is_valid():
		transport.call(method, path, body, cmd)
		return
	var payload := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	if use_line and line == null and is_inside_tree():
		line = P0Line.new()
		add_child(line)
	if use_line and line != null and line.send(base_url + path, _headers(), method, payload, func(r: int, c: int, _h, raw: PackedByteArray):
			_via = line.last_via if r == HTTPRequest.RESULT_SUCCESS else "line"
			_finish(r, c, raw, cmd)) == OK:
		return
	_via = "http"
	var http := P0HttpRequest.new()   # SGODOT-370: 8 s of live time, a world loading is not the server being slow
	add_child(http)
	http.request_completed.connect(_on_done.bind(http, cmd))
	var err := http.send(base_url + path, _headers(), method, payload)
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
	var ms := Time.get_ticks_msec() - _sent_ms   # the line's time, not the handlers' below
	var outcome := _handle(result, code, raw, cmd)
	print("P0 net: %s seq %d %d ms %s %s" % [str(cmd.get("type", "state")), int(view.get("seq", -1)), ms,
		str(outcome.code) if str(outcome.code) != "" else "ok", _via])
	busy = false
	if outcome.network:
		# A command whose reply was lost may still have done its work (preview B ②, 奕星 11-05: the floor reached and
		# paid on the server, the player kept on the floor until a tap 20 s later): read once what the server did, now,
		# after any world actions still waiting. A failed read is not read again: the runtime's own retry does (it
		# would only fail the same way).
		_refresh_queued = outcome.code == "network" and not entry.is_empty()
		# Later UI commands were based on what the player saw before the failure: drop them.
		for q in _queue.filter(func(q): return q.key != ""): command_settled.emit(q.key, false, "network")
		_queue = _queue.filter(func(q): return q.key == "")
	if str(entry.get("key", "")) != "": command_settled.emit(entry.key, outcome.ok, outcome.code)
	if not busy and not _queue.is_empty(): _post(_queue.pop_front())
	elif not busy and _refresh_queued: refresh()

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
	if data.has("state") and save_too_old(data.state):   # an old server's or an unmigrated save's: maintenance, not the world
		var held := {"code": "maintenance"}
		blocked.emit("maintenance", held)
		return {ok = false, code = "maintenance", network = true}
	if data.has("state"):
		var state: Dictionary = data.state
		if bj_mock != null: bj_mock.decorate(state)   # before it becomes the (read-only) view
		view = state
		_received_ms = Time.get_ticks_msec()
		_guide_maturity_checked = false
		_expiry_ms = P0Logic.next_expiry(view)
	if bool(data.get("ok", false)):
		state_changed.emit(view, data.get("events", []))
		return {ok = true, code = "", network = false}
	refused.emit(str(data.get("code", "")), data.get("detail", {}), cmd)
	if data.has("state"): state_changed.emit(view, [])
	return {ok = false, code = str(data.get("code", "")), network = false}

## v4q(2) ② (355 b1's two guards, 381 66475c4d): a state with no save_version, or one before SAVE_VERSION, is an old
## server's or a save not migrated yet — it never becomes the view; the runtime shows SYS-MAINT without a time
## (`We'll be back soon.` · Check again, which reads again, as for the server's own 503).
const SAVE_VERSION := 7
static func save_too_old(state) -> bool:
	return not state is Dictionary or state.get("save_version", null) == null or int(state.save_version) < SAVE_VERSION

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

## What this client can do that an older one could not (the server's `x-p0-features`): choose_home — a new save waits
## for the player to pick a home (SGODOT-303, the pick pages) instead of starting in the written city; guide_v3 — a new
## save starts the v3 guide with server-resolved presentation (341 c6f3189a). The old `guide` feature advertised
## by 0.2.11 is intentionally absent: that package cannot show the complete v3 guide.
# 0.2.14: the user opened the guide to ordinary new accounts on 10-29 (341). A main account's new save starts it; a save
# that already exists (legacy or not) keeps what it has, the server only reads the flag for a new save. A test account
# keeps the choice latched when Test options created it (aa0e971b): Off still makes a legacy test account.
const GUIDE_V3_READY := true
## locals: this client shows the keepers' local requests (q(272)): the server sends their map marks only then.
## save_v7: this client reads the v7 save (v4q(2) wipe, SGODOT-397 / 396): without it the server answers 426 like its
## version gate, so a build from before the wipe asks to be updated instead of playing on the new saves.
const FEATURES := "choose_home,guide_v3,locals,save_v7" if GUIDE_V3_READY else "choose_home,locals,save_v7"

func _headers() -> PackedStringArray:
	var headers := PackedStringArray(["x-p0-player: " + player_id, "content-type: application/json"])
	if access_key != "": headers.append("x-p0-key: " + access_key)
	if version > 0: headers.append("x-p0-version: %d" % version)
	headers.append("x-p0-features: " + features())
	return headers

## The x-p0-features this build sends, on its requests and the online handshake alike (P0Online.features).
func features() -> String:
	if not test_accounts.is_test(): return FEATURES
	return "choose_home,guide_v3,locals,save_v7" if test_accounts.guide_enabled() else "choose_home,locals,save_v7"

## The internal demo APK (tools/p0/build_demo_apk.sh) carries DEMO_CONFIG; no other build does, the file is
## written for that export only. The demo is exported as a debug build, so OS.is_debug_build() alone can't tell it
## from a test build (SGODOT-232 D2).
static func is_demo_build() -> bool:
	return FileAccess.file_exists(DEMO_CONFIG)

## The demo build's baked server: {"url": "https://…/v1", "key": "…", "version": versionCode, "name": versionName};
## {} when absent or malformed.
static func demo_config(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text) if text != "" else null
	if not parsed is Dictionary: return {}
	var url := str(parsed.get("url", "")).strip_edges().trim_suffix("/")
	if not (url.begins_with("http://") or url.begins_with("https://")): url = ""
	return {"url": url, "key": str(parsed.get("key", "")).strip_edges(), "version": int(parsed.get("version", 0)),
		"name": str(parsed.get("name", "")).strip_edges()}   # the version name, for Settings › Version (q(129))

static func _read_line(path: String, fallback: String) -> String:
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path).strip_edges()
		if text != "": return text
	return fallback
