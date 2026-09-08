extends GdUnitTestSuite
## E5：埋点只在配了 key 且用户没关掉时发；属性过脱敏；事件名必须在白名单里。

class Sink extends RefCounted:
	var calls: Array = []
	var fail := false
	func send(url: String, _headers: PackedStringArray, body: String) -> ApiClient.Response:
		calls.append({"url": url, "body": JSON.parse_string(body)})
		return ApiClient.Response.new(not fail, 200 if not fail else 0, {}, "" if not fail else "offline")

func _a(key := "k") -> Analytics:
	return Analytics.new(key, "https://ph.test", Callable())

func test_disabled_without_key_or_when_opted_out() -> void:
	var off := _a("")
	assert_bool(off.enabled()).is_false()
	assert_bool(await off.capture("app_open", "u1")).is_false()
	assert_int(off.queue.size()).is_equal(0)
	var on := _a()
	assert_bool(on.enabled()).is_true()
	on.opted_out = true
	assert_bool(await on.capture("app_open", "u1")).is_false()
	assert_int(await on.flush()).is_equal(0)

func test_unknown_event_names_are_refused() -> void:
	var a := _a()
	assert_bool(await a.capture("random_thing", "u1")).is_false()
	assert_bool(await a.capture("message_sent", "u1")).is_true()

func test_properties_are_scrubbed_and_location_never_leaves() -> void:
	var a := _a()
	assert_bool(await a.capture("message_sent", "u1", {"conversation_id": "c1", "text": "见面聊", "lat": 31.2, "lng": 121.4})).is_true()
	var props: Dictionary = a.queue[0]["properties"]
	assert_str(str(props["conversation_id"])).is_equal("c1")
	assert_str(str(props["text"])).is_equal(Scrub.REDACTED)
	assert_str(str(props["lat"])).is_equal(Scrub.REDACTED)
	assert_str(str(props["lng"])).is_equal(Scrub.REDACTED)
	assert_str(str(a.queue[0]["distinct_id"])).is_equal("u1")

func test_flush_posts_a_batch_and_keeps_events_when_offline() -> void:
	var sink := Sink.new()
	var a := Analytics.new("k", "https://ph.test", sink.send)
	await a.capture("app_open", "u1")
	await a.capture("post_published", "u1", {"images": 2})
	assert_int(await a.flush()).is_equal(2)
	assert_str(str(sink.calls[0]["url"])).is_equal("https://ph.test/batch/")
	var body: Dictionary = sink.calls[0]["body"]
	assert_str(str(body["api_key"])).is_equal("k")
	assert_int((body["batch"] as Array).size()).is_equal(2)
	assert_int(a.queue.size()).is_equal(0)
	# 断网：事件退回队列，不丢。
	sink.fail = true
	await a.capture("content_reported", "u1")
	assert_int(await a.flush()).is_equal(0)
	assert_int(a.queue.size()).is_equal(1)
	assert_str(str(a.queue[0]["event"])).is_equal("content_reported")

func test_anonymous_id_when_signed_out() -> void:
	var a := _a()
	await a.capture("app_open", "")
	assert_str(str(a.queue[0]["distinct_id"])).is_equal("anonymous")

func test_opt_out_persists_through_ui_state() -> void:
	UiState.clear()
	assert_bool(Analytics.is_opted_out()).is_false()
	Analytics.set_opt_out(true)
	assert_bool(Analytics.is_opted_out()).is_true()
	var a := _a()
	a.load_opt_out()
	assert_bool(a.enabled()).is_false()
	Analytics.set_opt_out(false)
	a.load_opt_out()
	assert_bool(a.enabled()).is_true()
	UiState.clear()
