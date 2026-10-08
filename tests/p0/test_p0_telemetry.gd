extends GdUnitTestSuite
## Observation log on the client (SGODOT-232 S7): commands carry how they were pressed beside the command, and UI
## moments go out in batches apart from the command queue.

var session: P0Session
var sent: Array

func before_test() -> void:
	session = auto_free(P0Session.new())
	sent = []
	session.transport = func(method: int, path: String, body: Dictionary, cmd: Dictionary): sent.append({path = path, body = body, cmd = cmd})
	session.view = {"seq": 3}

func test_commands_say_how_they_were_pressed() -> void:
	var key := {held = true}   # a dictionary, so the lambda sees the change (locals are captured by value)
	session.src_of = func(): return "hold" if key.held else "tap"
	var sow := {"type": "sow", "plot": 0, "seed": "seed_radish"}
	session.send(sow)
	assert_str(str(sent[0].body.src)).is_equal("hold")
	assert_bool(sow.has("src")).is_false()
	session.busy = false
	key.held = false
	session.send({"type": "sell", "item": "crop_radish", "qty": 1})
	assert_str(str(sent[1].body.src)).is_equal("tap")

func test_ui_moments_go_out_in_batches_without_touching_the_command_queue() -> void:
	session.report({"kind": "tip_shown", "key": "sow"})
	assert_int(sent.size()).is_equal(0)
	session._flush_ui()
	assert_str(str(sent[0].path)).is_equal("/p0/telemetry")
	assert_that(sent[0].body.events).is_equal([{"kind": "tip_shown", "key": "sow"}])
	assert_bool(session.busy).is_false()
	for i in 20: session.report({"kind": "screen"})
	assert_int(sent.size()).is_equal(2)   # a full batch goes at once
	assert_int((sent[1].body.events as Array).size()).is_equal(20)

## PR #23 review (刘邦): pressing the main action key is a tap even while it is still down; only the farm's
## hold-to-repeat commands are holds.
func test_a_press_is_a_tap_and_only_hold_repeats_are_holds() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	session.src_of = rt.src_of_press
	session.send({"type": "sow", "plot": 0, "seed": "seed_radish"})
	assert_str(str(sent[0].body.src)).is_equal("tap")
	session.busy = false
	rt.holding_repeat = true
	session.send({"type": "sow", "plot": 1, "seed": "seed_radish"})
	rt.holding_repeat = false
	assert_str(str(sent[1].body.src)).is_equal("hold")

## UI reports go out with the same headers as commands, the demo key included (a deployed server asks for it).
func test_ui_reports_carry_the_demo_key() -> void:
	session.player_id = "p0-telemetry-key"
	session.access_key = "demo-key"
	assert_that(Array(session._headers())).contains(["x-p0-player: p0-telemetry-key", "x-p0-key: demo-key"])

## int9: the vivo shows no app logcat, so each world's load timings (P0_TIMING) also go to the observation log.
func test_a_scene_load_reports_its_timings_and_the_device() -> void:
	var e := P0Runtime.scene_load_event("P0Outpost", "sh_tea_1", 912, 2036, 2287, false)
	assert_str(str(e.kind)).is_equal("scene_load")
	assert_that([e.scene, e.place, e.attach_ms, e.first_ms, e.second_ms, e.cold]).is_equal(["P0Outpost", "sh_tea_1", 912, 2036, 2287, false])
	assert_int(int(e.cores)).is_greater(0)
	assert_bool(e.has("model") and e.has("gpu")).is_true()
	session.report(e)
	session._flush_ui()
	assert_str(str(sent[0].path)).is_equal("/p0/telemetry")
	assert_str(str((sent[0].body.events as Array)[0].kind)).is_equal("scene_load")

## 亚瑟 on #94: only a navigation (or the first world after launch) reports a scene_load; a world attaching again when
## a layer above it closes has no navigation behind it and reports nothing.
func test_only_a_navigation_or_the_cold_start_reports_a_scene_load() -> void:
	P0Runtime._nav_pending = false
	P0Runtime._cold_done = false
	assert_that(P0Runtime.take_load_report()).is_equal({"report": true, "cold": true})     # the first world after launch
	assert_that(P0Runtime.take_load_report()).is_equal({"report": false, "cold": false})   # back from the farmhouse: no navigation
	P0Runtime.nav_started()
	assert_that(P0Runtime.take_load_report()).is_equal({"report": true, "cold": false})    # map → pond
	assert_that(P0Runtime.take_load_report()).is_equal({"report": false, "cold": false})   # taken once only
