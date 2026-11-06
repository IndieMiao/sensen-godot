extends Node
## P0Line (no class_name: preloaded where used, so a machine that never imported runs its tests — 亚瑟 on #771).
## 421 (preview B, 奕星 11-05): P0's commands and reads on one connection kept open. From China to the US-west server a
## new HTTPS request took 0.66–2.8 s (its TCP and TLS handshakes; 0.9 s typical), one on a connection kept open 0.2 s
## (周瑜, 蒙恬 0.64 / 0.20); P0Session sends one at a time, so the swings queued and the ladder waited behind them.
## Godot's HTTPRequest connects for every request: this steps an HTTPClient itself, one request at a time (the
## session's order), with P0HttpRequest's 8 s of live time and gzip as HTTPRequest takes it.
##
## Back to a new request each (P0HttpRequest, as before) for the rest of the run: user://p0_line_off or P0_LINE=0 at
## the start; the server's `x-p0-line: close` (its P0_LINE=close, the switch on the server). Two failures in a row on
## the line send it the old way too, until the old way has an answer (the network is back: no signal at launch, a
## tunnel) — then the line again, if it had answered in this run, at most COMEBACKS times a run (奕星 11-05).
## A request sent on a kept connection and lost before any reply (closed by the server or a NAT while idle)
## goes once more on a new one: every command carries expect_seq, so one that had gone through comes back
## stale_state with the state, never twice.

const IDLE_S := 45.0     # a connection idle longer is closed before the next request (Caddy keeps one 5 min)
const FAILS_OFF := 2     # failures in a row on the line before it goes back to a request each
const COMEBACKS := 3     # times a run takes the line again after failures (old_way_answered)

var wait_s := 8.0        # live seconds before a request with no answer is given up (RESULT_TIMEOUT), as P0HttpRequest
var off := false
var off_why := ""
var last_via := ""       # how the last reply came: "new" (connected for it) or "kept" (P0Session's log)

var _client := HTTPClient.new()
var _host := ""
var _port := 0
var _tls := false
var _job := {}           # the request on the line; {} none
var _idle := 0.0         # live seconds the open connection has waited since its last reply
var _fails := 0
var _ever := false       # the line has answered in this run
var _for_good := false   # off for the rest of the run: the device's switch, the server's close
var _comebacks := 0

## Whether this run may use the line at all (a switch for a device: user://p0_line_off, P0_LINE=0 on desktop).
static func wanted() -> bool:
	return not FileAccess.file_exists("user://p0_line_off") and OS.get_environment("P0_LINE") != "0"

func _init() -> void:
	if not wanted(): _turn_off("switched off on this device", true)

## A request on the line; done.call(result, code, headers, body) once, as HTTPRequest's request_completed. ERR_BUSY
## while one is out, ERR_UNAVAILABLE when off: the caller sends it the old way.
func send(url: String, headers: PackedStringArray, method: int, body: String, done: Callable) -> Error:
	if off: return ERR_UNAVAILABLE
	if not _job.is_empty(): return ERR_BUSY
	var to := split(url)
	if to.is_empty(): return ERR_INVALID_PARAMETER
	# a connection the server closed while idle reads CONNECTION_ERROR, not DISCONNECTED: begin again from closed
	if _client.get_status() != HTTPClient.STATUS_CONNECTED or to.host != _host or to.port != _port or to.tls != _tls \
			or _idle > IDLE_S:
		_client.close()
	_host = to.host
	_port = to.port
	_tls = to.tls
	var with_gzip := headers.duplicate()
	with_gzip.append("Accept-Encoding: gzip")
	_job = {path = to.path, headers = with_gzip, method = method, body = body, done = done, waited = 0.0, sent = false,
		kept = _client.get_status() == HTTPClient.STATUS_CONNECTED, again = false, code = 0,
		reply_headers = PackedStringArray(), data = PackedByteArray()}
	_step()
	return OK

## Whether a request is out on the line.
func busy() -> bool: return not _job.is_empty()

func _process(dt: float) -> void:
	if _job.is_empty():
		if _client.get_status() == HTTPClient.STATUS_CONNECTED:
			_idle += P0HttpRequest.live_dt(dt)
			_client.poll()   # notices a connection the server closed
		return
	_job.waited += P0HttpRequest.live_dt(dt)
	if _job.waited >= wait_s:
		_failed(HTTPRequest.RESULT_TIMEOUT)
		return
	_step()

## As far as the request can go this frame: connect, send, read the reply (all of it when it is all here).
func _step() -> void:
	for _i in 256:
		if _job.is_empty(): return
		var status := _client.get_status()
		match status:
			HTTPClient.STATUS_DISCONNECTED:
				if _job.code != 0:   # closed after its reply (Connection: close, or a body read to the end)
					_done()
					return
				if _job.sent:
					_lost(HTTPRequest.RESULT_CONNECTION_ERROR)
					return
				if _client.connect_to_host(_host, _port, TLSOptions.client() if _tls else null) != OK:
					_failed(HTTPRequest.RESULT_CANT_CONNECT)
					return
				_job.kept = false
				_idle = 0.0
				_client.poll()
				if _client.get_status() == HTTPClient.STATUS_DISCONNECTED: return
			HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
				_client.poll()
				if _client.get_status() == status: return   # nothing more this frame
			HTTPClient.STATUS_CONNECTED:
				if _job.code != 0:
					_done()
					return
				if not _job.sent:
					if _client.request(_job.method, _job.path, _job.headers, _job.body) != OK:
						_client.close()   # gone under us: a new one
						continue
					_job.sent = true
					continue
				_client.poll()
				if _client.has_response(): _take_head()
				elif _client.get_status() == status: return
			HTTPClient.STATUS_BODY:
				if _job.code == 0: _take_head()
				_client.poll()
				var chunk := _client.read_response_body_chunk()
				if not chunk.is_empty():
					var data: PackedByteArray = _job.data   # a packed array is a value: append to it, put it back
					data.append_array(chunk)
					_job.data = data
				elif _client.get_status() == HTTPClient.STATUS_BODY: return   # the rest still on the way
			HTTPClient.STATUS_CANT_RESOLVE:
				_failed(HTTPRequest.RESULT_CANT_RESOLVE)
				return
			HTTPClient.STATUS_CANT_CONNECT:
				_failed(HTTPRequest.RESULT_CANT_CONNECT)
				return
			HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
				_failed(HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR)
				return
			_:   # STATUS_CONNECTION_ERROR: cut before or inside its reply
				_lost(HTTPRequest.RESULT_CONNECTION_ERROR)
				return

func _take_head() -> void:
	_job.code = _client.get_response_code()
	_job.reply_headers = _client.get_response_headers()

## Lost on the way: once more on a new connection when it went on a kept one and nothing came back (closed while
## idle); else a failure.
func _lost(result: int) -> void:
	_client.close()
	if _job.kept and _job.code == 0 and not _job.again:
		_job.again = true
		_job.sent = false
		_job.kept = false
		return
	_failed(result)

func _failed(result: int) -> void:
	_client.close()
	_fails += 1
	if _fails >= FAILS_OFF: _turn_off("%d failures in a row" % _fails)
	var done: Callable = _job.done
	_job = {}
	done.call(result, 0, PackedStringArray(), PackedByteArray())

func _done() -> void:
	_fails = 0
	_idle = 0.0
	_ever = true
	var headers: PackedStringArray = _job.reply_headers
	var data: PackedByteArray = _job.data
	if header(headers, "content-encoding") == "gzip": data = data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if header(headers, "x-p0-line") == "close": _turn_off("the server says close", true)
	last_via = "kept" if _job.kept else "new"
	var done: Callable = _job.done
	var code: int = _job.code
	_job = {}
	done.call(HTTPRequest.RESULT_SUCCESS, code, headers, data)

func _turn_off(why: String, for_good := false) -> void:
	_for_good = _for_good or for_good
	if off: return
	off = true
	off_why = why
	_client.close()
	print("P0 net: line off (%s), a new request each from now" % why)

## The old way (P0HttpRequest) had an answer: with the line off after failures, the network is back, so the line
## again — if it had answered in this run, at most COMEBACKS times a run; the device's switch and the server's close
## stay. The answer's headers: a server's `x-p0-line: close` turns it off for good here too.
func old_way_answered(headers: PackedStringArray) -> void:
	if header(headers, "x-p0-line") == "close": _turn_off("the server says close", true)
	if not off or _for_good or not _ever or _comebacks >= COMEBACKS: return
	_comebacks += 1
	off = false
	off_why = ""
	_fails = 0
	_client.close()
	print("P0 net: line back (%d of %d)" % [_comebacks, COMEBACKS])

## Back from the background (Android): the open connection is likely gone with the app's sockets; an idle one is
## closed so the next request connects anew instead of waiting out a dead one.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and _job.is_empty(): _client.close()

## A reply header's value, lower case ("" none).
static func header(headers: PackedStringArray, name: String) -> String:
	for h in headers:
		var colon := h.find(":")
		if colon > 0 and h.substr(0, colon).strip_edges().to_lower() == name: return h.substr(colon + 1).strip_edges().to_lower()
	return ""

## {tls, host, port, path} of an http(s) URL, {} for anything else.
static func split(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	if not tls and not url.begins_with("http://"): return {}
	var rest := url.substr(8 if tls else 7)
	var slash := rest.find("/")
	var host := rest if slash < 0 else rest.substr(0, slash)
	var port := 443 if tls else 80
	var colon := host.rfind(":")
	if colon > 0 and host.substr(colon + 1).is_valid_int():
		port = int(host.substr(colon + 1))
		host = host.substr(0, colon)
	if host == "": return {}
	return {tls = tls, host = host, port = port, path = "/" if slash < 0 else rest.substr(slash)}
