extends GdUnitTestSuite
## E4：错误上报只在配了 DSN 时发；内容过脱敏；面包屑有上限。

class Sink extends RefCounted:
	var calls: Array = []
	func send(url: String, headers: PackedStringArray, body: String) -> ApiClient.Response:
		calls.append({"url": url, "headers": headers, "body": JSON.parse_string(body)})
		return ApiClient.Response.new(true, 200, {}, "")

const DSN := "https://abc123@o1.ingest.test/42"

func test_disabled_without_dsn() -> void:
	var r := ErrorReports.new("", Callable())
	assert_bool(r.enabled()).is_false()
	assert_bool(await r.capture("boom")).is_false()
	r.breadcrumb("nav", "map")
	assert_array(r.breadcrumbs).is_empty()

func test_dsn_parsing() -> void:
	var got := ErrorReports.parse_dsn(DSN)
	assert_str(str(got["url"])).is_equal("https://o1.ingest.test/api/42/store/")
	assert_str(str(got["key"])).is_equal("abc123")
	assert_bool(ErrorReports.parse_dsn("not a dsn").is_empty()).is_true()

func test_event_is_scrubbed_and_carries_auth_header() -> void:
	var sink := Sink.new()
	var r := ErrorReports.new(DSN, sink.send)
	r.breadcrumb("im", "sent to qa-alice@sensen.test", {"conversation_id": "c1", "text": "秘密"})
	assert_bool(await r.capture("send failed at 31.2304,121.4737", {"code": "BLOCKED", "lat": 31.2})).is_true()
	var body: Dictionary = sink.calls[0]["body"]
	assert_str(str(body["message"])).is_equal("send failed at %s" % Scrub.REDACTED)
	assert_str(str((body["extra"] as Dictionary)["code"])).is_equal("BLOCKED")
	assert_str(str((body["extra"] as Dictionary)["lat"])).is_equal(Scrub.REDACTED)
	var crumb: Dictionary = ((body["breadcrumbs"] as Dictionary)["values"] as Array)[0]
	assert_str(str(crumb["message"])).is_equal("sent to %s" % Scrub.REDACTED)
	assert_str(str((crumb["data"] as Dictionary)["text"])).is_equal(Scrub.REDACTED)
	var auth := ""
	for h in (sink.calls[0]["headers"] as PackedStringArray):
		if str(h).begins_with("x-sentry-auth"):
			auth = str(h)
	assert_bool(auth.contains("sentry_key=abc123")).is_true()

func test_breadcrumbs_are_capped() -> void:
	var r := ErrorReports.new(DSN, Callable())
	for i in 40:
		r.breadcrumb("nav", "step %d" % i)
	assert_int(r.breadcrumbs.size()).is_equal(ErrorReports.MAX_BREADCRUMBS)
	assert_str(str(r.breadcrumbs[-1]["message"])).is_equal("step 39")

func test_api_failure_drops_the_query_string() -> void:
	var sink := Sink.new()
	var r := ErrorReports.new(DSN, sink.send)
	assert_bool(await r.capture_api_failure("GET", "https://api.test/v1/feed?cursor=abc", 500, "SERVER")).is_true()
	var body: Dictionary = sink.calls[0]["body"]
	assert_bool(str(body["message"]).contains("cursor=abc")).is_false()
	assert_str(str(body["level"])).is_equal("error")
	assert_str(str((body["extra"] as Dictionary)["url"])).is_equal("https://api.test/v1/feed?[redacted]")
