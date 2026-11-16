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
## P0 rooms (join_with, 2026-11-02): this phone's LiveKit identity (the hub's peer id) and the peers this player blocks
## (the grant's `blocked`, then set_blocked from the hub's voice_blocks; SGODOT-384: only one's own blocks are sent, the
## blocked are never told); never a player id (亚瑟 on the voice plan).
var peer_self := ""
var blocked: Array = []
var _muted := {}   # identity → true: this phone's own Mute, set again after each connect
var _backend: Object
var _session: FarmSession
## How the grant is asked for: func(action: String, body: Dictionary) -> {ok: bool, json: Dictionary}, awaited; action is
## join / heartbeat / leave. join() makes Journey's from its FarmSession; join_with() takes the caller's (P0's).
var _request := Callable()
var _p0 := false
## Refusals a retry cannot mend: the session ends with the code (Journey's, and P0's voice/join — 后裔 on #645: voice off,
## not in a room, a room without voice such as Market Square, the voice room full, the age gate, no player key).
const FINAL_CODES := ["UNAUTHENTICATED", "VOICE_NO_PARTY", "VOICE_FULL", "MICROPHONE_DENIED",
	"VOICE_OFF", "NOT_IN_ROOM", "VOICE_NOT_HERE", "VOICE_ROOM_FULL", "AGE_GATE", "VOICE_BANNED"]
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
	elif OS.get_name() == "iOS": set_backend(VoiceBackendIOS.new())   # the native VoiceBridge over loopback UDP (SGODOT-387)

func set_backend(value: Object) -> void:
	if _backend and _backend.has_signal("voice_event") and _backend.is_connected("voice_event", _on_native_event):
		_backend.disconnect("voice_event", _on_native_event)
	_backend = value
	if _backend: _backend.connect("voice_event", _on_native_event)

## What the native side says it can do ({} for a test adapter without `capabilities`). The Android plugin is a
## JNISingleton, whose methods has_method never sees: only a scripted adapter is asked has_method; the singleton is asked
## capabilities() outright (SGODOT-384: per_participant and publish_permissions read false on phones, so Mute and Block
## never reached LiveKit — 李元芳 on 384 f25aa80d).
func _caps() -> Dictionary:
	if _backend == null or _adapter_without("capabilities"): return {}
	var caps = JSON.parse_string(str(_backend.call("capabilities")))
	return caps if caps is Dictionary else {}

## A scripted test adapter that lacks this method (a native singleton has every method its plugin registers).
func _adapter_without(method: String) -> bool:
	return _backend.get_script() != null and not _backend.has_method(method)

func supported() -> bool:
	if _backend == null: return false
	if _adapter_without("capabilities"): return true # Test adapters.
	var caps := _caps()
	return bool(caps.get("supported", false)) and int(caps.get("protocol", 0)) == 1

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
	var client := value.client
	_start(func(action: String, body: Dictionary) -> Dictionary:
		var r := await client.request("POST", "/online/voice/" + action, body)
		return {"ok": r.is_success(), "json": r.json}, false)

## P0's rooms and ponds (2026-11-02): the same session, its grant asked for by `request` (see _request) — the P0
## server's /v1/p0/voice/* for the room the player is in, granting `self` and `blocked` instead of a party.
func join_with(request: Callable) -> void:
	if _wanted: return
	error = ""
	if not supported():
		error = "VOICE_UNSUPPORTED"
		changed.emit()
		return
	_start(request, true)

func _start(request: Callable, p0: bool) -> void:
	_request = request
	_p0 = p0
	_generation += 1
	_joining = false
	_polling = false
	_request_id = _id()
	_native_id = _id()
	_wanted = true
	state = "permission"
	changed.emit()
	_backend.call("request_permission", _native_id)

func leave() -> void:
	_generation += 1
	_joining = false
	_polling = false
	_wanted = false
	_desired_microphone = false
	_desired_listening = true
	var lease := _lease_id
	var request := _request
	_drop_native()
	_lease_id = ""
	_room = ""
	party_id = ""
	peer_self = ""
	blocked = []
	_muted = {}
	participants = []
	microphone = false
	listening = true
	state = "idle"
	changed.emit()
	if not lease.is_empty() and request.is_valid(): _release(request, lease)

func _release(request: Callable, lease: String) -> void:
	await request.call("leave", {"lease_id": lease})

func invalidate_membership() -> void:
	if not _wanted: return
	_generation += 1
	_joining = false
	_polling = false
	# Stop receiving from a retired room before requesting a fresh grant.
	_drop_native()
	state = "reconnecting"
	_heartbeat_at = 0
	changed.emit()

## Before the room is up the wish is kept and taken at connect (P0's mic key joins with the mic on — it was dropped, and a
## first tap joined muted; 383 6372bffe); an idle session takes none.
func set_microphone(enabled: bool) -> void:
	if not _wanted: return
	_desired_microphone = enabled
	if state != "connected" or _native_id.is_empty(): return
	_backend.call("set_microphone", _native_id, enabled)

func set_listening(enabled: bool) -> void:
	if state != "connected" or _native_id.is_empty(): return
	_desired_listening = enabled
	_backend.call("set_listening", _native_id, enabled)

## Whether the native side can mute or block one person (GodotVoice capabilities `per_participant`, 2026-11-02).
func per_participant() -> bool:
	if _backend == null: return false
	if _adapter_without("capabilities"): return _backend.has_method("set_participant_volume")   # test adapters
	return bool(_caps().get("per_participant", false))

## Mute (P0): one person silent on this phone only, by identity; kept across a reconnect of this session.
func set_muted(identity: String, muted: bool) -> void:
	if identity.is_empty(): return
	if muted: _muted[identity] = true
	else: _muted.erase(identity)
	if _native_up() and per_participant():
		_backend.call("set_participant_volume", _native_id, identity, 0.0 if muted else 1.0)
	changed.emit()

func is_muted(identity: String) -> bool: return _muted.has(identity)

## Whether the native side can keep this phone's tracks from one person (capabilities `publish_permissions`, SGODOT-384).
func publish_permissions() -> bool:
	if _backend == null: return false
	if _adapter_without("capabilities"): return _backend.has_method("set_publish_allowed")   # test adapters
	return bool(_caps().get("publish_permissions", false))

## Block (P0): the peers this player blocks (the grant, then the hub's voice_blocks). Both ways, from this phone alone
## (SGODOT-384, 周瑜 on #647): none of their tracks are taken, and LiveKit refuses them this phone's (subscription
## permissions — a changed client cannot take them either); one no longer listed is allowed and taken again.
func set_blocked(ids: Array) -> void:
	var next: Array = ids.map(func(i): return str(i))
	var freed: Array = blocked.filter(func(i): return not next.has(i))
	blocked = next
	if _native_up():   # connecting too: the plugin takes the room's tracks at Connected by this list (周瑜 on #661)
		_block_natively(freed, true)
		_block_natively(blocked, false)
	changed.emit()

## A native room asked for (connecting, connected or reconnecting), not the permission request's id.
func _native_up() -> bool: return state != "permission" and not _native_id.is_empty()

func _block_natively(ids: Array, allow: bool) -> void:
	for id in ids:
		if per_participant(): _backend.call("set_participant_subscribed", _native_id, str(id), allow)
		if publish_permissions(): _backend.call("set_publish_allowed", _native_id, str(id), allow)

## After a connect: this session's mutes and blocks onto the fresh native room.
func _apply_people() -> void:
	_block_natively(blocked, false)
	if not per_participant(): return
	for id in _muted: _backend.call("set_participant_volume", _native_id, str(id), 0.0)

func _process(_delta: float) -> void:
	# scripted backends only — test adapters and the iOS bridge (VoiceBackendIOS reads its UDP here): has_method never
	# sees a JNISingleton's methods, and the Android plugin pushes its events (周瑜 on #650)
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
	if _joining or not _request.is_valid(): return
	_joining = true
	var generation := _generation
	var request := _request
	var started := Time.get_ticks_msec()
	_heartbeat_at = started + 3000   # pace another attempt even if this completion becomes obsolete
	var result: Dictionary = await request.call("join", {"request_id": _request_id})
	var json: Dictionary = result.get("json", {}) if result.get("json") is Dictionary else {}
	if generation != _generation or not _wanted or not _foreground:
		if bool(result.get("ok", false)) and json.has("lease_id"): _release(request, str(json.lease_id))
		return
	_joining = false
	if bool(result.get("stale", false)):
		if bool(result.get("ok", false)) and json.has("lease_id"): _release(request, str(json.lease_id))
		return
	if not bool(result.get("ok", false)):
		_failed(str(json.get("code", "VOICE_UNAVAILABLE")))
		return
	var grant: Dictionary = json
	if not _valid_grant(grant, _p0):
		_failed("VOICE_UNAVAILABLE")
		return
	_lease_id = str(grant.lease_id)
	_room = str(grant.room)
	party_id = str(grant.get("party_id", ""))
	capacity = int(grant.capacity)
	if _p0:
		peer_self = str(grant.self)
		blocked = (grant.get("blocked", []) as Array).map(func(i): return str(i)) if grant.get("blocked") is Array else []
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
	# the blocks before LiveKit is in the room: it takes no one's tracks by itself, so none of the blocked one's go
	# through first (SGODOT-384, 384 046f7b43); again at connected
	_apply_people()
	_backend.call("renew_lease", _native_id, maxi(0, _lease_deadline - Time.get_ticks_msec()))
	changed.emit()

func _heartbeat() -> void:
	_polling = true
	var generation := _generation
	var lease := _lease_id
	var started := Time.get_ticks_msec()
	_heartbeat_at = started + 4500   # an obsolete reply must not cause an every-frame retry or extend the lease
	var result: Dictionary = await _request.call("heartbeat", {"lease_id": lease})
	if generation != _generation or not _wanted: return
	_polling = false
	if bool(result.get("stale", false)): return
	var json: Dictionary = result.get("json", {}) if result.get("json") is Dictionary else {}
	var ok := bool(result.get("ok", false))
	_heartbeat_at = Time.get_ticks_msec() + (4500 if ok else 1500)
	if not ok:
		var code := str(json.get("code", "VOICE_UNAVAILABLE"))
		if code in FINAL_CODES:
			_failed(code)
		elif code in ["VOICE_EXPIRED", "LEASE_EXPIRED"]:   # P0's lease gone: join again, as Journey's
			_drop_native()
			state = "reconnecting"
			changed.emit()
		return
	if str(json.get("room", "")) != _room:
		invalidate_membership()
		return
	_lease_deadline = started + mini(20000, int(json.get("lease_ms", 0))) - 500
	if not _native_id.is_empty(): _backend.call("renew_lease", _native_id, maxi(0, _lease_deadline - Time.get_ticks_msec()))

func _failed(code: String) -> void:
	error = code
	if code in FINAL_CODES:
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
				# blocks and mutes before the mic goes out: no one blocked takes a track that is published first (SGODOT-384)
				_apply_people()
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

## Journey's party grant, or (p0) a P0 room's: `self` (the hub's peer id) instead of party_id, a room of up to 64
## (p0_outposts.json's capacities run to 40; a pond's 8) and `blocked` a list when there.
static func _valid_grant(grant: Dictionary, p0 := false) -> bool:
	for field in ["url", "token", "lease_id", "room"] + ([] if p0 else ["party_id"]):
		if not grant.get(field) is String or str(grant[field]).is_empty(): return false
	if p0 and (grant.get("self") == null or str(grant.self).is_empty()): return false
	if p0 and grant.has("blocked") and not grant.blocked is Array: return false
	var most := 65 if p0 else 9
	return (str(grant.url).begins_with("wss://") or str(grant.url).begins_with("ws://")) and int(grant.get("capacity", 0)) in range(2, most) and int(grant.get("lease_ms", 0)) in range(1000, 20001)

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
