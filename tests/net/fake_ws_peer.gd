class_name FakeWsPeer
extends RefCounted
## 鸭子类型的 WebSocketPeer 替身：测试直接拨 ready_state、往 inbox 塞报文。

var ready_state: int = WebSocketPeer.STATE_CONNECTING
var handshake_headers := PackedStringArray()
var url := ""
var connect_result: int = OK
var inbox: Array[String] = []
var sent: Array[String] = []
var polls := 0
var closed := false
var close_code := 1000
var close_reason := ""

func connect_to_url(p_url: String, _tls = null) -> int:
	url = p_url
	return connect_result

func poll() -> void:
	polls += 1

func get_ready_state() -> int:
	return ready_state

func get_available_packet_count() -> int:
	return inbox.size()

func get_packet() -> PackedByteArray:
	return inbox.pop_front().to_utf8_buffer()

func send_text(text: String) -> int:
	if ready_state != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	sent.append(text)
	return OK

func close(code := 1000, reason := "") -> void:
	closed = true
	close_code = code
	close_reason = reason
	ready_state = WebSocketPeer.STATE_CLOSED

func get_close_code() -> int:
	return close_code

func get_close_reason() -> String:
	return close_reason
