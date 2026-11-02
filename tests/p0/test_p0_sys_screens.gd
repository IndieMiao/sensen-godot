extends GdUnitTestSuite
## Whole-screen system states (SGODOT-233; WP6 E-03, §10.7.1, q(74)): the launch cover SYS-LOADING / -2 / -FAIL, the
## resume cover, SYS-LOADING-SCENE for the P0 worlds AppRouter opens, SYS-MAINT and SYS-UPDATE.

const STORE := "user://test_p0_sys_screens.json"
const K := P0SysScreen.Kind

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

func _view() -> Dictionary: return {"seq": 1, "energy": {"value": 100, "max": 200}, "coins": 50, "bag": {"capacity": 25, "slots": []}}

## The server's answer to the request on the wire, through the session as an HTTP reply would come.
func _reply(code: int, body: Dictionary) -> void:
	rt.session.busy = true
	rt.session._finish(HTTPRequest.RESULT_SUCCESS, code, JSON.stringify(body).to_utf8_buffer(), {})

func _state() -> void: _reply(200, {"ok": true, "state": _view(), "events": []})

# ---------------------------------------------------------------- launch
func test_the_launch_cover_waits_for_the_first_answer_and_a_world() -> void:
	rt.cover_launch()
	assert_int(rt.ui.screen_kind()).is_equal(K.LAUNCH)
	_state()
	assert_int(rt.ui.screen_kind()).is_equal(K.LAUNCH)   # no world yet
	var w := auto_free(Node.new()) as Node
	add_child(w)
	rt.attach(w)
	assert_int(rt.ui.screen_kind()).is_equal(-1)

func test_eight_seconds_add_the_spinner_and_twenty_say_cant_connect() -> void:
	rt.cover_launch()
	rt._tick_screens(P0Runtime.LAUNCH_SLOW_S + 0.1)
	assert_bool(rt.ui.screen().slow).is_true()
	assert_bool(rt.ui.screen().spinner.visible).is_true()
	rt._tick_screens(P0Runtime.LAUNCH_FAIL_S)
	assert_int(rt.ui.screen_kind()).is_equal(K.FAIL)
	assert_that([rt.ui.screen().card.title.text, rt.ui.screen().card.primary.text]).is_equal(["Can't connect", "Retry"])
	rt.ui.screen().card.primary.pressed.emit()   # Retry reads the state now
	assert_array(asked).contains(["/p0/state"])

func test_a_failed_first_read_is_cant_connect_not_a_banner() -> void:
	rt.cover_launch()
	rt.session.connection_failed.emit("Can't reach the farm server", {})
	assert_int(rt.ui.screen_kind()).is_equal(K.FAIL)
	assert_str(rt.ui.sys_text()).is_empty()
	assert_bool(rt.ui.offline).is_false()
	rt._tick_screens(P0Runtime.PROBE_S + 0.1)   # checked again on its own
	assert_array(asked).contains(["/p0/state"])

func test_back_does_not_close_a_system_screen() -> void:
	rt.cover_launch()
	assert_bool(rt.ui.close_top_layer()).is_true()
	assert_int(rt.ui.screen_kind()).is_equal(K.LAUNCH)

# ---------------------------------------------------------------- maintenance and update (q(74))
func test_a_maintenance_reply_shows_its_card_and_an_answer_takes_it_down() -> void:
	rt.session.view = _view()
	_reply(503, {"ok": false, "code": "maintenance"})
	assert_int(rt.ui.screen_kind()).is_equal(K.MAINT)
	assert_that([rt.ui.screen().card.title.text, rt.ui.screen().card.body.text, rt.ui.screen().card.primary.text]).is_equal(
		["Down for maintenance", "We'll be back soon.", "Check again"])
	assert_bool(rt.ui.offline).is_false()   # not a network failure: no banner, no Offline count
	assert_str(rt.ui.sys_text()).is_empty()
	rt._tick_screens(P0Runtime.MAINT_CHECK_S + 0.1)   # every 60 s on its own
	assert_array(asked).contains(["/p0/state"])
	asked.clear()
	rt.session.busy = false   # that read came back still in maintenance
	rt.ui.screen().card.primary.pressed.emit()   # Check again
	assert_array(asked).contains(["/p0/state"])
	_state()
	assert_int(rt.ui.screen_kind()).is_equal(-1)

func test_update_outranks_maintenance_and_stays_until_an_answer() -> void:
	rt.session.view = _view()
	_reply(426, {"ok": false, "code": "update_required", "url": "https://example.test/p0demo.apk"})
	assert_int(rt.ui.screen_kind()).is_equal(K.UPDATE)
	assert_str(rt.ui.screen().card.primary.text).is_equal("Update")
	_reply(503, {"ok": false, "code": "maintenance", "back_at": "2099-01-01T00:00:00Z"})
	assert_int(rt.ui.screen_kind()).is_equal(K.UPDATE)   # SYS-UPDATE > SYS-MAINT
	assert_bool(rt.ui.close_top_layer()).is_true()       # no close: Back does nothing
	assert_int(rt.ui.screen_kind()).is_equal(K.UPDATE)

func test_only_the_matching_body_code_is_a_whole_screen_refusal() -> void:
	var raw := func(d: Dictionary) -> PackedByteArray: return JSON.stringify(d).to_utf8_buffer()
	assert_str(str(P0Session.blocked_reply(HTTPRequest.RESULT_SUCCESS, 503, raw.call({"code": "maintenance"})).code)).is_equal("maintenance")
	assert_str(str(P0Session.blocked_reply(HTTPRequest.RESULT_SUCCESS, 426, raw.call({"code": "update_required", "url": "u"})).url)).is_equal("u")
	assert_that(P0Session.blocked_reply(HTTPRequest.RESULT_SUCCESS, 503, "Service Unavailable".to_utf8_buffer())).is_equal({})   # a proxy's 503
	assert_that(P0Session.blocked_reply(HTTPRequest.RESULT_SUCCESS, 503, raw.call({"code": "update_required"}))).is_equal({})
	assert_that(P0Session.blocked_reply(HTTPRequest.RESULT_CANT_CONNECT, 503, raw.call({"code": "maintenance"}))).is_equal({})
	# a plain 5xx is still a network failure: Didn't go through for a command
	var failed := []
	rt.session.connection_failed.connect(func(m, _c): failed.append(m))
	_reply(503, {"error": "upstream"})
	assert_int(failed.size()).is_equal(1)

func test_maintenance_time_reads_the_local_clock() -> void:
	var now := int(Time.get_unix_time_from_datetime_string("2026-10-09T05:00:00"))
	assert_str(P0Runtime.back_at_text("2026-10-09T06:30:00Z", now, 480)).is_equal("14:30")         # UTC+8, today
	assert_str(P0Runtime.back_at_text("2026-10-09T18:30:00Z", now, 480)).is_equal("Oct 10, 02:30")  # tomorrow there
	assert_str(P0Runtime.back_at_text("2026-10-09T04:00:00Z", now, 480)).is_empty()                 # already past
	assert_str(P0Runtime.back_at_text("", now, 480)).is_empty()
	assert_str(P0Runtime.back_at_text("soon", now, 480)).is_empty()

func test_the_version_goes_out_with_every_request() -> void:
	rt.session.version = 2026100901
	assert_array(Array(rt.session._headers())).contains(["x-p0-version: 2026100901"])
	rt.session.version = 0
	assert_bool(Array(rt.session._headers()).any(func(h): return str(h).begins_with("x-p0-version"))).is_false()

func test_an_outpost_room_is_left_while_a_card_is_up_and_joined_again_after() -> void:
	var online := P0Online.new()
	online.outpost = "tea_house"
	online._stopped = false
	add_child(auto_free(online))
	rt.session.view = _view()
	_reply(503, {"ok": false, "code": "maintenance"})
	assert_bool(online._stopped).is_true()
	_state()
	assert_bool(online._stopped).is_false()

# ---------------------------------------------------------------- resume and scene loading
func test_a_slow_read_on_return_gets_a_cover_over_the_place() -> void:
	rt.session.view = _view()
	rt.ui.set_place("San Francisco · Fern Pond")
	rt._on_resumed()
	assert_array(asked).contains(["/p0/state"])
	rt._tick_screens(0.0)
	assert_int(rt.ui.screen_kind()).is_equal(-1)   # quick reads never flash it
	rt._resume_ms -= UiTokens.MOTION_PENDING_DELAY_MS
	rt._tick_screens(0.0)
	assert_int(rt.ui.screen_kind()).is_equal(K.SCENE)
	assert_str(rt.ui.screen()._place.text).is_equal("San Francisco · Fern Pond")
	_state()
	assert_int(rt.ui.screen_kind()).is_equal(-1)

func test_opening_a_p0_world_names_where_the_player_is_going() -> void:
	var pond := rt._scene_overlay("res://scenes/p0/p0_pond.tscn", {"pond_id": "pond_san_francisco_03"}) as P0LoadingLayer
	assert_object(pond).is_not_null()
	# the city in full (q(107): the Today icon leaves the place chip 300 wide, so SF is no longer needed)
	assert_str(pond.screen._place.text).is_equal("San Francisco · Fern Pond")
	assert_str(P0LoadingLayer.destination("res://scenes/p0/p0_mine.tscn", {"floor": 3})).is_equal("San Francisco · Mine · Floor 3")
	assert_str(P0LoadingLayer.destination("res://scenes/p0/p0_farm.tscn", {})).is_equal("San Francisco · Homestead")
	assert_object(rt._scene_overlay("res://scenes/farm/farm.tscn", {})).is_null()   # not a P0 world: AppRouter's own
	pond.free()

func test_the_scene_cover_shows_after_the_pending_delay_and_backs_out_only_after_a_failure() -> void:
	var layer := P0LoadingLayer.new("SF · Fern Pond")
	add_child(auto_free(layer))
	assert_float(layer.screen.modulate.a).is_equal(0.0)
	assert_bool(layer.close_button.visible).is_false()   # AppRouter's Back reads it
	layer._process(UiTokens.MOTION_PENDING_DELAY_MS / 1000.0)
	assert_float(layer.screen.modulate.a).is_equal(1.0)
	layer._process(P0LoadingLayer.SLOW_S)
	assert_bool(layer.screen.slow).is_true()
	layer.failed()
	assert_that([layer.close_button.visible, layer.close_button.text]).is_equal([true, "Go back"])

func test_the_runtime_hands_appRouter_its_scene_cover_and_takes_it_back() -> void:
	assert_bool(AppRouter.loading_overlay_factory.is_valid()).is_true()
	remove_child(rt)
	assert_bool(AppRouter.loading_overlay_factory.is_valid()).is_false()
	add_child(rt)

## 蒙恬 on q(74): the outpost room's handshake carries the version too, so an old build's join is turned away (426)
## the same way as its requests; no version, no header.
func test_the_outpost_handshake_carries_the_version() -> void:
	var o := P0Online.new()
	add_child(auto_free(o))
	o.player_id = "p0-test"
	o.version = 2026100901
	o._connect()
	assert_array(Array(o.socket.handshake_headers)).contains(["x-p0-version: 2026100901"])
	o.version = 0
	o._connect()
	assert_bool(Array(o.socket.handshake_headers).any(func(h): return str(h).begins_with("x-p0-version"))).is_false()
	o.stop()

## 不知火舞 233 walkthrough: a place that would not open stays on the blurred screen being left (no launch backdrop,
## no wordmark); Can't connect's card plus Go back. Retry opens the same place again; Go back (and Back) stays put.
func test_a_failed_place_offers_retry_and_the_way_back() -> void:
	var shot := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8))
	var layer := P0LoadingLayer.new("SF · Fern Pond", shot, "res://scenes/p0/p0_pond.tscn", {"pond_id": "pond_san_francisco_03"})
	var opened := []
	layer.reopen = func(p, a): opened.append([p, a])
	add_child(auto_free(layer))
	layer.failed()
	var s := layer.screen
	assert_that([s._shot.visible, s._shot.texture == shot, s._mark.visible, s._art.visible, s._place.visible, s.spinner.visible]).is_equal(
		[true, true, false, false, false, false])
	assert_that([s.card.title.text, s.card.body.text, s.card.primary.text, s.card.secondary.text]).is_equal(
		["Couldn't get there", "Check your connection and try again.", "Retry", "Go back"])
	assert_object(layer.close_button).is_same(s.card.secondary)
	var cleared := [0]
	layer.close_button.pressed.connect(func(): cleared[0] += 1)
	s.card.primary.pressed.emit()   # Retry
	await get_tree().process_frame
	assert_int(cleared[0]).is_equal(1)   # AppRouter's transition is cleared first …
	assert_that(opened).is_equal([["res://scenes/p0/p0_pond.tscn", {"pond_id": "pond_san_francisco_03"}]])   # … then the same place

# ---------------------------------------------------------------- getting there (q(78))
func _arrive_at_pond() -> Node:
	rt.session.view = _view()
	rt._scene_overlay("res://scenes/p0/p0_pond.tscn", {"pond_id": "pond_san_francisco_03"}).free()
	var w := auto_free(Node.new()) as Node
	w.scene_file_path = "res://scenes/p0/p0_pond.tscn"
	add_child(w)
	rt.attach(w)
	return w

func test_the_scene_cover_stays_until_the_places_first_read_answers() -> void:
	_arrive_at_pond()
	assert_bool(asked.any(func(p): return str(p).begins_with("/p0/state"))).is_true()   # the arrival read
	rt._tick_screens(0.0)
	assert_int(rt.ui.screen_kind()).is_equal(-1)   # a quick trip never flashes it
	rt._arrive.t0 -= UiTokens.MOTION_PENDING_DELAY_MS
	rt._tick_screens(0.0)
	assert_int(rt.ui.screen_kind()).is_equal(K.SCENE)
	rt._tick_screens(P0Runtime.LAUNCH_SLOW_S)
	assert_bool(rt.ui.screen().slow).is_true()
	_state()
	assert_int(rt.ui.screen_kind()).is_equal(-1)

func test_a_failed_arrival_says_couldnt_get_there_and_retry_goes_again() -> void:
	_arrive_at_pond()
	rt.session.connection_failed.emit("Can't reach the farm server", {})
	assert_int(rt.ui.screen_kind()).is_equal(K.PLACE_FAIL)
	assert_str(rt.ui.screen().card.title.text).is_equal("Couldn't get there")
	assert_str(rt.ui.sys_text()).is_empty()   # over the Offline banner's place: no banner, no count
	assert_int(rt._net_fails).is_equal(0)
	asked.clear()
	rt.session.busy = false
	rt.ui.screen().card.primary.pressed.emit()   # Retry
	assert_int(rt.ui.screen_kind()).is_equal(K.SCENE)
	assert_bool(asked.any(func(p): return str(p).begins_with("/p0/state"))).is_true()
	rt._tick_screens(P0Runtime.ARRIVE_FAIL_S + 0.1)   # 20 s without an answer
	assert_int(rt.ui.screen_kind()).is_equal(K.PLACE_FAIL)

## SGODOT-382: a room that refused the join (TRAVEL_REQUIRED) sent the player back to the map before the trip arrived —
## the trip is over: no Couldn't get there 20 s later over the map; and one already up closes on Go back even when
## its trip was dropped.
func test_a_trip_that_ends_on_the_map_is_over_and_couldnt_get_there_always_closes() -> void:
	rt.session.view = _view()
	rt._scene_overlay("res://scenes/p0/p0_outpost.tscn", {"outpost_id": "gn-5355933~market0"}).free()
	var room := auto_free(Node.new()) as Node
	room.scene_file_path = "res://scenes/p0/p0_outpost.tscn"
	add_child(room)
	rt.attach(room)
	var map := auto_free(Node.new()) as Node
	map.scene_file_path = "res://scenes/p0/p0_map.tscn"
	add_child(map)
	rt.attach(map)   # the room left for the map (P0Outpost._on_online_failed)
	rt._tick_screens(P0Runtime.ARRIVE_FAIL_S + 0.1)
	assert_int(rt.ui.screen_kind()).is_equal(-1)   # nothing over the map
	rt._arrival_failed()   # as before the fix: Couldn't get there with no trip behind it
	assert_int(rt.ui.screen_kind()).is_equal(K.PLACE_FAIL)
	rt.swap_root = func(): pass
	rt.ui.screen().card.secondary.pressed.emit()   # Go back
	assert_int(rt.ui.screen_kind()).is_equal(-1)

## SGODOT-382: a pond (no travel card of its own) told travel_required goes back to the map for that city's travel card.
func test_travel_required_in_a_pond_goes_back_to_the_maps_travel_card() -> void:
	var w := _arrive_at_pond()
	_state()
	rt.swap_root = func(): pass
	rt.session.refused.emit("travel_required", {"preview": {"cluster": "gn-5355933", "name": "Hayward"}}, {"type": "cast"})
	assert_str(rt.after_leave).is_equal("travel:gn-5355933")
	assert_bool(is_instance_valid(w)).is_true()

## 周瑜 on #642: refused while the pond's fishing panel is up (its back lock closes the panel and keeps the pond) — it
## still goes back to the map for the travel card; the lock is not asked.
func test_travel_required_with_the_fishing_panel_up_still_goes_back_to_the_map() -> void:
	rt.session.view = _view()
	rt._scene_overlay("res://scenes/p0/p0_pond.tscn", {"pond_id": "pond_san_francisco_03"}).free()
	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar asked := 0\nfunc is_back_navigation_locked() -> bool:\n\tasked += 1\n\treturn true\n"
	stub.reload()
	var w := auto_free(Node.new()) as Node
	w.set_script(stub)
	w.scene_file_path = "res://scenes/p0/p0_pond.tscn"
	add_child(w)
	rt.attach(w)
	_state()
	var left := [0]
	rt.swap_root = func(): left[0] += 1
	rt.session.refused.emit("travel_required", {"preview": {"cluster": "gn-5355933", "name": "Hayward"}}, {"type": "cast"})
	assert_str(rt.after_leave).is_equal("travel:gn-5355933")
	assert_int(left[0]).is_equal(1)   # off to the map
	assert_int(w.asked).is_equal(0)   # the panel's lock never asked

func test_go_back_and_back_leave_for_where_the_player_came_from() -> void:
	var left := [0]
	rt.swap_root = func(): left[0] += 1   # not pushed on AppRouter here: Go back takes the map way
	_arrive_at_pond()
	rt.session.connection_failed.emit("Can't reach the farm server", {})
	rt.ui.screen().card.secondary.pressed.emit()   # Go back
	assert_int(rt.ui.screen_kind()).is_equal(-1)
	assert_int(left[0]).is_equal(1)
	_arrive_at_pond()
	rt.session.connection_failed.emit("Can't reach the farm server", {})
	assert_bool(rt.ui.close_top_layer()).is_true()   # Back is Go back
	assert_int(rt.ui.screen_kind()).is_equal(-1)
	assert_int(left[0]).is_equal(2)
