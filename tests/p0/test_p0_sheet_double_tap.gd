extends GdUnitTestSuite
## SGODOT-256 ①: tapping the Clay Bank fast must not leave its sheet full screen.

const STORE := "user://test_p0_sheet_double_tap.json"
var ui: P0Ui

func _view() -> Dictionary:
	return {"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000}, "names": {"clay": "Clay"},
		"bag": {"capacity": 25, "free": 25, "slots": []}, "plots": [], "coins": 40, "skills": {},
		"rest": {"used": 0, "limit": 1, "resets_in": 3600000}, "homestead": {"level": 1},
		"gather": {"spots": [{"id": "spot_clay_bank", "name": "Clay Bank", "open": false, "homestead": 2, "ready": false,
			"yield": [["clay", 2]]}]}}

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	ui = P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _fitted(d: UiDrawer) -> float: return d.body.get_combined_minimum_size().y + d.pad * 2.0

## The int10c case: a second tap reopens the sheet in the next frame's input, so the fit meant for "after layout" ran
## before the sheet's wrapped lines had a width and left it taller than the screen.
func test_a_sheet_reopened_before_layout_still_fits_its_content() -> void:
	P0MaterialCards.open_locked_spot(ui, ui.view, "spot_clay_bank")
	var d := P0MaterialCards.open_locked_spot(ui, ui.view, "spot_clay_bank")
	get_tree().emit_signal(&"process_frame")   # the next frame's process before the new sheet is laid out
	await await_idle_frame()
	await await_idle_frame()
	assert_float(d.height).is_less(ui.root.size.y * 0.6)
	assert_float(d.height).is_equal_approx(_fitted(d), 1.0)
	assert_float(d.size.y).is_equal_approx(d.height, 1.0)

func test_every_material_sheet_fits_after_layout() -> void:
	for open in [func(): return P0MaterialCards.open_locked_spot(ui, ui.view, "spot_clay_bank")]:
		var d: UiDrawer = open.call()
		await await_idle_frame()
		await await_idle_frame()
		assert_float(d.height).is_less(ui.root.size.y * 0.75)
		assert_float(d.height).is_equal_approx(_fitted(d), 1.0)

## A fast second tap on a farm card's button reaches the farm while a sheet is already up: it opens nothing more (the
## farm's own card since its gathering spots left for the cities and its mine mouth for the wild sites, SGODOT-355 b1).
func test_a_tap_on_a_farm_card_while_a_sheet_is_up_opens_nothing_more() -> void:
	var first := P0MaterialCards.open_locked_spot(ui, ui.view, "spot_clay_bank")
	var rt := P0Runtime.new()
	rt.ui = ui
	var fm := P0FarmMaterials.new()
	fm.rt = rt
	assert_bool(fm.tap_card("workbench")).is_true()   # taken, so the farm does nothing else with it
	assert_str(ui.modal_kind).is_equal("locked_spot")
	assert_object(ui._modal.get_child(1)).is_same(first)    # the same sheet: no second one opened
	fm.free()
	rt.free()
