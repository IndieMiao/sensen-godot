extends GdUnitTestSuite
## AuthSession：状态机、持久化、过期判定与刷新分支。时钟与刷新器全部注入。

var _now := 1_000_000

func before_test() -> void:
	_cleanup()

func after_test() -> void:
	_cleanup()

func _cleanup() -> void:
	if FileAccess.file_exists(AuthSession.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AuthSession.PATH))

func _session() -> AuthSession:
	var s := AuthSession.new()
	s.now_provider = func() -> int: return _now
	return s

func test_starts_signed_out_and_token_provider_returns_empty() -> void:
	var s := _session()
	assert_bool(s.is_signed_in()).is_false()
	assert_str(s.access_token()).is_empty()
	assert_bool(s.needs_refresh()).is_false()

func test_sign_in_flow_emits_states_and_persists() -> void:
	var s := _session()
	var states: Array = []
	s.changed.connect(func(v): states.append(v))
	s.begin_sign_in()
	s.complete_sign_in("u1", "id-1", "rt-1", 3600, "password")
	assert_array(states).is_equal([AuthSession.State.SIGNING_IN, AuthSession.State.SIGNED_IN])
	assert_bool(s.is_signed_in()).is_true()
	assert_str(s.access_token()).is_equal("id-1")
	assert_int(s.expires_at_ms).is_equal(_now + 3_600_000)
	assert_bool(FileAccess.file_exists(AuthSession.PATH)).is_true()

func test_restore_reads_back_the_same_session() -> void:
	var s := _session()
	s.complete_sign_in("u1", "id-1", "rt-1", 3600, "apple.com")
	var again := _session()
	assert_bool(again.restore()).is_true()
	assert_str(again.user_id).is_equal("u1")
	assert_str(again.id_token).is_equal("id-1")
	assert_str(again.refresh_token).is_equal("rt-1")
	assert_str(again.provider).is_equal("apple.com")
	assert_int(again.state).is_equal(AuthSession.State.SIGNED_IN)

func test_restore_tolerates_missing_or_corrupt_file() -> void:
	assert_bool(_session().restore()).is_false()
	var f := FileAccess.open(AuthSession.PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	assert_bool(_session().restore()).is_false()
	f = FileAccess.open(AuthSession.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"user_id": "u", "id_token": ""}))
	f.close()
	assert_bool(_session().restore()).is_false()

func test_fail_sign_in_records_error_and_stays_signed_out() -> void:
	var s := _session()
	s.begin_sign_in()
	s.fail_sign_in("INVALID_CODE")
	assert_int(s.state).is_equal(AuthSession.State.SIGNED_OUT)
	assert_str(s.last_error).is_equal("INVALID_CODE")

func test_sign_out_clears_fields_and_file() -> void:
	var s := _session()
	s.complete_sign_in("u1", "id-1", "rt-1", 3600, "password")
	s.sign_out()
	assert_bool(s.is_signed_in()).is_false()
	assert_str(s.id_token).is_empty()
	assert_bool(FileAccess.file_exists(AuthSession.PATH)).is_false()

func test_needs_refresh_uses_injected_clock_with_skew() -> void:
	var s := _session()
	s.complete_sign_in("u1", "id-1", "rt-1", 3600, "password")
	assert_bool(s.needs_refresh()).is_false()
	_now += 3_600_000 - AuthSession.REFRESH_SKEW_MS - 1
	assert_bool(s.needs_refresh()).is_false()
	_now += 1
	assert_bool(s.needs_refresh()).is_true()

func test_ensure_fresh_refreshes_when_expiring_and_persists_new_token() -> void:
	var s := _session()
	s.complete_sign_in("u1", "id-1", "rt-1", 3600, "password")
	var calls: Array = []
	s.refresher = func(rt: String) -> Dictionary:
		calls.append(rt)
		return {"ok": true, "id_token": "id-2", "refresh_token": "rt-2", "expires_in_s": 1800}
	assert_bool(await s.ensure_fresh()).is_true()
	assert_array(calls).is_empty() # 未到期不刷新
	_now += 3_600_000
	assert_bool(await s.ensure_fresh()).is_true()
	assert_array(calls).is_equal(["rt-1"])
	assert_str(s.access_token()).is_equal("id-2")
	assert_str(s.refresh_token).is_equal("rt-2")
	assert_int(s.expires_at_ms).is_equal(_now + 1_800_000)
	var again := _session()
	again.restore()
	assert_str(again.id_token).is_equal("id-2")

func test_refresh_transient_failure_keeps_session_but_returns_false() -> void:
	var s := _session()
	s.complete_sign_in("u1", "id-1", "rt-1", 3600, "password")
	s.refresher = func(_rt: String) -> Dictionary: return {"ok": false, "error": "NETWORK"}
	assert_bool(await s.refresh()).is_false()
	assert_bool(s.is_signed_in()).is_true()
	assert_str(s.access_token()).is_equal("id-1")
	assert_str(s.last_error).is_equal("NETWORK")
	assert_int(s.state).is_equal(AuthSession.State.SIGNED_IN)

func test_refresh_fatal_failure_signs_out() -> void:
	var s := _session()
	s.complete_sign_in("u1", "id-1", "rt-1", 3600, "password")
	s.refresher = func(_rt: String) -> Dictionary: return {"ok": false, "fatal": true, "error": "TOKEN_EXPIRED"}
	assert_bool(await s.refresh()).is_false()
	assert_bool(s.is_signed_in()).is_false()
	assert_bool(FileAccess.file_exists(AuthSession.PATH)).is_false()

func test_refresh_without_refresher_or_session_is_false() -> void:
	var s := _session()
	assert_bool(await s.refresh()).is_false()
	s.complete_sign_in("u1", "id-1", "rt-1", 3600, "password")
	assert_bool(await s.refresh()).is_false()
	assert_bool(s.is_signed_in()).is_true()
