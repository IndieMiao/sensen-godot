extends GdUnitTestSuite
## The landed-fish moment at the P0 pond (美术总监 / 不知火舞 on 231, 2026-10-09; spec comment 626cd8a0): the reply's
## `+25 XP` waited for nothing and rose over the fish still in flight. Now ① the reply's floats wait until the fish is in
## the hand and rise from 8 px over the player's head, a repeat species' `Pond Crucian ×1` in the same group after the XP
## and a first catch's Caught! card 0.5 s after them; ② the fish pops to 1.5× for its flight, 0.15 s in and out; and ③ (苏烈 on
## #143) the camera stays where the cast left it until the safe box moves it — or a pinch — and only then eases back.

const P0Pond := preload("res://scenes/p0/p0_pond.gd")
const STORE := "user://test_p0_catch_moment.json"
const PHONE := Vector2(360, 800)
const BAND := Rect2(0, 98, 360, 422)   # HUD row 2 … main key top at 360 × 800 in the pond (as test_p0_pond_camera)

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

# ---------------------------------------------------------------- ② the fish pops for its flight

func test_the_landed_fish_pops_to_1_5_for_its_flight_only_at_the_p0_pond() -> void:
	var view := FishingPresentation.new()
	assert_float(view.catch_pop).is_equal(1.0)   # Journey's pond, the street, remote players: as before
	for age in [0.0, 0.1, 0.6, 1.2]: assert_float(view.catch_scale(age)).is_equal(1.0)
	view.catch_pop = P0Pond.CATCH_POP
	assert_float(view.catch_scale(0.0)).is_equal(1.0)                                     # leaving the water
	assert_float(view.catch_scale(0.075)).is_between(1.01, 1.49)                         # growing
	for age in [FishingPresentation.CATCH_POP_S, 0.6, FishingPresentation.CATCH_LIFT_S - FishingPresentation.CATCH_POP_S]:
		assert_float(view.catch_scale(age)).is_equal_approx(1.5, 0.0001)                 # in flight
	assert_float(view.catch_scale(FishingPresentation.CATCH_LIFT_S - 0.075)).is_between(1.01, 1.49)   # back down …
	assert_float(view.catch_scale(FishingPresentation.CATCH_LIFT_S)).is_equal(1.0)        # … in the hand
	view.free()

## Through the presentation's own step: the fish node carries the scale on the arc, the camera untouched.
func test_the_arc_scales_the_fish_node_and_not_the_camera() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	add_child(auto_free(vp))
	var root := Node3D.new()
	vp.add_child(root)
	var actor := Node3D.new()
	actor.position = Vector3(6, 0, -2.6)
	root.add_child(actor)
	var rig := preload("res://assets/avatar/base/base_rig.tscn").instantiate() as AvatarRig
	actor.add_child(rig)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = P0Pond.view_size(PHONE, 1.0)
	root.add_child(cam)
	cam.make_current()
	P0Pond.place(cam, actor.position)
	var before := cam.global_transform
	var panel := P0FishingPanel.new()
	root.add_child(panel)
	panel.landing = Vector3(6, 0, -4.4)
	panel.set_process(false)
	panel.phase = "result"
	panel.model = {"outcome": "caught"}
	panel._last = {"outcome": "caught", "fish_id": "fish_crucian", "tier": 1}
	var view := FishingPresentation.new()
	view.close_up = false
	view.catch_pop = P0Pond.CATCH_POP
	root.add_child(view)
	view.configure(panel, actor, rig, cam, [])
	view.set_process(false)
	var seen := []
	for i in 25:   # 0.05 s a step: through the whole 1.25 s arc
		view.step(0.05)
		if view._catch.visible: seen.append(view._catch.scale.x)
	assert_float(seen.max()).is_equal_approx(1.5, 0.0001)
	assert_float(seen[0]).is_less(1.5)            # it grows out of the water
	assert_float(seen[-1]).is_less(1.5)           # and is back down before the hand
	assert_bool(view._catch.visible).is_false()   # in the hand
	assert_that(cam.global_transform).is_equal(before)
	view.finish()
	await get_tree().process_frame

class _Water extends FishingWater:   # the pond's water, its float rings recorded
	var calls := []
	func interact(point: Vector3, strength: float) -> void: calls.append([point, strength])

## The user 11-08 (SGODOT-447): a landed fish's float goes up with it to the hand; the water's rings and splash stayed
## under it and followed it. Through the whole arc they stay where it came out of the water, and fade there; the fish
## itself does leave that spot.
func test_a_landed_fishs_splash_stays_where_it_left_the_water() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	add_child(auto_free(vp))
	var root := Node3D.new()
	vp.add_child(root)
	var water := _Water.new()
	water.name = "zz_pond"
	root.add_child(water)
	var actor := Node3D.new()
	actor.position = Vector3(6, 0, -2.6)
	root.add_child(actor)
	var rig := preload("res://assets/avatar/base/base_rig.tscn").instantiate() as AvatarRig
	actor.add_child(rig)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	var panel := P0FishingPanel.new()
	root.add_child(panel)
	panel.site_id = "zz_pond"
	panel.landing = Vector3(6, 0, -4.4)
	panel.set_process(false)
	panel.phase = "playing"
	panel.model = {"outcome": "caught", "fish": 0.9}
	var view := FishingPresentation.new()
	view.close_up = false
	root.add_child(view)
	view.configure(panel, actor, rig, cam, [])
	view.set_process(false)
	for i in 10: view.step(0.05)   # the fight: the rings follow the float
	assert_float(Vector2(water.calls[-1][0].x - 6.0, water.calls[-1][0].z + 4.4).length()).is_greater(0.05)
	panel.phase = "result"
	panel._last = {"outcome": "caught", "fish_id": "fish_crucian", "tier": 1}
	water.calls.clear()
	var strengths := []
	var away := 0.0
	for i in 25:   # 0.05 s a step: the 1.25 s arc
		view.step(0.05)
		var at: Vector3 = water.calls[-1][0]
		assert_vector(Vector2(at.x, at.z)).override_failure_message("rings at %s, step %d" % [at, i]).is_equal_approx(Vector2(6, -4.4), Vector2.ONE * 0.001)
		strengths.append(float(water.calls[-1][1]))
		if view._splash.visible:
			assert_vector(Vector2(view._splash.global_position.x, view._splash.global_position.z)).is_equal_approx(Vector2(6, -4.4), Vector2.ONE * 0.001)
		if view._catch.visible: away = maxf(away, Vector2(view._catch.global_position.x - 6.0, view._catch.global_position.z + 4.4).length())
	assert_float(away).is_greater(0.5)   # the fish did fly off
	assert_float(strengths[0]).is_greater(0.5)   # the fight's rings, at first …
	for i in range(1, strengths.size()): assert_float(strengths[i]).is_less_equal(strengths[i - 1])   # … fading
	assert_float(strengths[-1]).is_less(0.01)
	view.step(0.05)
	assert_float(float(water.calls[-1][1])).is_equal(0.0)   # in the hand: no rings
	view.finish()
	await get_tree().process_frame

# ---------------------------------------------------------------- ① the reply's floats wait for the hand

class _Shows extends Node:   # a world showing the catch itself, as the pond with its panel open
	func p0_event(ev: Dictionary, _v: Dictionary) -> bool: return str(ev.get("kind", "")) == "catch"

func _floats(ui: P0Ui) -> Array:
	return ui.root.get_children().filter(func(c): return c is UiFloatText and not c.is_queued_for_deletion())

func _runtime() -> P0Runtime:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE if rt.ui != null else STORE
	add_child(rt)
	await get_tree().process_frame
	var v := {"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []},
		"skills": {"fishing": {"level": 2}}, "names": {"fish_crucian": "Pond Crucian"}}
	rt.session.view = v
	return rt

func test_a_landed_fishs_floats_wait_for_the_hand_and_rise_as_one_group() -> void:
	var rt: P0Runtime = await _runtime()
	rt.world = auto_free(_Shows.new())
	var catch := {"kind": "catch", "result": "landed", "fish": "fish_crucian", "rarity": 1}
	rt._on_state(rt.session.view, [{"kind": "xp", "skill": "fishing", "amount": 25, "percent": 100}, catch])
	await get_tree().process_frame
	assert_array(_floats(rt.ui)).is_empty()   # the fish is still in flight: nothing over it
	# The pond, at the end of the arc: the held floats and the repeat species' line from over the head, one group.
	var head := Vector2(180, 330)
	var held := rt.take_catch_floats()
	assert_array(rt.take_catch_floats()).is_empty()   # handed over once
	rt.ui.queue_floats(held, head)
	rt._on_catch(catch, [], head, 0.0)
	await get_tree().process_frame
	var fl := _floats(rt.ui)
	assert_array(fl.map(func(f): return f.text)).is_equal(["+25 XP", "Pond Crucian ×1"])   # Energy → XP → items
	assert_float(fl[0]._base_y + fl[0].pivot_offset.y).is_equal_approx(head.y, 0.5)       # rising from the head
	assert_float(fl[0].position.x + fl[0].pivot_offset.x).is_equal_approx(head.x, 0.5)

func test_an_escape_and_a_catch_the_world_does_not_show_float_at_once() -> void:
	var rt: P0Runtime = await _runtime()
	var t := [1000]
	rt.ui.float_clock = func(): return t[0]
	rt.world = auto_free(_Shows.new())
	rt._on_state(rt.session.view, [{"kind": "xp", "skill": "fishing", "amount": 2, "percent": 100},
		{"kind": "catch", "result": "escaped", "fish": "fish_crucian", "rarity": 1}])
	await get_tree().process_frame
	assert_array(rt.catch_floats).is_empty()
	assert_array(_floats(rt.ui).map(func(f): return f.text)).is_equal(["+2 XP"])
	t[0] += 2000   # a later cast: its XP is a line of its own
	rt.world = null   # no panel to show it (e.g. after a reconnect): the catch is said straight away, its line beside the XP
	rt._on_state(rt.session.view, [{"kind": "xp", "skill": "fishing", "amount": 25, "percent": 100},
		{"kind": "catch", "result": "landed", "fish": "fish_crucian", "rarity": 1}])
	await get_tree().process_frame
	assert_array(rt.catch_floats).is_empty()
	assert_array(_floats(rt.ui).map(func(f): return f.text)).contains(["+25 XP", "Pond Crucian ×1"])

## 刘邦 on #154: a player who leaves the pond mid-arc never lets the held floats rise; the next catch — an escape here —
## must not float the last fish's `+25 XP`.
func test_floats_held_for_a_fish_never_landed_do_not_leak_into_the_next_catch() -> void:
	var rt: P0Runtime = await _runtime()
	rt.world = auto_free(_Shows.new())
	rt._on_state(rt.session.view, [{"kind": "xp", "skill": "fishing", "amount": 25, "percent": 100},
		{"kind": "catch", "result": "landed", "fish": "fish_crucian", "rarity": 1}])
	assert_array(rt.catch_floats).is_not_empty()   # held, and the pond is left before the hand: nobody takes them
	rt._on_state(rt.session.view, [{"kind": "catch", "result": "escaped", "fish": "fish_crucian", "rarity": 1}])
	assert_array(rt.take_catch_floats()).is_empty()

func test_a_first_catchs_card_comes_after_its_floats() -> void:
	var rt: P0Runtime = await _runtime()
	rt.last_first_catch_xp = 20
	rt._on_catch({"kind": "catch", "result": "landed", "fish": "fish_crucian", "rarity": 1}, [], Vector2(180, 330), 0.2)
	await get_tree().process_frame
	assert_bool(rt.ui.has_modal()).is_false()   # the floats play first
	await get_tree().create_timer(0.3).timeout
	assert_bool(rt.ui.has_modal()).is_true()    # then Caught!
	assert_float(P0Pond.CARD_AFTER_FLOATS_S).is_equal(0.5)   # the pond's wait (不知火舞 on #154): about 1.8 s after the catch
	rt.ui.close_modal()

# ---------------------------------------------------------------- ③ the camera after the cast (苏烈 on #143)

func _pond() -> Node3D:
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_pond.gd\"\nfunc _ready() -> void: pass\n"
	stub.reload()
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	add_child(auto_free(vp))
	var pond: Node3D = Node3D.new()
	pond.set_script(stub)
	vp.add_child(pond)
	pond.entry = preload("res://modules/p0/p0_ponds.gd").location("pond_san_francisco_03")   # Fern Pond
	pond.bp = SystemPonds.blueprint(pond.entry)
	pond.grid = BlueprintGrid.new(pond.bp)
	pond.cam = Camera3D.new()
	pond.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	pond.cam.keep_aspect = Camera3D.KEEP_WIDTH
	pond.add_child(pond.cam)
	pond.cam.make_current()
	pond.actor = P0Actor.new()
	pond.add_child(pond.actor)
	pond.actor.setup(pond.bp, pond.grid, pond.cam)
	pond.panel = P0FishingPanel.new()   # closed: the walking band, pinches allowed
	pond.add_child(pond.panel)
	pond.panel.hide()
	pond._band = BAND
	pond._opening = false
	return pond

## After a cast the camera holds still — however long the player stands — until the safe box moves it; then the
## meadow's clamp comes back eased, not in one jump. The cast's framing here sits 1.5 m nearer than the walking band
## allows (as a near-bank cast leaves it), the player inside the safe box; a walk east leaves the box.
func test_after_a_cast_the_camera_holds_until_the_safe_box_moves_it_then_eases_back() -> void:
	var pond := _pond()
	var cam: Camera3D = pond.cam
	cam.size = P0Pond.view_size(PHONE, 1.0)
	pond._focus = pond.actor.position + Vector3(0, 0, 1.5)
	P0Pond.place(cam, pond._focus)
	assert_float(pond._focus.distance_to(P0Pond.clamp_focus(pond._focus, cam.size, PHONE, BAND, PondScenery.MEADOW))).is_greater(0.5)
	assert_bool(P0Follow.box(PHONE).has_point(cam.unproject_position(pond.actor.position))).is_true()
	pond.view = FishingPresentation.new()
	pond._end_fishing()
	assert_bool(pond._parked).is_true()
	var parked: Vector3 = pond._focus
	for i in 90:   # 1.5 s standing still: past the safe box's 0.6 s settle
		pond.actor.step(1.0 / 60.0)
		pond._follow(1.0 / 60.0)
	assert_vector(pond._focus).is_equal(parked)
	assert_bool(pond._parked).is_true()
	pond.actor.set_input(Vector2(1, 0))   # walk east, out of the safe box
	var moved := -1
	for i in 240:
		pond.actor.step(1.0 / 60.0)
		pond._follow(1.0 / 60.0)
		if not pond._parked:
			moved = i
			break
	assert_int(moved).is_greater(5)   # steps inside the box first: the camera did not move for those
	assert_bool(pond._settling).is_true()
	var target := P0Pond.clamp_focus(pond._focus, cam.size, PHONE, BAND, PondScenery.MEADOW, pond.actor.position)
	assert_float(pond._focus.distance_to(target)).is_greater(0.005)   # eased: not there in one frame
	pond.actor.set_input(Vector2.ZERO)
	for i in 180:
		pond.actor.step(1.0 / 60.0)
		pond._follow(1.0 / 60.0)
	assert_bool(pond._settling).is_false()   # back on the walking band's clamp
	assert_vector(pond._focus).is_equal_approx(P0Pond.clamp_focus(pond._focus, cam.size, PHONE, BAND, PondScenery.MEADOW, pond.actor.position), Vector3.ONE * 0.001)

## A pinch after a cast brings the clamp back the same way (不知火舞 on #143).
func test_a_pinch_after_a_cast_unparks_the_camera_eased() -> void:
	var pond := _pond()
	(pond.cam as Camera3D).size = P0Pond.view_size(PHONE, 1.0)
	pond._focus = pond.actor.position + Vector3(0, 0, 1.5)
	P0Pond.place(pond.cam, pond._focus)
	pond.view = FishingPresentation.new()
	pond._end_fishing()
	assert_bool(pond._parked).is_true()
	pond.p0_zoom(1.02, PHONE * 0.5)
	pond.p0_zoom_end()
	assert_bool(pond._parked).is_false()
	assert_bool(pond._settling).is_true()

## ① where: 8 px over the top of the outfit, above the figure's middle.
func test_a_landed_fishs_floats_rise_8_px_over_the_head() -> void:
	var pond := _pond()
	pond._update_camera(-1)
	for i in 30: await get_tree().process_frame   # the outfit assembles
	var box := DressingCamera.merged_aabb(pond.actor.rig)
	assert_bool(box.has_volume()).is_true()
	var cam: Camera3D = pond.cam
	var top := cam.unproject_position(Vector3(pond.actor.position.x, box.end.y, pond.actor.position.z))
	var at: Vector2 = pond.over_head()
	assert_vector(at).is_equal_approx(top - Vector2(0, 8), Vector2.ONE * 0.01)
	assert_float(at.y).is_less(cam.unproject_position(pond.actor.position + Vector3.UP).y)   # over the head, not the body
	assert_float(at.x).is_equal_approx(cam.unproject_position(pond.actor.position).x, 0.01)
