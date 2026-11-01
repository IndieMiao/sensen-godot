extends GdUnitTestSuite
## P1 greenhouse (q(118) ②, SGODOT-240; copy 李白, look 不知火舞 on 241): a glass roof over 4×4 plots placed by its
## anchor — the preview's rules match the server's, its card says what it does, and no tree goes under it.

func _view(plots := 40) -> Dictionary:
	var list := []
	for i in plots: list.append({"id": i, "state": "tilled", "crop": null, "covered": false, "facility": null, "greenhouse": false})
	return {"garden": {"plots": plots}, "plots": list, "facilities": [], "energy": {"value": 100, "max": 200},
		"bag": {"capacity": 25, "slots": [{"id": "seed_apple", "qty": 1}]}, "orchard": {"used": 0, "cap": 3},
		"crops": [{"id": "crop_apple", "seed": "seed_apple", "energy": 6, "perennial": true}]}

## A plot by its [col, row] on the garden grid; the 16 plots of the 4×4 block whose lowest col and row that is (the
## server tests' at() / block()).
static func _at(col: int, row: int) -> int: return P0Garden.id_of(P0Garden.PLOT_ORIGIN + Vector2i(col, row) * 2)
static func _block(col: int, row: int) -> Array:
	var ids := []
	for y in range(row, row + 4): for x in range(col, col + 4): ids.append(_at(x, y))
	ids.sort()
	return ids

func test_the_block_and_its_reason_match_the_server() -> void:
	var v := _view()   # 40 open: rows 1–4 whole
	var a := _at(1, 1)
	assert_bool(P0FarmFacilities.is_block("greenhouse")).is_true()
	assert_str(P0FarmFacilities.kind_of("craft_greenhouse")).is_equal("greenhouse")
	var block := P0FarmFacilities.cover_of(v, a, "greenhouse")
	block.sort()
	assert_array(block).is_equal(_block(1, 1))
	assert_str(P0FarmFacilities.spot_reason(v, a, -1, "greenhouse")).is_empty()
	assert_str(P0FarmFacilities.caption(v, a, "greenhouse")).is_equal("Greenhouse · 4×4")
	var busy := _at(2, 3)
	v.plots[busy].crop = "crop_radish"
	v.plots[busy].state = "growing"
	assert_str(P0FarmFacilities.spot_reason(v, a, -1, "greenhouse")).is_equal("Needs 4×4 clear plots")
	assert_array(P0FarmFacilities.blocked_of(v, a, "greenhouse")).is_equal([busy])
	assert_str(P0FarmFacilities.spot_reason(_view(), _at(5, 3), -1, "greenhouse")).is_equal("Needs 4×4 clear plots")   # off the grid
	assert_str(P0FarmFacilities.spot_reason(_view(26), a, -1, "greenhouse")).is_equal("Needs 4×4 clear plots")   # row 1 not open yet

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

## SGODOT-294's model (#296 / #303): base, roof and glass on one origin at the block's middle, on the ground; the glass
## on its own alpha-blended copy of the farm material (0.25, both faces, no shadow), the shared one left opaque; the
## placement preview is the base alone.
func test_the_greenhouse_is_the_294_model_with_its_own_glass() -> void:
	var bp := P0Garden.blueprint()
	var covers := _block(2, 0).map(func(id): return float(id))   # as the view sends them
	var gh: Node3D = auto_free(P0FarmFacilities.greenhouse_art(bp, covers))
	assert_array(gh.get_children().map(func(n): return str(n.name))).is_equal(["GreenhouseBase", "GreenhouseRoof", "GreenhouseGlass"])
	var mid := (bp.cell_to_world(P0Garden.cell_of(_at(2, 0))) + bp.cell_to_world(P0Garden.cell_of(_at(5, 3)))) * 0.5
	assert_vector(gh.position).is_equal_approx(Vector3(mid.x, 0.0, mid.z), Vector3.ONE * 0.001)
	for n in gh.get_children(): assert_object((n as MeshInstance3D).mesh).is_not_null()
	var glass := gh.get_child(2) as MeshInstance3D
	var mat := glass.material_override as StandardMaterial3D
	assert_object(mat).is_not_same(P0FarmFacilities.FarmArt.material())
	assert_that([mat.transparency, mat.cull_mode, mat.albedo_color.a, glass.cast_shadow]).is_equal([
		BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.CULL_DISABLED, P0FarmFacilities.GLASS_ALPHA,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF])
	assert_that([P0FarmFacilities.FarmArt.material().transparency, P0FarmFacilities.FarmArt.material().albedo_color.a]).is_equal(
		[BaseMaterial3D.TRANSPARENCY_DISABLED, 1.0])   # the farm's shared material stays opaque
	assert_object(gh.get_meta("glass")).is_same(mat)
	var preview: Node3D = auto_free(P0FarmFacilities.greenhouse_art(bp, covers, false))
	assert_array(preview.get_children().map(func(n): return str(n.name))).is_equal(["GreenhouseBase"])

## Its four posts stand on the walkway crossings at the block's corners (±2.60 m, 不知火舞 on 294 c92e7e18): those cells
## are walkable ground, no bed, and become solid; the beds under the glass stay walkable.
func test_the_posts_take_the_four_walkway_crossings() -> void:
	var bp := P0Garden.blueprint()
	var covers := _block(2, 0).map(func(id): return float(id))   # beds x 8–14, y 3–9
	var posts := P0FarmFacilities.post_cells(bp, covers)
	assert_array(posts).contains_exactly_in_any_order([Vector2i(7, 2), Vector2i(15, 2), Vector2i(7, 10), Vector2i(15, 10)])
	for c in posts:
		assert_int(P0Garden.id_of(c)).is_equal(-1)
		assert_bool(bp.is_walkable(c)).is_true()
	# the block on the grid's right edge (cols 4–7) keeps its posts on the field too
	var right := _block(4, 0).map(func(id): return float(id))
	assert_array(P0FarmFacilities.post_cells(bp, right)).contains_exactly_in_any_order([Vector2i(11, 2), Vector2i(19, 2), Vector2i(11, 10), Vector2i(19, 10)])
