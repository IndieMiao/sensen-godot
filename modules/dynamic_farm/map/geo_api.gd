extends Node
## Read-only preview transport. No installation credentials, POST or production fallback.
signal attempt_finished(details: Dictionary)
const MAX_ATTEMPTS := 3 # Includes the initial request.
const REQUEST_TIMEOUT_SECONDS := 12.0
var base_url := ""
var transport := Callable() # Existing domain-level fixtures; raw HTTP tests override _perform_http_request.
var _epoch := 0
var _request_sequence := 0
var _active: Array[HTTPRequest] = []
var _backoffs: Array[Timer] = []

static func valid_base(url: String) -> bool:
	return url.begins_with("https://") and url.length() > 8 and not "@" in url and not "?" in url and not "#" in url

func request(path: String, expected_sha256 := "") -> Dictionary:
	var epoch := _epoch
	var origin := base_url.trim_suffix("/") # Retries cannot drift to a later configuration.
	if not valid_base(origin) or not path.begins_with("/") or ".." in path or "?" in path or "#" in path:
		return {"ok":false,"code":"configuration"}
	if transport.is_valid():
		var value: Dictionary = await transport.call(path)
		return value if epoch == _epoch else {"ok":false,"code":"superseded"}
	_request_sequence += 1
	var request_id := _request_sequence
	var limit := MAX_ATTEMPTS if _retry_resource(path) != "other" else 1
	for attempt in range(1, limit + 1):
		if epoch != _epoch: return {"ok":false,"code":"superseded"}
		var reply: Dictionary = await _perform_http_request(origin + path, epoch)
		if epoch != _epoch or reply.get("cancelled", false): return {"ok":false,"code":"superseded"}
		var decoded := _decode_reply(reply, expected_sha256)
		var retry: bool = decoded.retryable and attempt < limit
		var delay := _retry_delay(attempt) if retry else 0.0
		var details := {"request": request_id, "resource": _retry_resource(path), "attempt": attempt,
			"result": int(reply.get("result", -1)), "status": int(reply.get("status", 0)),
			"start_error": int(reply.get("start_error", OK)),
			"code": decoded.code, "retry": retry, "delay_ms": int(delay * 1000)}
		# Bounded diagnostics: no URL, parcel ID, response body, credentials or coordinates.
		print("DYNAMIC_HTTP_ATTEMPT ", JSON.stringify(details))
		attempt_finished.emit(details.duplicate(true))
		if epoch != _epoch: return {"ok":false,"code":"superseded"}
		if not retry: return decoded.value
		if not await _wait_backoff(delay, epoch): return {"ok":false,"code":"superseded"}
	return {"ok":false,"code":"network"}

static func _retry_resource(path: String) -> String:
	if path == "/client-manifest.json": return "client_manifest"
	if path in ["/catalog.json", "/parcel-catalog.json"]: return "catalog"
	if path.begins_with("/farms/") and path.ends_with(".json"): return "farm"
	return "other"

func _retry_delay(failed_attempt: int) -> float:
	return 0.5 * pow(2.0, failed_attempt - 1) * randf_range(0.75, 1.25)

func _wait_backoff(seconds: float, epoch: int) -> bool:
	if epoch != _epoch: return false
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(timer)
	_backoffs.append(timer)
	timer.start(seconds)
	await timer.timeout
	_backoffs.erase(timer)
	timer.queue_free()
	return epoch == _epoch

func _configure_request(http: HTTPRequest) -> void:
	http.timeout = REQUEST_TIMEOUT_SECONDS
	http.body_size_limit = 2 * 1024 * 1024
	http.max_redirects = 0

func _perform_http_request(url: String, epoch: int) -> Dictionary:
	var http := HTTPRequest.new()
	_configure_request(http)
	add_child(http)
	_active.append(http)
	var error := http.request(url, PackedStringArray(["Accept: application/json"]))
	if error != OK:
		_active.erase(http); http.queue_free()
		return {"start_error": error}
	var reply: Array = await http.request_completed
	_active.erase(http); http.queue_free()
	if epoch != _epoch: return {"cancelled":true}
	return {"result": int(reply[0]), "status": int(reply[1]), "body": reply[3]}

static func _failure(code: String, retryable: bool) -> Dictionary:
	return {"value":{"ok":false,"code":code}, "code":code, "retryable":retryable}

static func _decode_reply(reply: Dictionary, expected_sha256: String) -> Dictionary:
	if reply.has("start_error"):
		return _failure("network" if reply.start_error == ERR_CANT_CONNECT else "request_setup", reply.start_error == ERR_CANT_CONNECT)
	var result := int(reply.get("result", HTTPRequest.RESULT_REQUEST_FAILED))
	if result != HTTPRequest.RESULT_SUCCESS:
		var transient := result in [HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH,
			HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE,
			HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR,
			HTTPRequest.RESULT_NO_RESPONSE, HTTPRequest.RESULT_TIMEOUT]
		return _failure("network" if transient else "invalid_response", transient)
	var status := int(reply.get("status", 0))
	if status >= 500 and status <= 599: return _failure("server", true)
	if status != 200: return _failure("http", false)
	var bytes: PackedByteArray = reply.get("body", PackedByteArray())
	if not expected_sha256.is_empty():
		var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
		if hash.finish().hex_encode() != expected_sha256: return _failure("integrity", false)
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return _failure("invalid_response", false)
	# Domain/schema validation belongs to the caller. A valid JSON contract failure must never trigger transport retries.
	return {"value":parser.data, "code":"json_received", "retryable":false}

func cancel_all() -> void:
	_epoch += 1
	var timers := _backoffs.duplicate()
	_backoffs.clear()
	for timer in timers:
		if not is_instance_valid(timer): continue
		timer.stop()
		timer.timeout.emit()
	var requests := _active.duplicate()
	_active.clear()
	for http in requests:
		if not is_instance_valid(http): continue
		http.cancel_request()
		# Wake our awaiting operation; epoch rejection happens before any consumer sees a payload.
		http.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())
