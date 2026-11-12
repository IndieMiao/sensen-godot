extends GdUnitTestSuite
## GDScript errors to the server (SGODOT-486; 亚瑟's store plan §4 ②): errors and script errors only, as client_error
## with message / stack / scene cut to their sizes and no other field; nothing while the account's gate is closed and
## nothing kept for later; the same error once an hour; 20 a session.

const ErrorReport := preload("res://modules/p0/p0_error_report.gd")
const HOUR := 3600000

var session: P0Session
var sent: Array

func before_test() -> void:
	session = auto_free(P0Session.new())
	sent = []
	session.transport = func(_m: int, path: String, body: Dictionary, _cmd: Dictionary): sent.append({path = path, body = body})

func _reported() -> Array:
	session._flush_ui()
	var out: Array = []
	for s in sent: out.append_array(s.body.events)
	return out

func _queue(r, message: String, stack := "f res://a.gd:1") -> void:
	r._pending.append([message, stack])

func test_the_words_and_the_stack_are_cut_to_size() -> void:
	assert_str(ErrorReport.message_of("cond", "the reason")).is_equal("the reason")
	assert_str(ErrorReport.message_of("push_error text", "")).is_equal("push_error text")
	assert_int(ErrorReport.message_of("x".repeat(900), "").length()).is_equal(500)
	var frames: Array = []
	for i in 30: frames.append(["f%d" % i, "res://" + "d/".repeat(120) + "a.gd", i])
	var lines := ErrorReport.stack_of(frames).split("\n")
	assert_int(lines.size()).is_equal(20)
	assert_bool(Array(lines).all(func(l): return l.length() <= 200)).is_true()
	assert_str(ErrorReport.stack_of([["_boom", "res://x.gd", 14]])).is_equal("_boom res://x.gd:14")

func test_an_event_is_four_fields_and_no_other() -> void:
	var e := ErrorReport.event_of("m", "s", "P0Farm" + "x".repeat(100))
	assert_array(e.keys()).contains_exactly_in_any_order(["kind", "message", "stack", "scene"])
	assert_str(str(e.kind)).is_equal("client_error")
	assert_int(str(e.scene).length()).is_equal(64)

func test_nothing_goes_while_the_gate_is_closed_nor_later() -> void:
	var r = ErrorReport.new()
	_queue(r, "boom")
	r.drain(session, "P0Farm", 1000)   # identity_ready false (no account yet, or not past the age gate)
	assert_array(_reported()).is_empty()
	session.identity_ready = true
	r.drain(session, "P0Farm", 2000)
	assert_array(_reported()).is_empty()   # dropped, not kept to send now
	_queue(r, "boom")
	r.drain(session, "P0Farm", 3000)
	assert_array(_reported()).is_equal([{"kind": "client_error", "message": "boom", "stack": "f res://a.gd:1", "scene": "P0Farm"}])

func test_the_same_error_once_an_hour() -> void:
	var r = ErrorReport.new()
	session.identity_ready = true
	for t in [0, 1000, HOUR - 1]:
		_queue(r, "same")
		r.drain(session, "", t)
	_queue(r, "other")
	r.drain(session, "", 5000)
	assert_int(_reported().size()).is_equal(2)
	sent.clear()
	_queue(r, "same")
	r.drain(session, "", HOUR + 1)
	assert_int(_reported().size()).is_equal(1)

func test_twenty_a_session() -> void:
	var r = ErrorReport.new()
	session.identity_ready = true
	for i in 30: _queue(r, "e%d" % i)
	r.drain(session, "", 0)
	assert_int(_reported().size()).is_equal(20)
	assert_int(r.sent).is_equal(20)

## The engine's own calls: an error and a script error are queued with their stack, a warning is not.
func test_it_takes_errors_not_warnings() -> void:
	var r = ErrorReport.new()
	OS.add_logger(r)
	push_warning("only a warning")
	push_error("c67 probe error")
	OS.remove_logger(r)
	var msgs: Array = r._pending.map(func(e): return e[0])
	assert_array(msgs).contains(["c67 probe error"])
	assert_array(msgs).not_contains(["only a warning"])
	var mine: Array = r._pending.filter(func(e): return e[0] == "c67 probe error")
	assert_str(str(mine[0][1])).contains("test_it_takes_errors_not_warnings")

## A runtime not in the tree adds no logger (tests); one in it does, and takes it away on leaving.
func test_the_runtime_holds_the_logger_while_it_is_up() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	assert_object(rt.errors).is_not_null()
	assert_bool(rt.session.identity_ready).is_false()
