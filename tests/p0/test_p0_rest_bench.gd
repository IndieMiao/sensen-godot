extends GdUnitTestSuite
## Rest bench state (FARM-7 / FARM-7-2 482:52; q(30), q(41); WP4-D10 ②; SGODOT-224).

func _view(rest := {}, value := 120) -> Dictionary:
	var r := {"used": 0, "limit": 1, "resets_in": 33120000, "amount": 60, "away_h": 2, "away_ready_in": 0}
	r.merge(rest, true)
	return {"rest": r, "energy": {"value": value, "max": 210}}

func test_available_rests_up_to_sixty() -> void:
	var s := P0Logic.rest_state(_view())
	assert_str(s.state).is_equal("ready")
	assert_str(s.badge).is_equal("available")
	assert_str(s.card).is_equal("Rest · +60 Energy · once a day")
	assert_str(s.sheet_state).is_equal("Available")
	assert_str(s.effect).is_equal("Restores up to 60 Energy")
	assert_array([s.fact, s.fact_value]).is_equal(["Uses left", "1 today"])
	assert_str(s.button).is_equal("Rest")
	assert_bool(s.can_rest).is_true()

func test_near_full_says_the_real_gain_and_full_greys() -> void:
	assert_str(P0Logic.rest_state(_view({}, 185)).button).is_equal("Rest · +25 Energy")   # WP4-D10 ②
	var s := P0Logic.rest_state(_view({}, 210))
	assert_str(s.state).is_equal("full")
	assert_str(s.reason).is_equal("Energy full")
	assert_bool(s.can_rest).is_false()

func test_two_hours_away_first() -> void:
	var s := P0Logic.rest_state(_view({"away_ready_in": 4320000}))
	assert_str(s.state).is_equal("away")
	assert_str(s.badge).is_equal("countdown")
	assert_str(s.caption).is_equal("1h 12m")
	assert_str(s.sheet_state).is_equal("Cooling down")
	assert_array([s.fact, s.fact_value]).is_equal(["Available in", "1h 12m"])
	assert_str(s.reason).is_equal("Ready in 1h 12m")
	assert_str(s.close).is_equal("Close")
	s = P0Logic.rest_state(_view({"away_ready_in": null}))   # never left home
	assert_str(s.state).is_equal("away")
	assert_str(s.reason).is_equal("After 2h away")

func test_used_today() -> void:
	var s := P0Logic.rest_state(_view({"used": 1, "away_ready_in": null}))
	assert_str(s.state).is_equal("used")
	assert_str(s.badge).is_equal("used_today")
	assert_array([s.fact, s.fact_value]).is_equal(["Uses", "1/1"])
	assert_str(s.note).is_equal("Available again at the next home-day reset.")
	assert_bool(s.can_rest).is_false()
