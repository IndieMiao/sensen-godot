extends GdUnitTestSuite
## C2 接线：登录后问权限 → 拿到 token 才报服务端；重复 token 不重复打接口；
## 登出把 token 从服务端撤掉；插件缺席（桌面）整条空转。

class FakeBridge extends PushBridge:
	var can := true
	var asked := 0
	var registered_calls := 0
	var plat := "ios"
	func available() -> bool:
		return can
	func request_authorization() -> void:
		asked += 1
	func register_for_remote() -> void:
		registered_calls += 1
	func platform() -> String:
		return plat

var t: FakeTransport
var api: PushApi
var bridge: FakeBridge

func before_test() -> void:
	UiState.clear()
	t = FakeTransport.new([])
	api = PushApi.new(ApiClient.new("https://example.test/v1", t.callable()))
	bridge = FakeBridge.new()

func after_test() -> void:
	UiState.clear()

func _svc() -> PushService:
	return PushService.new(bridge, api)

func test_no_bridge_means_nothing_happens() -> void:
	var svc := PushService.new(null, api)
	assert_bool(svc.usable()).is_false()
	svc.start() # 不该炸
	assert_int(t.requests.size()).is_equal(0)

func test_unavailable_platform_does_not_ask_for_permission() -> void:
	bridge.can = false
	var svc := _svc()
	assert_bool(svc.usable()).is_false()
	svc.start()
	assert_int(bridge.asked).is_equal(0)

## 授权拿到才注册远程推送；被拒就到此为止，不去打服务端。
func test_permission_gates_registration() -> void:
	var svc := _svc()
	svc.start()
	assert_int(bridge.asked).is_equal(1)
	var denied: Array = []
	svc.on_error = func(code: String): denied.append(code)
	bridge.authorization.emit(false)
	assert_int(bridge.registered_calls).is_equal(0)
	assert_array(denied).is_equal(["PUSH_DENIED"])
	bridge.authorization.emit(true)
	assert_int(bridge.registered_calls).is_equal(1)

func test_token_is_reported_once_and_remembered() -> void:
	t.responses = [{"status": 200, "json": {"ok": true}}]
	var svc := _svc()
	var seen: Array = []
	svc.registered.connect(func(tok: String): seen.append(tok))
	assert_bool(await svc.report("apns-token-abc")).is_true()
	assert_int(t.requests.size()).is_equal(1)
	assert_bool(str(t.requests[0].url).ends_with("/devices")).is_true()
	assert_str(str(t.requests[0].body["platform"])).is_equal("ios")
	assert_array(seen).is_equal(["apns-token-abc"])
	# 同一个 token 再来一次：不打服务端。
	assert_bool(await svc.report("apns-token-abc")).is_true()
	assert_int(t.requests.size()).is_equal(1)

func test_failed_report_is_not_remembered_and_surfaces_the_code() -> void:
	t.responses = [{"status": 0, "error": "offline"}]
	var svc := _svc()
	var errors: Array = []
	svc.on_error = func(code: String): errors.append(code)
	assert_bool(await svc.report("apns-token-abc")).is_false()
	assert_array(errors).is_equal(["NETWORK"])
	# 没记住：下次还会重报（游标只前进，补一条响应而不是重置数组）。
	t.responses.append({"status": 200, "json": {"ok": true}})
	assert_bool(await svc.report("apns-token-abc")).is_true()

func test_sign_out_unregisters_the_saved_token() -> void:
	t.responses = [{"status": 200, "json": {"ok": true}}, {"status": 200, "json": {"ok": true}}]
	var svc := _svc()
	assert_bool(await svc.report("apns-token-abc")).is_true()
	await svc.stop()
	assert_int(t.requests.size()).is_equal(2)
	assert_str(str(t.requests[1].method)).is_equal("DELETE")
	assert_str(str(t.requests[1].body["token"])).is_equal("apns-token-abc")
	# 撤掉之后不再记得它：换账号登录会重新报一遍。
	await svc.stop()
	assert_int(t.requests.size()).is_equal(2)
