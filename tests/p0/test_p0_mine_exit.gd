extends GdUnitTestSuite
## The way in and out of a 355 b1 mine (contract-efg §5 ① ⑧ ⑪, v4q(5) ① ⑪): the mines are wild sites, entered from the
## map's mouth card (P0Runtime.enter_mine: the mine opens on the reply's mine_floor event) and left back to the map at
## that mine's mouth — the Entrance, the elevator's Entrance row, a knock-out (its card first, E6, then the mouth card).
## The farm has no mine mouth any more.

const P0Mine := preload("res://scenes/p0/p0_mine.gd")
const PROBE := "res://tests/fixtures/scenes/stack_probe.tscn"
const Fx := preload("res://tests/p0/fixtures/mine_b1_view.gd")
const STORE := "user://test_p0_mine_exit.json"

func after_test() -> void:
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame
	P0Runtime.free_instance_for_tests()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	await get_tree().process_frame

## A stand-in for the map that records the mouth cards asked for (亚瑟's P0Map.open_wild_card).
func _map_probe() -> Node:
	var stub := GDScript.new()
	stub.source_code = "extends \"res://tests/fixtures/scenes/stack_probe.gd\"\nvar wild_cards: Array = []\nfunc open_wild_card(id: String) -> void: wild_cards.append(id)\nfunc suspend() -> void: pass\nfunc resume() -> void: pass\n"
	stub.reload()
	var map := AppRouter.push_instance(PROBE)
	map.set_script(stub)
	return map

func _runtime(sent: Array) -> P0Runtime:
	UiCommandButton.offline = false
	P0Runtime.free_instance_for_tests()
	var rt := P0Runtime.ensure()
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	rt.session.sent.connect(func(cmd): sent.append(cmd))
	await get_tree().process_frame
	rt.swap_root = func(): pass   # never the real scene change in a test
	return rt

## The mine sits on the map it was entered from: leaving pops that one layer, and the map opens this mine's mouth
## card (`Enter mine · Free` there: the player is still at the site).
func test_leaving_goes_back_to_the_map_at_the_mines_mouth() -> void:
	var rt := await _runtime([])
	var map := _map_probe()
	var mine_layer := AppRouter.push_instance(PROBE)
	rt.world = mine_layer
	var mine = auto_free(P0Mine.new())   # not in the tree: only its way out
	mine.rt = rt
	mine.mine_id = Fx.MINE
	mine._mine_name = "Ironvale Vein"
	mine.actor = auto_free(P0Actor.new())
	assert_str(P0Runtime.route_of(mine)).is_equal("mine:" + Fx.MINE)   # the map's way back is this mine, not the farm
	mine._leave()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_bool(AppRouter.top_instance() == map).is_true()
	assert_bool(is_instance_valid(mine_layer)).is_false()
	assert_array(map.wild_cards).is_equal([Fx.MINE])
	assert_str(rt.ui._place_text).is_equal("Ironvale Vein")   # the chip names the mine (E6), not the homestead
	mine._leave()   # once only
	await get_tree().process_frame
	assert_array(map.wild_cards).is_equal([Fx.MINE])

## The place chip in the mine leaves the same way as the Entrance (P0Runtime._on_place_pressed → p0_leave).
func test_the_place_chip_leaves_by_the_entrance() -> void:
	var rt := await _runtime([])
	var mine = auto_free(P0Mine.new())   # not in the tree: only its way out
	mine.rt = rt
	mine.mine_id = Fx.MINE
	mine.actor = auto_free(P0Actor.new())
	rt.world = mine
	rt._on_place_pressed()
	assert_bool(mine._leaving).is_true()

## Android Back in the mine (亚瑟 on #629, ⑥): an open panel closes first; with nothing open it leaves as the Entrance
## does — the map's mouth card opens and only the mine's layer goes (AppRouter pops nothing more). In a knock-out's
## moment it does nothing: that way out is under way.
func test_back_closes_a_panel_then_leaves_by_the_entrance() -> void:
	var rt := await _runtime([])
	var map := _map_probe()
	var mine_layer := AppRouter.push_instance(PROBE)
	rt.world = mine_layer
	var mine = auto_free(P0Mine.new())   # not in the tree: only its way out
	mine.rt = rt
	mine.mine_id = Fx.MINE
	mine._mine_name = "Ironvale Vein"
	mine.actor = auto_free(P0Actor.new())
	P0MaterialCards.open_elevator(rt.ui, Fx.view(1), 1, func(_c): pass)
	assert_str(rt.ui.modal_kind).is_equal("elevator")
	assert_bool(mine.is_back_navigation_locked()).is_true()
	assert_bool(rt.ui.has_modal()).is_false()
	assert_bool(mine._leaving).is_false()
	mine._ko = true
	assert_bool(mine.is_back_navigation_locked()).is_true()
	assert_bool(mine._leaving).is_false()
	mine._ko = false
	assert_bool(mine.is_back_navigation_locked()).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_bool(AppRouter.top_instance() == map).is_true()
	assert_array(map.wild_cards).is_equal([Fx.MINE])
	assert_str(rt.ui._place_text).is_equal("Ironvale Vein")

## A knock-out's way out (E6): back on the map the knock-out card first; its Close opens the mouth card (328:182498).
func test_the_knock_out_card_then_the_mouth_card() -> void:
	var rt := await _runtime([])
	var map := _map_probe()
	var spec := P0MaterialLogic.ko_card(Fx.view(12, {"records": {Fx.MINE: {"deepest": 14, "guards": []}}}), Fx.MINE, 12, [["iron_ore", 3]])
	var card := P0MaterialCards.open_ko_card(rt.ui, spec, func(): P0Mine.open_mouth_card(get_tree(), Fx.MINE))
	await get_tree().process_frame
	assert_str(rt.ui.modal_kind).is_equal("mine_ko")
	var texts: Array = card.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	assert_array(texts).contains(["Knocked out", "You're back at the entrance.", "You dropped half of what you found on this floor:",
		"Iron Ore ×3", "Your best here is still Floor 14."])
	assert_array(map.wild_cards).is_empty()   # not under the card
	rt.ui.close_modal()
	await get_tree().process_frame
	assert_array(map.wild_cards).is_equal([Fx.MINE])

## Into a mine: mine_enter from where the player is, and the mine opens over it on the reply's mine_floor event, on the
## floor the server landed the player on; a refused one opens nothing and the next try goes again.
func test_enter_mine_opens_the_mine_on_its_floor() -> void:
	var sent: Array = []
	var rt := await _runtime(sent)
	rt.enter_mine("wd-dev-quarry")
	assert_array(sent).is_equal([{"type": "mine_enter", "mine": "wd-dev-quarry", "floor": 1}])
	rt.enter_mine("wd-dev-quarry")   # one at a time
	assert_int(sent.size()).is_equal(1)
	rt._mine_opened([{"kind": "mine_floor", "mine": "wd-other", "floor": 3}])   # not this one: nothing opens
	assert_str(rt._entering_mine).is_equal("wd-dev-quarry")
	rt.session._inflight = {}   # the reply: refused — nothing opens, the next try may go (it waited behind the first read)
	rt.session._queue.clear()
	rt.session.busy = false
	rt.session.command_settled.emit("mine_enter", false, "not_here")
	assert_str(rt._entering_mine).is_empty()
	rt.enter_mine("wd-dev-quarry", 10)
	assert_str(rt._entering_mine).is_equal("wd-dev-quarry")
	assert_that(sent[1]).is_equal({"type": "mine_enter", "mine": "wd-dev-quarry", "floor": 10})

## v4q(5) ①: no mine mouth on the farm — no model, no card candidate, no Show target.
func test_the_farm_has_no_mine_mouth() -> void:
	var farm_src := FileAccess.get_file_as_string("res://scenes/p0/p0_farm.gd")
	assert_bool(farm_src.contains("MineArt.entrance()")).is_false()
	var m := P0FarmMaterials.new()
	assert_bool(m.card_candidates().any(func(c): return str(c[0]) == "mine")).is_false()
	assert_object(m.spot_at("mine")).is_null()
	assert_bool(m.has_method("tap_mouth")).is_false()
	m.free()
