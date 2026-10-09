extends GdUnitTestSuite
## Which pond the player is at (q(36), SGODOT-232 S6): the session sends the catalog pond id with the entry read and
## with every command from the pond, beside the command, so the server takes the template from its own table.

var session: P0Session
var sent: Array

func before_test() -> void:
	session = auto_free(P0Session.new())
	sent = []
	session.transport = func(method: int, path: String, body: Dictionary, cmd: Dictionary): sent.append({path = path, body = body, cmd = cmd})
	session.view = {"seq": 3}

func test_the_entry_read_names_the_pond() -> void:
	session.space = "pond"
	session.place = "pond_san_francisco_03"
	session.refresh()
	assert_str(str(sent[0].path)).is_equal("/p0/state?space=pond&place=pond_san_francisco_03")

func test_no_place_without_a_space() -> void:
	session.place = "pond_san_francisco_03"
	session.refresh()
	assert_str(str(sent[0].path)).is_equal("/p0/state")

func test_commands_carry_the_pond_they_were_issued_from() -> void:
	session.space = "pond"
	session.place = "pond_san_francisco_06"
	var cast := {"type": "cast"}
	session.send(cast)
	assert_str(str(sent[0].body.place)).is_equal("pond_san_francisco_06")
	assert_bool(cast.has("place")).is_false()   # beside the command, never inside it
	session.busy = false
	session.space = "home"
	session.place = ""
	session.send({"type": "rest"})
	assert_bool(sent[1].body.has("place")).is_false()
