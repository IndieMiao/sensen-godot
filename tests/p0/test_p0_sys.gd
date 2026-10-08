extends GdUnitTestSuite
## Network states (SGODOT-233; §10.7.1, WP6 SYS-CMD-FAIL / SYS-OFFLINE / -2 / -3): one failed request says `Didn't go
## through · try again` for 3 s; a second in a row goes Offline — the banner with Retry stays, the action keys read
## `Offline`, the server is checked every 5 s and on Retry; the next answer says `Back online` for 1.5 s.

const STORE := "user://test_p0_sys.json"

var rt: P0Runtime
var asked: Array = []

func before_test() -> void:
	asked = []
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, path, _b, _c): asked.append(path)   # no server: the test answers
	add_child(rt)
	await get_tree().process_frame
	rt.session.busy = false
	asked.clear()

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _fail() -> void: rt.session.connection_failed.emit("Can't reach the farm server", {"type": "buy", "item": "seed_radish"})
func _read_fail() -> void: rt.session.connection_failed.emit("Can't reach the farm server", {})   # a state read (refresh)
func _answer() -> void: rt.session.state_changed.emit(rt.session.view, [])

func test_one_failure_says_it_did_not_go_through() -> void:
	_fail()
	assert_str(rt.ui.sys_text()).is_equal("Didn't go through · try again")
	assert_int(rt.ui._sys.kind).is_equal(UiSysBanner.Kind.CMD_FAIL)
	assert_bool(rt.ui.offline).is_false()
	await get_tree().create_timer(P0Runtime.CMD_FAIL_S + 0.1).timeout
	assert_str(rt.ui.sys_text()).is_empty()

func test_two_in_a_row_go_offline_and_the_keys_say_so() -> void:
	_fail()
	_fail()
	assert_bool(rt.ui.offline).is_true()
	assert_str(rt.ui.sys_text()).is_equal("Offline · Reconnecting…")
	rt.ui.set_action({"verb": "Sow ×1", "sub": "2 Energy", "enabled": true, "need": 2, "cmd": {"type": "sow"}})
	var key: UiSceneAction = rt.ui._keys.key()
	assert_that([key.verb, key.cost, key.state]).is_equal(["Sow ×1", "Offline", UiSceneAction.State.UNAVAILABLE])
	_fail()   # a failed command while offline does not replace the Offline line
	assert_str(rt.ui.sys_text()).is_equal("Offline · Reconnecting…")

func test_retry_checks_now_and_an_answer_is_back_online() -> void:
	_fail()
	_fail()
	rt.ui._sys.retry_button().pressed.emit()
	assert_array(asked).contains(["/p0/state"])
	_answer()
	assert_bool(rt.ui.offline).is_false()
	assert_str(rt.ui.sys_text()).is_equal("Back online")
	rt.ui.set_action({"verb": "Sow ×1", "sub": "2 Energy", "enabled": true, "need": 2, "cmd": {"type": "sow"}})
	assert_str(rt.ui._keys.key().cost).is_equal("2 Energy")
	await get_tree().create_timer(P0Runtime.BACK_ONLINE_S + 0.1).timeout
	assert_str(rt.ui.sys_text()).is_empty()

func test_offline_checks_the_server_every_five_seconds() -> void:
	_fail()
	_fail()
	rt._probe_left = 0.05
	await get_tree().create_timer(0.2).timeout
	assert_array(asked).contains(["/p0/state"])
	assert_float(rt._probe_left).is_greater(P0Runtime.PROBE_S - 1.0)

func test_the_offline_line_stays_over_an_open_drawer() -> void:
	rt.ui.open_bag()
	await get_tree().process_frame
	_fail()
	_fail()
	assert_int(rt.ui._sys.get_index()).is_greater(rt.ui._modal.get_index())

## WP6 (206 31317bce): while the system line is up, the creel badge and the status line move down 48 under it.
func test_the_creel_badge_moves_down_under_the_system_line() -> void:
	var y: float = rt.ui._creel.position.y
	_fail()
	assert_float(rt.ui._creel.position.y).is_equal(y + P0Ui.SYS_SHIFT)
	await get_tree().create_timer(P0Runtime.CMD_FAIL_S + 0.1).timeout
	assert_float(rt.ui._creel.position.y).is_equal(y)

## §10.7.1 "离线时": every command button reads `Offline` and does nothing; one that only opens or browses keeps working;
## an already unavailable one keeps its reason; the drawer stays open. Back online gives them their labels back.
func test_offline_greys_the_command_buttons_and_leaves_the_rest() -> void:
	var buy := UiCommandButton.new("Buy")
	buy.sends = true
	var gift := UiCommandButton.new("Gift")   # opens the gift drawer: local
	var short := UiCommandButton.new("Craft")
	short.sends = true
	short.reason = "Need 2 more Timber"
	for b in [buy, gift, short]: rt.ui.root.add_child(b)
	var fired: Array = []
	buy.activated.connect(func(): fired.append("buy"))
	gift.activated.connect(func(): fired.append("gift"))
	_fail()
	_fail()
	assert_that([buy.text, buy.disabled, gift.text, short.text]).is_equal(["Offline", true, "Gift", "Need 2 more Timber"])
	var built_now := UiCommandButton.new("Sell")   # a drawer refreshed while offline builds its buttons Offline too
	built_now.sends = true
	assert_str(built_now.text).is_equal("Offline")
	built_now.free()
	buy.pressed.emit()
	gift.pressed.emit()
	assert_array(fired).is_equal(["gift"])
	_answer()
	assert_that([buy.text, buy.disabled]).is_equal(["Buy", false])

func test_the_offline_flag_does_not_outlive_its_ui() -> void:
	_fail()
	_fail()
	assert_bool(UiCommandButton.offline).is_true()
	remove_child(rt)
	assert_bool(UiCommandButton.offline).is_false()
	add_child(rt)

## F-08 / §10.7.1 界面命令: the button that sent a keyed command locks at once and dims after
## MOTION_PENDING_DELAY_MS without a reply (label kept); the reply gives it back.
func test_a_panel_command_tracks_the_button_that_sent_it() -> void:
	var buy := UiCommandButton.new("Buy")
	buy.sends = true
	rt.ui.root.add_child(buy)
	buy.activated.connect(func(): rt.ui.command.emit({"type": "buy", "item": "seed_radish", "qty": 1}))
	buy.pressed.emit()
	assert_int(buy.phase).is_equal(CommandLifecycle.State.SUBMITTING)
	assert_array(asked).contains(["/p0/commands"])
	rt.ui.lifecycle.tick(Time.get_ticks_msec() + UiTokens.MOTION_PENDING_DELAY_MS)
	assert_that([buy.phase, buy.text, buy.modulate.a]).is_equal([CommandLifecycle.State.PENDING, "Buy", UiTokens.OPACITY_PENDING])
	var sent_before := asked.size()
	buy.pressed.emit()   # a repeat tap before the result: ignored
	assert_int(asked.size()).is_equal(sent_before)
	rt.session._finish(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({"ok": true, "state": {}, "events": []}).to_utf8_buffer(), {})
	assert_int(buy.phase).is_equal(CommandLifecycle.State.IDLE)

## A world action that did not go through ends the hold: no more sowing along the row on a dead line.
func test_a_failed_world_action_ends_the_hold() -> void:
	rt.ui.fab_held = true
	rt.session.connection_failed.emit("Can't reach the farm server", {"type": "sow", "plots": [3]})
	assert_bool(rt.ui.fab_held).is_false()

## Which card buttons send a command (P0ItemInfo.sends): Pin, nav rows and a bag card's Gift (it opens the gift drawer)
## stay local; the gift drawer's Gift, Equip, Eat, Sell send; unavailable ones keep their reason.
func test_card_buttons_that_send_commands() -> void:
	var cases := [
		[{id = &"pin", kind = &"secondary"}, &"bag", false],
		[{id = &"gift", kind = &"nav"}, &"bag", false],
		[{id = &"gift", kind = &"primary"}, &"bag", false],
		[{id = &"gift", kind = &"primary"}, &"gift", true],
		[{id = &"equip", kind = &"primary"}, &"gear", true],
		[{id = &"eat", kind = &"primary"}, &"bag", true],
		[{id = &"sell", kind = &"secondary"}, &"counter_sell", true],
		[{id = &"equipped", kind = &"unavailable"}, &"gear", false],
	]
	for c in cases: assert_bool(P0ItemInfo.sends(c[0], c[1])).override_failure_message(str(c)).is_equal(c[2])

## 亚瑟 on #84: a background read (the 30 s refresh, the deferred first read) that fails once is nothing the player did —
## no `Didn't go through`; it still counts, so two failures in a row of any kind go Offline.
func test_one_failed_read_shows_nothing_but_counts() -> void:
	_read_fail()
	assert_str(rt.ui.sys_text()).is_empty()
	assert_bool(rt.ui.offline).is_false()
	_read_fail()
	assert_bool(rt.ui.offline).is_true()
	assert_str(rt.ui.sys_text()).is_equal("Offline · Reconnecting…")

func test_a_read_and_a_command_failing_in_a_row_go_offline() -> void:
	_read_fail()
	_fail()
	assert_bool(rt.ui.offline).is_true()
	_answer()
	_fail()
	assert_str(rt.ui.sys_text()).is_equal("Didn't go through · try again")
	_read_fail()
	assert_bool(rt.ui.offline).is_true()
