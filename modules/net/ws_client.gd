class_name WsClient
extends Node
## WebSocketPeer 封装（08-30 调研 §3.1 IM 长连接契约）：
## 前台保持连接；应用进入后台（NOTIFICATION_APPLICATION_PAUSED）主动断开；回前台重连，
## 连上后发 resync_needed(last_seq) 让上层按最后 seq 走 REST 增量补拉。离线消息走推送，
## 这里不做离线队列。
##
## peer 可注入（peer_factory）：真 WebSocketPeer 要网络，断线 / 重连 / 回前台这些分支在
## 真网络里没法稳定复现，测试用鸭子类型的假 peer 驱动。poll() 公开出来同理——不在树里的
## 节点不会跑 _process，测试直接推时间。

signal connected
signal disconnected(code: int, reason: String)
signal message_received(msg: Dictionary)
## 重连或回前台成功后发出；last_seq 为 -1 表示本次连接前从未收过带 seq 的消息。
signal resync_needed(last_seq: int)
signal state_changed(state: int)

enum State { IDLE, CONNECTING, OPEN, RECONNECT_WAIT, PAUSED }

const BACKOFF_BASE_S := 1.0
const BACKOFF_MAX_S := 30.0

var url := ""
## () -> String；非空时以 Authorization: Bearer 放进握手头。
var token_provider: Callable
## () -> WebSocketPeer 或同接口的假对象。
var peer_factory: Callable
var auto_reconnect := true
var last_seq := -1
var state := State.IDLE
var attempts := 0
var wait_left := 0.0

var _peer = null
var _had_session := false

func open(p_url: String) -> void:
	url = p_url
	attempts = 0
	auto_reconnect = true
	_connect()

## 主动关闭（登出 / 离开需要长连接的页面）；之后不再自动重连。
func close(code := 1000, reason := "") -> void:
	auto_reconnect = false
	_close_peer(code, reason)
	_set_state(State.IDLE)

func send(msg: Dictionary) -> bool:
	if state != State.OPEN or _peer == null:
		return false
	return _peer.send_text(JSON.stringify(msg)) == OK

func is_open() -> bool:
	return state == State.OPEN

func poll(delta: float) -> void:
	match state:
		State.RECONNECT_WAIT:
			wait_left -= delta
			if wait_left <= 0.0:
				_connect()
		State.CONNECTING, State.OPEN:
			_poll_peer()

func pause() -> void:
	if state == State.IDLE or state == State.PAUSED:
		return
	_close_peer(1000, "app paused")
	_set_state(State.PAUSED)

func resume() -> void:
	if state != State.PAUSED:
		return
	attempts = 0
	_connect()

static func backoff_for(attempt: int) -> float:
	return minf(BACKOFF_BASE_S * pow(2.0, float(attempt)), BACKOFF_MAX_S)

func _process(delta: float) -> void:
	poll(delta)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		resume()

func _connect() -> void:
	_peer = peer_factory.call() if peer_factory.is_valid() else WebSocketPeer.new()
	var headers := PackedStringArray()
	if token_provider.is_valid():
		var t = token_provider.call()
		if t is String and not (t as String).is_empty():
			headers.append("Authorization: Bearer %s" % t)
	_peer.handshake_headers = headers
	var err: int = _peer.connect_to_url(url)
	if err != OK:
		_peer = null
		disconnected.emit(-1, "connect_to_url failed: %d" % err)
		_after_drop()
		return
	_set_state(State.CONNECTING)

func _poll_peer() -> void:
	if _peer == null:
		return
	_peer.poll()
	var rs: int = _peer.get_ready_state()
	if rs == WebSocketPeer.STATE_OPEN:
		if state == State.CONNECTING:
			attempts = 0
			_set_state(State.OPEN)
			connected.emit()
			if _had_session:
				resync_needed.emit(last_seq)
			_had_session = true
		while _peer != null and _peer.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _peer.get_packet()
			_handle_text(pkt.get_string_from_utf8())
	elif rs == WebSocketPeer.STATE_CLOSED:
		var code: int = _peer.get_close_code()
		var reason: String = _peer.get_close_reason()
		_peer = null
		disconnected.emit(code, reason)
		_after_drop()

func _after_drop() -> void:
	if auto_reconnect:
		wait_left = backoff_for(attempts)
		attempts += 1
		_set_state(State.RECONNECT_WAIT)
	else:
		_set_state(State.IDLE)

func _close_peer(code: int, reason: String) -> void:
	if _peer == null:
		return
	# WebSocketPeer.close() 只是发起关闭握手，真正 CLOSED 要继续 poll 几帧；这里直接丢引用，
	# 由对象销毁断开底层连接。后台切换场景下没人等这几帧，服务端按超时清理即可。
	_peer.close(code, reason)
	_peer = null

func _handle_text(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var msg: Dictionary = parsed
	if msg.has("seq"):
		last_seq = maxi(last_seq, int(msg.seq))
	message_received.emit(msg)

func _set_state(v: int) -> void:
	if v == state:
		return
	state = v
	state_changed.emit(v)
