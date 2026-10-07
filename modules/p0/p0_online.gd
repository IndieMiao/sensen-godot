class_name P0Online
extends Node
## Outpost room connection (SGODOT-227): one WebSocket to the P0 server's /v1/p0/online. The server
## picks the room (Room 1, Room 2 …); this node sends our position at 10 Hz, keeps the roster and
## feeds other players' snapshot frames (frame v1, the realtime Room's format) to an OnlineCrowd.
## Our own position is never corrected from the server (client-authoritative, like the private farm).

signal joined(info: Dictionary)          # {outpost, room, capacity, rejoined, self, epoch}
signal seat_changed(id: int, seat: String)
signal result(seq: int, ok: bool, code: String)
signal failed(code: String)
signal connection_changed(connected: bool)

const PROTOCOL := 1
const SEND_S := 0.1
const PING_S := 10.0
const RETRY_S: Array[float] = [1.0, 2.0, 5.0]
const FRAME_HEADER := 12
const FRAME_MEMBER := 26
const MAX_MEMBERS := 64
## The server's action list (realtime ACTIONS + "sit"); OnlineCrowd indexes the same list.
const ACTIONS := ["idle", "run", "walk", "labour_sow", "labour_water", "labour_harvest", "labour_drain", "labour_shelter", "emote_wave", "attack", "mine", "labour_till", "labour_clear", "fishing_wait", "fishing_reel", "sit"]

var url := ""
var player_id := ""
var outpost := ""
var spawn_at := Vector2.ZERO
var appearance: Dictionary = {}
## () -> {position: Vector3, yaw: float, action: String}; read at the send rate.
var source := Callable()
## An OnlineCrowd (or anything with roster / sample / step) that draws the other players.
var crowd: Node
## Tests replace the socket send: transport.call(message: Dictionary).
var transport := Callable()
var socket: WebSocketPeer
var connected := false
var epoch := 0
var self_id := 0
var room := 0
var members: Dictionary = {}   # id → {id, player, seat, appearance}, ourselves included
var _seq := 0
var _act_seq := 0
var _send_left := 0.0
var _ping_left := PING_S
var _retry_left := -1.0
var _attempt := 0
var _stopped := true
var _last: Dictionary = {}
var _last_tick := -1

## http://host:3110/v1 → ws://host:3110/v1/p0/online (https → wss).
static func ws_url(base_url: String) -> String:
	var u := base_url.strip_edges().trim_suffix("/")
	if u.begins_with("https://"): u = "wss://" + u.substr(8)
	elif u.begins_with("http://"): u = "ws://" + u.substr(7)
	return u + "/p0/online"

## Members of a frame v1 for this epoch ([] for a stale or malformed frame).
static func decode_frame(data: PackedByteArray, for_epoch: int) -> Array:
	if data.size() < FRAME_HEADER or data.decode_u16(0) != 1 or int(data.decode_u32(6)) != for_epoch: return []
	var n := int(data.decode_u16(10))
	if n > MAX_MEMBERS or data.size() != FRAME_HEADER + n * FRAME_MEMBER: return []
	var out := []
	for i in n:
		var at := FRAME_HEADER + i * FRAME_MEMBER
		var position := Vector3(data.decode_float(at + 2), 0, data.decode_float(at + 6))
		if not position.is_finite(): continue
		out.append({"id": int(data.decode_u16(at)), "position": position, "yaw": data.decode_float(at + 10),
			"hp": 0, "max_hp": 0, "action": int(data[at + 18]), "seq": int(data.decode_u32(at + 20)), "serial": 0})
	return out

static func frame_tick(data: PackedByteArray) -> int:
	return int(data.decode_u32(2)) if data.size() >= FRAME_HEADER else -1

## Opens the socket and joins this outpost at our door position (room metres, x / z).
func start(outpost_id: String, at: Vector2) -> void:
	outpost = outpost_id
	spawn_at = at
	_stopped = false
	_attempt = 0
	_connect()

## Leaves the room on purpose (no reconnect, no seat kept).
func stop() -> void:
	_stopped = true
	if socket and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send({"t": "leave"})
		socket.close(1000, "LEAVING")
	_reset()

## Claims a seat; `at` is its position in room metres (the server moves us onto it before seating us).
func sit(seat: String, at := Vector2.INF) -> int:
	_act_seq += 1
	var m := {"t": "act", "seq": _act_seq, "epoch": epoch, "action": "sit", "node": seat}
	if at.is_finite(): m["at"] = [at.x, at.y]
	_send(m)
	return _act_seq

func stand() -> int:
	_act_seq += 1
	_send({"t": "act", "seq": _act_seq, "epoch": epoch, "action": "stand"})
	return _act_seq

func seat_of(id: int) -> String:
	return str(members.get(id, {}).get("seat", ""))

func _connect() -> void:
	_reset()
	socket = WebSocketPeer.new()
	socket.handshake_headers = PackedStringArray(["x-p0-player: " + player_id])
	if socket.connect_to_url(url) != OK: _retry()

func _reset() -> void:
	if connected: connection_changed.emit(false)
	connected = false
	epoch = 0
	self_id = 0
	members.clear()
	_last = {}
	_last_tick = -1
	if crowd: crowd.call("roster", {})

func _retry() -> void:
	_reset()
	_retry_left = RETRY_S[mini(_attempt, RETRY_S.size() - 1)]
	_attempt += 1

func _process(dt: float) -> void:
	if _stopped: return
	if _retry_left >= 0.0:
		_retry_left -= dt
		if _retry_left < 0.0: _connect()
		return
	if socket == null: return
	socket.poll()
	match socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not connected:
				connected = true
				_attempt = 0
				connection_changed.emit(true)
				_send({"t": "join", "outpost": outpost, "at": [spawn_at.x, spawn_at.y], "appearance": appearance} if not appearance.is_empty()
					else {"t": "join", "outpost": outpost, "at": [spawn_at.x, spawn_at.y]})
			while socket.get_available_packet_count() > 0:
				var packet := socket.get_packet()
				if socket.was_string_packet(): _message(packet.get_string_from_utf8())
				else: _frame(packet)
			_tick(dt)
		WebSocketPeer.STATE_CLOSED:
			var code := socket.get_close_code()
			socket = null
			if code == 4001: failed.emit("SESSION_REPLACED")   # another device took over: no reconnect
			if code == 4001 or code == 4002:
				_stopped = true
				_reset()
			else: _retry()

func _tick(dt: float) -> void:
	_ping_left -= dt
	if _ping_left <= 0.0:
		_ping_left = PING_S
		_send({"t": "ping", "at": Time.get_ticks_msec()})
	_send_left -= dt
	if epoch == 0 or _send_left > 0.0 or not source.is_valid(): return
	_send_left = SEND_S
	var s: Dictionary = source.call()
	var p: Vector3 = s.get("position", Vector3.ZERO)
	var now := {"x": snappedf(p.x, 0.01), "z": snappedf(p.z, 0.01), "yaw": snappedf(float(s.get("yaw", 0.0)), 0.01), "action": str(s.get("action", "idle"))}
	if now == _last: return   # nothing changed: the ping keeps the socket alive
	_last = now
	_seq += 1
	_send({"t": "input", "seq": _seq, "epoch": epoch, "x": now.x, "z": now.z, "yaw": now.yaw, "action": now.action})

func _message(text: String) -> void:
	var m = JSON.parse_string(text)
	if not (m is Dictionary): return
	match str(m.get("t", "")):
		"joined":
			epoch = int(m.epoch)
			self_id = int(m.self)
			room = int(m.room)
			_last = {}
			_last_tick = -1
			joined.emit(m)
		"roster":
			members.clear()
			for member in m.get("members", []): members[int(member.id)] = member
			_roster()
		"peer":
			var member: Dictionary = m.get("member", {})
			if not member.is_empty():
				members[int(member.id)] = member
				_roster()
		"left":
			members.erase(int(m.id))
			_roster()
		"seat":
			if members.has(int(m.id)): members[int(m.id)].seat = str(m.seat)
			seat_changed.emit(int(m.id), str(m.seat))
		"result":
			result.emit(int(m.seq), bool(m.ok), str(m.get("code", "")))
		"error":
			failed.emit(str(m.get("code", "")))

func _frame(data: PackedByteArray) -> void:
	var tick := frame_tick(data)
	if tick <= _last_tick: return
	var states := decode_frame(data, epoch)
	if states.is_empty() and data.size() != FRAME_HEADER: return
	_last_tick = tick
	if crowd == null: return
	for state in states:
		if int(state.id) != self_id and members.has(int(state.id)): crowd.call("sample", int(state.id), state)

func _roster() -> void:
	if crowd == null: return
	var others := {}
	for id in members:
		if int(id) != self_id: others[int(id)] = members[id]
	crowd.call("roster", others)

func _send(message: Dictionary) -> void:
	if transport.is_valid(): transport.call(message)
	elif socket and socket.get_ready_state() == WebSocketPeer.STATE_OPEN: socket.send_text(JSON.stringify(message))

func _exit_tree() -> void:
	if not _stopped: stop()
