extends Node
## GENSEN_VOICE_MEDIA_QA_V1. Native test driver, not the complete P0 account/game session.
signal changed
var backend: Object
var broker: Node
var config := {}
var state := "idle"
var error := ""
var participants: Array = []
var self_id := ""
var microphone := false
var listening := true
var renew_enabled := true
var blocked: Array[String] = []
var muted: Array[String] = []
var _code := ""
var _sid := ""
var _lease := ""
var _generation := 0
var _inflight := false
var _next_heartbeat := 0
var _room := ""
var _foreground := true
var _testing := false
var _android_arm_until := 0
var evidence: Array[Dictionary] = []
var _evidence_path := ""

func configure(settings: Dictionary, native: Object, transport: Node, testing := false) -> void:
	_testing = testing
	_evidence_path = "user://qa-evidence-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	config = settings.duplicate(true)
	backend = native
	broker = transport
	if backend: backend.connect("voice_event", _event)

func supported() -> bool:
	if backend == null or bool(config.get("validation_only", true)) or not _armed(): return false
	var parser := JSON.new()
	return parser.parse(str(backend.call("capabilities"))) == OK and parser.data is Dictionary and parser.data.get("supported", false) == true

func arm_android() -> void:
	if OS.get_name() == "Android" and config.get("client") == "android-b" and not config.get("validation_only", true) and _android_arm_until == 0:
		_android_arm_until = Time.get_ticks_msec() + 600000
		changed.emit()

func _armed() -> bool:
	if _testing: return true
	if OS.get_name() == "Android": return _android_arm_until > Time.get_ticks_msec()
	if OS.get_name() != "iOS" or not FileAccess.file_exists("user://.voice_qa_state.json"): return false
	var file := FileAccess.open("user://.voice_qa_state.json", FileAccess.READ)
	if file == null or file.get_length() > 1024: return false
	var parser := JSON.new()
	return parser.parse(file.get_as_text()) == OK and parser.data is Dictionary and parser.data.get("marker") == "GENSEN_VOICE_MEDIA_QA_V1" and parser.data.get("armed", false) == true and float(parser.data.get("expires_at", 0)) > Time.get_unix_time_from_system()

func join(capability: String) -> void:
	if _inflight or not _sid.is_empty() or not supported() or not _foreground: return
	if capability.is_empty() or capability.length() > 128 or capability.contains("\n") or capability.contains("\r"):
		error = "QA_CODE_INVALID"; changed.emit(); return
	_generation += 1
	_code = capability
	_sid = Crypto.new().generate_random_bytes(16).hex_encode()
	state = "permission"; error = ""; renew_enabled = true
	backend.call("request_permission", _sid)
	changed.emit()

func _process(_delta: float) -> void:
	if backend and backend.has_method("poll_events"): backend.call("poll_events")
	if not _sid.is_empty() and not _armed():
		leave(false); error = "QA_STOPPED"; changed.emit(); return
	if _foreground and renew_enabled and not _lease.is_empty() and not _inflight and Time.get_ticks_msec() >= _next_heartbeat:
		_heartbeat()

func _event(raw: String) -> void:
	var parser := JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary: return
	var event: Dictionary = parser.data
	if _sid.is_empty() or str(event.get("session", "")) != _sid: return
	var event_name := str(event.get("event", ""))
	var facts := {"event": event_name if event_name in ["permission","connected","participants","microphone","listening","reconnecting","disconnected","error"] else "unknown", "reason": safe_code(str(event.get("reason", ""))), "code": safe_code(str(event.get("code", "")))}
	for field in ["qa_native_uptime_ms", "qa_native_wall_seconds"]:
		var stamp: Variant = event.get(field)
		if typeof(stamp) in [TYPE_FLOAT,TYPE_INT] and float(stamp) >= 0 and float(stamp) < 1.0e15: facts[field] = stamp
	if event_name != "participants":
		if typeof(event.get("microphone")) == TYPE_BOOL: facts["microphone"] = event.microphone
		if typeof(event.get("listening")) == TYPE_BOOL: facts["listening"] = event.listening
		_record("native_event", facts)
	match str(event.get("event", "")):
		"permission":
			if state != "permission": return
			if event.get("granted", false) == true: _join_grant()
			else:
				leave(false); error = "MICROPHONE_DENIED"; changed.emit(); return
		"connected":
			state = "connected"
			_apply_people()
		"reconnecting": state = "reconnecting"
		"disconnected":
			leave(false)
			error = safe_code(str(event.get("reason", "DISCONNECTED"))); changed.emit(); return
		"error":
			var code := safe_code(str(event.get("code", "NATIVE_ERROR")))
			leave(false); error = code; changed.emit(); return
	if event.get("participants") is Array: participants = event.participants
	if event.has("microphone"): microphone = bool(event.microphone)
	if event.has("listening"): listening = bool(event.listening)
	changed.emit()

func _join_grant() -> void:
	if _inflight: return
	_inflight = true
	state = "requesting"
	var generation := _generation
	var code := _code
	var client := str(config.get("client", ""))
	var response: Dictionary = await broker.call("request", "join", {"client": client, "request_id": _sid}, code)
	_inflight = false
	var data: Dictionary = response.get("json", {}) if response.get("json") is Dictionary else {}
	if generation != _generation or _sid.is_empty() or not _foreground:
		if response.get("ok", false) and data.get("lease_id") is String:
			_release(str(data.lease_id), code)
		changed.emit(); return
	if not bool(response.get("ok", false)) or not valid_grant(data):
		if response.get("ok", false) and data.get("lease_id") is String: _release(str(data.lease_id), code)
		leave(false); error = safe_code(str(data.get("code", "BAD_GRANT"))); changed.emit(); return
	_lease = str(data.lease_id); _room = str(data.room); self_id = str(data.self)
	state = "connecting"
	_next_heartbeat = Time.get_ticks_msec() + 4500
	backend.call("connect_voice", _sid, str(data.url), str(data.token))
	_apply_people()
	backend.call("renew_lease", _sid, 19500)
	changed.emit()

func valid_grant(data: Dictionary) -> bool:
	for key in ["url", "token", "lease_id", "room", "self"]:
		if not data.get(key) is String or str(data[key]).is_empty(): return false
	return str(data.url).trim_suffix("/") == str(config.get("media_origin", "")).trim_suffix("/") and int(data.get("lease_ms", 0)) == 20000 and int(data.get("capacity", 0)) == 2 and str(data.room).begins_with("p0-ios-voice-qa-1118-") and str(data.self) == ("qa-ios-a" if config.get("client") == "ios-a" else "qa-android-b") and str(data.token).length() <= 16384

func _heartbeat() -> void:
	_inflight = true
	var generation := _generation
	var lease := _lease
	var response: Dictionary = await broker.call("request", "heartbeat", {"client": config.client, "lease_id": lease}, _code)
	_inflight = false
	_next_heartbeat = Time.get_ticks_msec() + 4500
	if generation != _generation or _sid.is_empty() or lease != _lease or not renew_enabled: return
	var data: Dictionary = response.get("json", {}) if response.get("json") is Dictionary else {}
	if response.get("ok", false) == true and int(data.get("lease_ms", 0)) == 20000 and str(data.get("room", "")) == _room:
		backend.call("renew_lease", _sid, 19500)
	else:
		error = safe_code(str(data.get("code", "HEARTBEAT_FAILED")))
		# No forged renewal. Native monotonic lease expiry remains authoritative.
	changed.emit()

func _release(lease: String, code: String) -> void:
	if lease.is_empty(): return
	await broker.call("request", "leave", {"client": config.client, "lease_id": lease}, code)

func leave(clear_people := true) -> void:
	_generation += 1
	var sid := _sid; var lease := _lease; var code := _code
	_sid = ""; _lease = ""; _room = ""; _code = ""
	if backend and not sid.is_empty(): backend.call("disconnect_voice", sid)
	if not lease.is_empty(): _release(lease, code)
	state = "idle"; microphone = false; listening = true; participants = []; self_id = ""
	if clear_people: blocked.clear(); muted.clear()
	changed.emit()

func set_microphone(on: bool) -> void:
	if state == "connected": backend.call("set_microphone", _sid, on)
func set_listening(on: bool) -> void:
	if state == "connected": backend.call("set_listening", _sid, on)
func set_muted(identity: String, on: bool) -> void:
	if identity.is_empty() or identity == self_id: return
	muted.erase(identity)
	if on: muted.append(identity)
	if state == "connected": backend.call("set_participant_volume", _sid, identity, 0.0 if on else 1.0)
	changed.emit()
func set_blocked(identity: String, on: bool) -> void:
	if identity.is_empty() or identity == self_id: return
	blocked.erase(identity)
	if on: blocked.append(identity)
	if state in ["connecting", "connected", "reconnecting"]:
		backend.call("set_participant_subscribed", _sid, identity, not on)
		backend.call("set_publish_allowed", _sid, identity, not on)
	changed.emit()
func _apply_people() -> void:
	for identity in blocked:
		backend.call("set_participant_subscribed", _sid, identity, false)
		backend.call("set_publish_allowed", _sid, identity, false)
	for identity in muted: backend.call("set_participant_volume", _sid, identity, 0.0)
func open_settings() -> void:
	if backend and supported() and backend.has_method("open_settings"): backend.call("open_settings")
func foreground(value: bool) -> void:
	_foreground = value
	if not value: leave(false)
func test_native_expiry() -> void:
	if state != "connected" or _inflight: return
	_inflight = true
	var generation := _generation
	var lease := _lease
	var response: Dictionary = await broker.call("request", "heartbeat", {"client": config.client, "lease_id": lease}, _code)
	_inflight = false
	if generation != _generation or lease != _lease or _sid.is_empty(): return
	var data: Dictionary = response.get("json", {}) if response.get("json") is Dictionary else {}
	if response.get("ok", false) == true and int(data.get("lease_ms", 0)) == 20000 and str(data.get("room", "")) == _room:
		renew_enabled = false
		_record("native_expiry_test_start", {"native_lease_ms": 5000, "server_lease_ms": 20000})
		backend.call("renew_lease", _sid, 5000)
	else: error = "HEARTBEAT_FAILED"
	changed.emit()

func _record(kind: String, fields: Dictionary) -> void:
	var row := {"kind": kind, "client": str(config.get("client", "")), "client_uptime_ms": Time.get_ticks_msec(), "client_wall_seconds": Time.get_unix_time_from_system()}
	row.merge(fields)
	evidence.append(row)
	if evidence.size() > 128: evidence.pop_front()
	if not _testing:
		var file := FileAccess.open(_evidence_path, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(evidence))

func safe_code(code: String) -> String:
	const CODES := ["NOT_ARMED","UNAUTHENTICATED","FORBIDDEN","RATE_LIMITED","INVALID_REQUEST","NETWORK","BAD_RESPONSE","BAD_GRANT","HEARTBEAT_FAILED","NATIVE_ERROR","MICROPHONE_DENIED","VOICE_CONNECT_FAILED","VOICE_CONTROL_FAILED","VOICE_STOP_FAILED","VOICE_EXPIRED","LEASE_EXPIRED","BACKGROUND","LEFT","DISCONNECTED","REPLACED","AUDIO_INTERRUPTED","TRANSPORT_FAILED","DESTROYED","QA_NOT_READY","QA_CODE_INVALID","QA_SCOPE_REJECTED","QA_STOPPED"]
	return code if code in CODES else "REQUEST_FAILED"
