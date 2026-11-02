extends GdUnitTestSuite
## SGODOT-370: a P0 request's wait counts live time, not a stall of the main thread (a world loading): after the stall
## it goes on and takes its answer — the first Go to an outpost after a cold start no longer ends in "Couldn't get
## there". A local server on its own thread answers (or keeps the line open without a word) while the test holds the
## main thread.

var _server: Thread
var _port := 0
var _stop := false

## A server on a thread: one connection, answered at once (`answer`) or held open without a word until the test ends.
func _serve(answer: bool) -> void:
	var tcp := TCPServer.new()
	assert_int(tcp.listen(0, "127.0.0.1")).is_equal(OK)
	_port = tcp.get_local_port()
	_stop = false
	_server = Thread.new()
	_server.start(func():
		var peer: StreamPeerTCP = null
		while not _stop and peer == null:
			if tcp.is_connection_available(): peer = tcp.take_connection()
			else: OS.delay_msec(2)
		var got := ""
		while not _stop and peer != null and not got.contains("\r\n\r\n"):
			peer.poll()
			var n := peer.get_available_bytes()
			if n > 0: got += peer.get_utf8_string(n)
			else: OS.delay_msec(2)
		if answer and peer != null:
			peer.put_data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 11\r\nConnection: close\r\n\r\n{\"ok\":true}".to_utf8_buffer())
		while not _stop: OS.delay_msec(5)
		if peer != null: peer.disconnect_from_host()
		tcp.stop())

func after_test() -> void:
	_stop = true
	if _server != null and _server.is_started(): _server.wait_to_finish()
	_server = null

func _until_done(http: HTTPRequest, max_ms := 6000) -> Array:
	var got := []
	http.request_completed.connect(func(r, c, _h, b): got.append_array([r, c, b.get_string_from_utf8()]))
	var until := Time.get_ticks_msec() + max_ms
	while got.is_empty() and Time.get_ticks_msec() < until: await get_tree().process_frame
	return got

func test_a_frame_counts_at_most_a_quarter_second() -> void:
	assert_float(P0HttpRequest.live_dt(0.016)).is_equal(0.016)
	assert_float(P0HttpRequest.live_dt(5.0)).is_equal(P0HttpRequest.FRAME_CAP_S)

## The case on 370: the main thread is stuck longer than the whole wait right after the request; it still gets there.
func test_a_stall_longer_than_the_wait_is_not_counted() -> void:
	_serve(true)
	var http: P0HttpRequest = auto_free(P0HttpRequest.new(2.0))
	add_child(http)
	await get_tree().process_frame
	assert_int(http.send("http://127.0.0.1:%d/p0/state?space=outpost" % _port)).is_equal(OK)
	OS.delay_msec(2500)   # the outpost loading: longer than the 2 s wait
	var got := await _until_done(http)
	assert_array(got).is_equal([HTTPRequest.RESULT_SUCCESS, 200, "{\"ok\":true}"])

## Why: the engine's own request steps on the main thread and its timer counts the stall — the same answer, too late.
func test_the_engines_own_request_counts_the_stall() -> void:
	_serve(true)
	var http: HTTPRequest = auto_free(HTTPRequest.new())
	http.timeout = 2.0
	add_child(http)
	await get_tree().process_frame
	assert_int(http.request("http://127.0.0.1:%d/p0/state?space=outpost" % _port)).is_equal(OK)
	OS.delay_msec(2500)
	var got := await _until_done(http)
	assert_int(int(got[0])).is_equal(HTTPRequest.RESULT_TIMEOUT)

## A server that never says a word: given up after the wait in live time, as before.
func test_no_answer_is_given_up_after_the_wait() -> void:
	_serve(false)
	var http: P0HttpRequest = auto_free(P0HttpRequest.new(0.5))
	add_child(http)
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	http.send("http://127.0.0.1:%d/p0/state" % _port)
	var got := await _until_done(http)
	assert_int(int(got[0])).is_equal(HTTPRequest.RESULT_TIMEOUT)
	assert_int(Time.get_ticks_msec() - t0).is_between(450, 2000)

## A second send while one is on the wire is refused (ERR_BUSY) and leaves that one's wait running (周瑜 on #582).
func test_a_refused_send_leaves_the_wait_running() -> void:
	_serve(false)
	var http: P0HttpRequest = auto_free(P0HttpRequest.new(0.5))
	add_child(http)
	await get_tree().process_frame
	http.send("http://127.0.0.1:%d/p0/state" % _port)
	assert_int(http.send("http://127.0.0.1:%d/p0/state" % _port)).is_equal(ERR_BUSY)
	var got := await _until_done(http)
	assert_int(int(got[0])).is_equal(HTTPRequest.RESULT_TIMEOUT)
