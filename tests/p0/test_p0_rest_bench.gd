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
	# No `card` line: the bench strip (P0WorldPrompts.bench), the bench sheet (P0Ui) and the Energy card's Rest tile
	# (P0Logic) each word their own, and nothing read it (李白 q(94)).
	assert_bool(s.has("card")).is_false()
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
	assert_str(s.sheet_state).is_equal("Rest · back after 2h away · 1h 12m to go")   # q(70), FARM-7 cooling card
	assert_str(s.wait).is_equal("in 1h 12m")
	# Under an hour the sentences say `42m`; the capsule under the bench's badge keeps ticking `42:00` (SGODOT-224).
	var soon := P0Logic.rest_state(_view({"away_ready_in": 2520000}))
	assert_str(soon.caption).is_equal("42:00")
	assert_str(soon.sheet_state).is_equal("Rest · back after 2h away · 42m to go")
	assert_str(soon.wait).is_equal("in 42m")
	assert_str(s.reason).is_equal("Not yet")
	assert_bool(s.can_rest).is_false()
	assert_str(s.close).is_equal("Close")
	# q(70): a new account that never left the farm (server away_ready_in null) shows no countdown at all.
	s = P0Logic.rest_state(_view({"away_ready_in": null}))
	assert_str(s.state).is_equal("away")
	assert_str(s.caption).is_empty()
	assert_str(s.sheet_state).is_equal("Rest · back after 2h away")
	assert_str(s.wait).is_equal("after 2h away")
	assert_bool(s.can_rest).is_false()

func test_used_today() -> void:
	var s := P0Logic.rest_state(_view({"used": 1, "away_ready_in": null}))
	assert_str(s.state).is_equal("used")
	assert_str(s.badge).is_equal("used_today")
	assert_array([s.fact, s.fact_value]).is_equal(["Uses", "1/1"])
	assert_str(s.note).is_equal("Available again in 9h 12m")   # to the 04:00 reset, as the mine's `Resets in` (q(96))
	assert_str(P0Logic.rest_state(_view({"used": 1, "resets_in": 2_520_000})).note).is_equal("Available again in 42m")   # q(97): not `42:00`
	assert_bool(s.can_rest).is_false()
