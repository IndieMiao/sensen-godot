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

## q(269) (SGODOT-377, the user's ③): no 2 h away first. A server before it still sends away_ready_in — a countdown, or
## null for "never left" — and neither stops Rest any more: no away state, no `Not yet` (不知火舞 on 377 3d9f426f).
func test_no_away_state_whatever_an_older_server_sends() -> void:
	for away in [4320000, null, 0]:
		var s := P0Logic.rest_state(_view({"away_ready_in": away}))
		assert_str(s.state).is_equal("ready")
		assert_str(s.sheet_state).is_equal("Available")
		assert_str(s.button).is_equal("Rest")
		assert_bool(s.can_rest).is_true()
	var now := {"rest": {"used": 0, "limit": 1, "resets_in": 33120000, "amount": 60}, "energy": {"value": 120, "max": 210}}
	assert_str(P0Logic.rest_state(now).state).is_equal("ready")   # the view since q(269): no away fields at all

func test_used_today() -> void:
	var s := P0Logic.rest_state(_view({"used": 1, "away_ready_in": null}))
	assert_str(s.state).is_equal("used")
	assert_str(s.badge).is_equal("used_today")
	assert_array([s.fact, s.fact_value]).is_equal(["Uses", "1/1"])
	assert_str(s.note).is_equal("Available again in 9h 12m")   # to the 04:00 reset, as the mine's `Resets in` (q(96))
	assert_str(P0Logic.rest_state(_view({"used": 1, "resets_in": 2_520_000})).note).is_equal("Available again in 42m")   # q(97): not `42:00`
	assert_bool(s.can_rest).is_false()

static func _tips() -> String: return "user://test_p0_rest_bench_%d.json" % OS.get_process_id()
static func _store() -> String: return "user://test_p0_rest_bench_bar_%d.json" % OS.get_process_id()

func after_test() -> void:
	for f in [_tips(), _store()]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _sheet_texts(ui: P0Ui) -> Array:
	return ui.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)

## SGODOT-377: the open bench card follows the view — used today, `Available again in …` ticks in place; the new
## day's read (used 0) turns it into the Rest card without closing it.
func test_the_open_card_counts_down_and_opens() -> void:
	var ui := P0Ui.new()
	ui.quick_store = _store()
	ui.tips_path = _tips()
	add_child(auto_free(ui))
	await await_idle_frame()
	var used := _view({"used": 1, "resets_in": 2_520_000}, 50)
	ui.set_view(used)
	ui.open_rest_card()
	await await_idle_frame()
	assert_array(_sheet_texts(ui)).contains(["Available again in 42m"])
	ui.set_view(P0Logic.project(used, 60000.0))
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("rest")
	assert_array(_sheet_texts(ui)).contains(["Available again in 41m"])
	assert_array(_sheet_texts(ui)).not_contains(["Available again in 42m"])
	ui.set_view(_view({}, 50))   # the 04:00 rollover's read
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("rest")
	var buttons := ui.find_children("*", "", true, false).filter(func(n): return n is UiCommandButton)
	assert_int(buttons.size()).is_equal(1)
	assert_bool((buttons[0] as UiCommandButton).reason == "").is_true()   # the Rest button

## 周瑜 on #602: near full, Energy ticking up changes the button's gain in place — the same button, not a rebuilt card
## (a tap pressed on one would be released on its replacement).
func test_the_open_cards_gain_changes_in_place() -> void:
	var ui := P0Ui.new()
	ui.quick_store = _store()
	ui.tips_path = _tips()
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view({}, 185))
	ui.open_rest_card()
	await await_idle_frame()
	var before: Array = ui.find_children("*", "", true, false).filter(func(n): return n is UiCommandButton)
	assert_str((before[0] as UiCommandButton).text).is_equal("Rest · +25 Energy")
	ui.set_view(_view({}, 186))
	await await_idle_frame()
	var after: Array = ui.find_children("*", "", true, false).filter(func(n): return n is UiCommandButton)
	assert_int(after.size()).is_equal(1)
	assert_bool(is_same(after[0], before[0])).is_true()
	assert_str((after[0] as UiCommandButton).label).is_equal("Rest · +24 Energy")
	assert_str((after[0] as UiCommandButton).text).is_equal("Rest · +24 Energy")
