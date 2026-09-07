extends GdUnitTestSuite
## WsClient：握手头带 token、连接状态机、seq 追踪、断线退避重连、后台断开 / 回前台补拉。
## 节点不入树，测试自己推 poll(delta)。
## 计数与 peer 列表放在辅助类里：GDScript lambda 按值捕获局部变量，闭包里 `n += 1` 改不到外面。

class PeerBox extends RefCounted:
	var peers: Array = []
	var connect_result: int = OK
	var token := "tok"

	func make() -> FakeWsPeer:
		var p := FakeWsPeer.new()
		p.connect_result = connect_result
		peers.append(p)
		return p

	func last() -> FakeWsPeer:
		return peers.back()

	func token_for() -> String:
		return token

class Probe extends RefCounted:
	var connected := 0
	var drops: Array = []
	var resyncs: Array = []
	var messages: Array = []

	func on_connected() -> void:
		connected += 1

	func on_disconnected(code: int, reason: String) -> void:
		drops.append([code, reason])

	func on_resync(seq: int) -> void:
		resyncs.append(seq)

	func on_message(m: Dictionary) -> void:
		messages.append(m)

var box: PeerBox
var probe: Probe

func before_test() -> void:
	box = PeerBox.new()
	probe = Probe.new()

func _ws() -> WsClient:
	var ws := auto_free(WsClient.new()) as WsClient
	ws.token_provider = box.token_for
	ws.peer_factory = box.make
	ws.connected.connect(probe.on_connected)
	ws.disconnected.connect(probe.on_disconnected)
	ws.resync_needed.connect(probe.on_resync)
	ws.message_received.connect(probe.on_message)
	return ws

func _open_and_connect(ws: WsClient) -> void:
	ws.open("wss://im.example/ws")
	box.last().ready_state = WebSocketPeer.STATE_OPEN
	ws.poll(0.016)

func test_open_connects_with_bearer_header_and_reports_connected_when_peer_opens() -> void:
	var ws := _ws()
	ws.open("wss://im.example/ws")
	assert_int(ws.state).is_equal(WsClient.State.CONNECTING)
	assert_str(box.last().url).is_equal("wss://im.example/ws")
	assert_bool(str(box.last().handshake_headers).contains("Authorization: Bearer tok")).is_true()
	ws.poll(0.016)
	assert_int(probe.connected).is_equal(0)
	box.last().ready_state = WebSocketPeer.STATE_OPEN
	ws.poll(0.016)
	assert_int(probe.connected).is_equal(1)
	assert_bool(ws.is_open()).is_true()

func test_no_token_means_no_auth_header() -> void:
	box.token = ""
	var ws := _ws()
	ws.open("wss://x")
	assert_bool(str(box.last().handshake_headers).contains("Authorization")).is_false()

func test_messages_are_parsed_and_seq_tracked() -> void:
	var ws := _ws()
	ws.open("wss://x")
	box.last().ready_state = WebSocketPeer.STATE_OPEN
	box.last().inbox.append(JSON.stringify({"type": "msg", "seq": 7}))
	box.last().inbox.append("not json")
	box.last().inbox.append(JSON.stringify({"type": "msg", "seq": 5}))
	ws.poll(0.016)
	assert_int(probe.messages.size()).is_equal(2)
	assert_int(ws.last_seq).is_equal(7) # 乱序到达不倒退

func test_send_only_when_open() -> void:
	var ws := _ws()
	assert_bool(ws.send({"a": 1})).is_false()
	ws.open("wss://x")
	assert_bool(ws.send({"a": 1})).is_false()
	box.last().ready_state = WebSocketPeer.STATE_OPEN
	ws.poll(0.016)
	assert_bool(ws.send({"a": 1})).is_true()
	assert_str(box.last().sent[0]).is_equal(JSON.stringify({"a": 1}))

func test_drop_schedules_backoff_reconnect_and_resyncs_from_last_seq() -> void:
	var ws := _ws()
	ws.open("wss://x")
	box.last().ready_state = WebSocketPeer.STATE_OPEN
	box.last().inbox.append(JSON.stringify({"seq": 41}))
	ws.poll(0.016)
	var first := box.last()
	first.ready_state = WebSocketPeer.STATE_CLOSED
	first.close_code = 1006
	first.close_reason = "abnormal"
	ws.poll(0.016)
	assert_array(probe.drops).is_equal([[1006, "abnormal"]])
	assert_int(ws.state).is_equal(WsClient.State.RECONNECT_WAIT)
	assert_float(ws.wait_left).is_equal_approx(WsClient.backoff_for(0), 0.001)
	assert_int(box.peers.size()).is_equal(1)
	ws.poll(0.5)
	assert_int(box.peers.size()).is_equal(1) # 还没到点
	ws.poll(0.6)
	assert_int(box.peers.size()).is_equal(2) # 重连
	assert_int(ws.state).is_equal(WsClient.State.CONNECTING)
	box.last().ready_state = WebSocketPeer.STATE_OPEN
	ws.poll(0.016)
	assert_array(probe.resyncs).is_equal([41])
	assert_int(ws.attempts).is_equal(0) # 连上即清零

func test_backoff_doubles_and_caps() -> void:
	assert_float(WsClient.backoff_for(0)).is_equal_approx(1.0, 0.001)
	assert_float(WsClient.backoff_for(1)).is_equal_approx(2.0, 0.001)
	assert_float(WsClient.backoff_for(3)).is_equal_approx(8.0, 0.001)
	assert_float(WsClient.backoff_for(10)).is_equal_approx(30.0, 0.001)

func test_repeated_failures_grow_backoff() -> void:
	var ws := _ws()
	ws.open("wss://x")
	box.last().ready_state = WebSocketPeer.STATE_CLOSED
	ws.poll(0.016)
	assert_float(ws.wait_left).is_equal_approx(1.0, 0.001)
	ws.poll(1.0)
	box.last().ready_state = WebSocketPeer.STATE_CLOSED
	ws.poll(0.016)
	assert_float(ws.wait_left).is_equal_approx(2.0, 0.001)
	assert_int(ws.attempts).is_equal(2)

func test_pause_closes_and_resume_reconnects_with_resync() -> void:
	var ws := _ws()
	ws.open("wss://x")
	box.last().ready_state = WebSocketPeer.STATE_OPEN
	box.last().inbox.append(JSON.stringify({"seq": 3}))
	ws.poll(0.016)
	var first := box.last()
	ws.pause()
	assert_bool(first.closed).is_true()
	assert_int(ws.state).is_equal(WsClient.State.PAUSED)
	ws.poll(60.0)
	assert_int(box.peers.size()).is_equal(1) # 后台不重连
	ws.resume()
	assert_int(box.peers.size()).is_equal(2)
	box.last().ready_state = WebSocketPeer.STATE_OPEN
	ws.poll(0.016)
	assert_array(probe.resyncs).is_equal([3])
	assert_bool(str(box.last().handshake_headers).contains("Bearer tok")).is_true()

func test_first_connection_does_not_request_resync() -> void:
	var ws := _ws()
	_open_and_connect(ws)
	assert_array(probe.resyncs).is_empty()

func test_close_stops_auto_reconnect() -> void:
	var ws := _ws()
	_open_and_connect(ws)
	ws.close()
	assert_int(ws.state).is_equal(WsClient.State.IDLE)
	assert_bool(box.last().closed).is_true()
	ws.poll(60.0)
	assert_int(box.peers.size()).is_equal(1)

func test_connect_failure_goes_straight_to_backoff() -> void:
	box.connect_result = ERR_CANT_CONNECT
	var ws := _ws()
	ws.open("wss://x")
	assert_array(probe.drops).is_equal([[-1, "connect_to_url failed: %d" % ERR_CANT_CONNECT]])
	assert_int(ws.state).is_equal(WsClient.State.RECONNECT_WAIT)

func test_lifecycle_notifications_drive_pause_and_resume() -> void:
	var ws := _ws()
	_open_and_connect(ws)
	ws.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_int(ws.state).is_equal(WsClient.State.PAUSED)
	ws.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_int(ws.state).is_equal(WsClient.State.CONNECTING)
	assert_int(box.peers.size()).is_equal(2)
