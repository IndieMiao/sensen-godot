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
	assert_str((k.get("_preview").get("_title") as Label).text).is_equal("Ready to queue")   # q(84)
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
	k._take_out(1, Vector2.INF)
	assert_array(k.pot).is_equal(["fish_crucian"])
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
