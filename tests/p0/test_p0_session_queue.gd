extends GdUnitTestSuite
## P0Session command queue (SGODOT-211, WP7-B F-08 §2): UI commands dedupe by key, every command carries
## expect_seq from the latest view, responses are handled before the next send, and a network failure
## drops the waiting UI commands but keeps world actions.

var session: P0Session
var sent: Array

func before_test() -> void:
	session = auto_free(P0Session.new())   # not added to the tree: no refresh, no files
	sent = []
	session.transport = func(method: int, path: String, body: Dictionary, cmd: Dictionary): sent.append({method = method, path = path, body = body, cmd = cmd})
	session.view = {"seq": 7}

func _reply(state_seq: int, ok := true, code := "") -> void:
	var data := {"ok": ok, "state": {"seq": state_seq}}
	if not ok: data["code"] = code
	session._finish(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify(data).to_utf8_buffer(), sent[-1].cmd)

func _fail() -> void:
	session._finish(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray(), sent[-1].cmd)

func test_commands_carry_the_seen_state_version() -> void:
	session.send({"type": "sell", "item": "crop_radish", "qty": 1})
	assert_int(int(sent[0].body.expect_seq)).is_equal(7)
	assert_bool(sent[0].cmd.has("expect_seq")).is_false()   # the caller's dictionary is not modified

func test_a_repeated_ui_command_is_ignored_until_its_result() -> void:
	var sell := {"type": "sell", "item": "crop_radish", "qty": 1}
	assert_bool(session.send(sell, P0Session.ui_key(sell))).is_true()
	assert_bool(session.send(sell.duplicate(), P0Session.ui_key(sell))).is_false()
	assert_int(sent.size()).is_equal(1)
	_reply(8)
	assert_bool(session.send(sell, P0Session.ui_key(sell))).is_true()
	assert_int(int(sent[1].body.expect_seq)).is_equal(8)

func test_different_ui_commands_queue_and_use_the_fresh_seq() -> void:
	var one := {"type": "sell", "item": "crop_radish", "qty": 1}
	var all := {"type": "sell", "item": "crop_radish", "qty": 5}
	session.send(one, P0Session.ui_key(one))
	session.send(all, P0Session.ui_key(all))
	assert_int(sent.size()).is_equal(1)
	_reply(8)   # the queued command leaves only after this reply is handled
	assert_int(sent.size()).is_equal(2)
	assert_int(int(sent[1].body.expect_seq)).is_equal(8)

func test_world_actions_are_never_deduped() -> void:
	session.send({"type": "sow", "plot": 3, "seed": "seed_radish"})
	session.send({"type": "sow", "plot": 3, "seed": "seed_radish"})
	_reply(8)
	assert_int(sent.size()).is_equal(2)

func test_commands_sent_from_a_reply_handler_wait_behind_the_queue() -> void:
	session.send({"type": "reel", "outcome": "landed"})
	session.send({"type": "collect"})
	session.state_changed.connect(func(_v, _e): if sent.size() == 1: session.send({"type": "eat", "item": "dish_x"}), CONNECT_ONE_SHOT)
	_reply(8)
	assert_str(str(sent[1].cmd.type)).is_equal("collect")
	_reply(9)
	assert_str(str(sent[2].cmd.type)).is_equal("eat")

func test_network_failure_drops_waiting_ui_commands_but_keeps_world_actions() -> void:
	var settled := []
	session.command_settled.connect(func(k, ok, code): settled.append([k, ok, code]))
	var buy := {"type": "buy", "item": "seed_radish", "qty": 1}
	var sell := {"type": "sell", "item": "crop_radish", "qty": 1}
	session.send(buy, P0Session.ui_key(buy))
	session.send(sell, P0Session.ui_key(sell))
	session.send({"type": "collect"})
	_fail()
	assert_int(sent.size()).is_equal(2)
	assert_str(str(sent[1].cmd.type)).is_equal("collect")
	assert_array(settled).contains_exactly([[P0Session.ui_key(sell), false, "network"], [P0Session.ui_key(buy), false, "network"]])

func test_settles_report_refusals() -> void:
	var settled := []
	session.command_settled.connect(func(k, ok, code): settled.append([ok, code]))
	var buy := {"type": "buy", "item": "seed_radish", "qty": 1}
	session.send(buy, P0Session.ui_key(buy))
	_reply(7, false, "no_coins")
	assert_array(settled).is_equal([[false, "no_coins"]])

## 李元芳's cold start (SGODOT-278): the first read leaves before the farm is attached (no space); the farm attaching
## while it is out asks for one more read, sent once it is back and carrying ?space=home, so the server settles where
## the player is (#233) without waiting 30 s.
func test_a_space_entered_while_a_read_is_out_reads_again_with_it() -> void:
	session.refresh()
	assert_str(str(sent[0].path)).is_equal("/p0/state")
	session.space = "home"
	assert_bool(session.busy).is_true()
	session.refresh_after()
	assert_int(sent.size()).is_equal(1)   # not while the first is out
	_reply(8)
	assert_int(sent.size()).is_equal(2)
	assert_str(str(sent[1].path)).is_equal("/p0/state?space=home")
	_reply(8)
	assert_int(sent.size()).is_equal(2)   # once

func test_a_read_queued_behind_a_failed_one_is_dropped() -> void:
	session.refresh()
	session.space = "home"
	session.refresh_after()
	_fail()
	assert_int(sent.size()).is_equal(1)   # the runtime's retry reads again, not this
