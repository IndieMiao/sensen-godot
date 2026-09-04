extends GdUnitTestSuite
## FarmSession：登录、建/取农场、命令重试与 version 对账、离线态、服务端时钟。

func _session(responses: Array) -> Array:
	var t := FakeTransport.new(responses)
	return [FarmSession.new(ApiClient.new("https://example.test/v1", t.callable())), t]

func _state(version: int) -> Dictionary:
	return {"version": version, "farm_id": "f1", "state": {"wallet": 30}}

func test_login_stores_token_and_player() -> void:
	var pair := _session([{"status": 200, "json": {"player_id": "p1", "token": "tok"}}])
	var s: FarmSession = pair[0]
	assert_bool(s.login()).is_true()
	assert_str(s.player_id).is_equal("p1")
	assert_str(s.client.token).is_equal("tok")

func test_ensure_farm_adopts_existing() -> void:
	var pair := _session([{"status": 200, "json": _state(7)}])
	var s: FarmSession = pair[0]
	assert_bool(s.ensure_farm("hk", "patch", 2)).is_true()
	assert_int(s.version).is_equal(7)
	assert_int(int(s.state.wallet)).is_equal(30)

func test_ensure_farm_creates_when_404() -> void:
	var pair := _session([{"status": 404, "json": {}}, {"status": 200, "json": _state(1)}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	assert_bool(s.ensure_farm("hk", "patch_a", 2)).is_true()
	assert_int(s.version).is_equal(1)
	assert_str(t.requests[1].method).is_equal("POST")
	assert_str(t.requests[1].body.layout_patch_id).is_equal("patch_a")
	assert_int(int(t.requests[1].body.blueprint_revision)).is_equal(2)

func test_send_posts_base_version_and_adopts_new_version() -> void:
	var pair := _session([{"status": 200, "json": _state(4)},
		{"status": 200, "json": {"version": 5, "state": {"wallet": 28}}}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s.ensure_farm("hk", "p", 2)
	assert_bool(s.send("sow", {"cell": [3, 3]})).is_true()
	assert_int(int(t.requests[1].body.base_version)).is_equal(4)
	assert_str(t.requests[1].body.type).is_equal("sow")
	assert_int(s.version).is_equal(5)
	assert_int(int(s.state.wallet)).is_equal(28)

func test_send_retries_transport_failure_with_same_key() -> void:
	# 服务端幂等：同 key 重发不会双花，所以传输层失败原样重来是安全的。
	var pair := _session([{"status": 200, "json": _state(4)},
		{"error": "timeout"}, {"status": 200, "json": {"version": 5, "state": {}}}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s.ensure_farm("hk", "p", 2)
	assert_bool(s.send("water", {})).is_true()
	assert_str(t.requests[1].body.idempotency_key).is_equal(t.requests[2].body.idempotency_key)

func test_send_reconciles_on_version_conflict_with_fresh_key() -> void:
	# 409 回包带最新状态：先对账，再用**新** key 重发（同 key 换 base_version 会被判
	# IDEMPOTENCY_MISMATCH）。
	var pair := _session([{"status": 200, "json": _state(4)},
		{"status": 409, "json": {"code": "VERSION_CONFLICT", "version": 9, "state": {"wallet": 12}}},
		{"status": 200, "json": {"version": 10, "state": {"wallet": 10}}}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s.ensure_farm("hk", "p", 2)
	assert_bool(s.send("harvest", {})).is_true()
	assert_int(int(t.requests[2].body.base_version)).is_equal(9)
	assert_str(t.requests[2].body.idempotency_key).is_not_equal(t.requests[1].body.idempotency_key)
	assert_int(s.version).is_equal(10)

func test_rejected_command_emits_code() -> void:
	var pair := _session([{"status": 200, "json": _state(4)},
		{"status": 422, "json": {"code": "INSUFFICIENT_FUNDS", "detail": "need 8"}}])
	var s: FarmSession = pair[0]
	s.ensure_farm("hk", "p", 2)
	var seen := []
	s.rejected.connect(func(code, detail): seen.append([code, detail]))
	assert_bool(s.send("buy_seed", {})).is_false()
	assert_int(s.version).is_equal(4)
	assert_array(seen[0]).is_equal(["INSUFFICIENT_FUNDS", "need 8"])

func test_two_failures_flip_offline_and_one_success_flips_back() -> void:
	var pair := _session([{"error": "down"}, {"error": "down"}, {"status": 200, "json": _state(1)}])
	var s: FarmSession = pair[0]
	var flips := []
	s.offline_changed.connect(func(v): flips.append(v))
	assert_bool(s.refresh()).is_false()   # 1 次失败还不算离线
	assert_bool(s.offline).is_false()
	assert_bool(s.refresh()).is_false()   # 第 2 次翻牌
	assert_bool(s.offline).is_true()
	s.offline = false                     # 手动放行，验证成功回包会清掉离线
	assert_bool(s.refresh()).is_true()
	assert_bool(s.offline).is_false()
	assert_array(flips).is_equal([true])

func test_offline_send_is_refused_without_queueing() -> void:
	# 不排队离线命令：排队会让玩家以为操作生效，回来发现全被拒，比当场说离线更糟。
	var pair := _session([])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s.offline = true
	var seen := []
	s.rejected.connect(func(code, _d): seen.append(code))
	assert_bool(s.send("sow", {})).is_false()
	assert_int(t.requests.size()).is_equal(0)
	assert_array(seen).is_equal(["OFFLINE"])

func test_server_now_uses_offset_not_local_clock() -> void:
	# 本地时钟不可信：玩家改系统时间不该让作物提前熟。
	var future := int(Time.get_unix_time_from_system() * 1000.0) + 3_600_000
	var pair := _session([{"status": 200, "json": {"version": 1, "state": {}, "server_time": future}}])
	var s: FarmSession = pair[0]
	s.refresh()
	assert_bool(s.clock_offset_ms > 3_000_000).is_true()
	assert_bool(absi(s.server_now() - future) < 5_000).is_true()

func test_state_changed_carries_version() -> void:
	var pair := _session([{"status": 200, "json": _state(3)}])
	var s: FarmSession = pair[0]
	var seen := []
	s.state_changed.connect(func(st, v): seen.append([int(st.wallet), v]))
	s.refresh()
	assert_array(seen[0]).is_equal([30, 3])
