extends GdUnitTestSuite
## P1 facilities on the client (q(59) §1.4–1.5 / §5, SGODOT-241): the spot rules the placement preview shares with the
## server's place command, the Facilities card's buttons, and the shared placement shell on P0Ui.

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

## Coverage is the ring of 8 on the garden grid, over the plots the homestead has, written as a count.
func test_cover_and_caption_count_the_ring_of_eight() -> void:
	assert_array(P0FarmFacilities.cover_of(_view(), 7)).contains_exactly_in_any_order([0, 1, 2, 6, 8, 12, 13, 14])
	assert_array(P0FarmFacilities.cover_of(_view(), 5)).contains_exactly_in_any_order([4, 10, 11, 30, 32])
	assert_array(P0FarmFacilities.cover_of(_view(30), 5)).contains_exactly_in_any_order([4, 10, 11])
	assert_str(P0FarmFacilities.caption(_view(), 7)).is_equal("Coverage preview · 8 plots")
	assert_str(P0FarmFacilities.caption(_view(), 0)).is_equal("Coverage preview · 3 plots")

# ---------------------------------------------------------------- the Facilities card
func _recipe(block = null, extra := {}) -> Dictionary:
	var r := {"id": "craft_sprinkler", "tab": "facilities", "item": "facility_sprinkler", "name": "Sprinkler", "to": "field",
		"cost": [{"id": "wood", "name": "Timber", "need": 8, "have": 8}, {"id": "copper_ore", "name": "Copper Ore", "need": 3, "have": 1}],
		"block": block, "cap": 4, "used": 0}
	r.merge(extra, true)
	return r

## q(59) §5: Build opens placement mode (nothing sent yet); the gate, the cap and a missing material on the button.
func test_the_sprinkler_card_writes_its_state_on_the_button() -> void:
	var b := P0MaterialLogic._craft_button(_recipe())
	assert_that([b.label, b.kind, b.cmd]).is_equal(["Build", "primary", {"type": "place_start", "recipe": "craft_sprinkler"}])
	b = P0MaterialLogic._craft_button(_recipe({"code": "skill_level_required", "detail": {"skill": "farming", "level": 6}}))
	assert_str(b.label).is_equal("Farming Lv6 needed")
	b = P0MaterialLogic._craft_button(_recipe({"code": "facility_cap", "detail": {"cap": 4, "used": 4, "homestead_next": 2}}))
	assert_str(b.label).is_equal("Sprinklers 4/4 · Homestead Lv2 adds 1")
	b = P0MaterialLogic._craft_button(_recipe({"code": "facility_cap", "detail": {"cap": 6, "used": 6, "homestead_next": null}}))
	assert_str(b.label).is_equal("Sprinklers 6/6")
	b = P0MaterialLogic._craft_button(_recipe({"code": "missing_materials", "detail": {"item": "copper_ore", "need": 3, "have": 1}}))
	assert_str(b.label).is_equal("Need 2 more Copper Ore")
	var card: Dictionary = P0MaterialLogic.workbench_model({"workbench": {"recipes": [_recipe()]}}, "facilities")[0]
	assert_str(str(card.effect)).is_equal("Waters 8 plots for you")

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
