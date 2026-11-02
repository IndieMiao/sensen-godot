class_name P0VoiceRoom
extends Node
## Voice in a P0 online room (SGODOT-383; the user, 11-02 via 奕星, q(274)): the outpost's or pond's room is the voice
## room — everyone in it hears everyone else. This node is the glue between the room (P0Online), the P0 server's
## /v1/p0/voice/* and the Voice autoload (PartyVoiceSession.join_with); the HUD's mic key and the people drawer
## (哪吒, 不知火舞's spec) read and call it. The mic starts off, a tap turns it on and another off; nothing is asked
## of the server before the player first wants voice.
##
## Per person (the least against harassment the user set): Mute is this phone's own, kept by the person's public handle
## (the roster's `player`, never their id: it outlives their peer id across layers); Block goes to the server, both ways,
## and comes back as `blocked` peer ids (the grant, the hub's voice_blocks); Report is one line on the server.
## The 13+ gate: the server keeps a yes / no; until it has a yes there is no voice (`age` "unknown": ask first).

signal changed
signal age_needed

const MUTES := "user://p0_voice_mutes.json"

var session: P0Session
var online: P0Online
var available := false   # the server has voice (P0_VOICE) and this phone can do it (Voice.supported())
var age := "unknown"     # "ok" / "no" / "unknown", the server's
var here := true         # this room has voice (not Market Square: the user, 11-02)
var voice: Node          # the Voice autoload (tests give their own)
## Tests replace the HTTP call: request.call(method, path, body) -> {ok, json}, awaited.
var request := Callable()
var _mutes: Array = []   # public handles muted on this phone
var _room := -1

func setup(p_session: P0Session, p_online: P0Online, role: String) -> void:
	session = p_session
	online = p_online
	here = role != "market"
	if voice == null: voice = get_node_or_null("/root/Voice")
	_mutes = _load_mutes()
	_room = online.room if online.epoch > 0 else -1   # joined already (the HUD comes after the room's first join)
	online.joined.connect(_on_room)
	online.roster_changed.connect(_apply_mutes)
	online.voice_blocks.connect(func(ids: Array): if voice: voice.call("set_blocked", ids))
	if voice and voice.has_signal("changed"): voice.connect("changed", func(): changed.emit())

## Whether to show the mic key at all: the server's voice on, a phone that can, a room that has it, and no 13+ no.
func offered() -> bool:
	return available and here and age != "no" and voice != null and bool(voice.call("supported"))

## The server's word on voice and the 13+ gate (GET /v1/p0/voice/status); the HUD asks once a room is joined.
func fetch_status() -> void:
	var r: Dictionary = await _call(HTTPClient.METHOD_GET, "status", {})
	var json: Dictionary = r.get("json", {}) if r.get("json") is Dictionary else {}
	available = bool(r.get("ok", false)) and bool(json.get("available", false))
	age = str(json.get("age", "unknown"))
	changed.emit()

## The mic key: on joins the room's voice (the 13+ gate first when not answered), off leaves it.
func toggle_mic() -> void:
	if not offered() or voice == null: return
	if bool(voice.call("active")):
		voice.call("set_microphone", not bool(voice.get("microphone")))
		return
	if age == "unknown":
		age_needed.emit()
		return
	voice.call("join_with", func(action: String, body: Dictionary) -> Dictionary: return await _call(HTTPClient.METHOD_POST, action, body))
	voice.call("set_microphone", true)

## The 13+ gate's answer (a birth year picked on the HUD's card; only yes / no goes out). A no hides voice for good.
func answer_age(ok: bool) -> void:
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "age", {"ok": ok})
	var json: Dictionary = r.get("json", {}) if r.get("json") is Dictionary else {}
	age = str(json.get("age", "no" if not ok else age))
	changed.emit()
	if age == "ok": toggle_mic()

func leave() -> void:
	if voice and bool(voice.call("active")): voice.call("leave")

## The people drawer's rows: everyone else in the room, with their voice state. {peer, handle, name, speaking, muted,
## blocked}; `name` as their name tag writes it.
func people() -> Array:
	var speaking := {}
	if voice:
		for p in voice.get("participants"): if p is Dictionary and bool(p.get("speaking", false)): speaking[str(p.get("id", ""))] = true
	var blocked: Array = voice.get("blocked") if voice else []
	var out := []
	for id in online.members:
		if int(id) == online.self_id: continue
		var handle := str(online.members[id].get("player", ""))
		out.append({"peer": int(id), "handle": handle, "name": "Traveller %s" % handle.substr(0, 4), "speaking": speaking.has(str(id)),
			"muted": _mutes.has(handle), "blocked": blocked.has(str(id))})
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

## Block / Unblock: the server keeps it both ways and tells both phones (voice_blocks).
func set_blocked(peer: int, on: bool) -> void:
	await _call(HTTPClient.METHOD_POST, "block", {"peer": peer, "on": on})

## Report: a line on the server for a person to read later; the toast is the HUD's.
func report(peer: int, reason := "") -> bool:
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "report", {"peer": peer, "reason": reason})
	return bool(r.get("ok", false))

## A new layer (or a reconnect into one): a voice session on goes again for this room's grant.
func _on_room(info: Dictionary) -> void:
	var room := int(info.get("room", 0))
	if _room != -1 and room != _room and voice and bool(voice.call("active")): voice.call("invalidate_membership")
	_room = room

## The mutes onto the peers of this layer (their peer ids change with the layer; their handles do not).
func _apply_mutes() -> void:
	if voice == null: return
	for id in online.members:
		if int(id) != online.self_id and _mutes.has(str(online.members[id].get("player", ""))): voice.call("set_muted", str(id), true)

func _call(method: int, action: String, body: Dictionary) -> Dictionary:
	if request.is_valid(): return await request.call(method, "/p0/voice/" + action, body)
	if session == null: return {"ok": false, "json": {}}
	var http := P0HttpRequest.new()
	add_child(http)
	var err := http.send(session.base_url + "/p0/voice/" + action, session._headers(), method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"ok": false, "json": {"code": "VOICE_UNAVAILABLE"}}
	var done: Array = await http.request_completed
	http.queue_free()
	var json = JSON.parse_string((done[3] as PackedByteArray).get_string_from_utf8()) if done[0] == HTTPRequest.RESULT_SUCCESS else null
	return {"ok": done[0] == HTTPRequest.RESULT_SUCCESS and int(done[1]) >= 200 and int(done[1]) < 300, "json": json if json is Dictionary else {}}

func _load_mutes() -> Array:
	if not FileAccess.file_exists(MUTES): return []
	var v = JSON.parse_string(FileAccess.get_file_as_string(MUTES))
	return (v as Array).map(func(h): return str(h)) if v is Array else []

func _save_mutes() -> void:
	var f := FileAccess.open(MUTES, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(_mutes))

func _exit_tree() -> void:
	leave()
