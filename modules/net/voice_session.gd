class_name PartyVoiceSession
extends Node
## One user-controlled voice session across world scenes. Credentials stay in memory.

signal changed

var state := "idle"
var error := ""
var microphone := false
var listening := true
var participants: Array = []
var capacity := 8
var party_id := ""
var _backend: Object
var _session: FarmSession
var _wanted := false
var _request_id := ""
var _native_id := ""
var _lease_id := ""
var _room := ""
var _generation := 0
var _joining := false
var _polling := false
var _heartbeat_at := 0
var _lease_deadline := 0
var _foreground := true
var _desired_microphone := false
var _desired_listening := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton("GodotVoice"): set_backend(Engine.get_singleton("GodotVoice"))

func set_backend(value: Object) -> void:
	if _backend and _backend.has_signal("voice_event") and _backend.is_connected("voice_event", _on_native_event):
		_backend.disconnect("voice_event", _on_native_event)
	_backend = value
	if _backend: _backend.connect("voice_event", _on_native_event)

func supported() -> bool:
	if _backend == null: return false
	if not _backend.has_method("capabilities"): return true # Test adapters.
	var caps = JSON.parse_string(str(_backend.call("capabilities")))
	return caps is Dictionary and caps.get("supported", false) and int(caps.get("protocol", 0)) == 1

func active() -> bool:
	return _wanted

func join(value: FarmSession) -> void:
	if _wanted: return
	error = ""
	if not supported():
		error = "VOICE_UNSUPPORTED"
		changed.emit()
		return
	if value == null or value.client == null or value.client.token.is_empty():
		error = "UNAUTHENTICATED"
		changed.emit()
		return
	_session = value
	_generation += 1
	_request_id = _id()
	_native_id = _id()
	_wanted = true
	state = "permission"
	changed.emit()
	_backend.call("request_permission", _native_id)

func leave() -> void:
	_generation += 1
	_wanted = false
	_desired_microphone = false
	_desired_listening = true
	var lease := _lease_id
	var client: ApiClient = _session.client if _session else null
	_drop_native()
	_lease_id = ""
	_room = ""
	party_id = ""
	participants = []
	microphone = false
	listening = true
	state = "idle"
	changed.emit()
	if not lease.is_empty() and client: _release(client, lease)

func _release(client: ApiClient, lease: String) -> void:
	await client.request("POST", "/online/voice/leave", {"lease_id": lease})

func invalidate_membership() -> void:
	if not _wanted: return
	_generation += 1
	# Stop receiving from a retired room before requesting a fresh grant.
	_drop_native()
	state = "reconnecting"
	_heartbeat_at = 0
	changed.emit()

func set_microphone(enabled: bool) -> void:
	if state != "connected" or _native_id.is_empty(): return
	_desired_microphone = enabled
	_backend.call("set_microphone", _native_id, enabled)

func set_listening(enabled: bool) -> void:
	if state != "connected" or _native_id.is_empty(): return
	_desired_listening = enabled
	_backend.call("set_listening", _native_id, enabled)

func _process(_delta: float) -> void:
	if _backend and _backend.has_method("poll_events"): _backend.call("poll_events")
	if not _wanted or not _foreground or state == "permission": return
	var now := Time.get_ticks_msec()
	if not _native_id.is_empty() and now >= _lease_deadline:
		_drop_native()
		state = "reconnecting"
		changed.emit()
	if _joining or _polling or now < _heartbeat_at: return
	if _native_id.is_empty(): _connect_voice()
	else: _heartbeat()

func _connect_voice() -> void:
	if _joining or _session == null: return
	_joining = true
	var generation := _generation
	var client := _session.client
	var started := Time.get_ticks_msec()
	var result := await client.request("POST", "/online/voice/join", {"request_id": _request_id})
	_joining = false
	if generation != _generation or not _wanted or not _foreground:
		if result.is_success() and result.json.has("lease_id"): _release(client, str(result.json.lease_id))
		return
	if not result.is_success():
		_failed(str(result.json.get("code", "VOICE_UNAVAILABLE")))
		return
	var grant: Dictionary = result.json
	if not _valid_grant(grant):
		_failed("VOICE_UNAVAILABLE")
		return
	_lease_id = str(grant.lease_id)
	_room = str(grant.room)
	party_id = str(grant.party_id)
	capacity = int(grant.capacity)
	_lease_deadline = started + mini(20000, int(grant.lease_ms)) - 500
	if _lease_deadline <= Time.get_ticks_msec():
		_heartbeat_at = Time.get_ticks_msec() + 500
		return
	_native_id = _id()
	microphone = false
	listening = true
	state = "connecting"
	error = ""
	_heartbeat_at = Time.get_ticks_msec() + 4500
	_backend.call("connect_voice", _native_id, str(grant.url), str(grant.token))
	_backend.call("renew_lease", _native_id, maxi(0, _lease_deadline - Time.get_ticks_msec()))
	changed.emit()

func _heartbeat() -> void:
	_polling = true
	var generation := _generation
	var lease := _lease_id
	var started := Time.get_ticks_msec()
	var result := await _session.client.request("POST", "/online/voice/heartbeat", {"lease_id": lease})
	_polling = false
	if generation != _generation or not _wanted: return
	_heartbeat_at = Time.get_ticks_msec() + (4500 if result.is_success() else 1500)
	if not result.is_success():
		var code := str(result.json.get("code", "VOICE_UNAVAILABLE"))
		if code in ["UNAUTHENTICATED", "VOICE_NO_PARTY"]:
			_failed(code)
		elif code == "VOICE_EXPIRED":
			_drop_native()
			state = "reconnecting"
			changed.emit()
		return
	if str(result.json.get("room", "")) != _room:
		invalidate_membership()
		return
	_lease_deadline = started + mini(20000, int(result.json.get("lease_ms", 0))) - 500
	if not _native_id.is_empty(): _backend.call("renew_lease", _native_id, maxi(0, _lease_deadline - Time.get_ticks_msec()))

func _failed(code: String) -> void:
	error = code
	if code in ["UNAUTHENTICATED", "VOICE_NO_PARTY", "VOICE_FULL", "MICROPHONE_DENIED"]:
		leave()
		error = code
		changed.emit()
	else:
		state = "reconnecting"
		_heartbeat_at = Time.get_ticks_msec() + 3000
		changed.emit()

func _on_native_event(raw: String) -> void:
	var event = JSON.parse_string(raw)
	if not event is Dictionary or str(event.get("session", "")) != _native_id: return
	match str(event.get("event", "")):
		"permission":
			if not _wanted: return
			if not bool(event.get("granted", false)):
				_failed("MICROPHONE_DENIED")
				return
			_native_id = ""
			state = "connecting"
			_heartbeat_at = 0
			if _foreground: _connect_voice()
		"connected", "participants", "microphone", "listening":
			if not _wanted: return
			if event.event == "connected":
				state = "connected"
				_backend.call("set_microphone", _native_id, _desired_microphone)
				_backend.call("set_listening", _native_id, _desired_listening)
			microphone = bool(event.get("microphone", false))
			listening = bool(event.get("listening", true))
			participants = event.get("participants", []) if event.get("participants") is Array else []
		"reconnecting": state = "reconnecting"
		"disconnected":
			_native_id = ""
			microphone = false
			participants = []
			if str(event.get("reason", "")) in ["BACKGROUND", "LEFT"]:
				leave()
			else:
				state = "reconnecting"
				_heartbeat_at = Time.get_ticks_msec() + 1000
		"error": error = str(event.get("code", "VOICE_UNAVAILABLE"))
	changed.emit()

func _drop_native() -> void:
	var id := _native_id
	_native_id = ""
	microphone = false
	participants = []
	if _backend and not id.is_empty(): _backend.call("disconnect_voice", id)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_foreground = false
		if state != "permission" and _wanted: leave()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_foreground = true
	elif what == NOTIFICATION_WM_CLOSE_REQUEST and _wanted:
		leave()

func _exit_tree() -> void:
	_drop_native()

static func _id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func _valid_grant(grant: Dictionary) -> bool:
	for field in ["url", "token", "lease_id", "room", "party_id"]:
		if not grant.get(field) is String or str(grant[field]).is_empty(): return false
	return (str(grant.url).begins_with("wss://") or str(grant.url).begins_with("ws://")) and int(grant.get("capacity", 0)) in range(2, 9) and int(grant.get("lease_ms", 0)) in range(1000, 20001)

func status_text() -> String:
	if not error.is_empty(): return error_text(error)
	match state:
		"permission": return L10n.text("Allow microphone access to join voice")
		"connecting", "reconnecting": return L10n.text("Connecting to party voice...")
		"connected": return L10n.format_text("Party voice · %d / %d", [participants.size(), capacity])
	return L10n.text("Party voice · microphone starts muted")

static func error_text(code: String) -> String:
	var messages := {"VOICE_UNSUPPORTED": "Party voice is not supported on this device yet",
		"VOICE_BUSY": "Voice service is busy. Retrying...",
		"VOICE_NO_PARTY": "Join a party before using voice", "VOICE_FULL": "Party voice is full (8 people)",
		"MICROPHONE_DENIED": "Microphone access was denied. You can enable it in Settings.",
		"MICROPHONE_FAILED": "Could not enable the microphone", "VOICE_EXPIRED": "Voice session expired. Join again.",
		"UNAUTHENTICATED": "Reconnect your game account to use voice"}
	return L10n.text(str(messages.get(code, "Party voice is unavailable. Try again.")))
