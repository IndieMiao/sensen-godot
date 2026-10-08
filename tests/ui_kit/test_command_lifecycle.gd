extends GdUnitTestSuite
## CommandLifecycle: submitting at once, pending only after the delay, idle on settle (SGODOT-211).

func test_states_follow_the_pending_delay() -> void:
	var lc: CommandLifecycle = auto_free(CommandLifecycle.new())
	var seen := []
	lc.changed.connect(func(k, s): seen.append([k, s]))
	lc.start("sell", 1000)
	assert_int(lc.state("sell")).is_equal(CommandLifecycle.State.SUBMITTING)
	lc.tick(1000 + UiTokens.MOTION_PENDING_DELAY_MS - 1)
	assert_int(lc.state("sell")).is_equal(CommandLifecycle.State.SUBMITTING)
	lc.tick(1000 + UiTokens.MOTION_PENDING_DELAY_MS)
	assert_int(lc.state("sell")).is_equal(CommandLifecycle.State.PENDING)
	lc.settle("sell")
	assert_int(lc.state("sell")).is_equal(CommandLifecycle.State.IDLE)
	assert_array(seen).is_equal([["sell", CommandLifecycle.State.SUBMITTING], ["sell", CommandLifecycle.State.PENDING], ["sell", CommandLifecycle.State.IDLE]])

func test_fast_results_never_show_pending() -> void:
	var lc: CommandLifecycle = auto_free(CommandLifecycle.new())
	lc.start("buy", 0)
	lc.settle("buy")
	lc.tick(UiTokens.MOTION_PENDING_DELAY_MS * 2)
	assert_int(lc.state("buy")).is_equal(CommandLifecycle.State.IDLE)

## 亚瑟 on #84: a compact command's caller width (a board row's 152) stays through PENDING and back and through
## Offline on and off — each redraw used to reset custom_minimum_size to 0.
func test_a_compact_commands_width_survives_pending_and_offline() -> void:
	var b := UiCommandButton.new("Deliver", UiCommandButton.Kind.PRIMARY, true)
	b.sends = true
	b.min_width = 152.0
	add_child(auto_free(b))
	await get_tree().process_frame
	var w := b.get_combined_minimum_size().x
	assert_float(w).is_greater_equal(152.0)
	for phase in [CommandLifecycle.State.PENDING, CommandLifecycle.State.IDLE]:
		b.phase = phase
		assert_float(b.get_combined_minimum_size().x).is_equal(w)
	UiCommandButton.set_offline(get_tree(), true)
	assert_float(b.get_combined_minimum_size().x).is_equal(w)
	UiCommandButton.set_offline(get_tree(), false)
	assert_float(b.get_combined_minimum_size().x).is_equal(w)
