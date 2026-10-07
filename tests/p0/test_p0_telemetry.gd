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
