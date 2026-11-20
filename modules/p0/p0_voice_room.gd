class_name P0VoiceRoom
extends Node
## Voice in a P0 online room (SGODOT-383; the user, 11-02 via 奕星, q(274)): the outpost's or pond's room is the voice
## room — everyone in it hears everyone else. This node is the glue between the room (P0Online), the P0 server's
## /v1/p0/voice/* and the Voice autoload (PartyVoiceSession.join_with); the HUD's mic key and the people drawer
## (哪吒, 不知火舞's spec) read and call it. The mic starts off, a tap turns it on and another off; nothing is asked
## of the server before the player first wants voice.
##
## Per person (the least against harassment the user set): Mute is this phone's own, kept by the person's public handle
## (the roster's `player`, never their id: it outlives their peer id across layers); Block goes to the server, which
## tells the blocker alone their `blocked` peer ids (the grant, the hub's voice_blocks): their phone shuts it both ways,
## LiveKit keeping their tracks from the blocked one, who is never told (SGODOT-384); Report is one line on the server.
## The 13+ gate: the server keeps a yes / no; until it has a yes there is no voice (`age` "unknown": ask first).

signal changed
signal age_needed
signal notice(text: String, failed: bool)

const P0Names := preload("res://modules/p0/p0_names.gd")   # a member's name (SGODOT-491)
const MUTES := "user://p0_voice_mutes.json"
const Ban := preload("res://modules/p0/p0_voice_ban.gd")
const STATUS_RETRY_MS := 5000
var ban := Ban.new()
var now_ms := func() -> int: return int(Time.get_unix_time_from_system() * 1000.0)
var _identity_context: Array = []
var _status_epoch := 0
var _status_busy := false
var _next_status := 0
var _expiry_checked := false
var _toggling := false
var _ban_sequence := 0
var _ban_applied := 0

var session: P0Session
var online: P0Online
var available := false   # the server has voice (P0_VOICE) and this phone can do it (Voice.supported())
var age := "unknown"     # "ok" / "no" / "unknown", the server's
var here := true         # this room has voice: every outpost room and pond, Market Square too since q(286) (SGODOT-415);
                         # not Grace Cathedral (奕星 11-06; 后裔's #800 NO_VOICE_ROLES)
var voice: Node          # the Voice autoload (tests give their own)
## Tests replace the HTTP call: request.call(method, path, body) -> {ok, json}, awaited.
var request := Callable()
var _mutes: Array = []   # public handles muted on this phone
var _room := -1

## `role`: the room's (P0Outpost.role); a role in NO_VOICE_ROLES has no mic key and no count (the server's VOICE_NOT_HERE).
const NO_VOICE_ROLES := ["church"]
func setup(p_session: P0Session, p_online: P0Online, role: String) -> void:
	session = p_session
	online = p_online
	here = not role in NO_VOICE_ROLES
	if voice == null: voice = get_node_or_null("/root/Voice")
	_mutes = _load_mutes()
	_room = online.room if online.epoch > 0 else -1   # joined already (the HUD comes after the room's first join)
	online.joined.connect(_on_room)
	# someone in or out: their mute put back, and the HUD's count and an open drawer read the room again (李元芳 on 415, 232
	# f8ecefed: the first in kept 0 while the drawer showed the second)
	online.roster_changed.connect(func():
		_apply_mutes()
		changed.emit())
	online.voice_blocks.connect(func(ids: Array): if voice: voice.call("set_blocked", ids))
	if voice and voice.has_signal("changed"): voice.connect("changed", func(): changed.emit())
	if session != null and not session.login_context_changed.is_connected(_identity_changed):
		session.login_context_changed.connect(_identity_changed)
	_sync_identity()

func _sync_identity() -> bool:
	var context := session.request_context() if is_instance_valid(session) else []
	if context == _identity_context: return false
	_identity_context = context
	_status_epoch += 1
	_status_busy = false
	_next_status = 0
	_expiry_checked = false
	_toggling = false
	_ban_sequence = 0
	_ban_applied = 0
	ban.reset()
	available = false
	age = "unknown"
	leave()
	changed.emit()
	return true

func _identity_changed() -> void:
	if _sync_identity() and is_instance_valid(session) and session.identity_ready and here and is_inside_tree(): fetch_status.call_deferred()

func _process(_dt: float) -> void:
	_sync_identity()
	if ban.expired(int(now_ms.call())) and not _expiry_checked and not _status_busy and Time.get_ticks_msec() >= _next_status:
		_expiry_checked = true  # one scheduled check; errors do not make an every-frame retry loop
		ban.stale = true
		fetch_status()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_instance_valid(session) and session.identity_ready and here:
		fetch_status(false)

func mic_blocked() -> bool:
	return ban.blocked or ban.kind == Ban.UNKNOWN or (ban.stale and ban.kind == Ban.CLEAR)

func ban_message() -> String: return ban.message(int(now_ms.call()))

## Whether to show the mic key at all: the server's voice on, a phone that can, a room that has it, and no 13+ no.
func offered() -> bool:
	return available and here and age != "no" and voice != null and bool(voice.call("supported"))

## The server's word on voice and the 13+ gate (GET /v1/p0/voice/status); the HUD asks once a room is joined.
func fetch_status(force := true) -> bool:
	_sync_identity()
	if not force and (_status_busy or Time.get_ticks_msec() < _next_status): return false
	_status_epoch += 1
	var epoch := _status_epoch
	_status_busy = true
	_next_status = Time.get_ticks_msec() + STATUS_RETRY_MS
	var r: Dictionary = await _call(HTTPClient.METHOD_GET, "status", {}, epoch)
	if epoch != _status_epoch: return false   # only the current status request owns this busy flag
	_status_busy = false
	if bool(r.get("stale", false)): return false
	var json: Dictionary = r.get("json", {}) if r.get("json") is Dictionary else {}
	if not bool(r.get("ok", false)):
		ban.stale = true
		changed.emit()
		return false
	if not json.get("available") is bool or not json.get("age") in ["ok", "no", "unknown"]:
		ban.stale = true
		changed.emit()
		return false
	available = bool(json.get("available", false))
	age = str(json.get("age", "unknown"))
	var known := false
	if json.has("ban"): known = ban.take(json.ban)
	else: ban.stale = true
	if known:
		_expiry_checked = ban.expired(int(now_ms.call()))
		if ban.blocked: leave()
	changed.emit()
	return known

## The mic key: the first tap joins the room's voice with the mic on (the 13+ gate first when not answered); after that
## it only turns the mic on and off. The voice is left with the place (_exit_tree) or the app going to the background.
func toggle_mic() -> void:
	_sync_identity()
	if not offered() or voice == null: return
	# A failed status refresh must never trap a player with their microphone on.
	if bool(voice.call("active")) and bool(voice.get("microphone")):
		voice.call("set_microphone", false)
		return
	if _toggling: return
	_toggling = true
	var context := _identity_context.duplicate()
	if Time.get_ticks_msec() >= _next_status:
		await fetch_status(false)
	if context != _identity_context:
		return
	_toggling = false
	if mic_blocked():
		var message := ban_message()
		notice.emit(message if message != "" else "Didn't go through · try again", message == "")
		return
	if bool(voice.call("active")):
		voice.call("set_microphone", not bool(voice.get("microphone")))
		return
	if age == "unknown":
		age_needed.emit()
		return
	voice.call("join_with", func(action: String, body: Dictionary) -> Dictionary:
		if not context.is_empty() and (not is_instance_valid(session) or not session.request_is_current(context)):
			return {"ok": false, "stale": true, "json": {}}
		return await _call(HTTPClient.METHOD_POST, action, body))
	voice.call("set_microphone", true)

## The 13+ gate's answer (a birth year picked on the HUD's card; only yes / no goes out). A no hides voice for good.
func answer_age(ok: bool) -> void:
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "age", {"ok": ok})
	if bool(r.get("stale", false)): return
	var json: Dictionary = r.get("json", {}) if r.get("json") is Dictionary else {}
	age = str(json.get("age", "no" if not ok else age))
	changed.emit()
	if age == "ok": toggle_mic()

func leave() -> void:
	if voice and bool(voice.call("active")): voice.call("leave")

## The people drawer's rows: the player first (q(289), SGODOT-415: `self` true; their own speaking from the voice's local
## participant), then everyone else in the room, with their voice state. {peer, handle, name, speaking, muted, blocked,
## self}; `name` as their name tag writes it. The HUD's count is all of them, the player too.
func people() -> Array:
	var speaking := {}
	var me_speaking := false
	if voice:
		for p in voice.get("participants"):
			if not (p is Dictionary and bool(p.get("speaking", false))): continue
			speaking[str(p.get("id", ""))] = true
			if bool(p.get("local", false)): me_speaking = true
	var blocked: Array = voice.get("blocked") if voice else []
	var out := []
	if online.members.has(online.self_id):
		var mine := str(online.members[online.self_id].get("player", ""))
		out.append({"peer": online.self_id, "handle": mine, "name": P0Names.of(online.members[online.self_id]), "self": true,
			"speaking": me_speaking or speaking.has(str(online.self_id)), "muted": false, "blocked": false})
	for id in online.members:
		if int(id) == online.self_id: continue
		var handle := str(online.members[id].get("player", ""))
		out.append({"peer": int(id), "handle": handle, "name": P0Names.of(online.members[id]), "speaking": speaking.has(str(id)),
			"muted": _mutes.has(handle), "blocked": blocked.has(str(id)), "self": false})
	return out

## Mute: one person silent on this phone, kept across layers and launches by their handle.
func set_muted(peer: int, muted: bool) -> void:
	var handle := str(online.members.get(peer, {}).get("player", ""))
	if handle == "": return
	if muted and not _mutes.has(handle): _mutes.append(handle)
	elif not muted: _mutes.erase(handle)
	_save_mutes()
	if voice: voice.call("set_muted", str(peer), muted)
	changed.emit()

## Block / Unblock: the server keeps it and tells this phone alone (voice_blocks); this phone shuts it both ways (384).
func set_blocked(peer: int, on: bool) -> void:
	await _call(HTTPClient.METHOD_POST, "block", {"peer": peer, "on": on})

## The Blocked list (q(28) Settings › Blocked players): who this player blocks, as handles — the blocked are out of
## sight in a room from the Block on (the hub keeps the two from each other), so Unblock is from here, wherever they are.
## [{handle, name}] (name as a name tag writes it), [] when the server has none; null when it is not reached or says
## nothing readable — never [], which the page would show as `No one blocked` (奕星, 384's list before the switch).
func blocked_list() -> Variant:
	var r: Dictionary = await _call(HTTPClient.METHOD_GET, "blocks", {})
	var json: Dictionary = r.get("json", {}) if r.get("json") is Dictionary else {}
	if not bool(r.get("ok", false)) or not json.get("blocked") is Array: return null
	var rows: Array = json.blocked
	return rows.map(func(b): return {"handle": str(b.get("handle", "")), "name": P0Names.of(b)})   # the current name (后裔: blocks' `name`)

## Unblock from the Blocked list, by handle: true when the server took it (both come back into each other's sight).
func unblock(handle: String) -> bool:
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "unblock", {"handle": handle})
	changed.emit()
	return bool(r.get("ok", false))

## Report: a line on the server for a person to read later; the toast is the HUD's — "sent" (Report sent), "already"
## (You already reported this: the server keeps no second line) or "failed".
func report(peer: int, reason := "") -> String:
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "report", {"peer": peer, "reason": reason})
	if not bool(r.get("ok", false)): return "failed"
	var json: Dictionary = r.get("json", {}) if r.get("json") is Dictionary else {}
	return "already" if bool(json.get("already", false)) else "sent"

## A new layer (or a reconnect into one): a voice session on goes again for this room's grant.
func _on_room(info: Dictionary) -> void:
	var room := int(info.get("room", 0))
	var moved := _room != -1 and room != _room
	if _room != -1 and room != _room and voice and bool(voice.call("active")): voice.call("invalidate_membership")
	_room = room
	if moved and session != null and session.identity_ready and here: fetch_status(false)

## The mutes onto the peers of this layer (their peer ids change with the layer; their handles do not).
func _apply_mutes() -> void:
	if voice == null: return
	for id in online.members:
		if int(id) != online.self_id and _mutes.has(str(online.members[id].get("player", ""))): voice.call("set_muted", str(id), true)

func _call(method: int, action: String, body: Dictionary, status_epoch := -1) -> Dictionary:
	_sync_identity()
	var owner := session
	var context := _identity_context.duplicate()
	var ban_sequence := -1
	if action in ["status", "join", "heartbeat"]:
		_ban_sequence += 1
		ban_sequence = _ban_sequence
	var result: Dictionary
	if request.is_valid():
		result = await request.call(method, "/p0/voice/" + action, body)
	else:
		result = await _http_call(method, action, body)
	if owner != session or (not context.is_empty() and (not is_instance_valid(owner) or not owner.request_is_current(context))) \
		or (status_epoch >= 0 and status_epoch != _status_epoch):
		return {"ok": false, "stale": true, "json": {}}
	var json: Dictionary = result.get("json", {}) if result.get("json") is Dictionary else {}
	if ban_sequence >= 0 and ban_sequence < _ban_applied:
		# A stale completion is not a current authentication failure (nor permission to renew a lease).
		# Keep a returned grant only so Voice can release its unused lease, never adopt it.
		return result.merged({"stale": true}, true)
	if ban_sequence >= 0 and (bool(result.get("ok", false)) or str(json.get("code", "")) == "VOICE_BANNED"):
		_ban_applied = ban_sequence
	if owner != null and result.has("status") and owner.take_account_refusal(HTTPRequest.RESULT_SUCCESS,
			int(result.status), JSON.stringify(json).to_utf8_buffer(), context):
		return {"ok": false, "json": {"code": "UNAUTHENTICATED"}}
	if not bool(result.get("ok", false)) and str(json.get("code", "")) == "VOICE_BANNED":
		_status_epoch += 1   # a late older status ban:null cannot erase this new refusal
		_status_busy = false
		_expiry_checked = false
		var known := false
		if json.has("until"): known = ban.take({"until": json.until})
		else: ban.stale = true
		ban.blocked = true
		changed.emit()
		if not known and action in ["join", "heartbeat"]:
			if is_inside_tree(): fetch_status.call_deferred()   # one refresh after terminal refusal, not a status retry loop
		if action == "join":
			var message := ban_message()
			notice.emit(message if message != "" else "Didn't go through · try again", message == "")
	return result

func _http_call(method: int, action: String, body: Dictionary) -> Dictionary:
	if not is_instance_valid(session): return {"ok": false, "json": {}}
	var http := P0HttpRequest.new()
	add_child(http)
	var err := http.send(session.base_url + "/p0/voice/" + action, session._headers(), method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"ok": false, "json": {"code": "VOICE_UNAVAILABLE"}}
	var done: Array = await http.request_completed
	http.queue_free()
	var json = JSON.parse_string((done[3] as PackedByteArray).get_string_from_utf8()) if done[0] == HTTPRequest.RESULT_SUCCESS else null
	return {"ok": done[0] == HTTPRequest.RESULT_SUCCESS and int(done[1]) >= 200 and int(done[1]) < 300,
		"status": int(done[1]) if done[0] == HTTPRequest.RESULT_SUCCESS else 0, "json": json if json is Dictionary else {}}

func _load_mutes() -> Array:
	if not FileAccess.file_exists(MUTES): return []
	var v = JSON.parse_string(FileAccess.get_file_as_string(MUTES))
	return (v as Array).map(func(h): return str(h)) if v is Array else []

func _save_mutes() -> void:
	var f := FileAccess.open(MUTES, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(_mutes))

func _exit_tree() -> void:
	leave()
