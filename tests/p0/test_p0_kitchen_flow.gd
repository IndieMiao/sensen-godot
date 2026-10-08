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

func test_a_dish_at_a_world_without_p0_event_still_gets_the_old_card() -> void:
	# The farm, the map and the outposts have no p0_event; _call gives null there (bool(null) used to abort the reply).
	var w: Node3D = auto_free(Node3D.new())
	add_child(w)
	rt.attach(w)
	rt.session.state_changed.emit(rt.session.view, [_dish()])
	await get_tree().process_frame
	assert_bool(rt.ui.has_modal()).is_true()
	assert_str(rt.ui.modal_kind).is_equal("card")
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

func test_the_watch_ends_when_its_pot_is_gone_from_the_stove() -> void:
	var r := await _farmhouse()
	var k: P0Kitchen = r.get("kitchen")
	k.watch({"id": 3, "ms": 5000, "elapsed": 0, "heats": []})
	k.serve([])   # the view has no stove: S5 Queue ×2 kept it on its own
	assert_str(k.phase).is_equal("idle")
	rt.session.view.cooking.stove = {"id": 4, "ms": 5000, "ready_in": 4000, "heats": []}   # the next pot is on now
	k.watch({"id": 3, "ms": 5000, "elapsed": 0, "heats": []})
	k.serve([])
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
	assert_bool(rt.ui.root.find_children("*", "Label", true, false).any(func(l): return (l as Label).text == "LEVEL UP")).is_true()
	assert_str(k.phase).is_equal("idle")

func test_the_tab_asked_for_is_the_tab_that_opens() -> void:
	# The rack's Open Experiment ›, the Energy card's Cook and ui.open_kitchen(tab) walk to the stove; arriving used to
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
	k._take_out(1, Vector2.INF)
	assert_array(k.pot).is_equal(["fish_crucian"])
	rt.ui.close_modal()
	await get_tree().process_frame
