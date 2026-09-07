extends GdUnitTestSuite
## AccountApi：五条请求的方法 / 路径 / Bearer，以及 {ok, status, code, reason} 的统一包装。

class TokenBox extends RefCounted:
	var token := "id-1"
	func get_token() -> String:
		return token

## Callable 不会持有 RefCounted：TokenBox 必须挂在套件变量上，否则 token_provider 立刻失效。
var box: TokenBox

func before_test() -> void:
	box = TokenBox.new()

func _api(t: FakeTransport) -> AccountApi:
	var c := ApiClient.new("https://example.test/v1", t.callable())
	c.token_provider = box.get_token
	return AccountApi.new(c)

func _has_bearer(headers: PackedStringArray, token: String) -> bool:
	for h in headers:
		if str(h).contains("Bearer %s" % token):
			return true
	return false

func test_sign_in_posts_with_bearer_and_unwraps_created_user() -> void:
	var t := FakeTransport.new([{"status": 201, "json": {"user_id": "u-1", "created": true, "email": "a@b.co"}}])
	var r: Dictionary = await _api(t).sign_in()
	assert_bool(r.ok).is_true()
	assert_int(r.status).is_equal(201)
	assert_str(r.user_id).is_equal("u-1")
	assert_bool(r.created).is_true()
	assert_str(t.requests[0].method).is_equal("POST")
	assert_bool(str(t.requests[0].url).ends_with("/v1/auth/firebase")).is_true()
	assert_bool(_has_bearer(t.requests[0].headers, "id-1")).is_true()

func test_me_delete_and_export_use_the_documented_routes() -> void:
	var t := FakeTransport.new([
		{"status": 200, "json": {"user_id": "u-1"}},
		{"status": 200, "json": {"ok": true, "deleted": true}},
		{"status": 200, "json": {"account": {"user_id": "u-1"}, "modules": {}}},
	])
	var api := _api(t)
	assert_str((await api.me()).user_id).is_equal("u-1")
	assert_bool((await api.delete_account()).deleted).is_true()
	assert_that((await api.export_data()).modules).is_equal({})
	assert_str(t.requests[0].method).is_equal("GET")
	assert_bool(str(t.requests[0].url).ends_with("/v1/users/me")).is_true()
	assert_str(t.requests[1].method).is_equal("DELETE")
	assert_bool(str(t.requests[1].url).ends_with("/v1/users/me")).is_true()
	assert_bool(str(t.requests[2].url).ends_with("/v1/users/me/export")).is_true()

func test_server_error_carries_code_reason_and_status() -> void:
	var t := FakeTransport.new([
		{"status": 500, "json": {"code": "DELETE_FAILED"}},
		{"status": 404, "json": {"message": "Route DELETE:/v1/users/me not found"}},
		{"status": 503, "json": {"code": "ACCOUNTS_NOT_CONFIGURED"}},
	])
	var api := _api(t)
	var a: Dictionary = await api.delete_account()
	assert_bool(a.ok).is_false()
	assert_str(a.code).is_equal("DELETE_FAILED")
	assert_int(a.status).is_equal(500)
	var b: Dictionary = await api.delete_account()
	assert_str(b.code).is_equal("HTTP_404") # 老服务器没这条路由：Fastify 的 404 没有 code 字段
	assert_int(b.status).is_equal(404)
	assert_str((await api.me()).code).is_equal("ACCOUNTS_NOT_CONFIGURED")

func test_transport_failure_is_network_with_reason() -> void:
	var r: Dictionary = await _api(FakeTransport.new([{"error": "timeout"}])).sign_in()
	assert_bool(r.ok).is_false()
	assert_str(r.code).is_equal("NETWORK")
	assert_str(r.reason).is_equal("timeout")
	assert_int(r.status).is_equal(0)
