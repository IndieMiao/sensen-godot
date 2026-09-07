extends GdUnitTestSuite
## FirstRun：周岁算法、年龄门结论持久化（不存生日）、同意版本、启动去向矩阵。

func before_test() -> void:
	FirstRun.clear()

func after_test() -> void:
	FirstRun.clear()

func test_age_years_respects_birthday_not_yet_reached() -> void:
	var today := {"year": 2026, "month": 9, "day": 7}
	assert_int(FirstRun.age_years({"year": 2013, "month": 9, "day": 7}, today)).is_equal(13)
	assert_int(FirstRun.age_years({"year": 2013, "month": 9, "day": 8}, today)).is_equal(12)
	assert_int(FirstRun.age_years({"year": 2013, "month": 10, "day": 1}, today)).is_equal(12)
	assert_int(FirstRun.age_years({"year": 2013, "month": 8, "day": 31}, today)).is_equal(13)
	assert_bool(FirstRun.is_under_min_age({"year": 2013, "month": 9, "day": 8}, today)).is_true()
	assert_bool(FirstRun.is_under_min_age({"year": 2013, "month": 9, "day": 7}, today)).is_false()

func test_record_age_gate_persists_only_the_verdict() -> void:
	var fr := FirstRun.new()
	assert_bool(fr.record_age_gate({"year": 2015, "month": 1, "day": 1}, {"year": 2026, "month": 9, "day": 7})).is_false()
	var again := FirstRun.load_state()
	assert_bool(again.age_gate_blocked).is_true()
	assert_bool(again.age_gate_passed).is_false()
	assert_bool(FileAccess.get_file_as_string(FirstRun.PATH).contains("2015")).is_false()
	FirstRun.clear()
	assert_bool(FirstRun.new().record_age_gate({"year": 2000, "month": 1, "day": 1}, {"year": 2026, "month": 9, "day": 7})).is_true()
	assert_bool(FirstRun.load_state().age_gate_passed).is_true()

func test_consent_tracks_version() -> void:
	var fr := FirstRun.new()
	assert_bool(fr.consent_current()).is_false()
	fr.record_consent()
	assert_bool(fr.consent_current()).is_true()
	assert_str(FirstRun.load_state().consent_version).is_equal(LegalLinks.CONSENT_VERSION)
	fr.consent_version = "2000-01-01"
	assert_bool(fr.consent_current()).is_false()

func test_next_route_matrix() -> void:
	var fr := FirstRun.new()
	assert_str(fr.next_route(false)).is_equal(AppRoutes.AGE_GATE)
	assert_str(fr.next_route(true)).is_equal(AppRoutes.AGE_GATE)
	fr.age_gate_blocked = true
	assert_str(fr.next_route(true)).is_equal(AppRoutes.AGE_GATE)
	fr.age_gate_blocked = false
	fr.age_gate_passed = true
	assert_str(fr.next_route(false)).is_equal(AppRoutes.CONSENT)
	fr.consent_version = "2000-01-01"
	assert_str(fr.next_route(true)).is_equal(AppRoutes.CONSENT)
	fr.consent_version = LegalLinks.CONSENT_VERSION
	assert_str(fr.next_route(false)).is_equal(AppRoutes.LOGIN)
	assert_str(fr.next_route(true)).is_equal(AppRoutes.SHELL)

func test_corrupt_state_file_is_treated_as_fresh() -> void:
	var f := FileAccess.open(FirstRun.PATH, FileAccess.WRITE)
	f.store_string("{nope")
	f.close()
	var fr := FirstRun.load_state()
	assert_bool(fr.age_gate_passed).is_false()
	assert_str(fr.next_route(true)).is_equal(AppRoutes.AGE_GATE)
