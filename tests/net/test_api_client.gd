extends GdUnitTestSuite
## ApiClient：URL 拼装、鉴权头、install_key 持久化。

func _client(t: FakeTransport) -> ApiClient:
	return ApiClient.new("https://example.test/v1", t.callable())

func test_prefixes_base_url_and_sends_json() -> void:
	var t := FakeTransport.new([{"status": 200, "json": {"ok": true}}])
	var r: ApiClient.Response = await _client(t).request("POST", "/farms", {"region_id": "hk"})
	assert_bool(r.is_success()).is_true()
	assert_str(t.requests[0].url).is_equal("https://example.test/v1/farms")
	assert_str(t.requests[0].body.region_id).is_equal("hk")

func test_omits_auth_header_until_token_set() -> void:
	var t := FakeTransport.new([{"status": 200}, {"status": 200}])
	var c := _client(t)
	await c.request("GET", "/farms/me")
	c.token = "abc"
	await c.request("GET", "/farms/me")
	assert_bool(str(t.requests[0].headers).contains("authorization")).is_false()
	assert_bool(str(t.requests[1].headers).contains("Bearer abc")).is_true()

func test_non_2xx_is_transport_ok_but_not_success() -> void:
	var t := FakeTransport.new([{"status": 409, "json": {"code": "VERSION_CONFLICT"}}])
	var r: ApiClient.Response = await _client(t).request("POST", "/x", {})
	assert_bool(r.ok).is_true()
	assert_bool(r.is_success()).is_false()
	assert_int(r.status).is_equal(409)

func test_transport_failure_reports_error() -> void:
	var t := FakeTransport.new([{"error": "timeout"}])
	var r: ApiClient.Response = await _client(t).request("GET", "/x")
	assert_bool(r.ok).is_false()
	assert_str(r.error).is_equal("timeout")

func test_missing_transport_does_not_crash() -> void:
	var r: ApiClient.Response = await ApiClient.new("https://example.test/v1").request("GET", "/x")
	assert_bool(r.ok).is_false()

func test_install_key_is_128_bit_hex_and_stable() -> void:
	# 换一次会话（重新读文件）必须拿到同一把钥匙，否则玩家每次启动都是新账号。
	DirAccess.remove_absolute(ApiClient.INSTALL_KEY_PATH)
	var first := ApiClient.install_key()
	assert_int(first.length()).is_equal(32)
	assert_bool(first.is_valid_hex_number()).is_true()
	assert_str(ApiClient.install_key()).is_equal(first)
	DirAccess.remove_absolute(ApiClient.INSTALL_KEY_PATH)
	assert_str(ApiClient.install_key()).is_not_equal(first)
	DirAccess.remove_absolute(ApiClient.INSTALL_KEY_PATH)

# ---- A1：token 注入 / 401 刷新重试 / 幂等重试 / 错误码 ----
# 可变状态放在 AuthStub 里：GDScript lambda 按值捕获局部变量，闭包里的赋值改不到外面。

class AuthStub extends RefCounted:
	var tok := ""
	var refreshes := 0
	var recover := true

	func token() -> String:
		return tok

	func refresh() -> bool:
		refreshes += 1
		if recover:
			tok = "new"
		return recover

func test_token_provider_wins_over_static_token_when_non_empty() -> void:
	var t := FakeTransport.new([{"status": 200}, {"status": 200}])
	var c := _client(t)
	c.token = "static"
	var auth := AuthStub.new()
	c.token_provider = auth.token
	await c.request("GET", "/x")
	assert_bool(str(t.requests[0].headers).contains("Bearer static")).is_true()
	auth.tok = "fresh"
	await c.request("GET", "/x")
	assert_bool(str(t.requests[1].headers).contains("Bearer fresh")).is_true()

func test_401_triggers_one_refresh_then_retries_with_new_token() -> void:
	var t := FakeTransport.new([{"status": 401, "json": {"code": "UNAUTHENTICATED"}}, {"status": 200, "json": {"ok": true}}])
	var c := _client(t)
	var auth := AuthStub.new()
	auth.tok = "old"
	c.token_provider = auth.token
	c.on_unauthorized = auth.refresh
	var r: ApiClient.Response = await c.request("GET", "/me")
	assert_bool(r.is_success()).is_true()
	assert_int(auth.refreshes).is_equal(1)
	assert_int(t.requests.size()).is_equal(2)
	assert_bool(str(t.requests[0].headers).contains("Bearer old")).is_true()
	assert_bool(str(t.requests[1].headers).contains("Bearer new")).is_true()

func test_401_without_recovery_is_returned_as_is() -> void:
	var t := FakeTransport.new([{"status": 401, "json": {"code": "UNAUTHENTICATED"}}, {"status": 401}])
	var c := _client(t)
	var auth := AuthStub.new()
	auth.recover = false
	c.on_unauthorized = auth.refresh
	var r: ApiClient.Response = await c.request("GET", "/me")
	assert_int(r.status).is_equal(401)
	assert_int(auth.refreshes).is_equal(1)
	assert_int(t.requests.size()).is_equal(1)
	assert_str(r.code()).is_equal("UNAUTHENTICATED")

func test_idempotent_request_retries_transport_failures_with_same_key() -> void:
	var t := FakeTransport.new([{"error": "timeout"}, {"error": "timeout"}, {"status": 201, "json": {"id": "m1"}}])
	var c := _client(t)
	c.retry_delay_s = 0.0
	var r: ApiClient.Response = await c.request_idempotent("POST", "/messages", {"text": "hi"}, "k-123")
	assert_bool(r.is_success()).is_true()
	assert_int(t.requests.size()).is_equal(3)
	for req in t.requests:
		assert_bool(str(req.headers).contains("idempotency-key: k-123")).is_true()

func test_idempotent_request_does_not_retry_business_failures() -> void:
	var t := FakeTransport.new([{"status": 409, "json": {"code": "DUPLICATE"}}, {"status": 200}])
	var c := _client(t)
	c.retry_delay_s = 0.0
	var r: ApiClient.Response = await c.request_idempotent("POST", "/messages", {}, "k-1")
	assert_int(r.status).is_equal(409)
	assert_int(t.requests.size()).is_equal(1)

func test_idempotent_request_gives_up_after_max_attempts_and_generates_key() -> void:
	var t := FakeTransport.new([{"error": "down"}, {"error": "down"}])
	var c := _client(t)
	c.retry_delay_s = 0.0
	var r: ApiClient.Response = await c.request_idempotent("POST", "/messages", {}, "", 2)
	assert_bool(r.ok).is_false()
	assert_int(t.requests.size()).is_equal(2)
	var h0 := str(t.requests[0].headers)
	assert_bool(h0.contains("idempotency-key: ")).is_true()
	assert_str(h0).is_equal(str(t.requests[1].headers))
	assert_int(ApiClient.new_idempotency_key().length()).is_equal(32)

func test_response_code_mapping() -> void:
	assert_str(ApiClient.Response.new(false, 0, {}, "timeout").code()).is_equal("timeout")
	assert_str(ApiClient.Response.new(false, 0, {}, "").code()).is_equal("TRANSPORT")
	assert_str(ApiClient.Response.new(true, 422, {"code": "INVALID"}).code()).is_equal("INVALID")
	assert_str(ApiClient.Response.new(true, 503, {}).code()).is_equal("HTTP_503")
