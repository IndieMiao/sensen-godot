extends GdUnitTestSuite
## D7 客户端：设备 token 上报 / 注销。

func _api(t: FakeTransport) -> PushApi:
	return PushApi.new(ApiClient.new("https://example.test/v1", t.callable()))

func test_register_sends_token_and_platform() -> void:
	var t := FakeTransport.new([{"status": 200, "json": {"ok": true}}])
	var r: Dictionary = await _api(t).register("tok-abc-123", "ios")
	assert_bool(bool(r.get("ok", false))).is_true()
	assert_str(str(t.requests[0].method)).is_equal("PUT")
	assert_bool(str(t.requests[0].url).ends_with("/v1/devices")).is_true()
	assert_that(t.requests[0].body).is_equal({"token": "tok-abc-123", "platform": "ios"})

func test_unregister_sends_only_the_token() -> void:
	var t := FakeTransport.new([{"status": 200, "json": {"ok": true}}])
	assert_bool(bool((await _api(t).unregister("tok-abc-123")).get("ok", false))).is_true()
	assert_str(str(t.requests[0].method)).is_equal("DELETE")
	assert_that(t.requests[0].body).is_equal({"token": "tok-abc-123"})

func test_platform_is_empty_on_desktop() -> void:
	# 桌面没有推送通道：不猜一个平台名送上去，让服务端按 SCHEMA 拒掉。
	if OS.has_feature("ios") or OS.has_feature("android"):
		return
	assert_str(PushApi.default_platform()).is_empty()

func test_errors_carry_the_code() -> void:
	var t := FakeTransport.new([{"status": 503, "json": {"code": "PUSH_NOT_CONFIGURED"}}])
	var r: Dictionary = await _api(t).register("tok-abc-123", "android")
	assert_bool(bool(r.get("ok", false))).is_false()
	assert_str(str(r.get("code", ""))).is_equal("PUSH_NOT_CONFIGURED")
