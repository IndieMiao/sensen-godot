extends SceneTree
const Api := preload("res://modules/dynamic_farm/map/geo_api.gd")
const Controller := preload("res://modules/dynamic_farm/map/selection_controller.gd")
const Fixture := preload("res://tests/dynamic_farm/selection_fixtures.gd")

class ScriptedApi extends "res://modules/dynamic_farm/map/geo_api.gd":
	var responses: Array = []
	var urls: Array[String] = []
	var delay := 0.001
	func _perform_http_request(url: String, _epoch_value: int) -> Dictionary:
		urls.append(url)
		return responses.pop_front() if not responses.is_empty() else {"result":HTTPRequest.RESULT_TIMEOUT,"status":0}
	func _retry_delay(_failed_attempt: int) -> float: return delay

class Native extends MapBridge:
	func supports_parcels() -> bool: return true

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func success(body := '{"value":7}') -> Dictionary:
	return {"result":HTTPRequest.RESULT_SUCCESS,"status":200,"body":body.to_utf8_buffer()}

func make_api(responses: Array) -> ScriptedApi:
	var api := ScriptedApi.new(); api.base_url = "https://fixture.invalid"; api.responses = responses
	root.add_child(api)
	return api

func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	return hash.finish().hex_encode()

func _run() -> void:
	var api := make_api([{ "result":HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR,"status":0}, {"result":0,"status":503}, success()])
	var attempts: Array = []
	api.attempt_finished.connect(func(row: Dictionary): attempts.append(row))
	var result: Dictionary = await api.request("/client-manifest.json", digest('{"value":7}'.to_utf8_buffer()))
	verify(result.get("value") == 7 and api.urls.size() == 3, "TLS then 503 recover within three total attempts with pin enforced")
	verify(attempts.size() == 3 and attempts[0].retry and attempts[1].retry and not attempts[2].retry, "attempt evidence records transient decisions and final success")
	verify(attempts[0].result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR and attempts[1].status == 503, "TLS result and HTTP status remain distinct")
	api.queue_free()
	for path in ["/client-manifest.json", "/catalog.json", "/parcel-catalog.json", "/farms/p-4591A011*.json"]:
		api = make_api([{ "result":HTTPRequest.RESULT_TIMEOUT,"status":0}, {"result":HTTPRequest.RESULT_CONNECTION_ERROR,"status":0}, {"result":0,"status":502}, success()])
		result = await api.request(path)
		verify(result.get("ok") == false and api.urls.size() == 3 and api.responses.size() == 1, "retry budget stops at three total attempts: " + path)
		api.queue_free()
	for status in [301, 400, 401, 403, 404, 408, 429]:
		api = make_api([{ "result":0,"status":status}, success()])
		result = await api.request("/client-manifest.json")
		verify(api.urls.size() == 1 and result.get("code") == "http", "non-5xx HTTP is terminal: " + str(status))
		api.queue_free()
	for code in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, HTTPRequest.RESULT_NO_RESPONSE, HTTPRequest.RESULT_TIMEOUT, HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH]:
		api = make_api([{ "result":code,"status":0}, success()])
		result = await api.request("/farms/p-A.json")
		verify(api.urls.size() == 2 and result.get("value") == 7, "temporary transport error retries: " + str(code))
		api.queue_free()
	for code in [HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED, HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED, HTTPRequest.RESULT_REQUEST_FAILED]:
		api = make_api([{ "result":code,"status":0}, success()])
		result = await api.request("/client-manifest.json")
		verify(api.urls.size() == 1 and result.get("ok") == false, "size/decode/redirect/unclassified failure is terminal: " + str(code))
		api.queue_free()
	api = make_api([success(), success()])
	result = await api.request("/client-manifest.json", "0".repeat(64))
	verify(result.get("code") == "integrity" and api.urls.size() == 1, "hash mismatch never retries")
	api.queue_free()
	for body in ["not json", "[]", "null"]:
		api = make_api([success(body), success()])
		result = await api.request("/client-manifest.json")
		verify(result.get("code") == "invalid_response" and api.urls.size() == 1, "malformed or wrong top-level JSON never retries: " + body)
		api.queue_free()
	api = make_api([success('{"ok":false,"code":"network","retryable":true}'), success()])
	result = await api.request("/farms/p-A.json")
	verify(api.urls.size() == 1, "server JSON cannot forge the transport retry decision")
	api.queue_free()
	var wrong_contract := Fixture.manifest(); wrong_contract.schema = 3
	api = make_api([success(JSON.stringify(wrong_contract)), success(JSON.stringify(Fixture.manifest()))])
	var controller := Controller.new(); controller.api = api; controller.bridge = Native.new()
	controller.config = {"dataset_version":Fixture.C.DATASET,"base_url":"https://fixture.invalid","manifest_sha256":digest(JSON.stringify(wrong_contract).to_utf8_buffer())}
	root.add_child(controller); await controller.activate()
	verify(api.urls.size() == 1 and not controller.map_ready and controller.message.contains("Could not load"), "a pinned but invalid manifest contract is rejected once by the real caller")
	controller.queue_free(); await process_frame; api.queue_free()
	api = make_api([{ "result":0,"status":503}, success()])
	api.delay = 0.2
	api.attempt_finished.connect(func(row: Dictionary):
		if row.retry: create_timer(0.01).timeout.connect(api.cancel_all, CONNECT_ONE_SHOT))
	result = await api.request("/client-manifest.json")
	verify(result.get("code") == "superseded" and api.urls.size() == 1 and api._backoffs.is_empty(), "cancelling during backoff wakes and retires the chain before another HTTP request")
	result = await api.request("/farms/p-B.json")
	verify(result.get("value") == 7 and api.urls.size() == 2, "a new request after cancellation starts cleanly")
	await create_timer(0.25).timeout
	verify(api.urls.size() == 2, "retired backoff cannot fire after the replacement request")
	api.queue_free()
	api = make_api([{ "result":0,"status":503}, success()])
	api.attempt_finished.connect(func(row: Dictionary):
		if row.retry: api.base_url = "https://changed.invalid")
	result = await api.request("/farms/p-A.json")
	verify(api.urls == ["https://fixture.invalid/farms/p-A.json", "https://fixture.invalid/farms/p-A.json"], "all attempts use the original origin even when later configuration changes")
	api.queue_free()
	api = make_api([{ "result":0,"status":503}, success()])
	result = await api.request("/health")
	verify(api.urls.size() == 1, "unrelated endpoints do not silently gain retries")
	api.queue_free()
	api = make_api([{ "start_error":ERR_INVALID_PARAMETER}, success()])
	result = await api.request("/client-manifest.json")
	verify(api.urls.size() == 1 and result.get("code") == "request_setup", "invalid request setup does not retry")
	api.queue_free()
	var policy := Api.new()
	for sample in 10:
		var first: float = policy._retry_delay(1); var second: float = policy._retry_delay(2)
		verify(first >= 0.375 and first <= 0.625 and second >= 0.75 and second <= 1.25, "two bounded exponential backoff intervals include jitter " + str(sample))
	policy.free()
	await process_frame
	print("DYNAMIC READ RETRIES ", checks - failures, "/", checks)
	quit(1 if failures else 0)
