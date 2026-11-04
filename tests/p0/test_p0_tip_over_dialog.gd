extends GdUnitTestSuite
## 不知火舞 355 G19 (v4q(4) ⑥): `Travel costs Energy and coins.` comes up over the first paid travel card, while it is
## open — not after Fly — and goes with it (Fly or ✕ closes the card; the Energy card over it replaces it). Every other
## tip still waits for the dialog to close (方案 §10.3 ⑥).

const TIPS := "user://test_p0_tip_over_dialog_tips.json"

var ui: P0Ui

func _ui() -> P0Ui:
	ui = P0Ui.new()
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view({"energy": {"value": 150, "max": 200}, "coins": 40, "skills": {"farming": {"level": 1, "xp": 0}},
		"bag": {"capacity": 25, "slots": []}, "profile": {"name": "Farmer", "city": "San Francisco", "since_ms": 1_791_539_492_778}})
	return ui

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TIPS))

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TIPS))

func _frames(n := 3) -> void:
	for i in n: await get_tree().process_frame

func test_the_travel_tip_comes_up_over_its_card_and_goes_with_it() -> void:
	await _ui()
	P0PlaceSheet.open(ui, {"title": "San Jose", "primary": "Fly"}, func(): pass, Callable(), Callable(), "travel_card")
	ui.teach("travel")
	await _frames()
	assert_bool(ui.tip_showing("travel")).is_true()          # over the open card, Fly not pressed
	ui.close_modal()                                         # ✕ (Fly closes it the same way)
	await _frames()
	assert_bool(ui.tip_on_screen()).is_false()
	assert_bool(ui.first_time("travel")).is_false()          # seen: never again

func test_a_card_over_it_takes_the_travel_tip_away() -> void:
	await _ui()
	P0PlaceSheet.open(ui, {"title": "San Jose", "primary": "Fly"}, func(): pass, Callable(), Callable(), "travel_card")
	ui.teach("travel")
	await _frames()
	assert_bool(ui.tip_showing("travel")).is_true()
	P0PlaceSheet.open(ui, {"title": "Energy"}, func(): pass)   # Fly short of Energy: the Energy card replaces the dialog
	await _frames()
	assert_bool(ui.tip_on_screen()).is_false()

func test_any_other_tip_still_waits_for_the_dialog() -> void:
	await _ui()
	P0PlaceSheet.open(ui, {"title": "Mission Market Square"}, func(): pass)
	ui.teach("map")
	await _frames()
	assert_bool(ui.tip_on_screen()).is_false()               # waits under the card
	ui.close_modal()
	await _frames()
	assert_bool(ui.tip_showing("map")).is_true()             # comes up as it closes
