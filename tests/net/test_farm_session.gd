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
	assert_bool(await s.login()).is_true()
	assert_str(s.player_id).is_equal("p1")
	assert_str(s.client.token).is_equal("tok")

func test_unresolved_kitchen_reply_blocks_trade_but_allows_its_reconciliation() -> void:
	var pair := _session([{"status": 200, "json": _state(2)}])
	var s: FarmSession = pair[0]
	var transport: FakeTransport = pair[1]
	s.set_meta("pending_kitchen_command", {"type": "cook_dish"})
	assert_bool(await s.send("sell_at_stall", {"items": []})).is_false()
	assert_str(s.last_error_code).is_equal("PENDING_ACTION")
	assert_int(transport.requests.size()).is_equal(0)
	assert_bool(await s.send("cook_dish", {"recipe": "salad"}, &"pending_kitchen_command")).is_true()
	assert_int(transport.requests.size()).is_equal(1)

func test_ensure_farm_adopts_existing() -> void:
	var pair := _session([{"status": 200, "json": _state(7)}])
	var s: FarmSession = pair[0]
	assert_bool(await s.ensure_farm("hk", "patch", 2)).is_true()
	assert_int(s.version).is_equal(7)
	assert_int(int(s.state.wallet)).is_equal(30)

func test_farm_lookup_distinguishes_missing_farm_from_connection_failure() -> void:
	var pair := _session([
		{"status": 404, "json": {"code": "NO_FARM"}},
		{"error": "connection failed"},
		{"status": 200, "json": _state(7)},
	])
	var s: FarmSession = pair[0]
	assert_bool(await s.refresh()).is_false()
	assert_str(s.last_error_code).is_equal("NO_FARM")
	assert_bool(await s.refresh()).is_false()
	assert_str(s.last_error_code).is_equal("TRANSPORT")
	assert_bool(await s.refresh()).is_true()
	assert_str(s.last_error_code).is_empty()
	assert_bool(s.has_farm()).is_true()

func test_state_changed_observes_derived_from_the_same_accepted_response() -> void:
	var body := _state(7)
	body.state = {"clock": {"chapter_index": 1}}
	body.derived = {"chapter_index": 1, "next_chapter_opens_at": 321000}
	var pair := _session([{"status": 200, "json": body}])
	var s: FarmSession = pair[0]
	s.derived = {"chapter_index": 0, "next_chapter_opens_at": 1000}
	var seen := []
	var session_ref: WeakRef = weakref(s)
	s.state_changed.connect(func(state, _version):
		var current := session_ref.get_ref() as FarmSession
		seen.append([state.clock.chapter_index, current.derived.chapter_index, current.derived.next_chapter_opens_at]))
	assert_bool(await s.refresh()).is_true()
	assert_that(seen).is_equal([[1, 1, 321000]])

func test_legacy_response_clears_derived_instead_of_reusing_a_past_chapter_deadline() -> void:
	var pair := _session([{"status": 200, "json": _state(8)}])
	var s: FarmSession = pair[0]
	s.derived = {"chapter_index": 0, "next_chapter_opens_at": 1000}
	assert_bool(await s.refresh()).is_true()
	assert_that(s.derived).is_equal({})

func test_stale_response_cannot_replace_derived_or_the_authoritative_time_sample() -> void:
	var pair := _session([])
	var s: FarmSession = pair[0]
	s._adopt({"version": 8, "server_time": 100000, "state": {"wallet": 40},
		"derived": {"chapter_index": 1, "next_chapter_opens_at": null}})
	s._adopt({"version": 7, "server_time": 900000, "state": {"wallet": 20},
		"derived": {"chapter_index": 0, "next_chapter_opens_at": 910000}})
	assert_int(s.state.wallet).is_equal(40)
	assert_int(s.derived.chapter_index).is_equal(1)
	assert_int(s.server_now()).is_less(200000)

func test_accepted_server_clock_uses_monotonic_elapsed_time() -> void:
	var pair := _session([])
	var s: FarmSession = pair[0]
	s._adopt({"version": 1, "server_time": 100000, "state": {}})
	s.clock_offset_ms += 86_400_000
	s._server_sample_ticks_ms -= 2000
	assert_bool(absi(s.server_now() - 102000) < 1000).is_true()

func test_ensure_farm_creates_when_404() -> void:
	var pair := _session([{"status": 404, "json": {}}, {"status": 200, "json": _state(1)}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	assert_bool(await s.ensure_farm("hk", "patch_a", 2)).is_true()
	assert_int(s.version).is_equal(1)
	assert_str(t.requests[1].method).is_equal("POST")
	assert_str(t.requests[1].body.layout_patch_id).is_equal("patch_a")
	assert_int(int(t.requests[1].body.blueprint_revision)).is_equal(2)

func test_placement_is_saved_only_after_server_capability_check() -> void:
	var location := {"lat": 31.225, "lng": 121.485}
	var body := _state(0)
	body["location"] = location
	var pair := _session([{"status": 404, "json": {}},
		{"status": 200, "json": {"farm_placement_version": 1}}, {"status": 201, "json": body}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	assert_bool(await s.ensure_farm("shanghai", "sh_a", 2, location)).is_true()
	assert_str(t.requests[1].url).ends_with("/regions")
	assert_that(t.requests[2].body.location).is_equal(location)
	assert_that(s.location).is_equal(location)

func test_old_server_cannot_silently_ignore_a_chosen_location() -> void:
	var pair := _session([{"status": 404, "json": {}}, {"status": 200, "json": {"regions": []}}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	assert_bool(await s.ensure_farm("shanghai", "sh_a", 2, {"lat": 31.225, "lng": 121.485})).is_false()
	assert_str(s.last_error_code).is_equal("LOCATION_UNSUPPORTED")
	assert_int(t.requests.size()).is_equal(2)
	assert_bool(s.has_farm()).is_false()

func test_existing_farm_keeps_authoritative_location_even_when_another_is_selected() -> void:
	var original := {"lat": 31.225, "lng": 121.485}
	var body := _state(7)
	body["location"] = original
	var pair := _session([{"status": 200, "json": body}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	assert_bool(await s.ensure_farm("shanghai", "sh_a", 2, {"lat": 31.235, "lng": 121.495})).is_true()
	assert_that(s.location).is_equal(original)
	assert_int(t.requests.size()).is_equal(1)

func test_old_farm_response_clears_stale_cached_placement() -> void:
	var pair := _session([{"status": 200, "json": _state(7)}])
	var s: FarmSession = pair[0]
	s.location = {"lat": 31.225, "lng": 121.485}
	await s.refresh()
	assert_that(s.location).is_equal({})

func test_malformed_placement_is_not_sent_to_server() -> void:
	var pair := _session([{"status": 404, "json": {}}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	assert_bool(await s.ensure_farm("shanghai", "sh_a", 2, {"lat": "31.225", "lng": 121.485})).is_false()
	assert_str(s.last_error_code).is_equal("INVALID_LOCATION")
	assert_int(t.requests.size()).is_equal(1)

func test_send_posts_base_version_and_adopts_new_version() -> void:
	var pair := _session([{"status": 200, "json": _state(4)},
		{"status": 200, "json": {"version": 5, "state": {"wallet": 28}}}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	await s.ensure_farm("hk", "p", 2)
	assert_bool(await s.send("sow", {"cell": [3, 3]})).is_true()
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
	await s.ensure_farm("hk", "p", 2)
	assert_bool(await s.send("water", {})).is_true()
	assert_str(t.requests[1].body.idempotency_key).is_equal(t.requests[2].body.idempotency_key)

func test_refresh_resolves_a_lost_command_before_reading_or_spending_again() -> void:
	var pair := _session([{"error": "timeout"}, {"error": "timeout"},
		{"status": 200, "json": _state(5)}, {"status": 200, "json": _state(4)},
		{"status": 200, "json": _state(6)}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s._adopt(_state(4))
	var payload := {"recipe": "salad"}
	assert_bool(await s.send("cook_dish", payload)).is_false()
	payload.recipe = "tea"
	assert_bool(await s.send("sell_at_stall", {"items": []}, &"pending_kitchen_command")).is_false()
	assert_str(s.last_error_code).is_equal("PENDING_ACTION")
	assert_int(t.requests.size()).is_equal(2)
	assert_bool(await s.refresh()).is_true()
	assert_that(t.requests[2].body).is_equal(t.requests[0].body)
	assert_str(str(t.requests[2].method)).is_equal("POST")
	assert_str(str(t.requests[3].method)).is_equal("GET")
	assert_int(s.version).is_equal(5)
	assert_bool(await s.send("cook_dish", {"recipe": "tea"})).is_true()
	assert_int(int(t.requests[4].body.base_version)).is_equal(5)
	assert_str(t.requests[4].body.idempotency_key).is_not_equal(t.requests[0].body.idempotency_key)

func test_failed_reconciliation_keeps_the_envelope_and_never_falls_through_to_get() -> void:
	var pair := _session([{"error": "timeout"}, {"error": "timeout"},
		{"error": "timeout"}, {"error": "timeout"},
		{"status": 200, "json": _state(5)}, {"status": 200, "json": _state(5)}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s._adopt(_state(4))
	assert_bool(await s.send("give_gift", {"resident_id": "bistro_owner", "crop": "L"})).is_false()
	assert_bool(await s.refresh()).is_false()
	assert_bool(s.offline).is_true()
	assert_int(t.requests.size()).is_equal(4)
	assert_bool(await s.refresh()).is_true()
	assert_bool(s.offline).is_false()
	for index in range(1, 5):
		assert_that(t.requests[index].body).is_equal(t.requests[0].body)
		assert_str(str(t.requests[index].method)).is_equal("POST")
	assert_str(str(t.requests[5].method)).is_equal("GET")

func test_recovery_conflict_proves_no_application_without_automatically_resending() -> void:
	var conflict := _state(9)
	conflict.code = "VERSION_CONFLICT"
	var pair := _session([{"error": "timeout"}, {"error": "timeout"},
		{"status": 409, "json": conflict}, {"status": 200, "json": _state(9)},
		{"status": 200, "json": _state(10)}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s._adopt(_state(4))
	assert_bool(await s.send("cook_dish", {"recipe": "salad"})).is_false()
	assert_bool(await s.refresh()).is_true()
	assert_that(t.requests[2].body).is_equal(t.requests[0].body)
	assert_str(str(t.requests[3].method)).is_equal("GET")
	assert_int(t.requests.size()).is_equal(4)
	assert_bool(await s.send("cook_dish", {"recipe": "salad"})).is_true()
	assert_int(int(t.requests[4].body.base_version)).is_equal(9)
	assert_str(t.requests[4].body.idempotency_key).is_not_equal(t.requests[0].body.idempotency_key)

func test_conflict_retry_that_loses_its_reply_retains_the_replacement_envelope() -> void:
	var conflict := _state(9)
	conflict.code = "VERSION_CONFLICT"
	var pair := _session([{"status": 409, "json": conflict},
		{"error": "timeout"}, {"error": "timeout"},
		{"status": 200, "json": _state(10)}, {"status": 200, "json": _state(10)}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s._adopt(_state(4))
	assert_bool(await s.send("cook_dish", {"recipe": "salad"})).is_false()
	assert_bool(await s.refresh()).is_true()
	assert_str(t.requests[1].body.idempotency_key).is_not_equal(t.requests[0].body.idempotency_key)
	assert_int(int(t.requests[1].body.base_version)).is_equal(9)
	assert_that(t.requests[2].body).is_equal(t.requests[1].body)
	assert_that(t.requests[3].body).is_equal(t.requests[1].body)
	assert_str(str(t.requests[4].method)).is_equal("GET")

func test_replayed_rejection_is_not_reported_as_a_successful_purchase() -> void:
	var pair := _session([{"error": "timeout"}, {"status": 200, "json": {
		"outcome": "replayed", "replayed_outcome": "rejected", "code": "INSUFFICIENT_FUNDS"}},
		{"status": 200, "json": _state(4)}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s._adopt(_state(4))
	assert_bool(await s.send("buy_seeds", {"crop": "R", "qty": 1})).is_false()
	assert_str(s.last_error_code).is_equal("INSUFFICIENT_FUNDS")
	assert_int(s.version).is_equal(4)
	assert_bool(await s.refresh()).is_true()
	assert_str(str(t.requests[2].method)).is_equal("GET")

func test_proxy_timeout_is_unconfirmed_even_when_http_transport_succeeds() -> void:
	var pair := _session([{"status": 504, "json": {}},
		{"status": 200, "json": _state(5)}, {"status": 200, "json": _state(5)}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s._adopt(_state(4))
	assert_bool(await s.send("buy_seeds", {"crop": "R", "qty": 1})).is_false()
	assert_str(s.last_error_code).is_equal("TRANSPORT")
	assert_bool(await s.refresh()).is_true()
	assert_that(t.requests[1].body).is_equal(t.requests[0].body)
	assert_str(str(t.requests[2].method)).is_equal("GET")

func test_auth_failure_during_recovery_cannot_discard_an_unconfirmed_command() -> void:
	var pair := _session([{"error": "timeout"}, {"error": "timeout"},
		{"status": 401, "json": {"code": "UNAUTHENTICATED"}},
		{"status": 200, "json": _state(5)}, {"status": 200, "json": _state(5)}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	s._adopt(_state(4))
	assert_bool(await s.send("cook_dish", {"recipe": "salad"})).is_false()
	assert_bool(await s.refresh()).is_false()
	assert_str(s.last_error_code).is_equal("TRANSPORT")
	assert_int(t.requests.size()).is_equal(3)
	assert_bool(await s.refresh()).is_true()
	assert_that(t.requests[3].body).is_equal(t.requests[0].body)
	assert_str(str(t.requests[4].method)).is_equal("GET")

func test_send_reconciles_on_version_conflict_with_fresh_key() -> void:
	# 409 回包带最新状态：先对账，再用**新** key 重发（同 key 换 base_version 会被判
	# IDEMPOTENCY_MISMATCH）。
	var pair := _session([{"status": 200, "json": _state(4)},
		{"status": 409, "json": {"code": "VERSION_CONFLICT", "version": 9, "state": {"wallet": 12}}},
		{"status": 200, "json": {"version": 10, "state": {"wallet": 10}}}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	await s.ensure_farm("hk", "p", 2)
	assert_bool(await s.send("harvest", {})).is_true()
	assert_int(int(t.requests[2].body.base_version)).is_equal(9)
	assert_str(t.requests[2].body.idempotency_key).is_not_equal(t.requests[1].body.idempotency_key)
	assert_int(s.version).is_equal(10)

func test_rejected_command_emits_code() -> void:
	var pair := _session([{"status": 200, "json": _state(4)},
		{"status": 422, "json": {"code": "INSUFFICIENT_FUNDS", "detail": "need 8"}}])
	var s: FarmSession = pair[0]
	await s.ensure_farm("hk", "p", 2)
	var seen := []
	s.rejected.connect(func(code, detail): seen.append([code, detail]))
	assert_bool(await s.send("buy_seed", {})).is_false()
	assert_int(s.version).is_equal(4)
	assert_array(seen[0]).is_equal(["INSUFFICIENT_FUNDS", "need 8"])

func test_two_failures_flip_offline_and_one_success_flips_back() -> void:
	var pair := _session([{"error": "down"}, {"error": "down"}, {"status": 200, "json": _state(1)}])
	var s: FarmSession = pair[0]
	var flips := []
	s.offline_changed.connect(func(v): flips.append(v))
	assert_bool(await s.refresh()).is_false()   # 1 次失败还不算离线
	assert_bool(s.offline).is_false()
	assert_bool(await s.refresh()).is_false()   # 第 2 次翻牌
	assert_bool(s.offline).is_true()
	s.offline = false                     # 手动放行，验证成功回包会清掉离线
	assert_bool(await s.refresh()).is_true()
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
	assert_bool(await s.send("sow", {})).is_false()
	assert_int(t.requests.size()).is_equal(0)
	assert_array(seen).is_equal(["OFFLINE"])

func test_server_now_uses_offset_not_local_clock() -> void:
	# 本地时钟不可信：玩家改系统时间不该让作物提前熟。
	var future := int(Time.get_unix_time_from_system() * 1000.0) + 3_600_000
	var pair := _session([{"status": 200, "json": {"version": 1, "state": {}, "server_time": future}}])
	var s: FarmSession = pair[0]
	await s.refresh()
	assert_bool(s.clock_offset_ms > 3_000_000).is_true()
	assert_bool(absi(s.server_now() - future) < 5_000).is_true()

func test_state_changed_carries_version() -> void:
	var pair := _session([{"status": 200, "json": _state(3)}])
	var s: FarmSession = pair[0]
	var seen := []
	s.state_changed.connect(func(st, v): seen.append([int(st.wallet), v]))
	await s.refresh()
	assert_array(seen[0]).is_equal([30, 3])

func test_adopt_records_the_servers_blueprint() -> void:
	# 服务端农场用哪张蓝图是权威：2026-09-04 真机上客户端按本地选的 sh_b 进场、服务端却是 sh_c。
	var pair := _session([{"status": 200, "json": {"farm_id": "f1", "version": 2, "state": {},
		"layout_patch_id": "sh_c", "blueprint_revision": 2, "region_id": "shanghai"}}])
	var s: FarmSession = pair[0]
	await s.refresh()
	assert_str(s.layout_patch_id).is_equal("sh_c")
	assert_int(s.blueprint_revision).is_equal(2)
	assert_str(s.region_id).is_equal("shanghai")

func test_sends_are_serialized_so_versions_never_go_stale() -> void:
	# 并发两条：第二条必须等第一条回包、用新 version 发，而不是拿旧 version 撞 409。
	var pair := _session([{"status": 200, "json": _state(4)},
		{"status": 200, "json": {"version": 5, "state": {}}},
		{"status": 200, "json": {"version": 6, "state": {}}}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	await s.ensure_farm("hk", "p", 2)
	# 通过 Callable.call 起两条协程而不 await：语法层面只有这条路能"同时"发两条。
	Callable(s, "send").call("clear_cells", {"cell_ids": ["1,1"]})
	Callable(s, "send").call("clear_cells", {"cell_ids": ["2,1"]})
	for i in 5:
		await get_tree().process_frame
	assert_int(t.requests.size()).is_equal(3)
	assert_int(int(t.requests[1].body.base_version)).is_equal(4)
	assert_int(int(t.requests[2].body.base_version)).is_equal(5)
	assert_int(s.version).is_equal(6)

func test_stale_response_never_regresses_state() -> void:
	# 版本只增不减：迟到的旧回包不能把状态倒退回去。
	var pair := _session([{"status": 200, "json": {"version": 7, "state": {"wallet": 70}, "farm_id": "f"}},
		{"status": 200, "json": {"version": 5, "state": {"wallet": 50}, "farm_id": "f"}}])
	var s: FarmSession = pair[0]
	await s.refresh()
	await s.refresh()
	assert_int(s.version).is_equal(7)
	assert_int(int(s.state.wallet)).is_equal(70)

func test_refresh_waits_for_in_flight_commands() -> void:
	var pair := _session([{"status": 200, "json": _state(4)},
		{"status": 200, "json": {"version": 5, "state": {"wallet": 1}}},
		{"status": 200, "json": {"version": 5, "state": {"wallet": 1}}}])
	var s: FarmSession = pair[0]
	var t: FakeTransport = pair[1]
	await s.ensure_farm("hk", "p", 2)
	Callable(s, "send").call("clear_cells", {"cell_ids": ["1,1"]})
	Callable(s, "refresh").call()
	for i in 5:
		await get_tree().process_frame
	assert_str(str(t.requests[1].method)).is_equal("POST")
	assert_str(str(t.requests[2].method)).is_equal("GET")
	assert_int(s.version).is_equal(5)
