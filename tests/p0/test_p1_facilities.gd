extends GdUnitTestSuite
## P1 facilities on the client (q(59) §1.4–1.5 / §5, SGODOT-241): the spot rules the placement preview shares with the
## server's place command, the Facilities card's buttons, and the shared placement shell on P0Ui.

const FARM := preload("res://scenes/p0/p0_farm.gd")   # the shared placement edge pan (placement_edge / edge_push)

static func _store() -> String: return "user://test_p1_facilities_bar_%d.json" % OS.get_process_id()
static func _tips() -> String: return "user://test_p1_facilities_tips_%d.json" % OS.get_process_id()

func after_test() -> void:
	for f in [_store(), _tips()]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _view(plots := 40) -> Dictionary:
	var list := []
	for i in plots: list.append({"id": i, "state": "tilled", "crop": null, "covered": false, "facility": null})
	return {"garden": {"plots": plots}, "plots": list, "facilities": [], "energy": {"value": 100, "max": 200},
		"bag": {"capacity": 25, "slots": []}, "coins": 100}

# ---------------------------------------------------------------- spot rules
## The bar's reasons (q(59) §5): Plot occupied for a crop or another facility, Outside your fields off the homestead's
## plots (and for plots 30–39 before Homestead Lv3); a sprinkler being moved may stay on its own plot's neighbours.
func test_spot_reasons_follow_the_place_command() -> void:
	var v := _view()
	assert_str(P0FarmFacilities.spot_reason(v, 7)).is_empty()
	v.plots[4].state = "sown"
	v.plots[4].crop = "crop_radish"
	assert_str(P0FarmFacilities.spot_reason(v, 4)).is_equal("Plot occupied")
	v.plots[9].facility = 2
	assert_str(P0FarmFacilities.spot_reason(v, 9)).is_equal("Plot occupied")
	assert_str(P0FarmFacilities.spot_reason(v, 9, 2)).is_empty()   # Move: its own plot does not count
	assert_str(P0FarmFacilities.spot_reason(v, -1)).is_equal("Outside your fields")
	assert_str(P0FarmFacilities.spot_reason(_view(30), 33)).is_equal("Outside your fields")

## A plot by its [col, row] on the garden grid (content.garden.plots; the server tests' at()).
static func _at(col: int, row: int) -> int: return P0Garden.id_of(P0Garden.PLOT_ORIGIN + Vector2i(col, row) * 2)

## Coverage is the ring of 8 on the garden grid, over the plots the homestead has, written as a count. With 40 open
## (SGODOT-355 b1 order) rows 4…1 are whole and row 0 has its middle four, cols 2–5.
func test_cover_and_caption_count_the_ring_of_eight() -> void:
	var ring := []
	for col in range(2, 5): for row in range(2, 5): if Vector2i(col, row) != Vector2i(3, 3): ring.append(_at(col, row))
	assert_array(P0FarmFacilities.cover_of(_view(), _at(3, 3))).contains_exactly_in_any_order(ring)
	# at the open edge: row 0 has only col 5 of 5–7
	assert_array(P0FarmFacilities.cover_of(_view(), _at(6, 1))).contains_exactly_in_any_order(
		[_at(5, 0), _at(5, 1), _at(7, 1), _at(5, 2), _at(6, 2), _at(7, 2)])
	assert_array(P0FarmFacilities.cover_of(_view(36), _at(6, 1))).contains_exactly_in_any_order(
		[_at(5, 1), _at(7, 1), _at(5, 2), _at(6, 2), _at(7, 2)])
	assert_str(P0FarmFacilities.caption(_view(), _at(3, 3))).is_equal("Coverage preview · 8 plots")
	assert_str(P0FarmFacilities.caption(_view(), _at(-1, 4))).is_equal("Coverage preview · 3 plots")   # the grid's corner

# ---------------------------------------------------------------- the Facilities card
func _recipe(block = null, extra := {}) -> Dictionary:
	var r := {"id": "craft_sprinkler", "tab": "facilities", "item": "facility_sprinkler", "name": "Sprinkler", "to": "field",
		"cost": [{"id": "wood", "name": "Timber", "need": 8, "have": 8}, {"id": "copper_ore", "name": "Copper Ore", "need": 3, "have": 1}],
		"block": block, "cap": 4, "used": 0, "gate": {"skill": "farming", "level": 6, "ok": true}}
	r.merge(extra, true)
	return r

## q(59) §5: Build opens placement mode (nothing sent yet); the gate, the cap and a missing material on the button.
func test_the_sprinkler_card_writes_its_state_on_the_button() -> void:
	var b := P0MaterialLogic._craft_button(_recipe())
	assert_that([b.label, b.kind, b.cmd]).is_equal(["Build", "primary", {"type": "place_start", "recipe": "craft_sprinkler"}])
	b = P0MaterialLogic._craft_button(_recipe({"code": "skill_level_required", "detail": {"skill": "farming", "level": 6}}))
	assert_str(b.label).is_equal("Farming Lv6 needed")
	b = P0MaterialLogic._craft_button(_recipe({"code": "facility_cap", "detail": {"cap": 4, "used": 4, "homestead_next": 2}}))
	assert_that([b.label, b.toast]).is_equal(["Sprinklers 4/4", "Sprinklers 4/4 · Homestead Lv2 adds 1"])   # q(130) ①
	b = P0MaterialLogic._craft_button(_recipe({"code": "facility_cap", "detail": {"cap": 6, "used": 6, "homestead_next": null}}))
	assert_str(b.label).is_equal("Sprinklers 6/6")
	b = P0MaterialLogic._craft_button(_recipe({"code": "missing_materials", "detail": {"item": "copper_ore", "need": 3, "have": 1}}))
	assert_str(b.label).is_equal("Need 2 more Copper Ore")
	var card: Dictionary = P0MaterialLogic.workbench_model({"workbench": {"recipes": [_recipe()]}}, "facilities")[0]
	assert_str(str(card.effect)).is_equal("Farming Lv6 · Waters 8 plots for you")   # FARM-5-FAC: the level first, unlocked too

## FARM-5-FAC (不知火舞 B7 286 6e15f758): a facility that can be built says how many stand of how many may, left of
## Build — `Sprinklers 2/6`; short of materials or at the cap (the grey key counts then, q(130)) the line stays empty.
func test_a_buildable_facility_counts_beside_build() -> void:
	var count := func(block, extra := {}) -> String:
		return str(P0MaterialLogic.workbench_model({"workbench": {"recipes": [_recipe(block, extra)]}}, "facilities")[0].have)
	assert_str(count.call(null, {"used": 2, "cap": 6})).is_equal("Sprinklers 2/6")
	assert_str(count.call(null, {"name": "Greenhouse", "used": 0, "cap": 1})).is_equal("Greenhouses 0/1")
	assert_str(count.call({"code": "missing_materials", "detail": {"item": "copper_ore", "need": 3, "have": 1}})).is_equal("")
	assert_str(count.call({"code": "facility_cap", "detail": {"cap": 6, "used": 6}}, {"used": 6, "cap": 6})).is_equal("")

## q(136) (FAC-STATUS 2116:32993): a sprinkler's status card reads `Waters 8 plots · −15%`, the greenhouse's
## `16 plots · −25%` form, and Move — the card's one action — is the green primary key (it was the outlined secondary).
func test_the_sprinkler_status_card_reads_its_cut_and_moves_on_the_primary_key() -> void:
	var f := {"id": 5.0, "kind": "sprinkler", "plot": 8.0, "covers": [1.0, 2.0, 3.0, 7.0, 9.0, 13.0, 14.0, 15.0]}
	var card := P0FarmFacilities.sprinkler_card(f)
	assert_that([card.title, card.lead, card.button, card.kind]).is_equal(["Sprinkler", "Waters 8 plots · −15%", "Move", &"primary"])
	assert_str(str(P0FarmFacilities.sprinkler_card({"kind": "sprinkler", "covers": [1.0]}).lead)).is_equal("Waters 1 plot · −15%")
	var ui := await _ui()
	var sheet := ui.open_facility_card(card, func(): pass)
	await await_idle_frame()
	var keys := sheet.find_children("*", "UiCommandButton", true, false).filter(func(b): return b.visible)
	assert_int(keys.size()).is_equal(1)
	assert_that([(keys[0] as UiCommandButton).label, (keys[0] as UiCommandButton).kind]).is_equal(["Move", UiCommandButton.Kind.PRIMARY])

## The drawer shows the tabs the view lists: Tools | Supplies on a P0 server, Facilities when P1 sends it.
func test_the_workbench_shows_facilities_when_the_view_lists_it() -> void:
	var p0 := P0WorkbenchDrawer.new({"workbench": {"tabs": ["tools", "supplies"], "recipes": []}})
	add_child(auto_free(p0))
	assert_array(p0._shown_tabs).is_equal(["tools", "supplies"])
	var p1 := P0WorkbenchDrawer.new({"workbench": {"tabs": ["tools", "supplies", "facilities"], "recipes": []}}, "facilities")
	add_child(auto_free(p1))
	assert_array(p1._shown_tabs).is_equal(["tools", "supplies", "facilities"])
	assert_str(p1.tab).is_equal("facilities")

# ---------------------------------------------------------------- the placement shell
func _ui() -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = _store()
	ui.tips_path = _tips()
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_surface("farm")
	await await_idle_frame()
	return ui

## q(23): the HUD keeps its first row, the quick bar and keys step aside, the bar has Cancel and the main key; the
## main key on a bad spot shows the reason; ending puts the farm's controls back.
func test_placement_mode_takes_the_screen_and_gives_it_back() -> void:
	var ui := await _ui()
	assert_bool(ui._keys.visible).is_true()
	var done := []
	ui.placement_done.connect(func(ok): done.append(ok))
	ui.begin_placement({"confirm": "Build"})
	await await_idle_frame()
	assert_bool(ui.placing()).is_true()
	assert_bool(ui._keys.visible or ui._bar.visible).is_false()
	assert_bool(ui.hud._row2.visible).is_false()
	ui.set_placement({"caption": "Coverage preview · 8 plots", "reason": ""})
	assert_str(ui._place_bar._caption.text).is_equal("Coverage preview · 8 plots")
	ui._place_bar._ok.activated.emit()
	ui.set_placement({"caption": "", "reason": "Plot occupied"})
	assert_str(ui._place_bar._ok.reason).is_equal("Plot occupied")
	ui._place_bar._cancel.activated.emit()
	assert_array(done).is_equal([true, false])
	ui.end_placement()
	await await_idle_frame()
	assert_bool(ui.placing()).is_false()
	assert_bool(ui._keys.visible).is_true()
	assert_bool(ui.hud._row2.visible).is_true()

## A card or drawer closing in placement mode (Decorate's piece card, the Compost Bin's, a drawer that opened Decorate)
## leaves the main key, the switch key and the quick bar away (不知火舞 on 284, Figma DECOR-NONE-SELECTED 2243:33040 /
## DECOR-PLACE: only Done or the place bar at the bottom; q(23): no labour while placing). Ending placement brings
## them back.
func test_a_card_closing_while_placing_keeps_the_farm_keys_away() -> void:
	var ui := await _ui()
	ui.begin_placement({"confirm": "Done"})
	await await_idle_frame()
	var card := ui.open_facility_card({"title": "Garden Lantern", "lead": "1×1 · Classic lamp", "button": "Move"}, func(): pass)
	await await_idle_frame()
	assert_object(card).is_not_null()
	ui.close_modal()
	await await_idle_frame()
	assert_bool(ui.placing()).is_true()
	assert_bool(ui._keys.visible).override_failure_message("the main key and ⇄ came back").is_false()
	assert_bool(ui._bar.visible).override_failure_message("the quick bar came back").is_false()
	assert_bool(ui._creel.visible).is_false()
	assert_bool(ui._place_bar.visible).is_true()
	ui.end_placement()
	await await_idle_frame()
	assert_bool(ui._keys.visible and ui._bar.visible).is_true()

## Decorate's 2×1 / 3×2 decor (不知火舞 on 284 ee15926a): spec.secondary adds a middle key in the secondary look,
## Cancel · Rotate · Place equally wide; it says placement_secondary. Without it the bar keeps its two keys.
func test_the_bar_takes_an_optional_middle_key() -> void:
	var ui := await _ui()
	var turned := []
	ui.placement_secondary.connect(func(): turned.append(true))
	ui.begin_placement({"confirm": "Build"})
	await await_idle_frame()
	assert_bool(ui._place_bar._second.visible).is_false()
	assert_float(ui._place_bar._ok.size.x).is_greater(ui._place_bar._cancel.size.x)   # the sprinkler's two-key bar
	ui.end_placement()
	ui.begin_placement({"confirm": "Place", "secondary": "Rotate"})
	await await_idle_frame()
	await await_idle_frame()
	var bar: UiPlaceBar = ui._place_bar
	assert_bool(bar._second.visible).is_true()
	assert_str(bar._second.label).is_equal("Rotate")
	assert_int(bar._second.kind).is_equal(UiCommandButton.Kind.SECONDARY)
	assert_float(bar._ok.size.x).is_equal_approx(bar._cancel.size.x, 1.0)
	assert_float(bar._second.size.x).is_equal_approx(bar._cancel.size.x, 1.0)
	bar._second.activated.emit()
	assert_array(turned).is_equal([true])
	# fcbd30a7: a bad spot greys the main key keeping its verb; the reason replaces the caption, a tap still says why
	var said := []
	bar.unavailable.connect(func(r): said.append(r))
	ui.set_placement({"caption": "Garden Bench · 3/20 placed", "reason": "Outside your yard"})
	assert_str(bar._ok.text).is_equal("Place")
	assert_bool(bar._ok.is_unavailable()).is_true()
	assert_str(bar._caption.text).is_equal("Outside your yard")
	bar._ok.pressed.emit()
	assert_array(said).is_equal(["Outside your yard"])
	ui.set_placement({"reason": ""})
	assert_str(bar._caption.text).is_equal("Garden Bench · 3/20 placed")
	ui.set_placement({"reason": "Space taken", "secondary": ""})   # a square piece selected next: back to two keys
	assert_bool(bar._second.visible).is_false()
	assert_str(bar._ok.text).is_equal("Space taken")   # the two-key bar keeps the reason on its key
	assert_str(bar._caption.text).is_equal("Garden Bench · 3/20 placed")

## A press on the scene in placement mode moves the preview (placement_point) and summons no stick.
func test_placement_presses_move_the_preview_not_the_player() -> void:
	var ui := await _ui()
	var points := []
	var sticks := []
	ui.placement_point.connect(func(p, phase): points.append(phase))
	ui.joystick.connect(func(v): if v != Vector2.ZERO: sticks.append(v))
	ui.begin_placement({"confirm": "Build"})
	for e in [_button(Vector2(180, 400), true), _motion(Vector2(220, 430)), _button(Vector2(220, 430), false)]:
		ui.pad._gui_input(e)
	assert_array(points).is_equal(["press", "drag", "release"])
	assert_array(sticks).is_empty()

## A Facilities card's Build asks the world for placement mode and sends nothing.
func test_build_on_the_card_asks_for_placement_and_sends_nothing() -> void:
	var ui := await _ui()
	var asked := []
	var sent := []
	ui.placement_requested.connect(func(r): asked.append(r))
	ui.command.connect(func(c): sent.append(c))
	var d := ui.open_workbench("facilities")
	d.command_requested.emit({"type": "place_start", "recipe": "craft_sprinkler"})
	assert_array(asked).is_equal(["craft_sprinkler"])
	assert_array(sent).is_empty()

static func _button(at: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	return e

static func _motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e

# ---------------------------------------------------------------- placement camera (不知火舞 on 241)
## A finger within 48 px of an edge pushes that way, harder nearer the edge; elsewhere nothing.
func test_edge_push_grows_toward_the_edge() -> void:
	assert_float(FARM.edge_push(180.0, 0.0, 360.0)).is_equal(0.0)
	assert_float(FARM.edge_push(48.0, 0.0, 360.0)).is_equal(0.0)
	assert_float(FARM.edge_push(24.0, 0.0, 360.0)).is_equal_approx(-0.5, 0.001)
	assert_float(FARM.edge_push(0.0, 0.0, 360.0)).is_equal_approx(-1.0, 0.001)
	assert_float(FARM.edge_push(348.0, 0.0, 360.0)).is_equal_approx(0.75, 0.001)

## Two fingers in placement mode pan (placement_pan) and pinch (zoom); the preview does not move with them.
func test_two_fingers_pan_and_pinch_and_leave_the_preview() -> void:
	var ui := await _ui()
	var pans := []
	var zooms := []
	var points := []
	ui.placement_pan.connect(func(px, _at): pans.append(px))
	ui.zoom.connect(func(f, _at): zooms.append(f))
	ui.placement_point.connect(func(_p, phase): points.append(phase))
	ui.begin_placement({"confirm": "Build"})
	var pad = ui.pad
	pad._gui_input(_touch(0, Vector2(100, 400), true))
	pad._gui_input(_touch(1, Vector2(200, 400), true))
	pad._gui_input(_drag(1, Vector2(240, 420)))   # spread 100 → ~143, centre moves right and down
	assert_int(pans.size()).is_equal(1)
	assert_float((pans[0] as Vector2).x).is_greater(0.0)
	assert_float(float(zooms[0])).is_less(1.0)   # fingers apart: zoom in
	pad._gui_input(_button(Vector2(240, 420), false))   # the mouse twin's release
	assert_array(points).is_empty()
	pad._gui_input(_touch(1, Vector2(240, 420), false))
	pad._gui_input(_touch(0, Vector2(100, 400), false))
	pad._gui_input(_button(Vector2(150, 300), true))   # one finger again: the preview's
	assert_array(points).is_equal(["press"])

static func _touch(i: int, at: Vector2, down: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = at
	e.pressed = down
	return e

static func _drag(i: int, at: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = at
	return e
