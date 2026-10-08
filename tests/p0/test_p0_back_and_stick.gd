extends GdUnitTestSuite
## Android Back closes the top UI layer first, and a world change ends the stick (int5 hand test 012–013, 023–024,
## 029–030, 035–039; SGODOT-221).

const STORE := "user://test_p0_back_quickbar.json"

class FakeWorld extends Node:
	var sticks: Array = []
	func p0_joystick(v: Vector2) -> void: sticks.append(v)
	func p0_surface() -> String: return "farm"

func _view() -> Dictionary:
	return {"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000}, "coins": 40, "skills": {},
		"bag": {"capacity": 25, "free": 24, "slots": [{"id": "seed_radish", "qty": 20}]}, "plots": [],
		"names": {"seed_radish": "Radish Seeds"}, "crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2}],
		"rest": {"used": 0, "limit": 1, "resets_in": 3600000}}

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _ui() -> P0Ui:
	var u := P0Ui.new()
	u.quick_store = STORE
	add_child(auto_free(u))
	u.layer = 128
	return u

func test_back_closes_one_layer_at_a_time() -> void:
	var ui := _ui()
	await await_idle_frame()
	ui.set_mode("farm")
	ui.set_surface("farm")
	ui.set_view(_view())
	assert_bool(ui.close_top_layer()).is_false()   # nothing open: the world may leave
	ui.open_radial()
	assert_bool(ui._radial.visible).is_true()
	assert_bool(ui.close_top_layer()).is_true()
	assert_bool(ui._radial.visible).is_false()
	ui.open_inbox()
	assert_bool(ui.has_modal()).is_true()
	assert_bool(ui.close_top_layer()).is_true()   # the Inbox, not the farm
	assert_bool(ui.has_modal()).is_false()
	ui._on_pin_toggled("seed_radish", true)
	assert_object(ui._pin_menu).is_not_null()
	assert_bool(ui.close_top_layer()).is_true()
	assert_object(ui._pin_menu).is_null()
	assert_bool(ui.close_top_layer()).is_false()

func test_end_stick_resets_the_pad_and_stops_the_world() -> void:
	var ui := _ui()
	await await_idle_frame()
	var got := []
	ui.joystick.connect(func(v): got.append(v))
	var pad = ui.pad
	pad._arb.press(0, Vector2(100, 400), 0)
	pad._arb.move(0, Vector2(160, 400), 50)
	assert_bool(pad._arb.is_steering()).is_true()
	ui.end_stick()
	assert_bool(pad._arb.is_active()).is_false()
	assert_array(got).is_equal([Vector2.ZERO])

func test_switching_worlds_stops_the_one_left_behind() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var farm: FakeWorld = auto_free(FakeWorld.new())
	var house: FakeWorld = auto_free(FakeWorld.new())
	rt.attach(farm)
	farm.sticks.clear()
	rt.ui.joystick.emit(Vector2(1, 0))   # walking into the door
	rt.attach(house)
	assert_array(farm.sticks).contains([Vector2.ZERO])   # the farm stops under the farmhouse
	assert_vector(farm.sticks.back()).is_equal(Vector2.ZERO)
	rt.detach(house)
	assert_vector(house.sticks.back()).is_equal(Vector2.ZERO)
