extends GdUnitTestSuite
## q(219) (SGODOT-338 / 345): an account's first two bites always land. The server marks the open cast `sure`; the panel
## then keeps the hook window open (the float stays down until the player hooks), the reel's progress never drops to
## zero and there is no 30 s timeout. The player still hooks and reels: nothing is sent until they do. Other bites fail
## as before. Driven frame by frame on a P0Runtime whose session records commands instead of sending them.

class Recorder extends P0Session:
	var cmds: Array = []
	func send(cmd: Dictionary, _key := "") -> bool:
		cmds.append(cmd)
		return true

const STEP := 0.05   # FishingModel's step_ms
## The reel's fish swims by a seeded generator, and left alone the bar still overlaps it now and then: with randi()'s seed
## a reel with the thumb off was landed by luck about 8% of the time (22% within 35 s on a sure bite), so these tests
## seed it. With seed 1 a Common fish left alone escapes when not sure and is still on the line after 40 s when sure.
const SEED := 1

func _setup(sure: bool) -> P0FishingPanel:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var rec: Recorder = auto_free(Recorder.new())
	rec.view = {"fishing": {"cast": {"rarity": 1, "hook_ms": 2200, "breaks": null, "sure": sure}}}
	rt.session = rec
	var panel: P0FishingPanel = auto_free(P0FishingPanel.new())
	panel.rt = rt
	add_child(panel)
	await get_tree().process_frame
	panel.set_process(false)   # frames are stepped by hand below
	panel.show()
	panel.on_cast({"bite_in": 0, "rarity": 1, "breaks": null})
	return panel

## Hook, with the reel seeded (SEED) instead of randi().
func _hook(panel: P0FishingPanel) -> void:
	panel._p0_hook()
	panel.model = FishingModel.initial(SEED)

func _sent(panel: P0FishingPanel) -> Array:
	return (panel.rt.session as Recorder).cmds

## The bite came and the hook window ran out 5 s ago.
func _miss_the_window(panel: P0FishingPanel) -> void:
	var now := float(Time.get_ticks_msec())
	panel._bite_at = now - 7200.0
	panel._hook_until = now - 5000.0
	panel._process(0.016)

func test_a_sure_bite_waits_for_the_hook() -> void:
	var panel := await _setup(true)
	_miss_the_window(panel)
	assert_str(panel.phase).is_equal("hook")      # the float stays down, the key says Hook
	assert_array(_sent(panel)).is_empty()         # nothing settles until the player hooks
	for i in 200: panel._process(STEP)            # 10 s more: still waiting for the tap
	assert_str(panel.phase).is_equal("hook")
	assert_array(_sent(panel)).is_empty()

func test_any_other_bite_still_escapes_when_the_window_runs_out() -> void:
	var panel := await _setup(false)
	_miss_the_window(panel)
	assert_array(_sent(panel)).is_equal([{"type": "reel", "outcome": "escaped"}])

func test_a_sure_reel_left_alone_never_fails_and_lands_once_reeled() -> void:
	var panel := await _setup(true)
	_miss_the_window(panel)
	_hook(panel)
	panel.held = false
	for i in 700:   # 35 s with the thumb off: past the 30 s timeout, the bar sinks and the fish swims off
		panel._process(STEP)
		assert_str(str(panel.model.outcome)).is_equal("playing")
		assert_float(float(panel.model.progress)).is_greater_equal(FishingModel.SURE_FLOOR)
	assert_array(_sent(panel)).is_empty()
	panel._process(0.8)   # a stalled frame (the app paused) is skipped, not reported
	assert_array(_sent(panel)).is_empty()
	P0FishingPanel.auto_play = true   # now reel properly: the band on the fish
	for i in 600:
		panel._process(STEP)
		if not _sent(panel).is_empty(): break
	P0FishingPanel.auto_play = false
	assert_array(_sent(panel)).is_equal([{"type": "reel", "outcome": "landed"}])

func test_any_other_reel_left_alone_escapes() -> void:
	var panel := await _setup(false)
	panel._bite_at = float(Time.get_ticks_msec()) - 100.0
	panel._process(0.016)
	_hook(panel)
	panel.held = false
	for i in 700:
		panel._process(STEP)
		if not _sent(panel).is_empty(): break
	assert_array(_sent(panel)).is_equal([{"type": "reel", "outcome": "escaped"}])

func test_the_model_floor_and_timeout_only_change_with_sure() -> void:
	var tier: Dictionary = (FishingModel.data().tiers["4"] as Dictionary).duplicate()   # Legendary: the fastest loss
	var plain := FishingModel.initial(7)
	while plain.outcome == "playing": FishingModel.step(plain, false, tier)
	assert_str(str(plain.outcome)).is_equal("escaped")
	tier["sure"] = true
	var sure := FishingModel.initial(7)
	var least := 1.0
	for i in int(FishingModel.data().max_steps) * 2:
		FishingModel.step(sure, false, tier)
		least = minf(least, float(sure.progress))
	assert_str(str(sure.outcome)).is_equal("playing")
	# down to the floor and never under it (the fish passing through the idle bar lifts it now and then: q(282)'s band)
	assert_float(least).is_equal_approx(FishingModel.SURE_FLOOR, 0.0001)
	assert_float(float(sure.progress)).is_greater_equal(FishingModel.SURE_FLOOR)

func after_test() -> void:
	P0FishingPanel.auto_play = false
