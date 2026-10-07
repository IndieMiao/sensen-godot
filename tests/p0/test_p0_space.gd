extends GdUnitTestSuite
## Rest's 2 h away rule (q(41)): each command carries the space the player issued it from, beside the command
## (never inside the dedupe key), and the runtime sets that space when a world attaches or detaches.

var session: P0Session
var sent: Array

func before_test() -> void:
	session = auto_free(P0Session.new())
	sent = []
	session.transport = func(method: int, path: String, body: Dictionary, cmd: Dictionary): sent.append({path = path, body = body, cmd = cmd})
	session.view = {"seq": 3}

func _world(source: String) -> Object:
	var script := GDScript.new()
	script.source_code = "extends RefCounted\n" + source
	script.reload()
	return script.new()

func test_the_state_read_says_where_the_player_is() -> void:
	session.refresh()
	assert_str(str(sent[0].path)).is_equal("/p0/state")
	session.busy = false
	session.space = "outpost"
	session.refresh()
	assert_str(str(sent[1].path)).is_equal("/p0/state?space=outpost")

func test_commands_carry_the_space_beside_the_command() -> void:
	session.space = "pond"
	session.send({"type": "cast"})
	assert_str(str(sent[0].body.space)).is_equal("pond")
	assert_bool(sent[0].cmd.has("space")).is_false()

func test_no_space_is_sent_when_unknown() -> void:
	session.send({"type": "rest"})
	assert_bool(sent[0].body.has("space")).is_false()

func test_a_queued_command_keeps_the_space_it_was_issued_from() -> void:
	session.space = "pond"
	session.send({"type": "cast"})
	session.send({"type": "reel", "outcome": "landed"})   # waits behind the cast
	session.space = "home"
	session._finish(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({"ok": true, "state": {"seq": 4}}).to_utf8_buffer(), sent[-1].cmd)
	assert_str(str(sent[1].body.space)).is_equal("pond")

func test_dedupe_ignores_the_space() -> void:
	var sell := {"type": "sell", "item": "crop_radish", "qty": 1}
	session.space = "home"
	assert_bool(session.send(sell, P0Session.ui_key(sell))).is_true()
	session.space = "outpost"
	assert_bool(session.send(sell.duplicate(), P0Session.ui_key(sell))).is_false()
	assert_int(sent.size()).is_equal(1)

func test_space_of_prefers_the_world_then_its_surface() -> void:
	assert_str(P0Runtime.space_of(_world("func p0_surface() -> String: return \"farm\""))).is_equal("home")
	assert_str(P0Runtime.space_of(_world("func p0_surface() -> String: return \"pond\""))).is_equal("pond")
	assert_str(P0Runtime.space_of(_world("func p0_surface() -> String: return \"map\""))).is_equal("map")
	assert_str(P0Runtime.space_of(_world("func p0_surface() -> String: return \"room\""))).is_equal("")
	var house := _world("func p0_surface() -> String: return \"room\"\nfunc p0_space() -> String: return \"home\"")
	assert_str(P0Runtime.space_of(house)).is_equal("home")

func test_leaving_two_rooms_at_once_ends_on_the_map() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)   # builds the runtime's UI (detach closes its modal)
	await get_tree().process_frame
	var farm: Node = auto_free(Node.new())
	var house: Node = auto_free(Node.new())
	rt.world = house
	rt.session.space = "home"
	rt.detach(house)   # leave_world() from the farmhouse pops the farmhouse, then the farm under it
	rt.detach(farm)
	assert_str(rt.session.space).is_equal("map")
