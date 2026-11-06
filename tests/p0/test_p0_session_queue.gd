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
	var data := {"ok": ok, "state": {"seq": state_seq, "save_version": 7}}
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

# preview B ② (奕星 11-05): a ladder's reply lost, the floor reached and paid on the server; the player stayed on the
# floor until a tap 20 s later. The session reads what the server did as soon as the command has failed.
func test_a_command_whose_reply_was_lost_reads_what_the_server_did() -> void:
	var settled := []
	session.command_settled.connect(func(k, ok, code): settled.append([k, ok, code]))
	session.send({"type": "mine_floor", "to": 11, "via": "ladder"}, "mine_move")
	assert_bool(session.send({"type": "mine_floor", "to": 11, "via": "ladder"}, "mine_move")).is_false()   # a tap again
	_fail()
	assert_array(settled).contains_exactly([["mine_move", false, "network"]])
	assert_int(sent.size()).is_equal(2)
	assert_str(str(sent[1].path)).is_equal("/p0/state")
	_reply(9)
	assert_int(int(session.view.seq)).is_equal(9)
	assert_int(sent.size()).is_equal(2)   # once
	assert_bool(session.send({"type": "mine_floor", "to": 12, "via": "ladder"}, "mine_move")).is_true()

func test_after_a_lost_reply_waiting_world_actions_go_first_then_the_read_and_a_failed_read_is_not_read_again() -> void:
	session.send({"type": "sow", "plot": 3, "seed": "seed_radish"})
	session.send({"type": "collect"})
	_fail()
	assert_str(str(sent[1].cmd.type)).is_equal("collect")
	_reply(8)
	assert_str(str(sent[2].path)).is_equal("/p0/state")
	_fail()
	assert_int(sent.size()).is_equal(3)

func test_a_blocked_reply_reads_nothing_more() -> void:
	session.send({"type": "sow", "plot": 3, "seed": "seed_radish"})
	var body := JSON.stringify({"code": "maintenance"}).to_utf8_buffer()
	session._finish(HTTPRequest.RESULT_SUCCESS, 503, body, sent[-1].cmd)
	assert_int(sent.size()).is_equal(1)   # the runtime's maintenance screen checks again on its own

func test_a_read_queued_behind_a_failed_one_is_dropped() -> void:
	session.refresh()
	session.space = "home"
	session.refresh_after()
	_fail()
	assert_int(sent.size()).is_equal(1)   # the runtime's retry reads again, not this

# SGODOT-341: guide acknowledgement and passive maturity reads share the real command queue.
func _guide_timer(ms: float) -> void:
	session.view = {"seq": 7, "guide": {"step": "t_sow_rest"},
		"plots": [{"id": 0, "crop": "crop_quick_radish", "state": "growing", "ready_in": ms}]}

func test_expired_guide_crop_reads_once_without_changing_the_local_step() -> void:
	_guide_timer(45000)
	session._refresh_guide_maturity(44999)
	assert_array(sent).is_empty()
	session._refresh_guide_maturity(45000)
	session._refresh_guide_maturity(46000)
	assert_int(sent.size()).is_equal(1)
	assert_str(str(sent[0].path)).is_equal("/p0/state")
	assert_str(str(session.view.guide.step)).is_equal("t_sow_rest")

func test_expired_crop_waits_for_the_command_and_does_not_storm_after_failure() -> void:
	_guide_timer(45000)
	session.send({"type": "sow", "plot": 2, "seed": "seed_lettuce"})
	session._refresh_guide_maturity(45000)
	session._refresh_guide_maturity(46000)
	assert_int(sent.size()).is_equal(1)
	_reply(8)
	assert_int(sent.size()).is_equal(2)
	assert_str(str(sent[1].path)).is_equal("/p0/state")
	_fail()
	session._refresh_guide_maturity(47000)
	assert_int(sent.size()).is_equal(2)

func test_an_expired_crop_on_a_legacy_save_does_not_add_a_read() -> void:
	_guide_timer(45000)
	var legacy: Dictionary = session.view.duplicate(true)   # the session's view is read-only (SGODOT-260 Q3): a changed copy in its place
	legacy.guide = {"step": null, "end": "legacy"}
	session.view = legacy
	session._refresh_guide_maturity(50000)
	assert_array(sent).is_empty()

func test_guide_ack_is_deduped_and_build_uses_its_returned_seq() -> void:
	session.view = _guided(session.view)
	assert_bool(session.guide_ack("t_city")).is_true()
	assert_bool(session.guide_ack("t_city")).is_false()
	session.send({"type": "choose_home", "city": "gn-1850147", "spot": 0}, "build")
	assert_int(sent.size()).is_equal(1)
	assert_str(str(sent[0].body.step)).is_equal("t_city")
	_reply(8)
	assert_str(str(sent[1].body.type)).is_equal("choose_home")
	assert_int(int(sent[1].body.expect_seq)).is_equal(8)
	assert_bool(session.guide_ack("t_city")).is_false()

func test_ack_failure_discards_the_queued_build_until_an_explicit_retry() -> void:
	session.view = _guided(session.view)
	session.guide_ack("t_city")
	session.send({"type": "choose_home", "city": "gn-1850147", "spot": 0}, "build")
	_fail()
	assert_int(sent.size()).is_equal(2)
	assert_str(str(sent[1].path)).is_equal("/p0/state")   # what the lost ack did, not the build
	var still := _guided({"seq": 7, "save_version": 7})   # the ack had not gone through
	session._finish(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({"ok": true, "state": still}).to_utf8_buffer(), {})
	assert_int(sent.size()).is_equal(2)
	assert_bool(session.guide_ack("t_city")).is_true()
	assert_int(sent.size()).is_equal(3)

func test_a_resolved_row_deadline_also_queues_one_refresh() -> void:
	session.view = {"guide": {"step": "t_harvest_quick", "row": {"countdown": "crop_quick_radish", "ready_in": 3000}}}
	session._refresh_guide_maturity(2999)
	assert_array(sent).is_empty()
	session._refresh_guide_maturity(3000)
	session._refresh_guide_maturity(4000)
	assert_int(sent.size()).is_equal(1)
	_fail()
	session._refresh_guide_maturity(5000)
	assert_int(sent.size()).is_equal(1)

func test_an_authoritative_zero_countdown_waits_for_action_instead_of_reading_forever() -> void:
	session.view = {"guide": {"step": "t_nadia_1", "recover": "r_radish_wait", "row": {"countdown": "crop_radish", "ready_in": 0}}}
	for elapsed in [0.0, 1000.0, 10000.0]: session._refresh_guide_maturity(elapsed)
	assert_array(sent).is_empty()

## The view with the guide on its first step (the session's view is read-only, SGODOT-260 Q3: a changed copy in its place).
func _guided(v: Dictionary) -> Dictionary:
	var out := v.duplicate(true)
	out.guide = {"step": "t_city"}
	return out
