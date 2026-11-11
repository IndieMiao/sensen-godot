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

func _view() -> Dictionary: return {"seq": 1, "save_version": 7, "energy": {"value": 100, "max": 200}, "coins": 50, "bag": {"capacity": 25, "slots": []}}

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

## q(290) (李元芳 on 0.2.25: a read given up at its 8 s took the screen to Can't connect, the slow card never came): a
## failed first read is no banner and not Can't connect yet — it goes again a second on, the slow card comes at 8 s and
## Can't connect at 20 with nothing read; then it is checked again on its own.
func test_a_failed_first_read_goes_again_and_cant_connect_waits_for_twenty_seconds() -> void:
	rt.cover_launch()
	rt.session.connection_failed.emit("Can't reach the farm server", {})
	assert_int(rt.ui.screen_kind()).is_equal(K.LAUNCH)
	assert_str(rt.ui.sys_text()).is_empty()
	assert_bool(rt.ui.offline).is_false()
	asked.clear()
	rt._tick_screens(P0Runtime.LAUNCH_RETRY_S + 0.05)   # read again
	assert_array(asked).contains(["/p0/state"])
	rt.session.busy = false
	rt.session.connection_failed.emit("Can't reach the farm server", {})   # and failed again
	rt._tick_screens(P0Runtime.LAUNCH_SLOW_S)
	assert_int(rt.ui.screen_kind()).is_equal(K.LAUNCH)
	assert_bool(rt.ui.screen().slow).is_true()   # the slow card, not Can't connect
	rt._tick_screens(P0Runtime.LAUNCH_FAIL_S - P0Runtime.LAUNCH_SLOW_S)
	assert_int(rt.ui.screen_kind()).is_equal(K.FAIL)
	asked.clear()
	rt.session.busy = false
	rt._tick_screens(P0Runtime.PROBE_S + 0.1)   # checked again on its own
	assert_array(asked).contains(["/p0/state"])
	rt.session.connection_failed.emit("Can't reach the farm server", {})   # a failure past 20 s stays Can't connect
	assert_int(rt.ui.screen_kind()).is_equal(K.FAIL)

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
	assert_str(P0LoadingLayer.destination("res://scenes/p0/p0_farm.tscn", {})).is_equal("San Francisco · Home")
	assert_object(rt._scene_overlay("res://scenes/farm/farm.tscn", {})).is_null()   # not a P0 world: AppRouter's own
	pond.free()

func test_the_scene_cover_shows_after_the_pending_delay_and_backs_out_only_after_a_failure() -> void:
	var layer := P0LoadingLayer.new("SF · Fern Pond")
	add_child(auto_free(layer))
	assert_float(layer.screen.modulate.a).is_equal(0.0)
	assert_bool(layer.close_button.visible).is_false()   # AppRouter's Back reads it
	layer._process(UiTokens.MOTION_PENDING_DELAY_MS / 1000.0)
	await get_tree().create_timer(P0LoadingLayer.FADE_IN_S + 0.05).timeout   # in over 150 ms (spec v1 §4)
	assert_float(layer.screen.modulate.a).is_equal(1.0)
	layer._process(P0LoadingLayer.SLOW_S)
	assert_bool(layer.screen.slow).is_true()
	var s := layer.screen
	# the town map's slow line: on its own pill under the bar, no spinner (L123v2 L2)
	assert_that([s._slow_pill.visible, s._caption.visible, s.spinner.visible, s._bar_track.visible]).is_equal([true, true, false, true])
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

## SGODOT-397 / 396 (后裔): the handshake carries the requests' x-p0-features, save_v7 in it — without it the server
## turns the join away with 426 like the version gate.
func test_the_handshake_carries_the_features_with_save_v7() -> void:
	assert_bool(P0Session.FEATURES.split(",").has("save_v7")).is_true()
	var o := P0Online.new()
	add_child(auto_free(o))
	o.player_id = "p0-test"
	o.features = P0Session.FEATURES
	o._connect()
	assert_array(Array(o.socket.handshake_headers)).contains(["x-p0-features: " + P0Session.FEATURES])
	o.stop()

## 不知火舞 233 walkthrough: a place that would not open stays on the blurred screen being left (no launch backdrop,
## no wordmark); Can't connect's card plus Go back. Retry opens the same place again; Go back (and Back) stays put.
func test_a_failed_place_offers_retry_and_the_way_back() -> void:
	var layer := P0LoadingLayer.new("SF · Fern Pond", null, "res://scenes/p0/p0_pond.tscn", {"pond_id": "pond_san_francisco_03"})
	var opened := []
	layer.reopen = func(p, a): opened.append([p, a])
	add_child(auto_free(layer))
	layer.failed()
	var s := layer.screen
	# the same town map under the modal scrim; the pin, the place and the bar folded away (L123v2 L3)
	assert_that([s._map.visible, s._scrim.visible, s._shot.visible, s._mark.visible, s._art.visible, s._place.visible, s._pin.visible,
		s._bar_track.visible, s.spinner.visible]).is_equal([true, true, false, false, false, false, false, false, false])
	assert_that([s.card.title.text, s.card.body.text, s.card.primary.text, s.card.secondary.text]).is_equal(
		["Couldn't get there", "Check your connection and try again.", "Retry", "Go back"])
	assert_object(layer.close_button).is_same(s.card.secondary)
	var cleared := [0]
	layer.close_button.pressed.connect(func(): cleared[0] += 1)
	s.card.primary.pressed.emit()   # Retry
	await get_tree().process_frame
	assert_int(cleared[0]).is_equal(1)   # AppRouter's transition is cleared first …
	assert_that(opened).is_equal([["res://scenes/p0/p0_pond.tscn", {"pond_id": "pond_san_francisco_03"}]])   # … then the same place

## The user 11-06 (00:40; 不知火舞's spec v1 + 425 120c7163, frame L123v2): the scene cover is the town map under a 15 %
## haze, the destination's pin, the place on a white pill and a 200 × 8 bar on the centre line — no spinner, no screen
## read back from the GPU.
func test_the_scene_cover_is_the_town_map_with_the_pin_the_place_and_the_bar() -> void:
	var layer := P0LoadingLayer.new("San Francisco · Fern Pond", null, "res://scenes/p0/p0_pond.tscn", {"pond_id": "pond_san_francisco_03"})
	add_child(auto_free(layer))
	var s := layer.screen
	s.size = Vector2(360, 800)
	s._layout()
	assert_that([s._map.visible, s._haze.visible, s._shot.visible, s._scrim.visible, s.spinner.visible]).is_equal([true, true, false, false, false])
	assert_str(s._map.texture.resource_path).is_equal(P0SysScreen.SCENE_MAP)   # loaded with the cover, not the script
	assert_float(s._haze.color.a).is_equal_approx(0.15, 0.001)
	assert_object(s._pin_icon.texture).is_not_null()   # the pond's own pin icon
	assert_float(s._pin.position.y + s._pin.size.y).is_equal(360.0)   # the disc ends at 360
	assert_float(s._place_pill.position.y + s._place_pill.size.y * 0.5).is_equal(410.0)
	assert_that([s._bar_track.position, s._bar_track.size]).is_equal([Vector2(80, 444), Vector2(200, 8)])
	assert_that(s._place.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_TEXT)
	var pill := s._place_pill.get_theme_stylebox(&"panel") as UiStyleBox
	assert_that([pill.bg_color, pill.border_color, pill.border_width, pill.shadow_offset]).is_equal(
		[UiTokens.COLOR_SURFACE, UiTokens.COLOR_BORDER, 1.0, Vector2(0, 2)])
	assert_that((s._bar_track.get_theme_stylebox(&"panel") as UiStyleBox).bg_color).is_equal(Color("E1DAC8"))
	# a taller screen keeps them on its centre (y − 400 from it)
	s.size = Vector2(360, 900)
	s._layout()
	assert_float(s._bar_track.position.y).is_equal(494.0)

## The bar: the threaded load's own progress up to 85 %, filled once the scene is in, eased (≤ 0.25 s), never back;
## then it holds and fades out, taking no touch. A cover never shown (a quick load) goes at once.
func test_the_scene_cover_bar_follows_the_load_and_the_cover_fades_out_after_it() -> void:
	var layer := P0LoadingLayer.new("San Francisco · Fern Pond", null, "res://scenes/p0/p0_farm.tscn", {})
	add_child(layer)
	layer._process(UiTokens.MOTION_PENDING_DELAY_MS / 1000.0)   # shown
	layer.progress(0.5)
	layer._process(0.1)
	assert_float(layer.screen.progress).is_greater(0.0)
	layer._process(1.0)
	assert_float(layer.screen.progress).is_equal_approx(0.425, 0.001)   # 0.5 of the load = 42.5 %
	layer.progress(0.2)   # never back
	layer._process(1.0)
	assert_float(layer.screen.progress).is_equal_approx(0.425, 0.001)
	layer.progress(1.0)
	layer._process(1.0)
	assert_float(layer.screen.progress).is_equal_approx(0.85, 0.001)
	layer.finish()
	assert_int(layer.screen.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(layer.is_in_group(GameUi.MODAL_GROUP)).is_false()
	layer._process(1.0)
	assert_float(layer.screen.progress).is_equal(1.0)
	assert_bool(is_instance_valid(layer)).is_true()   # it holds, then fades out …
	await get_tree().create_timer(P0LoadingLayer.MIN_SHOWN_S + P0LoadingLayer.FADE_OUT_S + 0.3).timeout
	assert_bool(is_instance_valid(layer)).is_false()   # … and goes
	var quick := P0LoadingLayer.new("San Francisco · Fern Pond", null, "res://scenes/p0/p0_farm.tscn", {})
	add_child(quick)
	quick.finish()   # never shown: no hold, no fade
	await get_tree().process_frame
	assert_bool(is_instance_valid(quick)).is_false()

## Each destination's pin wears its map pin's icon: the farm's home, a pond's site, a mine's type; none for others.
func test_the_launch_screen_does_not_load_the_town_map() -> void:
	var launch := auto_free(P0SysScreen.new()) as P0SysScreen
	launch.show_kind(P0SysScreen.Kind.LAUNCH)
	assert_object(launch._map.texture).is_null()

func test_the_scene_cover_pin_wears_the_destination_icon() -> void:
	assert_object(P0LoadingLayer.icon_for("res://scenes/p0/p0_farm.tscn", {})).is_same(P0Logic.icon("home"))
	assert_object(P0LoadingLayer.icon_for("res://scenes/p0/p0_pond.tscn", {"pond_id": "pond_san_francisco_03"})).is_not_null()
	assert_object(P0LoadingLayer.icon_for("res://scenes/p0/p0_mine.tscn", {"mine": "wd-nowhere", "floor": 1})).is_same(P0Logic.icon("quarry"))
	assert_object(P0LoadingLayer.icon_for("res://scenes/other.tscn", {})).is_null()

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
	stub.source_code = "extends Node\nvar asked := 0\nfunc is_back_navigation_locked() -> bool:\n\tasked += 1\n\treturn true"
	stub.reload()
	var w := auto_free(Node.new()) as Node
	w.set_script(stub)
	w.scene_file_path = "res://scenes/p0/p0_pond.tscn"
	add_child(w)
	rt.attach(w)
	_state()
	rt.return_to = "pond:pond_san_francisco_03"   # the map's chip would go back here
	var left := [0]
	rt.swap_root = func(): left[0] += 1
	rt.session.refused.emit("travel_required", {"preview": {"cluster": "gn-5355933", "name": "Hayward"}}, {"type": "cast"})
	assert_str(rt.after_leave).is_equal("travel:gn-5355933")
	assert_int(left[0]).is_equal(1)   # off to the map
	assert_int(w.asked).is_equal(0)   # the panel's lock never asked
	# not a place to go back to: the map's chip names where the player is (不知火舞 on #642: it kept the pond's name)
	assert_str(rt.return_to).is_equal("farm")

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

# ---------------------------------------------------------------- q(290) the splash (不知火舞's spec v1, 302 c9986a33)

## A screen on a phone-sized host (it fills its parent).
func _screen_on(size: Vector2) -> P0SysScreen:
	var host: Control = auto_free(Control.new())
	host.size = size
	add_child(host)
	var s := P0SysScreen.new()
	host.add_child(s)
	return s

## 420 (spec v1.1 §2): the splash keeps the screen's height, centred, at her five ratios (21:9-ish 0.43, the art's
## 0.4618, 18:9, 16:9, 3:4) — the art's bottom on the screen's, the wordmark's top (row 85) at least 8 under the status
## bar (24 on Android, 47 on an iPhone).
func test_the_splash_keeps_the_screens_height_centred() -> void:
	for c in [[Vector2(360, 837.2), 47.0], [Vector2(375, 812), 47.0], [Vector2(360, 720), 24.0], [Vector2(360, 640), 24.0],
			[Vector2(600, 800), 24.0]]:
		var screen: Vector2 = c[0]
		var l := P0SysScreen.splash_layout(screen)
		var s := float(l.scale)
		var o: Vector2 = l.origin
		var why := "%s" % screen
		assert_float(s).override_failure_message(why).is_equal_approx(screen.y / 812.0, 0.0001)
		assert_float(o.y).override_failure_message(why).is_equal(0.0)
		assert_float(o.y + P0SysScreen.SPLASH_SIZE.y * s).override_failure_message(why).is_equal_approx(screen.y, 0.01)   # the art's bottom too
		assert_float(o.x * 2.0 + P0SysScreen.SPLASH_SIZE.x * s).override_failure_message(why).is_equal_approx(screen.x, 0.01)   # centred
		assert_bool(o.y + P0SysScreen.SPLASH_MARK_TOP * s >= float(c[1]) + 8.0).override_failure_message(why).is_true()
	# The art (747 of the 1214, at x 233): 21:9 cuts 14 off each side of it; 16:9 shows 32 of the blurred sides each side
	var art_left := func(screen: Vector2) -> float:
		var l := P0SysScreen.splash_layout(screen)
		return float((l.origin as Vector2).x) + 233.0 / 1618.0 * 812.0 * float(l.scale)
	assert_float(roundf(art_left.call(Vector2(360, 840)))).is_equal(-14.0)
	assert_float(roundf(art_left.call(Vector2(360, 640)))).is_equal(32.0)

## The boot splash draws the same file the same way: project.godot's image is this script's, Keep Height (3), and the
## engine's rect (RenderingServerTypes::get_splash_stretched_screen_rect, in the window's pixels) is this layout's at the
## content scale — so the boot splash hands over to the launch cover pixel for pixel.
func test_the_boot_splash_is_the_same_image_laid_out_the_same() -> void:
	assert_bool(ProjectSettings.get_setting("application/boot_splash/show_image")).is_true()
	assert_int(ProjectSettings.get_setting("application/boot_splash/stretch_mode")).is_equal(3)
	assert_str(ProjectSettings.get_setting("application/boot_splash/image")).is_equal(P0SysScreen.SPLASH.resource_path)
	assert_str((ProjectSettings.get_setting("application/boot_splash/bg_color") as Color).to_html(false)).is_equal(
		P0SysScreen.SPLASH_SKY.to_html(false))
	var img := Vector2(P0SysScreen.SPLASH.get_size())
	assert_vector(img).is_equal(Vector2(1214, 1618))
	assert_float(P0SysScreen.SPLASH_SIZE.x / P0SysScreen.SPLASH_SIZE.y).is_equal_approx(img.x / img.y, 0.000001)
	for c in [[Vector2(1080, 2400), 3.0], [Vector2(1170, 2532), 3.0], [Vector2(720, 1280), 2.0], [Vector2(1080, 2160), 3.0]]:
		var window: Vector2 = c[0]
		var k: float = c[1]
		var engine := Rect2(Vector2((window.x - img.x * window.y / img.y) / 2.0, 0.0), Vector2(img.x * window.y / img.y, window.y))
		var l := P0SysScreen.splash_layout(window / k)
		var ours := Rect2((l.origin as Vector2) * k, P0SysScreen.SPLASH_SIZE * float(l.scale) * k)
		assert_vector(ours.position).override_failure_message("%s" % window).is_equal_approx(engine.position, Vector2.ONE * 0.01)
		assert_vector(ours.size).override_failure_message("%s" % window).is_equal_approx(engine.size, Vector2.ONE * 0.01)

## The launch cover is the splash on the sky colour, no farm backdrop and no wordmark over it; Can't connect is the same
## art under the scrim with its card; maintenance keeps its backdrop and wordmark (not in q(290)).
func test_the_launch_and_cant_connect_show_the_splash_and_nothing_over_it() -> void:
	var s := _screen_on(Vector2(360, 720))   # an 18:9: the blurred sides showing
	s.show_kind(K.LAUNCH)
	assert_float(s._splash.modulate.a).is_equal(1.0)   # whole from its first frame (420): no fade in from the sky
	assert_float(s.modulate.a).is_equal(1.0)
	await get_tree().process_frame
	assert_that(s._bg.color).is_equal(P0SysScreen.SPLASH_SKY)
	assert_that([s._splash.visible, s._art.visible, s._mark.visible, s._scrim.visible, s._slow_card.visible]).is_equal(
		[true, false, false, false, false])
	assert_vector(s._splash.size).is_equal_approx(P0SysScreen.SPLASH_SIZE * (720.0 / 812.0), Vector2.ONE * 0.01)
	assert_float(s._splash.get_rect().get_center().x).is_equal_approx(180.0, 0.01)
	s.show_kind(K.FAIL)
	await get_tree().process_frame
	assert_that([s._splash.visible, s._mark.visible, s._art.visible, s._scrim.visible, s.card.visible]).is_equal([true, false, false, true, true])
	s.show_kind(K.MAINT)
	await get_tree().process_frame
	assert_that([s._splash.visible, s._mark.visible, s._art.visible]).is_equal([false, true, true])
	assert_that(s._bg.color).is_equal(UiTokens.COLOR_SURFACE)

## 8 s in: the spinner and `Taking longer than usual…` on a 90 % surface card, centred, ending 16 above the art's small
## Gensen mark (row 752) — not over a face.
func test_taking_longer_sits_on_a_card_above_the_arts_gensen_mark() -> void:
	var s := _screen_on(Vector2(360, 800))
	s.show_kind(K.LAUNCH)
	s.taking_longer()
	await get_tree().process_frame
	var l := P0SysScreen.splash_layout(s.size)
	var card := s._slow_card.get_rect()
	assert_bool(s._slow_card.visible).is_true()
	assert_float(card.end.y).is_equal_approx(roundf(float((l.origin as Vector2).y) + 752.0 * float(l.scale) - 16.0), 1.0)
	assert_float(card.get_center().x).is_equal_approx(180.0, 1.0)
	assert_bool(card.encloses(s.spinner.get_rect())).is_true()
	assert_float(s._caption.position.y + s._caption.get_combined_minimum_size().y).is_less_equal(card.end.y)
	var box := s._slow_card.get_theme_stylebox(&"panel") as UiStyleBox
	assert_float(box.bg_color.a).is_equal_approx(0.9, 0.001)

## Taken down, the launch cover is gone at once for everything that asks (screen_kind), and still fades into the scene
## under it: at least 0.8 s after it showed, then 300 ms, its layer freed after.
func test_the_splash_fades_into_the_scene_after_its_least_time() -> void:
	rt.cover_launch()
	var layer := rt.ui._screen_layer
	var screen := rt.ui.screen()
	rt.ui.hide_screen([K.LAUNCH])
	assert_int(rt.ui.screen_kind()).is_equal(-1)
	assert_bool(is_instance_valid(layer)).is_true()   # still drawn
	assert_int(screen.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)   # takes no touch now
	await get_tree().create_timer(0.5).timeout
	assert_bool(is_instance_valid(layer)).is_true()   # under its 0.8 s
	await get_tree().create_timer(0.9).timeout
	assert_bool(is_instance_valid(layer)).is_false()

## iOS 0.2.25 crashed at launch (蒙恬's stack: Viewport::get_visible_rect on a null viewport): the launch cover comes from
## a deferred call before the UI is in the tree, and safe_top() read its viewport. Out of the tree it is 0 and nothing is
## read; the cover (laid out by the screen's height alone since 420) shows once it is in the tree.
func test_the_launch_cover_before_the_ui_is_in_the_tree_reads_no_viewport() -> void:
	OS.set_environment("P0_DEV_SAFE_TOP", "24")
	var ui := P0Ui.new()
	ui.quick_store = STORE
	assert_float(ui.safe_top()).is_equal(0.0)   # out of the tree: no viewport read
	assert_float(ui.safe_bottom()).is_equal(0.0)
	ui.show_screen(K.LAUNCH)
	add_child(auto_free(ui))
	await get_tree().process_frame
	assert_float(ui.safe_top()).is_equal(24.0)
	assert_int(ui.screen_kind()).is_equal(K.LAUNCH)
	assert_bool(ui.screen()._splash.visible).is_true()
	OS.unset_environment("P0_DEV_SAFE_TOP")
