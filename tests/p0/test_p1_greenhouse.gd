extends GdUnitTestSuite
## P1 greenhouse (q(118) ②, SGODOT-240; copy 李白, look 不知火舞 on 241): a glass roof over 4×4 plots placed by its
## anchor — the preview's rules match the server's, its card says what it does, and no tree goes under it.

func _view(plots := 40) -> Dictionary:
	var list := []
	for i in plots: list.append({"id": i, "state": "tilled", "crop": null, "covered": false, "facility": null, "greenhouse": false})
	return {"garden": {"plots": plots}, "plots": list, "facilities": [], "energy": {"value": 100, "max": 200},
		"bag": {"capacity": 25, "slots": [{"id": "seed_apple", "qty": 1}]}, "orchard": {"used": 0, "cap": 3},
		"crops": [{"id": "crop_apple", "seed": "seed_apple", "energy": 6, "perennial": true}]}

const BLOCK7 := [7, 8, 9, 10, 13, 14, 15, 16, 19, 20, 21, 22, 25, 26, 27, 28]

func test_the_block_and_its_reason_match_the_server() -> void:
	var v := _view()
	assert_bool(P0FarmFacilities.is_block("greenhouse")).is_true()
	assert_str(P0FarmFacilities.kind_of("craft_greenhouse")).is_equal("greenhouse")
	var block := P0FarmFacilities.cover_of(v, 7, "greenhouse")
	block.sort()
	assert_array(block).is_equal(BLOCK7)
	assert_str(P0FarmFacilities.spot_reason(v, 7, -1, "greenhouse")).is_empty()
	assert_str(P0FarmFacilities.caption(v, 7, "greenhouse")).is_equal("Greenhouse · 4×4")
	v.plots[14].crop = "crop_radish"
	v.plots[14].state = "growing"
	assert_str(P0FarmFacilities.spot_reason(v, 7, -1, "greenhouse")).is_equal("Needs 4×4 clear plots")
	assert_array(P0FarmFacilities.blocked_of(v, 7, "greenhouse")).is_equal([14])
	assert_str(P0FarmFacilities.spot_reason(_view(), 23, -1, "greenhouse")).is_equal("Needs 4×4 clear plots")   # off the grid
	assert_str(P0FarmFacilities.spot_reason(_view(30), 4, -1, "greenhouse")).is_equal("Needs 4×4 clear plots")   # before Lv3

func test_a_sprinkler_never_goes_under_glass_nor_a_tree() -> void:
	var v := _view()
	v.plots[8].greenhouse = true
	assert_str(P0FarmFacilities.spot_reason(v, 8)).is_equal("Plot occupied")
	var a := P0Logic.main_action(v, v.plots[8], "seed_apple")
	assert_that([a.verb, a.sub, a.enabled, a.toast]).is_equal(["Plant", "Outside only", false, "No trees in the greenhouse"])

func test_the_card_buttons_say_the_cap_and_the_coins() -> void:
	var r := {"id": "craft_greenhouse", "tab": "facilities", "item": "facility_greenhouse", "name": "Greenhouse", "to": "field",
		"cost": [], "cap": 1, "used": 1}
	r.block = {"code": "facility_cap", "detail": {"cap": 1, "used": 1, "farming_next": 10}}
	var b := P0MaterialLogic._craft_button(r)
	assert_that([b.label, b.toast]).is_equal(["Greenhouses 1/1", "Greenhouses 1/1 · Farming Lv10 adds 1"])   # q(130) ①
	r.block = {"code": "facility_cap", "detail": {"cap": 2, "used": 2, "farming_next": null}}
	assert_str(str(P0MaterialLogic._craft_button(r).label)).is_equal("Greenhouses 2/2")
	r.block = {"code": "no_coins", "detail": {"need": 120}}
	assert_str(str(P0MaterialLogic._craft_button(r).label)).is_equal("Need 120 more coins")
	var card: Dictionary = P0MaterialLogic.workbench_model({"workbench": {"recipes": [{"id": "craft_greenhouse", "tab": "facilities",
		"item": "facility_greenhouse", "name": "Greenhouse", "to": "field", "cost": [], "block": null, "coins_need": 340, "coins_have": 230,
		"gate": {"skill": "farming", "level": 8, "ok": true}}]}}, "facilities")[0]
	assert_that([card.effect, card.cost[-1].name, card.cost[-1].have, card.cost[-1].need]).is_equal(["Farming Lv8 · Any seed grows inside", "Coins", 230, 340])

## The status card (李白): its plots and cut; crops under it grey Move with `Move · Harvest first`. The view's numbers are
## JSON floats, as the server sends them: a crop on 13.0 is found under covers of floats.
func test_the_card_greys_move_while_something_grows_under_glass() -> void:
	var covers := [0.0, 1.0, 2.0, 3.0, 6.0, 7.0, 8.0, 9.0, 12.0, 13.0, 14.0, 15.0, 18.0, 19.0, 20.0, 21.0]
	var f := {"id": 4.0, "kind": "greenhouse", "plot": 0.0, "covers": covers}
	var v := {"plots": [{"id": 13.0, "state": "tilled", "crop": null}, {"id": 16.0, "state": "growing", "crop": "crop_radish"}]}
	var card := P0FarmFacilities.greenhouse_card(v, f)
	assert_that([card.title, card.lead, card.button, card.kind, card.reason]).is_equal(["Greenhouse", "16 plots · −25%", "Move", &"primary", ""])
	v.plots[0] = {"id": 13.0, "state": "growing", "crop": "crop_radish"}
	assert_str(str(P0FarmFacilities.greenhouse_card(v, f).reason)).is_equal("Move · Harvest first")

## q(139): the card's one action is the green primary key while the greenhouse can move, the grey key with its reason
## while something grows under the glass.
func test_the_cards_move_is_primary_when_it_works_and_grey_when_it_does_not() -> void:
	var covers := [0.0, 1.0, 2.0, 3.0, 6.0, 7.0, 8.0, 9.0, 12.0, 13.0, 14.0, 15.0, 18.0, 19.0, 20.0, 21.0]
	var f := {"id": 4.0, "kind": "greenhouse", "plot": 0.0, "covers": covers}
	var ui := P0Ui.new()
	ui.quick_store = "user://test_p1_greenhouse_quick.json"
	ui.tips_path = "user://test_p1_greenhouse_tips.json"
	add_child(auto_free(ui))
	await await_idle_frame()
	for growing in [false, true]:
		var v := {"plots": [{"id": 13.0, "state": "growing" if growing else "tilled", "crop": "crop_radish" if growing else null}]}
		var sheet := ui.open_facility_card(P0FarmFacilities.greenhouse_card(v, f), func(): pass)
		await await_idle_frame()
		var keys := sheet.find_children("*", "UiCommandButton", true, false).filter(func(b): return b.visible)
		assert_int(keys.size()).is_equal(1)
		var key := keys[0] as UiCommandButton
		if growing: assert_that([key.label, key.reason]).is_equal(["Move · Harvest first", "Move · Harvest first"])
		else: assert_that([key.label, key.kind, key.reason]).is_equal(["Move", UiCommandButton.Kind.PRIMARY, ""])
		ui.close_modal()
		await await_idle_frame()
	for path in [ui.quick_store, ui.tips_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Moving a greenhouse: its own plots are not in the way, with the view's ids as the JSON floats they are.
func test_a_greenhouse_moved_over_its_own_plots_is_not_in_its_own_way() -> void:
	var covers := [0.0, 1.0, 2.0, 3.0, 6.0, 7.0, 8.0, 9.0, 12.0, 13.0, 14.0, 15.0, 18.0, 19.0, 20.0, 21.0]
	var v := {"garden": {"plots": 40}, "facilities": [{"id": 4.0, "kind": "greenhouse", "plot": 0.0, "covers": covers}], "plots": []}
	for i in 40: v.plots.append({"id": float(i), "state": "tilled", "crop": null, "facility": null, "greenhouse": covers.has(float(i))})
	assert_array(P0FarmFacilities.blocked_of(v, 1, "greenhouse", 4)).is_empty()   # one column over: its own plots are free
	assert_array(P0FarmFacilities.blocked_of(v, 1, "greenhouse")).is_not_empty()   # another greenhouse would be in the way

## Its own name strip (不知火舞 on 241, 4e7d1119): `Greenhouse · −25%`, the strip Fish Trap uses (text · fact).
func test_the_greenhouse_strip_reads_its_cut() -> void:
	var p := P0FarmFacilities.greenhouse_prompt({"id": 4.0, "kind": "greenhouse"})
	assert_that([p.text, p.fact, p.button]).is_equal(["Greenhouse", "−25%", true])
