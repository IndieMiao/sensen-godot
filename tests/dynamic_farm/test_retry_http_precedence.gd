extends SceneTree
class ScriptedApi extends "res://modules/dynamic_farm/map/geo_api.gd":
	var calls := 0
	var status := 404
	func _perform_http_request(_url: String, _epoch_value: int) -> Dictionary:
		calls += 1
		return {"result":HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH,"status":status}
	func _retry_delay(_failed_attempt: int) -> float: return 0.001
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func _run() -> void:
	for status in [401, 403, 404, 429, 301]:
		var api := ScriptedApi.new(); api.base_url = "https://fixture.invalid"; api.status = status; root.add_child(api)
		var reply: Dictionary = await api.request("/client-manifest.json")
		verify(api.calls == 1 and reply.get("code") == "http", "known terminal HTTP wins over body mismatch: " + str(status))
		api.queue_free(); await process_frame
	for status in [0, 200, 503]:
		var api := ScriptedApi.new(); api.base_url = "https://fixture.invalid"; api.status = status; root.add_child(api)
		var reply: Dictionary = await api.request("/client-manifest.json")
		verify(api.calls == 3 and reply.get("ok") == false, "unknown/200/503 truncated response retains three-attempt budget: " + str(status))
		api.queue_free(); await process_frame
	print("DYNAMIC HTTP PRECEDENCE ", checks - failures, "/", checks)
	quit(1 if failures else 0)
