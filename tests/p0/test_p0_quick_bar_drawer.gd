extends GdUnitTestSuite
## The bag drawer's way onto the quick bar (SGODOT-225 interface, q(61)): bar pools, pin_to / unpin / place_at and
## docking the bar as the drawer's top row.

const STORE := "user://test_p0_quickbar_drawer.json"

var ui: P0Ui

func _view(extra: Array = []) -> Dictionary:
	var slots: Array = [{"id": "seed_radish", "qty": 20}, {"id": "seed_lettuce", "qty": 10}, {"id": "crop_radish", "qty": 3},
		{"id": "fert_compost", "qty": 4}, {"id": "bait_worm", "qty": 6}]
	slots.append_array(extra)
	return {
		"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000},
		"crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2}],
		"names": {"seed_radish": "Radish Seeds", "seed_lettuce": "Lettuce Seeds", "fert_compost": "Compost"},
		"bag": {"capacity": 25, "free": 18, "slots": slots},
		"plots": [], "rest": {"used": 0, "limit": 1, "resets_in": 3600000}, "coins": 40, "skills": {},
	}

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	ui = P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	ui.layer = 128
	await await_idle_frame()
	ui.set_mode("farm")
	ui.set_surface("farm")
	ui.set_view(_view())

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _ids() -> Array:
	return ui._bar.slots.map(func(s): return str(s.get("id", "")))

func test_each_bar_takes_its_own_pool_and_fills_itself_with_seeds_only() -> void:
	assert_str(ui.bar_action_of("seed_radish")).is_equal("farm")
	assert_str(ui.bar_action_of("fert_compost")).is_equal("farm")
	assert_str(ui.bar_action_of("bait_worm")).is_equal("fish")
	assert_str(ui.bar_action_of("crop_radish")).is_empty()
	assert_bool(ui.accepts("fert_compost")).is_true()
	assert_bool(ui.accepts("bait_worm")).is_false()   # the Farming bar is on screen
	assert_array(_ids()).is_equal(["seed_radish", "seed_lettuce"])   # Compost waits to be put there

func test_a_bag_item_lands_where_it_is_dropped_without_a_pin_and_stays() -> void:
	assert_bool(ui.place_at(4, "fert_compost")).is_true()
	assert_array(_ids()).is_equal(["seed_radish", "seed_lettuce", "", "", "fert_compost"])   # the gaps stay gaps
	assert_bool(ui.is_pinned("fert_compost")).is_false()
	ui.set_view(_view())
	assert_str(_ids()[4]).is_equal("fert_compost")   # in the Farming pool, so a refresh keeps it
	assert_bool(ui.place_at(0, "bait_worm")).is_false()
	assert_bool(ui.place_at(5, "fert_compost")).is_false()

func test_dropping_on_a_pinned_item_sends_it_off_with_its_pin_not_as_removed() -> void:
	ui.pin_to("seed_lettuce")
	assert_bool(ui.place_at(1, "fert_compost")).is_true()
	assert_str(_ids()[1]).is_equal("fert_compost")
	assert_bool(ui.is_pinned("seed_lettuce")).is_false()
	assert_array(ui._quick_for("farm").removed).not_contains(["seed_lettuce"])
	assert_array(_ids()).contains(["seed_lettuce"])   # not removed: the bar's free end takes it back like any seed

func test_an_item_already_on_the_bar_swaps_places() -> void:
	ui.place_at(0, "seed_lettuce")
	assert_array(_ids()).is_equal(["seed_lettuce", "seed_radish"])

func test_dropping_a_removed_item_back_clears_its_removal() -> void:
	ui._on_slot_removed("seed_radish")
	assert_array(ui._quick_for("farm").removed).contains(["seed_radish"])
	ui.place_at(2, "seed_radish")
	assert_array(ui._quick_for("farm").removed).not_contains(["seed_radish"])
	assert_str(_ids()[2]).is_equal("seed_radish")

func test_pin_to_takes_the_first_gap_then_the_free_end() -> void:
	ui._on_slot_removed("seed_radish")   # its slot stays a gap
	assert_array(_ids()).is_equal(["", "seed_lettuce"])
	assert_bool(ui.pin_to("fert_compost")).is_true()
	assert_array(_ids()).is_equal(["fert_compost", "seed_lettuce"])
	assert_bool(ui.pin_to("seed_radish")).is_true()
	assert_array(_ids()).is_equal(["fert_compost", "seed_lettuce", "seed_radish"])
	assert_bool(ui.is_pinned("seed_radish")).is_true()
	ui.unpin("seed_radish")
	assert_bool(ui.is_pinned("seed_radish")).is_false()
	assert_str(_ids()[2]).is_equal("seed_radish")   # unpinning leaves it where it is

func test_pin_to_on_a_full_bar_replaces_the_last_unpinned_and_stops_at_five_pins() -> void:
	ui.set_view(_view([{"id": "seed_potato", "qty": 5}, {"id": "seed_carrot", "qty": 2}, {"id": "seed_herb", "qty": 1}]))
	assert_array(_ids()).is_equal(["seed_radish", "seed_lettuce", "seed_potato", "seed_carrot", "seed_herb"])
	assert_bool(ui.pin_to("fert_compost")).is_true()
	assert_array(_ids()).is_equal(["seed_radish", "seed_lettuce", "seed_potato", "seed_carrot", "fert_compost"])
	for id in ["seed_radish", "seed_lettuce", "seed_potato", "seed_carrot"]: ui.pin_to(id)
	assert_bool(ui.can_pin("seed_herb")).is_false()   # the card greys Pin: Bar full · Unpin one first
	assert_bool(ui.pin_to("seed_herb")).is_false()
	assert_bool(ui.can_pin("seed_radish")).is_true()   # already pinned: Unpin stays available

func test_pinning_for_another_action_is_recorded_for_that_bar() -> void:
	assert_bool(ui.pin_to("bait_worm")).is_true()
	assert_array(_ids()).is_equal(["seed_radish", "seed_lettuce"])
	assert_bool(ui.is_pinned("bait_worm")).is_true()
	ui.set_mode("fish")
	ui.set_view(_view())
	assert_str(_ids()[0]).is_equal("bait_worm")

func test_the_bar_docks_into_the_drawer_row_and_comes_back_on_close() -> void:
	await await_idle_frame()
	var home := ui._bar.get_global_rect()
	var index := ui._bar.get_index()
	var row := VBoxContainer.new()   # stands in for P0BagDrawer.quick_row
	ui._kit.add_child(row)
	ui.dock_bar_into(row)
	await await_idle_frame()
	assert_bool(ui.is_bar_docked()).is_true()
	assert_object(ui._bar.get_parent()).is_same(row)
	assert_vector(ui._bar.size).is_equal(Vector2(UiTokens.SIZE_QUICK_BAR_W, UiTokens.SIZE_QUICK_BAR_H))
	assert_bool(ui._bar.zones_below).is_true()
	ui.close_modal()   # every close (Close, a scrim tap, a slide down) goes through _drop_modal
	await await_idle_frame()
	assert_bool(ui.is_bar_docked()).is_false()
	assert_object(ui._bar.get_parent()).is_same(ui._kit)
	assert_int(ui._bar.get_index()).is_equal(index)
	assert_bool(ui._bar.zones_below).is_false()
	assert_vector(ui._bar.get_global_rect().position).is_equal(home.position)
	ui.undock_bar()   # again: nothing happens
	assert_object(ui._bar.get_parent()).is_same(ui._kit)
