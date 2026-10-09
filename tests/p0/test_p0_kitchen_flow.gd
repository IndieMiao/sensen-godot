extends GdUnitTestSuite
## The farmhouse kitchen's controller through the real runtime and UI (SGODOT-226, PR #54 review): a dish reaching a
## world without p0_event still gets its card, a refused or failed Cook / collect gives the buttons and the stove
## back, a level-up waits behind COOK-4, the watch ends when its pot is gone, and a tab asked for is the tab opened.

const FARMHOUSE := preload("res://scenes/p0/rooms/p0_farmhouse.gd")

var rt: P0Runtime

func before_test() -> void:
	rt = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.transport = func(_method: int, _path: String, _body: Dictionary, _cmd: Dictionary): pass   # nothing goes out
	rt.session.view = _view()

func _view() -> Dictionary:
	return {
		"seq": 5,
		"energy": {"value": 120, "max": 200}, "bag": {"capacity": 25, "free": 20, "slots": [{"id": "fish_crucian", "qty": 3}]},
		"skills": {"cooking": {"level": 2, "xp": 40, "floor": 30, "next": 100}, "farming": {"level": 1}, "fishing": {"level": 1}},
		"homestead": {"level": 1},
		"rarity_names": ["Common", "Fine", "Rare", "Legendary"],
		"items": {"fish_crucian": {"name": "Pond Crucian", "kind": "fish", "family": "W", "rarity": 1, "cook": true}},
		"names": {"fish_crucian": "Pond Crucian", "dish_grilled_crucian": "Grilled Crucian"},
		"cooking": {"slots": 2, "stove": null, "conveniences": ["cook_again"],
			"derive": [[1, 2, 3], [2, 3, 3], [3, 3, 4], [4, 4, 4]],
			"tiers": {"1": {"energy": 20, "ms": 5000}, "2": {"energy": 40, "ms": 15000}, "3": {"energy": 70, "ms": 30000}},
			"cookbook": [{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "rarity": 1, "in": ["fish_crucian"], "known": true,
				"cooked": true, "can_cook": true, "slots": 1}]},
	}

## A view as if it had just arrived: P0Session.current() projects timers from the last reply's arrival, and a view
## assigned straight into the session would otherwise look as old as the whole test run (its pots done).
func _set_view(v: Dictionary) -> void:
	rt.session.view = v
	rt.session.set("_received_ms", Time.get_ticks_msec())

func _farmhouse() -> P0Room:
	var r: P0Room = FARMHOUSE.new()
	r.use_runtime = false
	add_child(r)
	auto_free(r)
	r.rt = rt
	rt.attach(r)
	await get_tree().process_frame
	return r

func _dish(first := false) -> Dictionary:
	return {"kind": "dish", "pot": 3, "dish": "dish_grilled_crucian", "quality": 1, "qty": 1, "first": first, "mystery": false, "hits": 1}

func test_a_dish_away_from_the_farmhouse_pops_no_card() -> void:
	# §7.2.7 step 7 (q(46), 不知火舞 on 251): away from the stove the dish waits there and Today / the stove's sign say
	# so. A pot Queue ×2 kept on its own says nothing away from the kitchen (q(46) / q(71)); a collect answered after
	# the player left says where it went. The farm, the map and the outposts have no p0_event; _call gives null there
	# (bool(null) used to abort the reply).
	var w: Node3D = auto_free(Node3D.new())
	add_child(w)
	rt.attach(w)
	var kept := _dish()
	kept.auto = true
	rt.ui.clear_toast()
	rt.session.state_changed.emit(rt.session.view, [{"kind": "cabinet", "id": "dish_grilled_crucian@good", "delta": 1}, kept])
	# Read the toast at once: this test has no server, and a "Can't reach" toast may replace it a few frames later.
	assert_str(rt.ui.toast_text()).is_equal("")   # Queue ×2 away from the kitchen: silent
	for i in 2: await get_tree().process_frame
	assert_bool(rt.ui.has_modal()).is_false()
	rt.ui.clear_toast()
	rt.session.state_changed.emit(rt.session.view, [{"kind": "cabinet", "id": "dish_grilled_crucian@good", "delta": 1}, _dish()])
	assert_str(rt.ui.toast_text()).is_equal("Kept")   # a collect answered after leaving: where it went (no cabinet figures)
	var none := _dish()
	none.none = true
	rt.ui.clear_toast()
	rt.session.state_changed.emit(rt.session.view, [none])
	assert_str(rt.ui.toast_text()).is_equal("")   # a pot that made no dish says nothing here
	for i in 2: await get_tree().process_frame
	assert_bool(rt.ui.has_modal()).is_false()
	rt.detach(w)

func test_a_refused_or_failed_cook_gives_the_cook_buttons_back() -> void:
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("cookbook")
	k._on_cook({"type": "cook", "recipe": "dish_grilled_crucian"})
	assert_bool(k._cook_sent).is_true()
	rt._on_refused("stove_busy", {"ready_in": 3000}, {"type": "cook", "recipe": "dish_grilled_crucian"})
	assert_bool(k._cook_sent).is_false()
	k._on_cook({"type": "cook", "recipe": "dish_grilled_crucian"})
	rt.session.connection_failed.emit("Can't reach the farm server", {"type": "cook", "recipe": "dish_grilled_crucian"})
	assert_bool(k._cook_sent).is_false()
	rt.ui.close_modal()
	await get_tree().process_frame

func test_a_refused_or_failed_collect_returns_the_kitchen_to_idle() -> void:
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	for failure in ["refused", "send_failed"]:
		k.phase = "serve"
		k._retrying = true
		if failure == "refused": rt._on_refused("not_ready", {}, {"type": "collect", "taps": []})
		else: rt.session.connection_failed.emit("Can't reach the farm server", {"type": "collect", "taps": []})
		assert_str(k.phase).override_failure_message(failure).is_equal("idle")
		assert_bool(k._retrying).override_failure_message(failure).is_false()
		assert_bool(k.tap()).override_failure_message(failure + ": taps reach the room again").is_false()

func test_the_watch_ends_when_its_pot_is_gone_and_moves_on_to_the_next_pot() -> void:
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch({"id": 3, "ms": 5000, "elapsed": 0, "heats": []})
	k.serve([])   # the view has no stove: S5 Queue ×2 kept it on its own and nothing waited
	assert_str(k.phase).is_equal("idle")
	# The view already shows Queue ×2's turn-over (it settles the stove as the next command will): collect the watched
	# pot to land it now, with its toast (q(71)), instead of ending the watch as before Queue ×2 had an entry. If a
	# command kept it already, stale_pot sends the watch on to the next pot all the same.
	var sent: Array = []
	rt.session.transport = func(_m: int, _p: String, _b: Dictionary, cmd: Dictionary): sent.append(cmd)
	var turned := _view()
	turned.cooking.stove = {"id": 4, "ms": 5000, "ready_in": 4000, "elapsed": 1000, "heats": []}
	_set_view(turned)
	k.watch({"id": 3, "ms": 5000, "elapsed": 0, "heats": []})
	k.serve([])
	assert_str(k.phase).is_equal("rotate")
	assert_array(sent.map(func(c): return [c.type, c.get("pot")])).is_equal([["collect", 3]])
	rt._on_refused("stale_pot", {"pot": 4}, {"type": "collect", "pot": 3})
	assert_str(k.phase).is_equal("watch")
	assert_int(int(k.get("_stove").id)).is_equal(4)
	k.stop_watching()

# ---------------------------------------------------------------- Queue ×2 (Cooking Lv5, q(71))
func _queue_view() -> Dictionary:
	var v := _view()
	v.cooking.conveniences = ["cook_again", "queue_two"]
	v.cooking.stove = {"id": 3, "dish": "dish_grilled_crucian", "ms": 15000, "elapsed": 1000, "ready_in": 14000, "heats": []}
	return v

func test_queue_next_opens_the_drawer_in_queue_mode_and_the_queued_pot_returns_to_the_watch() -> void:
	_set_view(_queue_view())
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch(rt.session.view.cooking.stove)
	assert_bool(k.get("_queue_next").visible).is_true()
	assert_str(k.get("_sheet_header").state).is_equal("Cooking")
	k.open_queue()
	assert_str(k.phase).is_equal("compose")
	assert_bool(k.drawer.queue_mode).is_true()
	assert_str(k.drawer.get("_cook").label).is_equal("Queue")
	assert_str(k.drawer.get("_recipe_button").label).is_equal("Queue")
	assert_str(P0KitchenLogic.header(rt.session.view).state).is_equal("Cooking 0:14")   # Stove 1/1 · Cooking Lv · Cooking m:ss
	assert_str((k.get("_pot_card") as UiPotCard).result_title()).is_equal("Grilled Crucian")   # 256 ⑤ A': no Ready to queue
	# Experiment in the queue drawer: the pot on the stove does not grey Queue out (no Stove busy).
	k.drawer.tab = "experiment"
	k._on_ingredient("fish_crucian", Vector2.INF)
	assert_str(k.drawer.get("_cook").reason).is_equal("")
	assert_str(k.drawer.get("_cook").label).is_equal("Queue")
	k.drawer.tab = "cookbook"
	k.drawer.cook_requested.emit({"type": "cook", "recipe": "dish_grilled_crucian"})
	# The reply: the pot went in behind the one cooking.
	var v := _queue_view()
	v.seq = 6
	v.cooking.queued = {"id": 4, "dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "starts_in": 14000}
	_set_view(v)
	rt.session.state_changed.emit(v, [{"kind": "pot", "id": 4, "dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "queued": true}])
	await get_tree().process_frame
	assert_str(k.phase).is_equal("watch")
	assert_int(int(k.get("_stove").id)).is_equal(3)   # still the pot that was cooking
	assert_bool(rt.ui.has_modal()).is_false()
	assert_str(k.get("_sheet_header").state).is_equal("Cooking · Queued 1")
	assert_bool(k.get("_queue_next").visible).is_false()   # full: no button, not a grey one
	var badge: UiWorldIconButton = k.get("_queue_badge")
	assert_bool(badge.visible).is_true()
	assert_object(badge.icon).is_same(P0Logic.icon("dish_grilled_crucian"))
	k.open_queue()   # full: nothing opens
	assert_str(k.phase).is_equal("watch")
	k.stop_watching()
	# Away from the pot, the stove's world prompt keeps its countdown and hangs +1 (the prompts hide while watching).
	var mark: Dictionary = r._marker("use_stove_1", v)
	assert_str(str(mark.get("badge", ""))).is_equal("countdown")
	assert_str(str(mark.get("count", ""))).is_equal("+1")

## 不知火舞 on 226 (§7.2.3): the queue drawer is not leaving the pot. Its ring goes on over the pot, drawn over the
## drawer's layer; a tap on the pot band inside the ring's window judges it with its float and the drawer stays open;
## back at the watch the ring stands judged. Outside every window the tap is the scrim's, as before: back.
func _band_press(k: P0Kitchen) -> void:
	var band: Control = (k.get("_wrap") as Control).get_child(0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	band.gui_input.emit(press)

func test_the_heat_ring_goes_on_under_the_queue_drawer_and_a_hit_there_stands() -> void:
	var v := _queue_view()
	v.cooking.stove.heats = [{"at": 3000, "spin": 1600, "gold": 0.5, "width": 0.2}]
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch(rt.session.view.cooking.stove)
	k.open_queue()
	assert_str(k.phase).is_equal("compose")
	k.set("_start_ms", Time.get_ticks_msec() - 2500)   # the ring grows over the pot 1 s before its turn
	k._process(0.0)
	var ring: UiHeatRing = k.get("_ring")
	assert_bool(ring.visible).is_true()
	assert_int(ring.get_index()).is_greater(rt.ui._modal.get_index())   # over the drawer, the slot bar and the preview
	k.set("_start_ms", Time.get_ticks_msec() - int(3000 + 0.5 * 1600))   # the needle on gold
	var picked := k.drawer.selected_page
	var tab := k.drawer.tab
	_band_press(k)
	assert_str(k.phase).is_equal("compose")   # the drawer stays, its choice untouched
	assert_str(k.drawer.selected_page).is_equal(picked)
	assert_str(k.drawer.tab).is_equal(tab)
	assert_bool(rt.ui.has_modal()).is_true()
	assert_bool(bool(k.get("_judged").get(0, false))).is_true()
	assert_float(ring.mark_turn).is_equal_approx(0.5, 0.02)   # its dot where the needle was (SGODOT-256 ⑩)
	var floats: Array = rt.ui.root.find_children("*", "UiFloatText", true, false).map(func(f): return (f as UiFloatText).text)
	assert_array(floats).contains(["Nice heat! ★"])
	rt.ui.close_modal()   # back to the watch: the ring stands as hit, not judged again
	await get_tree().process_frame
	assert_str(k.phase).is_equal("watch")
	assert_bool(bool(k.get("_judged").get(0, false))).is_true()
	k._process(0.0)
	assert_int(ring.result).is_equal(1)
	k.stop_watching()

func test_a_tap_on_the_pot_band_outside_a_ring_closes_the_queue_drawer_as_before() -> void:
	var v := _queue_view()
	v.cooking.stove.heats = [{"at": 9000, "spin": 1600, "gold": 0.5, "width": 0.2}]
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch(rt.session.view.cooking.stove)
	k.open_queue()
	_band_press(k)
	await get_tree().process_frame
	assert_bool(rt.ui.has_modal()).is_false()
	assert_str(k.phase).is_equal("watch")
	assert_bool(k.get("_judged").has(0)).is_false()   # nothing judged
	k.stop_watching()

## 不知火舞 on 226: while a ring shows (growing 1 s before its window, the 350 ms it stays after its turn) a tap on the
## pot band outside the window does nothing, as tap() swallows it while watching; the drawer stays.
func test_a_tap_on_the_pot_band_while_a_ring_shows_but_outside_its_window_keeps_the_drawer() -> void:
	var v := _queue_view()
	v.cooking.stove.heats = [{"at": 3000, "spin": 1600, "gold": 0.5, "width": 0.2}]
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch(rt.session.view.cooking.stove)
	k.open_queue()
	for at in [2400, 3000 + 1600 + 200]:   # growing; then turned and still showing
		k.set("_start_ms", Time.get_ticks_msec() - at)
		k._process(0.0)
		assert_bool((k.get("_ring") as UiHeatRing).visible).override_failure_message(str(at)).is_true()
		_band_press(k)
		await get_tree().process_frame
		assert_str(k.phase).override_failure_message(str(at)).is_equal("compose")
		assert_bool(rt.ui.has_modal()).is_true()
	assert_bool(bool(k.get("_judged").get(0, true))).is_false()   # the turn went by: a miss, from the clock, not the taps
	assert_float((k.get("_ring") as UiHeatRing).mark_turn).is_equal(1.0)   # its dot where the untouched needle stopped
	rt.ui.close_modal()
	await get_tree().process_frame
	k.stop_watching()

## 刘邦 on #120: the queue drawer closing with no pot left on the stove does not leave its running ring on screen.
func test_the_ring_goes_when_the_queue_drawer_closes_on_an_empty_stove() -> void:
	var v := _queue_view()
	v.cooking.stove.heats = [{"at": 3000, "spin": 1600, "gold": 0.5, "width": 0.2}]
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch(rt.session.view.cooking.stove)
	k.open_queue()
	k.set("_start_ms", Time.get_ticks_msec() - 3500)
	k._process(0.0)
	var ring: UiHeatRing = k.get("_ring")
	assert_bool(ring.visible).is_true()
	var empty := _queue_view()
	empty.cooking.stove = null   # kept and gone meanwhile (another device, a command's settle)
	_set_view(empty)
	rt.ui.close_modal()
	await get_tree().process_frame
	assert_str(k.phase).is_equal("idle")
	assert_bool(ring.visible).is_false()

## 不知火舞 on #131: a float rising from the ring's centre covered a dot on the upper half (an early tap at 1 o'clock, a
## ring gone round at 12): those floats start at the ring's lower edge, short of the centre after their 48 px rise; a
## dot on the lower half (a hit) keeps the centre.
func test_a_judged_rings_float_starts_clear_of_its_dot() -> void:
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch({"id": 3, "ms": 15000, "elapsed": 0, "heats": [{"at": 3000, "spin": 1600, "gold": 0.5, "width": 0.2}]})
	k._process(0.0)
	var ring: UiHeatRing = k.get("_ring")
	var centre: Vector2 = k._ring_center()
	var edge := UiHeatRing.OUTER * ring.scale.y
	for t in [0.0, 0.1, 0.9, 1.0]:   # upper half
		assert_vector(k.float_from(t)).override_failure_message(str(t)).is_equal_approx(centre + Vector2(0.0, edge), Vector2(0.01, 0.01))
	for t in [0.4, 0.5, 0.6]:   # lower half
		assert_vector(k.float_from(t)).override_failure_message(str(t)).is_equal_approx(centre, Vector2(0.01, 0.01))
	assert_float(edge).is_greater(UiFloatText._RISE)   # risen, the float's foot stays below the centre
	k.stop_watching()

func test_queue_next_is_offered_only_from_cooking_lv5_with_nothing_waiting() -> void:
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	rt.session.view.cooking.stove = {"id": 3, "ms": 15000, "elapsed": 1000, "ready_in": 14000, "heats": []}
	k.watch(rt.session.view.cooking.stove)   # Lv1–4: no Queue ×2
	assert_bool(k.get("_queue_next").visible).is_false()
	k.open_queue()
	assert_str(k.phase).is_equal("watch")
	k.stop_watching()
	_set_view(_queue_view())
	k.watch(rt.session.view.cooking.stove)
	k.open_queue()
	rt.ui.close_modal()   # × without queueing: back to the same pot
	await get_tree().process_frame   # the drawer leaves the tree at the end of the frame
	assert_str(k.phase).is_equal("watch")
	assert_int(int(k.get("_stove").id)).is_equal(3)
	k.stop_watching()

func test_the_stove_turns_over_with_a_toast_and_no_card() -> void:
	# q(71): the watched pot is done with another waiting: collect it (its taps), no plate, no result card; the toast
	# says what was kept and what cooks now, and the watch moves on to the next pot.
	var v := _queue_view()
	v.cooking.queued = {"id": 4, "dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "starts_in": 0}
	_set_view(v)
	var sent: Array = []
	rt.session.transport = func(_m: int, _p: String, _b: Dictionary, cmd: Dictionary): sent.append(cmd)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch(v.cooking.stove)
	k.serve([1200])
	assert_str(k.phase).is_equal("rotate")
	assert_array(sent.map(func(c): return [c.type, c.get("pot"), c.get("taps")])).is_equal([["collect", 3, [1200]]])
	var after := _view()
	after.seq = 7
	after.cooking.conveniences = ["cook_again", "queue_two"]
	after.cooking.stove = {"id": 4, "dish": "dish_grilled_crucian", "ms": 5000, "elapsed": 0, "ready_in": 5000, "heats": []}
	_set_view(after)
	rt.ui.clear_toast()
	var dish := _dish()
	dish.pot = 3
	rt.session.state_changed.emit(after, [{"kind": "cabinet", "id": "dish_grilled_crucian@good", "delta": 1}, dish,
		{"kind": "queue", "id": 4, "dish": "dish_grilled_crucian", "started_at": 0, "ms": 5000}])
	for i in 2: await get_tree().process_frame
	assert_bool(rt.ui.has_modal()).is_false()   # no COOK-4
	assert_str(rt.ui.toast_text()).is_equal("Grilled Crucian kept · Grilled Crucian cooking")
	assert_str(k.phase).is_equal("watch")
	assert_int(int(k.get("_stove").id)).is_equal(4)
	assert_str(k.get("_sheet_header").state).is_equal("Cooking")
	k.stop_watching()

func test_a_pot_kept_on_its_own_in_the_kitchen_names_the_next_one() -> void:
	# In the farmhouse but not watching: a command settled the stove (Queue ×2) — the toast, no card.
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	var kept := _dish()
	kept.auto = true
	rt.ui.clear_toast()
	rt.session.state_changed.emit(rt.session.view, [kept, {"kind": "queue", "id": 4, "dish": null, "started_at": 0, "ms": 5000}])
	for i in 2: await get_tree().process_frame
	assert_bool(rt.ui.has_modal()).is_false()
	assert_str(rt.ui.toast_text()).is_equal("Grilled Crucian kept · Unknown dish cooking")
	assert_str(k.phase).is_equal("idle")

func test_a_level_up_in_the_same_reply_waits_behind_the_result_card() -> void:
	# C16: the dish card first, then the level-up; the result card used to drop the level-up a frame after it opened.
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.phase = "serve"
	rt.session.state_changed.emit(rt.session.view, [_dish(true), {"kind": "level", "skill": "cooking", "level": 3}])
	for i in 3: await get_tree().process_frame
	assert_str(rt.ui.modal_kind).is_equal("kitchen_card")
	assert_int(rt.ui._card_queue.size()).is_equal(1)
	rt.ui.close_modal()   # Keep
	for i in 2: await get_tree().process_frame
	assert_bool(rt.ui.has_modal()).is_true()
	assert_int(rt.ui.root.find_children("*", "UiMomentBanner", true, false).size()).is_equal(1)   # the level-up banner (233)
	assert_str(k.phase).is_equal("idle")

## 不知火舞 on #120: the Cookbook's selected page is marked from the drawer's first frame, not after the first refresh.
func test_the_cookbook_marks_its_selected_page_as_the_drawer_opens() -> void:
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("cookbook")
	var grid: UiInventoryGrid = k.drawer.get("_pages")
	assert_str(k.drawer.selected_page).is_not_empty()
	assert_int(grid.cell_for(k.drawer.selected_page).state).is_equal(UiItemCell.State.SELECTED)
	rt.ui.close_modal()
	await get_tree().process_frame

func test_the_tab_asked_for_is_the_tab_that_opens() -> void:
	# The rack's Open Experiment › and the Energy card's Cook walk to the stove; arriving used to
	# open Cookbook (or Cook Again) first and then drop the tab.
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.last_page = "dish_grilled_crucian"   # Cook Again would apply to a plain tap on the stove
	r.p0_dev(PackedStringArray(["at", "stand_stove"]))
	r.call("p0_open_kitchen", "experiment")
	for i in 30:
		if k.phase != "idle": break
		await get_tree().process_frame
	assert_str(k.phase).is_equal("compose")
	assert_str(k.drawer.tab).is_equal("experiment")
	rt.ui.close_modal()
	# A plain tap on the stove afterwards is not sent to Experiment by a tab left over.
	assert_str(str(r.get("_pending_tab"))).is_equal("")

func test_a_second_tap_on_a_bag_cell_puts_a_second_one_in() -> void:
	# §7.2.7: tapping a cell adds one (the cell counts down), the slot bar takes one back. Two of the same is a real
	# combination (Carrot Cake, Salted Potatoes; the two-radish trials of the int6 list).
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("experiment")
	k._on_ingredient("fish_crucian", Vector2.INF)
	k._on_ingredient("fish_crucian", Vector2.INF)
	assert_array(k.pot).is_equal(["fish_crucian", "fish_crucian"])
	k._on_ingredient("fish_crucian", Vector2.INF)   # two slots: the pot is full, nothing more goes in
	assert_array(k.pot).is_equal(["fish_crucian", "fish_crucian"])
	assert_str(rt.ui.toast_text()).is_equal("The pot is full · tap ✕ above to take one out")   # q(64)
	# 256 ⑤ A': each ✕ wears the gold-brown ring while the toast says where to look.
	var card: UiPotCard = k.get("_pot_card")
	var filled := card.slots().filter(func(sl): return (sl as UiPotSlot).state == UiPotSlot.State.FILLED)
	assert_int(filled.size()).is_equal(2)
	assert_bool(filled.all(func(sl): return (sl as UiPotSlot).point_at_remove)).is_true()
	k._take_out(1, Vector2.INF)
	assert_array(k.pot).is_equal(["fish_crucian"])
	assert_bool(card.slots().any(func(sl): return (sl as UiPotSlot).point_at_remove)).is_false()   # it did its job
	rt.ui.close_modal()
	await get_tree().process_frame

func test_back_in_a_room_takes_the_open_layers_own_way_back() -> void:
	# 李元芳 int7: in the farmhouse, Back on a Fish-dex card closed the whole layer (close_modal) instead of going back to
	# the Fish-dex, as it does on the farm; the next Back left the room. Rooms now use the UI's close_top_layer.
	var r := await _farmhouse()
	var back_to := []
	rt.ui._open_modal(Control.new())   # a second-level card …
	rt.ui._modal_back = func(): back_to.append("fish-dex")   # … whose way back is the Fish-dex (open_fish_card)
	assert_bool(r.is_back_navigation_locked()).is_true()
	assert_array(back_to).is_equal(["fish-dex"])
	# With the layer gone, Back is the door's again: the room walks out and still handles Back itself.
	rt.ui.close_modal()
	await get_tree().process_frame
	assert_bool(r.is_back_navigation_locked()).is_true()
	assert_str(str(r.get("_walk").get("name", ""))).is_equal("exit")

func test_a_turn_over_that_finds_no_room_falls_back_to_the_result_card() -> void:
	# q(46): cabinet and bag full, the kept pot stays on the stove and the waiting one does not fire (no `queue` event):
	# the turn-over the player watched shows the result card, which says the dish was left on the stove.
	var v := _queue_view()
	v.cooking.queued = {"id": 4, "dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "starts_in": 0}
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch(v.cooking.stove)
	k.serve([])
	assert_str(k.phase).is_equal("rotate")
	rt.session.state_changed.emit(v, [{"kind": "plate", "ids": ["dish_grilled_crucian@good"]}, _dish()])
	for i in 3: await get_tree().process_frame
	assert_str(k.phase).is_equal("card")
	assert_str(rt.ui.modal_kind).is_equal("kitchen_card")
	rt.ui.close_modal()
	await get_tree().process_frame

func test_up_close_the_stove_strip_keeps_the_pot_and_the_far_button_the_countdown() -> void:
	# 不知火舞 on #104 (1760:103708): the strip near the stove is i-pot + `Stove 1/1 · Cooking 0:22`, like the bench's
	# strip; the countdown stays on the button seen from afar.
	var v := _view()
	v.cooking.stove = {"id": 3, "dish": "dish_grilled_crucian", "ms": 30000, "elapsed": 8000, "ready_in": 22000, "heats": []}
	_set_view(v)
	var r := await _farmhouse()
	r.p0_dev(PackedStringArray(["at", "stand_stove"]))
	for i in 3: r.p0_frame(rt.session.current(), 1.0 / 30.0)
	var bar: UiWorldNameBar = rt.ui._name_bars.get("room:use_stove_1")
	assert_object(bar).is_not_null()
	assert_int(bar.status).is_equal(-1)
	assert_object(bar.icon).is_same(P0Logic.icon("pot"))
	assert_str(bar.fact).is_equal("Cooking 0:22")
	r.p0_dev(PackedStringArray(["at", "exit"]))   # walk away: the stove folds back into its button
	for i in 3: r.p0_frame(rt.session.current(), 1.0 / 30.0)
	var b: UiWorldIconButton = rt.ui._icons.get("room:use_stove_1")
	assert_int(b.status).is_equal(UiStatusBadge.State.COUNTDOWN)

func test_a_turn_over_collect_that_fails_recovers_like_a_failed_serve() -> void:
	# 后裔 on #104: with the stove empty, or the same pot still on it (no network), the rotate refusal used to leave the
	# player hidden and the camera on the stove, or re-enter the watch and resend 250 ms later. Now only a different
	# pot on the stove is watched; anything else recovers as a failed serve does.
	var v := _queue_view()
	v.cooking.queued = {"id": 4, "dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "starts_in": 0}
	_set_view(v)
	var sent: Array = []
	rt.session.transport = func(_m: int, _p: String, _b: Dictionary, cmd: Dictionary): sent.append(cmd)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	for failure in ["send_failed", "empty"]:
		k.watch(v.cooking.stove)
		k.serve([])
		assert_str(k.phase).override_failure_message(failure).is_equal("rotate")
		if failure == "send_failed":   # the same pot is still on the stove
			rt.session.connection_failed.emit("Can't reach the farm server", {"type": "collect", "pot": 3})
		else:
			var empty := _view()
			_set_view(empty)
			rt._on_refused("stove_empty", {}, {"type": "collect", "pot": 3})
		assert_str(k.phase).override_failure_message(failure).is_equal("idle")
		assert_bool(r.actor.visible).override_failure_message(failure + ": the player is back").is_true()
		var before := sent.size()
		for i in 20: await get_tree().process_frame   # no watch, so no automatic resend
		assert_int(sent.size()).override_failure_message(failure + ": nothing resent").is_equal(before)
		_set_view(v)

func test_a_first_time_dish_on_a_turn_over_floats_its_first_cook_xp_from_the_pot() -> void:
	# q(85) (不知火舞 on 226): the turn-over has no result card to carry the first-cook strip, so `First cooked · +N
	# Cooking XP` floats from the pot beside the pot's own XP, and a Success toast says `New recipe! <dish> kept`.
	# A normal serve keeps the bonus on its card (int6 C11).
	var v := _queue_view()
	v.cooking.queued = {"id": 4, "dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "starts_in": 0}
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch(v.cooking.stove)
	k.serve([])
	assert_str(k.phase).is_equal("rotate")
	var after := _view()
	after.seq = 8
	after.cooking.conveniences = ["cook_again", "queue_two"]
	after.cooking.stove = {"id": 4, "dish": "dish_grilled_crucian", "ms": 5000, "elapsed": 0, "ready_in": 5000, "heats": []}
	_set_view(after)
	rt.ui.clear_toast()
	var shown: Array = []
	rt.ui._toasts.shown.connect(func(text: String, severity): shown.append([text, severity]))
	var dish := _dish(true)
	dish.pot = 3
	rt.session.state_changed.emit(after, [dish, {"kind": "first", "what": "cook:dish_grilled_crucian", "xp": 10},
		{"kind": "xp", "skill": "cooking", "amount": 10, "percent": 100}, {"kind": "xp", "skill": "cooking", "amount": 5, "percent": 100},
		{"kind": "queue", "id": 4, "dish": "dish_grilled_crucian", "started_at": 0, "ms": 5000}])
	for i in 2: await get_tree().process_frame
	assert_bool(rt.ui.has_modal()).is_false()
	assert_array(shown).is_equal([["New recipe! Grilled Crucian kept", ToastLayer.Severity.SUCCESS]])
	var xp: Array = rt.ui.root.find_children("*", "UiFloatText", true, false).filter(func(f): return (f as UiFloatText).text.contains("Cooking XP"))
	assert_array(xp.map(func(f): return (f as UiFloatText).text)).contains_exactly_in_any_order(["First cooked · +10 Cooking XP", "+5 Cooking XP ★"])
	k.stop_watching()

func test_a_new_recipe_turn_over_with_no_room_falls_back_to_the_card_with_its_first_cook_xp() -> void:
	# 后裔 on #108: cabinet and bag full, the next pot does not fire (no `queue` event) and the card comes back. It used to
	# read `First cooked · +0 Cooking XP` (the dish's snapshot predates its `first`) and float the bonus as well.
	var v := _queue_view()
	v.cooking.queued = {"id": 4, "dish": "dish_grilled_crucian", "rarity": 1, "ms": 5000, "starts_in": 0}
	_set_view(v)
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch(v.cooking.stove)
	k.serve([])
	var dish := _dish(true)
	dish.pot = 3
	rt.session.state_changed.emit(v, [{"kind": "plate", "ids": ["dish_grilled_crucian@good"]}, dish,
		{"kind": "first", "what": "cook:dish_grilled_crucian", "xp": 10}, {"kind": "xp", "skill": "cooking", "amount": 10, "percent": 100},
		{"kind": "xp", "skill": "cooking", "amount": 5, "percent": 100}])
	for i in 3: await get_tree().process_frame
	assert_str(rt.ui.modal_kind).is_equal("kitchen_card")
	var texts: Array = rt.ui.root.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	assert_bool(texts.any(func(t): return str(t).contains("+10 Cooking XP") and str(t).contains("First cooked"))).override_failure_message(str(texts.filter(func(t): return str(t).contains("First")))).is_true()
	var floats: Array = rt.ui.root.find_children("*", "UiFloatText", true, false).map(func(f): return (f as UiFloatText).text)
	assert_bool(floats.any(func(t): return str(t).begins_with("First cooked"))).is_false()   # on the card's strip only
	rt.ui.close_modal()
	await get_tree().process_frame

func test_a_pot_kept_away_from_the_kitchen_floats_and_toasts_nothing_but_the_command_still_does() -> void:
	# 不知火舞 on 226: away from the kitchen a pot Queue ×2 kept on its own is silent, its floats and toasts included (the
	# stove is not on screen to float from); the XP still counts (the server has added it) and a Cooking level-up still
	# shows its banner. The server settles the stove before the command, so the reply carries the harvest that sent it.
	var w: Node3D = auto_free(Node3D.new())
	add_child(w)
	rt.attach(w)
	var kept := _dish(true)
	kept.auto = true
	rt.ui.clear_toast()
	rt.session.state_changed.emit(rt.session.view, [{"kind": "item", "id": "dish_grilled_crucian_good", "delta": 1}, kept,
		{"kind": "energy", "delta": 10, "reason": "reward"}, {"kind": "reward", "id": "first_dish_1", "energy": 10},
		{"kind": "first", "what": "cook:dish_grilled_crucian", "xp": 10}, {"kind": "xp", "skill": "cooking", "amount": 10, "percent": 100},
		{"kind": "xp", "skill": "cooking", "amount": 5, "percent": 100}, {"kind": "level", "skill": "cooking", "level": 2, "energy": 0, "gifts": []},
		{"kind": "queue", "id": 4, "dish": "dish_herb_grilled_fish", "started_at": 0, "ms": 60000},
		{"kind": "item", "id": "crop_radish", "delta": 2}, {"kind": "xp", "skill": "farming", "amount": 4, "percent": 100}])
	for i in 3: await get_tree().process_frame
	var floats: Array = rt.ui.root.find_children("*", "UiFloatText", true, false).map(func(f): return (f as UiFloatText).text)
	assert_array(floats).contains_exactly_in_any_order(["+2 crop_radish", "+4 XP"])   # the harvest's own (no names in this view)
	for word in ["First cooked", "Cooking", "Energy"]:
		assert_bool(floats.any(func(t): return str(t).contains(word))).override_failure_message(str(floats)).is_false()
	assert_str(rt.ui.toast_text()).is_equal("")
	assert_int(rt.ui.root.find_children("*", "UiMomentBanner", true, false).size()).is_equal(1)   # the Cooking Lv2 banner
	rt.ui.close_modal()
	rt.detach(w)

func test_a_level_up_gift_that_did_not_fit_is_said_after_its_banner_away_from_the_kitchen() -> void:
	# 不知火舞 on 226: the gifts of a Cooking level-up a pot kept on its own brought are the level-up's, not the pot's.
	# LOCK-14's Sent to Inbox card (q(87)) still comes, behind the level-up banner; the pot's own floats stay quiet.
	var w: Node3D = auto_free(Node3D.new())
	add_child(w)
	rt.attach(w)
	var kept := _dish(false)
	kept.auto = true
	rt.ui.clear_toast()
	rt.session.state_changed.emit(rt.session.view, [kept, {"kind": "xp", "skill": "cooking", "amount": 5, "percent": 100},
		{"kind": "level", "skill": "cooking", "level": 3, "energy": 0, "gifts": [["spice_pepper", 2]]},
		{"kind": "parcel", "id": "spice_pepper", "qty": 2, "key": "level:cooking:3:0", "waiting": false, "expires_in": 86400000},
		{"kind": "queue", "id": 4, "dish": null, "started_at": 0, "ms": 60000}])
	for i in 3: await get_tree().process_frame
	assert_int(rt.ui.root.find_children("*", "UiMomentBanner", true, false).size()).is_equal(1)
	assert_dict(rt.ui.inbox_notice_shown()).is_empty()   # not over the banner
	assert_str(rt.ui.toast_text()).is_equal("")
	var floats: Array = rt.ui.root.find_children("*", "UiFloatText", true, false).map(func(f): return (f as UiFloatText).text)
	assert_bool(floats.any(func(t): return str(t).contains("Cooking"))).override_failure_message(str(floats)).is_false()
	rt.ui.close_modal()
	for i in 2: await get_tree().process_frame
	assert_dict(rt.ui.inbox_notice_shown()).is_equal({title = "Sent to Inbox", item = "spice_pepper", quantity = "×2", line = "Expires in 24h"})
	rt.detach(w)

func test_a_level_up_gift_that_did_not_fit_is_said_after_its_banner_where_the_player_is() -> void:
	# 不知火舞 on 233 (q(49), one thing at a time): with the player there too, the banner speaks of the level-up first and
	# the Sent to Inbox card comes once it closes, even when the reply's parcel comes before the level-up.
	var w: Node3D = auto_free(Node3D.new())
	add_child(w)
	rt.attach(w)
	rt.ui.clear_toast()
	rt.session.state_changed.emit(rt.session.view, [{"kind": "parcel", "id": "crop_radish", "qty": 3, "key": "harvest:1:0", "waiting": false, "expires_in": 86400000},
		{"kind": "xp", "skill": "farming", "amount": 40, "percent": 100},
		{"kind": "level", "skill": "farming", "level": 3, "energy": 30, "gifts": [["seed_lettuce", 4]]},
		{"kind": "parcel", "id": "seed_lettuce", "qty": 4, "key": "level:farming:3:0", "waiting": false, "expires_in": 86400000}])
	for i in 3: await get_tree().process_frame
	assert_int(rt.ui.root.find_children("*", "UiMomentBanner", true, false).size()).is_equal(1)
	assert_dict(rt.ui.inbox_notice_shown()).is_empty()   # not over the banner
	rt.ui.close_modal()
	for i in 2: await get_tree().process_frame
	assert_dict(rt.ui.inbox_notice_shown()).is_equal({title = "Sent to Inbox", item = "crop_radish", quantity = "×3", line = "+1 more · Expires in 24h"})
	rt.detach(w)

func test_parcels_without_a_level_up_are_said_at_once() -> void:
	var w: Node3D = auto_free(Node3D.new())
	add_child(w)
	rt.attach(w)
	rt.ui.clear_toast()
	rt.session.state_changed.emit(rt.session.view, [{"kind": "parcel", "id": "crop_radish", "qty": 3, "key": "harvest:1:0", "waiting": false, "expires_in": 86400000}])
	await get_tree().process_frame
	assert_dict(rt.ui.inbox_notice_shown()).is_equal({title = "Sent to Inbox", item = "crop_radish", quantity = "×3", line = "Expires in 24h"})
	assert_str(rt.ui.toast_text()).is_equal("")   # the card, not the old one-line toast
	rt.detach(w)

func test_a_gift_meal_sent_to_the_inbox_is_the_card_not_a_toast() -> void:
	# q(88): Pip's meal with the bag full; the old `Bag full · Pip's meal sent to Inbox` toast is gone.
	var w: Node3D = auto_free(Node3D.new())
	add_child(w)
	rt.attach(w)
	rt.ui.clear_toast()
	rt.session.state_changed.emit(rt.session.view, [{"kind": "parcel", "id": "dish_grilled_crucian", "qty": 1, "key": "gift_meal:res_pip:d",
		"waiting": false, "expires_in": 33120000, "gift": true},
		{"kind": "gift_meal", "resident": "res_pip", "dish": "dish_grilled_crucian", "given": true, "to": "parcel"}])
	await get_tree().process_frame
	var pip := str(P0Logic.content().get("residents", {}).get("res_pip", {}).get("name", ""))
	assert_dict(rt.ui.inbox_notice_shown()).is_equal({title = "Sent to Inbox", item = "Grilled Crucian", quantity = "×1",
		line = "From %s · Expires in 9h 12m" % pip})
	assert_str(rt.ui.toast_text()).is_equal("")
	rt.detach(w)

func test_the_pot_card_shows_icons_one_result_line_and_says_what_opens_the_lock() -> void:
	# 256 ⑤ A' (row 53): slots carry no names; an empty pot has no result line, seasonings alone read `?`, a fish names
	# its dish; the locked 3rd slot is only a lock and a tap on it says what opens it.
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("experiment")
	await get_tree().process_frame
	var card: UiPotCard = k.get("_pot_card")
	var states := card.slots().map(func(sl): return (sl as UiPotSlot).state)
	assert_array(states).is_equal([UiPotSlot.State.EMPTY, UiPotSlot.State.EMPTY, UiPotSlot.State.LOCKED])
	assert_str(card.result_title()).is_equal("")   # no line: the card is just its slots
	assert_str(k.drawer.get("_cook").reason).is_equal("Add an ingredient")
	assert_array(card.find_children("*", "Label", true, false).filter(func(l): return l.is_visible_in_tree() and (l as Label).text != "")).is_empty()
	k._on_ingredient("fish_crucian", Vector2.INF)
	await get_tree().process_frame
	assert_str(card.result_title()).is_equal("Grilled Crucian")
	assert_bool(card.result_rarity_shown()).is_true()
	assert_str(card.result_time()).is_equal("5 s")
	var lock: UiPotSlot = card.slots()[2]
	lock.locked_tapped.emit()
	assert_str(rt.ui.toast_text()).starts_with("Cooking Lv4")
	rt.ui.close_modal()
	await get_tree().process_frame

func test_the_queue_drawer_sets_the_pot_lower_so_its_heat_ring_clears_the_hud() -> void:
	# 不知火舞 on #142: over the queue drawer the ring's top met the HUD's second row. The pot sits QUEUE_DROP px lower
	# there than over the cooking drawer (HUD + 8 ≤ ring, ring + 8 ≤ pot card, card + 8 ≤ drawer in the 360 × 800 shot).
	_set_view(_queue_view())
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.open("cookbook")
	var plain: Vector3 = r.get("_shot").center
	rt.ui.close_modal()
	await get_tree().process_frame
	k.watch(rt.session.view.cooking.stove)
	k.open_queue()
	var queued: Vector3 = r.get("_shot").center
	var view: Vector2 = r._view()
	var visible_h: float = float(r.get("_shot").size) * view.y / view.x
	var forward: Vector3 = -r.get("_cam_dir")
	var up := (Vector3.UP - forward * forward.dot(Vector3.UP)).normalized()
	var drop := P0Kitchen.QUEUE_DROP / r.get_viewport().get_visible_rect().size.y * visible_h
	assert_float((queued - plain).dot(up)).is_equal_approx(drop, 0.0001)   # the view's centre up: the pot lower on screen
	rt.ui.close_modal()
	await get_tree().process_frame
