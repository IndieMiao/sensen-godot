extends GdUnitTestSuite
const P0Line := preload("res://modules/p0/p0_line.gd")
## P0Line (421, preview B, 奕星 11-05): P0's requests on one connection kept open; a request lost on a kept connection
## goes once more on a new one; gzip as HTTPRequest takes it; back to a new request each for the rest of the run on
## the server's `x-p0-line: close` or two failures in a row.

## A small HTTP/1.1 server on 127.0.0.1, stepped by the test: each request is answered by `answer.call(n)` (the n-th
## request, from 0): {status, headers, body, close (Connection: close), cut (closed with no reply), silent}.
class Mini:
	var server := TCPServer.new()
	var port := 0
	var peers: Array = []
	var bufs: Array = []
	var connections := 0
	var requests: Array[String] = []
	var answer: Callable = func(_n): return {}

	func start() -> void:
		for p in range(47310, 47410):
			if server.listen(p, "127.0.0.1") == OK:
				port = p
				return

	func url(path := "/v1/p0/commands") -> String: return "http://127.0.0.1:%d%s" % [port, path]

	func step() -> void:
		while server.is_connection_available():
			peers.append(server.take_connection())
			bufs.append(PackedByteArray())
			connections += 1
		for i in peers.size():
			var peer: StreamPeerTCP = peers[i]
			if peer == null: continue
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				peers[i] = null
				continue
			var n := peer.get_available_bytes()
			var buf: PackedByteArray = bufs[i]
			if n > 0: buf.append_array(peer.get_data(n)[1])
			bufs[i] = buf
			var text := buf.get_string_from_ascii()
			var end := text.find("\r\n\r\n")
			if end < 0: continue
			var head := text.substr(0, end)
			var length := 0
			for line in head.split("\r\n"):
				if line.to_lower().begins_with("content-length:"): length = int(line.get_slice(":", 1).strip_edges())
			if buf.size() < end + 4 + length: continue
			bufs[i] = buf.slice(end + 4 + length)
			var first := head.get_slice("\r\n", 0).split(" ")
			requests.append(first[0] + " " + first[1])
			var r: Dictionary = answer.call(requests.size() - 1)
			if r.get("silent", false): continue
			if r.get("cut", false):
				peer.disconnect_from_host()
				peers[i] = null
				continue
			var body: PackedByteArray = r.get("body", '{"ok":true}'.to_utf8_buffer())
			var out := "HTTP/1.1 %d OK\r\nContent-Length: %d\r\n" % [int(r.get("status", 200)), body.size()]
			for h in r.get("headers", []): out += str(h) + "\r\n"
			if r.get("close", false): out += "Connection: close\r\n"
			peer.put_data((out + "\r\n").to_ascii_buffer())
			peer.put_data(body)
			if r.get("close", false) or r.get("then_close", false):
				peer.disconnect_from_host()
				peers[i] = null

	func stop() -> void:
		for p in peers:
			if p != null: (p as StreamPeerTCP).disconnect_from_host()
		server.stop()

var mini: Mini
var line: P0Line
var replies: Array

func before_test() -> void:
	mini = Mini.new()
	mini.start()
	line = auto_free(P0Line.new())
	line.off = false   # whatever this machine's switch says
	add_child(line)
	replies = []

func after_test() -> void:
	mini.stop()

func _send(path := "/v1/p0/commands", body := "{}") -> Error:
	return line.send(mini.url(path), PackedStringArray(["content-type: application/json"]), HTTPClient.METHOD_POST, body,
		func(result, code, headers, data): replies.append({result = result, code = code, headers = headers, body = data.get_string_from_utf8()}))

func _wait(count: int) -> void:
	for i in 600:
		mini.step()
		if replies.size() >= count: return
		await get_tree().process_frame

func test_requests_share_one_connection() -> void:
	mini.answer = func(n): return {"body": ('{"n":%d}' % n).to_utf8_buffer()}
	assert_int(_send()).is_equal(OK)
	assert_int(_send()).is_equal(ERR_BUSY)   # one at a time, as P0Session sends
	await _wait(1)
	assert_str(line.last_via).is_equal("new")
	_send("/v1/p0/state?space=mine")
	await _wait(2)
	_send()
	await _wait(3)
	assert_array(replies.map(func(r): return [r.result, r.code, r.body])).is_equal([
		[HTTPRequest.RESULT_SUCCESS, 200, '{"n":0}'], [HTTPRequest.RESULT_SUCCESS, 200, '{"n":1}'], [HTTPRequest.RESULT_SUCCESS, 200, '{"n":2}']])
	assert_array(mini.requests).is_equal(["POST /v1/p0/commands", "POST /v1/p0/state?space=mine", "POST /v1/p0/commands"])
	assert_int(mini.connections).is_equal(1)
	assert_str(line.last_via).is_equal("kept")

func test_a_request_cut_on_a_kept_connection_goes_once_more_on_a_new_one() -> void:
	# the server (or a NAT) closed it as the request went: nothing came back, so it goes again; a command that had gone
	# through comes back stale_state by its expect_seq
	mini.answer = func(n): return {"cut": n == 1}
	_send()
	await _wait(1)
	_send()
	await _wait(2)
	assert_int(replies[1].result).is_equal(HTTPRequest.RESULT_SUCCESS)
	assert_int(mini.requests.size()).is_equal(3)
	assert_int(mini.connections).is_equal(2)
	assert_bool(line.off).is_false()

func test_a_connection_the_server_closed_after_its_reply_is_made_again() -> void:
	mini.answer = func(n): return {"close": n == 0}
	_send()
	await _wait(1)
	_send()
	await _wait(2)
	assert_array(replies.map(func(r): return r.code)).is_equal([200, 200])
	assert_int(mini.requests.size()).is_equal(2)   # never twice: it was not sent on the closed one
	assert_int(mini.connections).is_equal(2)

func test_a_connection_the_server_dropped_while_idle_is_made_again() -> void:
	# no Connection: close, the server just closes it a moment after its reply (Node's 5 s keep-alive, a NAT)
	mini.answer = func(n): return {"then_close": n == 0}
	_send()
	await _wait(1)
	for i in 10:
		mini.step()
		await get_tree().process_frame
	_send()
	await _wait(2)
	assert_array(replies.map(func(r): return [r.result, r.code])).is_equal([[HTTPRequest.RESULT_SUCCESS, 200], [HTTPRequest.RESULT_SUCCESS, 200]])
	assert_int(mini.requests.size()).is_equal(2)
	assert_int(mini.connections).is_equal(2)
	assert_str(line.last_via).is_equal("new")

func test_a_cut_on_a_new_connection_is_a_failure_not_sent_again() -> void:
	mini.answer = func(_n): return {"cut": true}
	_send()
	await _wait(1)
	assert_int(replies[0].result).is_equal(HTTPRequest.RESULT_CONNECTION_ERROR)
	assert_int(mini.requests.size()).is_equal(1)

func test_a_gzip_reply_is_read_as_its_text() -> void:
	mini.answer = func(_n): return {"headers": ["Content-Encoding: gzip"], "body": '{"ok":true,"seq":9}'.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)}
	_send()
	await _wait(1)
	assert_str(replies[0].body).is_equal('{"ok":true,"seq":9}')

func test_the_servers_close_sends_the_rest_of_the_run_the_old_way() -> void:
	mini.answer = func(_n): return {"headers": ["x-p0-line: close"]}
	_send()
	await _wait(1)
	assert_int(replies[0].code).is_equal(200)   # this reply still counts
	assert_bool(line.off).is_true()
	assert_str(line.off_why).is_equal("the server says close")
	assert_int(_send()).is_equal(ERR_UNAVAILABLE)

func test_two_failures_in_a_row_send_the_rest_of_the_run_the_old_way() -> void:
	mini.stop()   # nothing listens: refused
	_send()
	await _wait(1)
	assert_int(replies[0].result).is_not_equal(HTTPRequest.RESULT_SUCCESS)
	assert_bool(line.off).is_false()
	_send()
	await _wait(2)
	assert_bool(line.off).is_true()
	assert_str(line.off_why).is_equal("2 failures in a row")

func test_a_reply_between_failures_starts_the_count_again() -> void:
	mini.answer = func(n): return {"cut": n != 1}
	_send()
	await _wait(1)
	_send()
	await _wait(2)
	_send()
	await _wait(3)
	assert_array(replies.map(func(r): return r.result)).is_equal([HTTPRequest.RESULT_CONNECTION_ERROR,
		HTTPRequest.RESULT_SUCCESS, HTTPRequest.RESULT_CONNECTION_ERROR])
	assert_bool(line.off).is_false()

func test_no_answer_waits_its_live_seconds() -> void:
	line.wait_s = 0.3
	mini.answer = func(_n): return {"silent": true}
	_send()
	await _wait(1)
	assert_int(replies[0].result).is_equal(HTTPRequest.RESULT_TIMEOUT)

func test_urls() -> void:
	assert_that(P0Line.split("https://farm.sensenjoy.cn/preview/p0/v1/p0/commands")).is_equal(
		{tls = true, host = "farm.sensenjoy.cn", port = 443, path = "/preview/p0/v1/p0/commands"})
	assert_that(P0Line.split("http://127.0.0.1:3141/v1/p0/state?space=mine")).is_equal(
		{tls = false, host = "127.0.0.1", port = 3141, path = "/v1/p0/state?space=mine"})
	assert_that(P0Line.split("http://example.com")).is_equal({tls = false, host = "example.com", port = 80, path = "/"})
	assert_that(P0Line.split("ws://x/y")).is_equal({})
	assert_str(P0Line.header(PackedStringArray(["X-P0-Line:  Close "]), "x-p0-line")).is_equal("close")
