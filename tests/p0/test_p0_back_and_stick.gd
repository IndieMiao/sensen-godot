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

func test_finger_cards_stay_below_the_hud_and_above_the_bar() -> void:
	# int5 hand test 8: a card dragged under the HUD lost its tap to the Energy chip.
	var ui := _ui()
	await await_idle_frame()
	ui.set_mode("farm")
	ui.set_surface("farm")
	ui.set_view(_view())
	await await_idle_frame()
	assert_bool(ui.hud.visible).is_true()
	ui.tag("homestead", "Homestead Lv1 · Tap to upgrade", Vector2(60, 30), true, Vector2(60, 40))
	var c: UiTapCard = ui._cards["homestead"]
	assert_float(c.position.y).is_greater_equal(float(UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H))
	ui.tag("stall", "Tap to shop", Vector2(200, ui._kit.size.y - 10), true)
	var s: UiTapCard = ui._cards["stall"]
	assert_float(s.position.y + s.size.y).is_less_equal(ui._bar.position.y)

func test_a_root_world_leaves_for_the_map_once_nothing_is_left_to_close() -> void:
	# int5b hand test 2: booted into the farm (no map under it), Back closed the Inbox and then did nothing,
	# because AppRouter ignores Back on a P0 world that is the root scene.
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var swaps := [0]
	rt.swap_root = func(): swaps[0] += 1
	var farm: FakeWorld = auto_free(FakeWorld.new())
	rt.attach(farm)
	rt.ui.set_view(_view())
	rt.ui.open_inbox()
	assert_bool(rt.ui.close_top_layer() or rt.root_back()).is_true()   # first Back: the Inbox
	assert_int(swaps[0]).is_equal(0)
	assert_bool(rt.ui.close_top_layer() or rt.root_back()).is_true()   # second Back: to the map
	assert_int(swaps[0]).is_equal(1)

func test_end_stick_before_the_pad_exists_is_harmless() -> void:
	# farm-dev after #40: a farm started as the root scene attaches before P0Ui._ready built the pad.
	var u: P0Ui = auto_free(P0Ui.new())   # not in the tree: no _ready, no pad
	assert_object(u.pad).is_null()
	var sticks := []
	u.joystick.connect(func(v): sticks.append(v))
	u.end_stick()
	assert_array(sticks).is_equal([Vector2.ZERO])

