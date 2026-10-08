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

func _fail() -> void: rt.session.connection_failed.emit("Can't reach the farm server", {})
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
