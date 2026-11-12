extends Logger
## GDScript errors reported to the server (SGODOT-486; 亚瑟's store plan §4 ②, 后裔's client_error file): the engine's
## errors and script errors (not warnings, not prints), each as {kind: client_error, message ≤ 500, stack — its first
## 20 frames, a line each ≤ 200 — scene ≤ 64}, through P0Session.report() to /v1/p0/telemetry. The version, platform
## and channel go as the request's headers; nothing of the player's — no ID, no input — and no other field (the privacy
## policy and both stores' forms say "not linked to the player"; the server keeps no ID or IP for these). The same error
## at most once an hour, 20 a session. Only once P0Session.identity_ready (the account's gate, 后裔's PR-A: a token or a
## claim, past the age gate): before that, or after it closes again, an error is dropped, never kept to send later.
## The engine calls _log_error from any thread: it only queues (under a mutex); drain() sends, on the main thread.

const KIND := "client_error"
const MESSAGE_MAX := 500
const STACK_LINES := 20
const LINE_MAX := 200
const SCENE_MAX := 64
const SAME_EVERY_MS := 3600000   # the same error once an hour
const SESSION_MAX := 20
const PENDING_MAX := 50          # queued between two drains at most (an error storm in one frame)

var _mutex := Mutex.new()
var _pending: Array = []   # [message, stack] waiting for drain()
var _last := {}            # error key → when it was last sent (ms)
var sent := 0              # reported this session

## An engine error: queued if it is an error or a script error (from any thread; nothing is sent here).
func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != ERROR_TYPE_ERROR and error_type != ERROR_TYPE_SCRIPT: return
	var frames: Array = []
	for b in script_backtraces:
		for i in b.get_frame_count(): frames.append([b.get_frame_function(i), b.get_frame_file(i), b.get_frame_line(i)])
		if not frames.is_empty(): break   # the first language's (GDScript) frames
	if frames.is_empty(): frames.append([function, file, line])
	var e := [message_of(code, rationale), stack_of(frames)]
	_mutex.lock()
	if _pending.size() < PENDING_MAX: _pending.append(e)
	_mutex.unlock()

func _log_message(_message: String, _error: bool) -> void:
	pass

## The error's words: the engine's rationale when it has one (its condition `code` then says only where), else the
## code (push_error's text, a script error's), cut to MESSAGE_MAX.
static func message_of(code: String, rationale: String) -> String:
	return (rationale if rationale != "" else code).left(MESSAGE_MAX)

## The call stack as lines `function file:line`, the first STACK_LINES, each cut to LINE_MAX, one string.
static func stack_of(frames: Array) -> String:
	var lines: PackedStringArray = []
	for f in frames.slice(0, STACK_LINES): lines.append(("%s %s:%d" % [f[0], f[1], f[2]]).left(LINE_MAX))
	return "\n".join(lines)

## The event for one error, its scene cut to SCENE_MAX: these four fields and no other.
static func event_of(message: String, stack: String, scene: String) -> Dictionary:
	return {"kind": KIND, "message": message, "stack": stack, "scene": scene.left(SCENE_MAX)}

## Sends what was queued (main thread, once a frame): dropped while the gate is closed, else each one not sent within
## the hour, up to SESSION_MAX.
func drain(session: P0Session, scene: String, now_ms: int) -> void:
	_mutex.lock()
	var batch := _pending
	_pending = []
	_mutex.unlock()
	if batch.is_empty() or session == null or not session.identity_ready: return
	for e in batch:
		if sent >= SESSION_MAX: return
		var key := str(e[0]) + "|" + str(e[1]).get_slice("\n", 0)
		if _last.has(key) and now_ms - int(_last[key]) < SAME_EVERY_MS: continue
		_last[key] = now_ms
		sent += 1
		session.report(event_of(e[0], e[1], scene))
