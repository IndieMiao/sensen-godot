extends GdUnitTestSuite
## Net 的 IM 接线：WS 地址推导、连上后按游标补拉（分页到 latest_seq）、WS 推送转 im_event、去重与游标推进、Dev 不连。

const NetScript := preload("res://modules/net/net_service.gd")

class Recorder extends RefCounted:
	var events: Array = []
	func on_event(e: Dictionary) -> void:
		events.append(e)

class PeerBox extends RefCounted:
	var peer: FakeWsPeer
	func make():
		peer = FakeWsPeer.new()
		return peer

var net: Node
var t: FakeTransport
var rec: Recorder
var peers: PeerBox

func before_test() -> void:
	net = NetScript.new()
	add_child(auto_free(net))
	t = FakeTransport.new([])
	net.use_transport(t.callable(), "https://example.test/v1")
	rec = Recorder.new()
	net.im_event.connect(rec.on_event)
	peers = PeerBox.new()
	net.ws.peer_factory = peers.make

func test_ws_url_derived_from_rest_base() -> void:
	assert_str(NetScript.ws_url_for("https://api.example.test/v1")).is_equal("wss://api.example.test/v1/im/ws")
	assert_str(NetScript.ws_url_for("http://127.0.0.1:3101/v1/")).is_equal("ws://127.0.0.1:3101/v1/im/ws")

func test_resync_pages_until_latest_and_advances_cursor() -> void:
	t.responses = [
		{"status": 200, "json": {"events": [{"seq": 1, "type": "message"}, {"seq": 2, "type": "read"}], "latest_seq": 3}},
		{"status": 200, "json": {"events": [{"seq": 3, "type": "message"}], "latest_seq": 3}},
	]
	assert_int(await net.resync()).is_equal(3)
	assert_int(net.im_last_seq).is_equal(3)
	assert_int(net.ws.last_seq).is_equal(3)
	assert_int(rec.events.size()).is_equal(3)
	assert_bool(str(t.requests[0].url).ends_with("/v1/im/sync?since=0&limit=200")).is_true()
	assert_bool(str(t.requests[1].url).ends_with("/v1/im/sync?since=2&limit=200")).is_true()
	# 已经追平：再同步一次只发一个请求
	t.responses.append({"status": 200, "json": {"events": [], "latest_seq": 3}})
	assert_int(await net.resync()).is_equal(0)
	assert_bool(str(t.requests[2].url).ends_with("/v1/im/sync?since=3&limit=200")).is_true()

func test_ws_frames_become_events_and_stale_duplicates_are_dropped() -> void:
	net.im_last_seq = 4
	net.ws.open("wss://example.test/v1/im/ws")
	peers.peer.ready_state = WebSocketPeer.STATE_OPEN
	t.responses = [{"status": 200, "json": {"events": [], "latest_seq": 4}}] # connected → resync
	net.ws.poll(0.0)
	await get_tree().process_frame
	peers.peer.inbox.append(JSON.stringify({"type": "hello", "user_id": "u"}))
	peers.peer.inbox.append(JSON.stringify({"type": "message", "seq": 5, "conversation_id": "c1"}))
	peers.peer.inbox.append(JSON.stringify({"type": "message", "seq": 5, "conversation_id": "c1"})) # 重复
	peers.peer.inbox.append(JSON.stringify({"type": "read", "seq": 3, "conversation_id": "c1"}))   # 旧的
	peers.peer.inbox.append(JSON.stringify({"type": "pong"}))
	net.ws.poll(0.0)
	assert_int(rec.events.size()).is_equal(1)
	assert_int(int(rec.events[0].seq)).is_equal(5)
	assert_int(net.im_last_seq).is_equal(5)

func test_connect_im_skips_dev_sessions_and_opens_for_real_ones() -> void:
	net.auth.complete_sign_in("dev-local", "dev-token", "", 3600, "dev", "dev@local")
	net.connect_im()
	assert_int(net.ws.state).is_equal(WsClient.State.IDLE)
	net.auth.sign_out()
	net.auth.complete_sign_in("uid-1", "id-1", "rt-1", 3600, "password", "a@b.co")
	net.connect_im()
	assert_int(net.ws.state).is_equal(WsClient.State.CONNECTING)
	assert_str(peers.peer.url).is_equal("wss://example.test/v1/im/ws")
	assert_bool(Array(peers.peer.handshake_headers).has("Authorization: Bearer id-1")).is_true()
	net.disconnect_im()
	assert_int(net.ws.state).is_equal(WsClient.State.IDLE)

## 桌面 QA 实例用环境变量把服务指到局域网；不设时不影响默认。
func test_base_url_honours_environment_override() -> void:
	OS.set_environment("SENSEN_SERVER_BASE", "http://192.168.1.2:3101/v1/")
	assert_str(NetScript.base_url()).is_equal("http://192.168.1.2:3101/v1")
	OS.set_environment("SENSEN_SERVER_BASE", "")
	assert_bool(NetScript.base_url().begins_with("http")).is_true()
