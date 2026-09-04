extends GdUnitTestSuite
## ApiClient：URL 拼装、鉴权头、install_key 持久化。

func _client(t: FakeTransport) -> ApiClient:
	return ApiClient.new("https://example.test/v1", t.callable())

func test_prefixes_base_url_and_sends_json() -> void:
	var t := FakeTransport.new([{"status": 200, "json": {"ok": true}}])
	var r := _client(t).request("POST", "/farms", {"region_id": "hk"})
	assert_bool(r.is_success()).is_true()
	assert_str(t.requests[0].url).is_equal("https://example.test/v1/farms")
	assert_str(t.requests[0].body.region_id).is_equal("hk")

func test_omits_auth_header_until_token_set() -> void:
	var t := FakeTransport.new([{"status": 200}, {"status": 200}])
	var c := _client(t)
	c.request("GET", "/farms/me")
	c.token = "abc"
	c.request("GET", "/farms/me")
	assert_bool(str(t.requests[0].headers).contains("authorization")).is_false()
	assert_bool(str(t.requests[1].headers).contains("Bearer abc")).is_true()

func test_non_2xx_is_transport_ok_but_not_success() -> void:
	var t := FakeTransport.new([{"status": 409, "json": {"code": "VERSION_CONFLICT"}}])
	var r := _client(t).request("POST", "/x", {})
	assert_bool(r.ok).is_true()
	assert_bool(r.is_success()).is_false()
	assert_int(r.status).is_equal(409)

func test_transport_failure_reports_error() -> void:
	var t := FakeTransport.new([{"error": "timeout"}])
	var r := _client(t).request("GET", "/x")
	assert_bool(r.ok).is_false()
	assert_str(r.error).is_equal("timeout")

func test_missing_transport_does_not_crash() -> void:
	var r := ApiClient.new("https://example.test/v1").request("GET", "/x")
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
