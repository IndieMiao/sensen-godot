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
