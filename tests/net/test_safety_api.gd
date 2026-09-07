extends GdUnitTestSuite
## SafetyApi：举报 / 拉黑 / 解除 / 列表的路径与请求体。

class TokenBox extends RefCounted:
	func get_token() -> String:
		return "id-1"

var box: TokenBox

func before_test() -> void:
	box = TokenBox.new()

func _api(t: FakeTransport) -> SafetyApi:
	var c := ApiClient.new("https://example.test/v1", t.callable())
	c.token_provider = box.get_token
	return SafetyApi.new(c)

func test_report_block_unblock_and_list_routes() -> void:
	var t := FakeTransport.new([
		{"status": 201, "json": {"id": "r1", "created": true, "auto_hidden": false}},
		{"status": 200, "json": {"ok": true, "created": true}},
		{"status": 200, "json": {"ok": true, "removed": true}},
		{"status": 200, "json": {"items": [{"user_id": "u-2"}]}},
	])
	var api := _api(t)
	assert_bool((await api.report("post", "p1", "spam", " ads ")).created).is_true()
	assert_bool((await api.block("u-2")).created).is_true()
	assert_bool((await api.unblock("u-2")).removed).is_true()
	assert_int((await api.blocks()).items.size()).is_equal(1)
	assert_str(t.requests[0].method).is_equal("POST")
	assert_bool(str(t.requests[0].url).ends_with("/v1/reports")).is_true()
	assert_that(t.requests[0].body).is_equal({"target_type": "post", "target_id": "p1", "reason": "spam", "detail": " ads "})
	assert_str(t.requests[1].method).is_equal("PUT")
	assert_bool(str(t.requests[1].url).ends_with("/v1/users/u-2/block")).is_true()
	assert_str(t.requests[2].method).is_equal("DELETE")
	assert_bool(str(t.requests[3].url).ends_with("/v1/users/me/blocks")).is_true()

func test_report_without_detail_omits_field_and_reasons_match_server() -> void:
	var t := FakeTransport.new([{"status": 201, "json": {"id": "r1"}}])
	await _api(t).report("user", "u-9", "minor_safety")
	assert_bool(t.requests[0].body.has("detail")).is_false()
	assert_int(SafetyApi.REASONS.size()).is_equal(8)
	assert_bool(SafetyApi.REASONS.has("other")).is_true()
