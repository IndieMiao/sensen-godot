extends GdUnitTestSuite
## STALL-NEW / STALL-NEW-2 (SGODOT-233, E-04; 1378:92885 / 1378:93021, §9.5.2): goods unlocked since the stall was last
## opened put New on its world icon (after ✓ and !) and `◆ New for you` on their rows for that visit; the visit clears it.

const STORE := "user://test_p0_stall_new.json"
const TIPS := "user://test_p0_stall_new_tips.json"

var ui: P0Ui

func _view(farming := 1) -> Dictionary:
	var buy := []
	for o in [["seed_radish", 1, 4], ["seed_lettuce", 1, 6], ["seed_herb", 2, 2], ["seed_carrot", 2, 9]]:
		buy.append({"id": o[0], "name": o[0], "price": o[2], "gate": o[1], "skill": "farming", "unlocked": farming >= int(o[1]), "left": null})
	return {"energy": {"value": 150, "max": 200}, "coins": 194,
		"skills": {"farming": {"level": farming, "xp": 50 if farming > 1 else 0}},
		"names": {"seed_radish": "Radish Seeds", "seed_lettuce": "Lettuce Seeds", "seed_herb": "Herb Seeds", "seed_carrot": "Carrot Seeds"},
		"stall": {"buy": buy}, "bag": {"capacity": 25, "slots": []}}

func before_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	ui = P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func test_day_one_has_nothing_new_and_a_level_up_brings_new() -> void:
	ui.set_view(_view(1))
	assert_bool(ui.stall_has_new()).is_false()   # what could already be bought counts as seen
	ui.set_view(_view(2))
	assert_array(ui.stall_new_ids()).is_equal(["seed_herb", "seed_carrot"])
	assert_int(P0WorldPrompts.stall(ui.view, true).status).is_equal(UiStatusBadge.State.NEW)
	assert_int(P0WorldPrompts.stall(ui.view, false).status).is_equal(-1)

func test_one_visit_shows_new_for_you_then_it_is_seen() -> void:
	ui.set_view(_view(1))
	ui.stall_has_new()
	ui.set_view(_view(2))
	ui.open_stall()
	await await_idle_frame()
	var d: P0CounterDrawer = ui._counter
	var carrot := P0ItemInfo.spec(ui.view, "seed_carrot", &"counter_buy", d._opts())
	assert_array(carrot.facts).contains([P0ItemInfo.NEW_FOR_YOU])
	assert_str(str(carrot.get("gate_tone", ""))).is_equal("new")
	var radish := P0ItemInfo.spec(ui.view, "seed_radish", &"counter_buy", d._opts())
	assert_bool(radish.facts.has(P0ItemInfo.NEW_FOR_YOU)).is_false()
	assert_bool(ui.stall_has_new()).is_false()   # the visit cleared the stall's New
	ui.close_modal()
	ui.open_stall()
	await await_idle_frame()
	assert_bool(P0ItemInfo.spec(ui.view, "seed_carrot", &"counter_buy", ui._counter._opts()).facts.has(P0ItemInfo.NEW_FOR_YOU)).is_false()

## 亚瑟 on #77: a board sheet's Back (BOARD-1 / BOARD-3 / BOARD-DROPPED) opens the counter again — the same visit, so
## `◆ New for you` is still on the Buy rows when the player switches back to them.
func test_new_for_you_stays_for_the_whole_visit_across_the_board_sheets() -> void:
	ui.set_view(_view(1))
	ui.stall_has_new()
	ui.set_view(_view(2))
	ui.open_stall()
	await await_idle_frame()
	var back := func(): ui.open_counter("homestead", {"section": "board"})
	P0BoardRequest._sheet(ui, "board_request", "Back", back)
	await await_idle_frame()
	ui.back_modal()   # BOARD-1's Back
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("counter")
	ui._counter.set_section("buy")
	assert_array(ui._counter._opts().get("new_ids", [])).is_equal(["seed_herb", "seed_carrot"])
	assert_bool(P0ItemInfo.spec(ui.view, "seed_carrot", &"counter_buy", ui._counter._opts()).facts.has(P0ItemInfo.NEW_FOR_YOU)).is_true()
	ui.close_modal()   # the visit ends: the next one has nothing new
	ui.open_stall()
	await await_idle_frame()
	assert_array(ui._counter._opts().get("new_ids", [])).is_empty()

## Entering on the Stall Board leaves the shelf unseen until its Buy page has been in front.
func test_a_visit_that_only_reads_the_board_keeps_the_stalls_new() -> void:
	ui.set_view(_view(1))
	ui.stall_has_new()
	ui.set_view(_view(2))
	ui.open_stall("board")
	await await_idle_frame()
	assert_bool(ui.stall_has_new()).is_true()
	ui._counter.set_section("buy")
	assert_bool(ui.stall_has_new()).is_false()
	ui.close_modal()
