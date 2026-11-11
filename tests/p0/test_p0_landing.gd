extends GdUnitTestSuite
## q(311) ④ (SGODOT-470): the landing's wait — CONNECT_MS while the room's socket opens, then WAIT_MS from its opening
## (gs66 11-11: a slow first load's long frames ate the 1.5 s before the socket was even open, and the player stayed on
## the spawn though the room had put them elsewhere) and MIN_FRAMES frames at least (one long frame is one); the first
## `joined` lands, a later one or one past the wait does not.

func _online() -> P0Online:
	var o: P0Online = auto_free(P0Online.new())
	o.transport = func(_m: Dictionary): pass
	o.outpost = "landmark:alcatraz_island"
	return o

func test_the_wait_counts_from_the_socket_opening() -> void:
	var o := _online()
	var l := P0Landing.new()
	var places: Array[Vector2] = [Vector2(0, 0), Vector2(0.75, 0)]
	l.begin(o, places, Vector3.ZERO)
	var opened_by: int = l._until - Time.get_ticks_msec()
	assert_int(opened_by).is_greater(P0Landing.WAIT_MS)   # still opening: CONNECT_MS
	assert_bool(l.pending()).is_true()
	o.connection_changed.emit(true)
	var left: int = l._until - Time.get_ticks_msec()
	assert_int(left).is_less_equal(P0Landing.WAIT_MS)
	assert_int(left).is_greater(P0Landing.WAIT_MS - 200)
	var to := l.target({"first": true, "spawn": [0.75, 0.0]}, Vector3.ZERO)
	assert_vector(to).is_equal(Vector3(0.75, 0, 0))
	assert_bool(l.pending()).is_false()

func test_past_the_wait_nobody_moves_and_no_places_go_again() -> void:
	var o := _online()
	var places: Array[Vector2] = [Vector2(0, 0), Vector2(0.75, 0)]
	o.spawns = places
	var l := P0Landing.new()
	l.begin(o, places, Vector3.ZERO)
	l._until = Time.get_ticks_msec() - 1   # the wait ran out …
	assert_bool(l.pending()).is_true()       # … but in fewer than MIN_FRAMES frames (one long frame): still waiting
	l._frame0 -= P0Landing.MIN_FRAMES
	assert_bool(l.pending()).is_false()
	assert_bool(o.spawns.is_empty()).is_true()
	assert_vector(l.target({"first": true, "spawn": [0.75, 0.0]}, Vector3.ZERO)).is_equal(Vector3.INF)

## A room that does not answer: CONNECT_MS at most (and MIN_FRAMES), then the cover goes and the spawn stays.
func test_a_room_that_never_opens_waits_connect_ms() -> void:
	var l := P0Landing.new()
	var places: Array[Vector2] = [Vector2(0, 0), Vector2(0.75, 0)]
	l.begin(_online(), places, Vector3.ZERO)
	assert_int(l._until - Time.get_ticks_msec()).is_less_equal(P0Landing.CONNECT_MS)
	assert_int(P0Landing.CONNECT_MS).is_less_equal(2000)

func test_only_the_spawn_waits_for_nothing() -> void:
	var l := P0Landing.new()
	var places: Array[Vector2] = [Vector2(0, 0)]
	l.begin(_online(), places, Vector3.ZERO)
	assert_bool(l.pending()).is_false()

## A refused or unreachable room (the socket closed before opening), or a join the room refuses: no waiting at all
## (不知火舞 on #988) — only a socket still opening with no answer yet waits CONNECT_MS.
func test_a_refused_or_unreachable_room_ends_the_wait_at_once() -> void:
	var places: Array[Vector2] = [Vector2(0, 0), Vector2(0.75, 0)]
	for how in ["unreachable", "failed"]:
		var o := _online()
		o.spawns = places
		var l := P0Landing.new()
		l.begin(o, places, Vector3.ZERO)
		assert_bool(l.pending()).is_true()
		if how == "unreachable": o.unreachable.emit()
		else: o.failed.emit("PASS_REQUIRED")
		assert_bool(l.pending()).override_failure_message(how).is_false()
		assert_bool(o.spawns.is_empty()).is_true()

## P0Online says so when the socket closes before it opened.
func test_online_says_unreachable_when_the_socket_closes_unopened() -> void:
	var o := _online()
	var said := [0]
	o.unreachable.connect(func(): said[0] += 1)
	o.url = "ws://127.0.0.1:1/v1/p0/online"   # nothing listens there
	o.player_id = "p0-testunreachable01"
	o.transport = Callable()
	add_child(o)
	o._open()
	for i in 120:
		await get_tree().process_frame
		if said[0] > 0: break
	assert_int(said[0]).is_greater(0)
	o.stop()

