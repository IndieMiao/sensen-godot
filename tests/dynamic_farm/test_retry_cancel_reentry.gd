extends SceneTree
## Exercise real Timer/HTTPRequest signal reentry without opening a socket.
class DeferredApi extends "res://modules/dynamic_farm/map/geo_api.gd":
	var gave_transient := false
	var pending_http: Dictionary = {}
	func _retry_delay(_attempt: int) -> float: return 5.0
	func _perform_http_request(url: String, epoch: int) -> Dictionary:
		if url.ends_with("/p-old.json") and not gave_transient:
			gave_transient = true
			return {"result":0,"status":503}
		var http := HTTPRequest.new(); add_child(http); _active.append(http)
		pending_http[url.get_file()] = http
		var reply: Array = await http.request_completed
		_active.erase(http); http.queue_free()
		if epoch != _epoch: return {"cancelled":true}
		return {"result":reply[0],"status":reply[1],"body":reply[3]}
var checks := 0
var failures := 0
var old_result: Dictionary = {}
var replacement_result: Dictionary = {}
var earlier_inflight_result: Dictionary = {}
var replacement_started := false
func _initialize() -> void: _run.call_deferred()
func verify(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)
func cancelled_then_replace(api: DeferredApi) -> void:
	old_result = await api.request("/farms/p-old.json")
	# This continuation resumes synchronously inside cancel_all's Timer.timeout emission.
	replacement_started = true
	replacement_result = await api.request("/farms/p-new.json")
func earlier_inflight(api: DeferredApi) -> void:
	earlier_inflight_result = await api.request("/farms/p-earlier.json")
func _run() -> void:
	var api := DeferredApi.new(); api.base_url = "https://fixture.invalid"; root.add_child(api)
	cancelled_then_replace(api)
	earlier_inflight(api)
	await process_frame
	verify(api._backoffs.size() == 1 and api._active.size() == 1, "old timer and earlier in-flight request exist before cancellation")
	api.cancel_all()
	verify(old_result.get("code") == "superseded" and replacement_started, "cancelled timer wakes the old caller and starts its replacement")
	verify(earlier_inflight_result.get("code") == "superseded", "the original in-flight request is still retired")
	verify(replacement_result.is_empty() and api._active.size() == 1, "replacement created during cancel callback remains in flight")
	if api._active.size() == 1:
		api._active[0].request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"value":"new"}'.to_utf8_buffer())
	await process_frame
	verify(replacement_result.get("value") == "new", "replacement completes successfully instead of being cancelled with the old cohort")
	verify(api._active.is_empty() and api._backoffs.is_empty(), "all completed request and timer bookkeeping is released")
	api.queue_free(); await process_frame
	print("DYNAMIC RETRY CANCEL REENTRY ", checks - failures, "/", checks)
	quit(1 if failures else 0)
