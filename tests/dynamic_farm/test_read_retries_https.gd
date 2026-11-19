extends SceneTree
class LocalApi extends "res://modules/dynamic_farm/map/geo_api.gd":
	var certificate: X509Certificate
	var short_timeout := false
	var fast_backoff := false
	func _configure_request(http: HTTPRequest) -> void:
		super._configure_request(http)
		http.set_tls_options(TLSOptions.client(certificate))
		if short_timeout: http.timeout = 0.25
	func _retry_delay(failed_attempt: int) -> float:
		return 0.01 if fast_backoff else super._retry_delay(failed_attempt)
var checks := 0
var failures := 0
var pending_result: Dictionary = {}
var attempts: Array = []
func _initialize() -> void: _run.call_deferred()
func verify(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)
func capture(row: Dictionary) -> void: attempts.append(row)
func pending(api: LocalApi) -> void: pending_result = await api.request("/farms/p-slow.json")
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3: printerr("Expected localhost HTTPS origin, test CA, unrelated CA"); quit(1); return
	var cert := X509Certificate.new(); var other := X509Certificate.new()
	if cert.load(args[1]) != OK or other.load(args[2]) != OK: quit(1); return
	var api := LocalApi.new(); api.certificate = cert; api.base_url = args[0]; root.add_child(api)
	api.attempt_finished.connect(capture)
	var started := Time.get_ticks_msec()
	var result: Dictionary = await api.request("/client-manifest.json", '{"value":"ok"}'.sha256_text())
	verify(result.get("value") == "ok" and attempts.size() == 3, "actual TLS HTTP 503/503/200 recovers in exactly three attempts")
	verify(attempts.map(func(row: Dictionary): return row.status) == [503, 503, 200], "actual HTTP status evidence matches the server sequence")
	var backoff_ms: int = attempts[0].delay_ms + attempts[1].delay_ms
	verify(attempts[0].delay_ms >= 375 and attempts[0].delay_ms <= 625 and attempts[1].delay_ms >= 750 and attempts[1].delay_ms <= 1250 and Time.get_ticks_msec() - started >= backoff_ms - 60, "real HTTPS recovery waits through production exponential jitter intervals")
	api.fast_backoff = true
	attempts.clear(); result = await api.request("/parcel-catalog.json")
	verify(result.get("code") == "http" and attempts.size() == 1 and attempts[0].status == 404, "private catalog 404 is terminal over actual HTTPS")
	attempts.clear(); result = await api.request("/farms/p-hash.json", '{"value":"ok"}'.sha256_text())
	verify(result.get("code") == "integrity" and attempts.size() == 1, "actual HTTPS hash mismatch does not retry")
	attempts.clear(); result = await api.request("/farms/p-invalid.json")
	verify(result.get("code") == "invalid_response" and attempts.size() == 1, "actual HTTPS invalid JSON does not retry")
	attempts.clear(); result = await api.request("/farms/p-exhaust.json")
	verify(result.get("code") == "server" and attempts.size() == 3, "actual persistent 502 ends after three requests")
	attempts.clear(); pending(api)
	await create_timer(0.05).timeout
	verify(api._active.size() == 1, "real delayed HTTPS request is in flight before cancellation")
	api.cancel_all(); await process_frame
	verify(pending_result.get("code") == "superseded" and api._active.is_empty() and api._backoffs.is_empty(), "cancelling a real HTTPRequest retires it without retry")
	result = await api.request("/farms/p-replacement.json")
	verify(result.get("value") == "ok", "replacement request succeeds after cancelling a real request")
	attempts.clear(); api.short_timeout = true
	result = await api.request("/farms/p-timeout.json")
	verify(result.get("code") == "network" and attempts.size() == 3, "real timeout is retried but bounded")
	verify(attempts.all(func(row: Dictionary): return row.result == HTTPRequest.RESULT_TIMEOUT), "all timeout attempts preserve their actual transport result")
	attempts.clear(); api.short_timeout = false; api.certificate = other
	result = await api.request("/farms/p-untrusted.json")
	verify(result.get("code") == "network" and attempts.size() == 3, "actual TLS verification failure is bounded and never bypasses certificate checks")
	verify(attempts.all(func(row: Dictionary): return row.result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR), "TLS failure is distinct from HTTP status")
	api.queue_free(); await process_frame
	print("DYNAMIC HTTPS RETRIES ", checks - failures, "/", checks)
	quit(1 if failures else 0)
