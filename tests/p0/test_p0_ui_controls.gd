extends GdUnitTestSuite
## P0 world controls wired to the UI kit (SGODOT-221): action key group, quick bar, radial, finger cards, badges.

const STORE := "user://test_p0_quickbar.json"

var ui: P0Ui

func _view() -> Dictionary:
	return {
		"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000},
		"crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2}],
		"names": {"seed_radish": "Radish Seeds", "seed_lettuce": "Lettuce Seeds"},
		"bag": {"capacity": 25, "free": 22, "slots": [{"id": "seed_radish", "qty": 20}, {"id": "seed_lettuce", "qty": 10}, {"id": "crop_radish", "qty": 3}]},
		"plots": [], "rest": {"used": 0, "limit": 1, "resets_in": 3600000}, "coins": 40, "skills": {},
	}

func _make() -> P0Ui:
	var u := P0Ui.new()
	u.quick_store = STORE
	add_child(auto_free(u))
	u.layer = 128   # above anything an earlier suite leaves in the tree (tests/scenes leaks a MapPoc)
	return u

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	ui = _make()
	await await_idle_frame()
	ui.set_mode("farm")
	ui.set_surface("farm")

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

## Desktop test runs read the mouse (UiSceneAction reads touches only on touchscreens).
func _touch(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = at
	e.global_position = at
	e.pressed = down
	get_viewport().push_input(e, true)

func test_action_key_shows_the_main_action_states() -> void:
	assert_object(ui._keys.tool_icon).is_equal(P0Logic.icon("hoe"))   # the starting mode has its tool badge
	var k := ui._keys.key()
	ui.set_action({"verb": "Till", "sub": "Free", "enabled": true, "amber": false, "cmd": {"type": "till"}, "need": 0})
	assert_str(k.verb).is_equal("Till")
	assert_str(k.cost).is_empty()   # zero-Energy actions carry no price (LOCK-02)
	assert_int(k.state).is_equal(UiSceneAction.State.DEFAULT)
	ui.set_action({"verb": "Sow ×1", "sub": "Need 2 Energy", "enabled": true, "amber": true, "cmd": {"type": "energy_card"}, "need": 2})
	assert_str(k.cost).is_equal("Need 2 Energy")
	assert_int(k.state).is_equal(UiSceneAction.State.INSUFFICIENT)
	ui.set_action({"verb": "Sow", "sub": "Pick a seed", "enabled": false, "amber": false, "cmd": {}, "need": 0})
	assert_str(k.cost).is_equal("Pick a seed")   # reasons stay, only the free price goes
	assert_int(k.state).is_equal(UiSceneAction.State.UNAVAILABLE)

func test_key_fires_on_touch_down_and_holds_until_release() -> void:
	var sent := []
	ui.action_pressed.connect(func(cmd): sent.append(cmd))
	ui.set_action({"verb": "Water", "sub": "Free", "enabled": true, "amber": false, "cmd": {"type": "water", "plot": 2}, "need": 0})
	var at := ui._keys.key().get_global_rect().get_center()
	_touch(at, true)
	await await_idle_frame()
	assert_array(sent).is_equal([{"type": "water", "plot": 2}])
	assert_bool(ui.fab_held).is_true()
	assert_str(ui.fab_verb).is_equal("Water")
	_touch(at, false)
	await await_idle_frame()
	assert_bool(ui.fab_held).is_false()

func test_controls_sit_where_bar_1_puts_them() -> void:
	var view := ui.root.size
	var bar := ui._bar.get_global_rect()
	var keys := ui._keys.get_global_rect()
	assert_float(bar.position.x).is_equal(float(UiTokens.SIZE_QUICK_BAR_X))
	assert_float(bar.end.y).is_equal(view.y - float(UiTokens.SIZE_QUICK_BAR_BOTTOM))
	assert_float(keys.end.x).is_equal(view.x - float(UiTokens.SPACE_PAGE))
	assert_float(bar.position.y - keys.end.y).is_equal(P0Ui._KEY_ABOVE_BAR)

func test_quick_bar_fills_from_the_bag_and_picks_the_first_seed_once() -> void:
	ui.set_view(_view())
	assert_array(ui._bar.slots.map(func(s): return s.id)).is_equal(["seed_radish", "seed_lettuce"])
	assert_str(ui._bar.slots[0].title).is_equal("Radish Seeds")
	assert_int(ui._bar.slots[0].quantity).is_equal(20)
	assert_str(ui.selected_seed).is_equal("seed_radish")
	assert_str(ui._bar.selected).is_equal("seed_radish")
	ui._on_slot_tapped("seed_radish")   # tap again clears (§10.3.4)
	ui.set_view(_view())
	assert_str(ui.selected_seed).is_empty()
	ui._on_slot_tapped("seed_lettuce")
	assert_str(ui._bar.selected).is_equal("seed_lettuce")

func test_pins_and_removals_persist_per_action() -> void:
	ui.set_view(_view())
	ui._on_pin_toggled("seed_lettuce", true)
	assert_bool(ui._bar.slots[1].pinned).is_true()
	assert_object(ui._pin_menu).is_not_null()
	ui._on_slot_removed("seed_radish")
	assert_array(ui._bar.slots.map(func(s): return s.id)).is_equal(["seed_lettuce"])
	var again := _make()
	await await_idle_frame()
	again.set_mode("farm")
	again.set_view(_view())
	assert_array(again._bar.slots.map(func(s): return s.id)).is_equal(["seed_lettuce"])
	assert_bool(again._bar.slots[0].pinned).is_true()
	assert_array(again._quick_for("fish").pins).is_empty()   # each action keeps its own (LOCK-05)

func test_map_keeps_only_bag_and_hides_the_keys() -> void:
	ui.set_surface("map")
	assert_bool(ui._bar.visible).is_false()   # until the map drops its old dock (map_bag)
	assert_bool(ui._keys.visible).is_false()
	ui.map_bag = true
	ui.set_surface("map")
	assert_bool(ui._bar.visible).is_true()
	assert_bool(ui._bar.bag_only).is_true()
	assert_bool(ui._keys.visible).is_false()
	ui.set_surface("room")   # farmhouse kitchen / outpost rooms: Bag only, no keys
	assert_bool(ui._bar.visible).is_true()
	assert_bool(ui._bar.bag_only).is_true()
	assert_bool(ui._keys.visible).is_false()
	ui.set_surface("busy")
	assert_bool(ui._bar.visible).is_false()
	ui.set_surface("farm")
	assert_bool(ui._bar.bag_only).is_false()
	assert_bool(ui._keys.visible).is_true()

func test_switch_key_fans_the_radial_out_from_the_character() -> void:
	ui.player_screen = Vector2(100, 300)
	ui.open_radial()
	assert_bool(ui._radial.visible).is_true()
	assert_bool(ui.has_modal()).is_true()
	assert_array(ui._radial.options.map(func(o): return o.available)).is_equal([true, false, false, false])
	assert_str(ui._radial.selected).is_equal("farm")
	ui.open_radial()   # the switch key again closes it
	assert_bool(ui._radial.visible).is_false()
	assert_bool(ui.has_modal()).is_false()

func test_finger_card_forwards_its_tap_to_the_facility() -> void:
	var taps := []
	ui.tapped.connect(func(p): taps.append(p))
	ui.tag("stall", "Tap to shop", Vector2(180, 300), true, Vector2(180, 340))
	var card: UiTapCard = ui._cards.stall
	assert_bool(card.visible).is_true()
	assert_str(card.text).is_equal("Tap to shop")
	assert_float(card.get_rect().end.y).is_equal(300.0 - UiTokens.SPACE_WITHIN)
	await await_idle_frame()
	var on_card := card.hit_rect().get_center()
	ui._tap_at(on_card, false)   # the scene pad's real tap on the card = the facility's tap
	assert_array(taps).is_equal([Vector2(180, 340)])
	ui._tap_at(on_card, true)    # a double tap on a card never recenters
	assert_array(taps).is_equal([Vector2(180, 340), Vector2(180, 340)])
	ui._tap_at(Vector2(40, 600), false)   # elsewhere it is the world's tap
	assert_vector(taps[-1]).is_equal(Vector2(40, 600))
	# Near the edge the card stays on screen and its pointer keeps aiming at the facility.
	ui.tag("stall", "Tap to shop", Vector2(4, 300), true)
	assert_float(card.position.x).is_equal(float(UiTokens.SPACE_WITHIN))
	ui.tag("stall", "Tap to shop", Vector2(180, 300), false)
	assert_bool(card.visible).is_false()

func test_badges_show_state_and_lift_the_finger_card() -> void:
	ui.badge("home", UiStatusBadge.State.COUNTDOWN, Vector2(200, 260), true, "1:12")
	var b: UiStatusBadge = ui._badges.home
	assert_bool(b.visible).is_true()
	assert_int(b.state).is_equal(UiStatusBadge.State.COUNTDOWN)
	assert_str(b.caption).is_equal("1:12")
	assert_int(b.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)   # display only (LOCK-07)
	assert_float(ui.badge_height("home")).is_greater(float(UiTokens.SIZE_STATUS_BADGE_WORLD))
	ui.badge("home", UiStatusBadge.State.READY, Vector2(200, 260), false)
	assert_float(ui.badge_height("home")).is_equal(0.0)
	# Off screen past the UI's own width: a fixed x passed or failed with the headless root size other suites left.
	ui.badge("home", UiStatusBadge.State.READY, Vector2(ui._kit.size.x + 100, 260), true)   # facility off screen
	assert_bool(b.visible).is_false()

func test_a_drag_from_a_finger_card_starts_the_joystick() -> void:
	# PR #12 review fix 3: the card is passive, so the press reaches the scene pad under it.
	ui.tag("stall", "Tap to shop", Vector2(180, 300), true)
	await await_idle_frame()
	var card: UiTapCard = ui._cards.stall
	var at := card.hit_rect().get_center()
	var sticks := []
	var taps := []
	ui.joystick.connect(func(v): sticks.append(v))
	ui.tapped.connect(func(p): taps.append(p))
	assert_int(card._card.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	_touch(at, true)
	var drag := InputEventMouseMotion.new()
	drag.position = at + Vector2(0, -40)
	drag.global_position = drag.position
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(drag, true)
	_touch(at + Vector2(0, -40), false)
	await await_idle_frame()
	assert_bool(sticks.any(func(v): return v != Vector2.ZERO)).is_true()
	assert_array(taps).is_empty()

func test_teaching_card_stays_clear_of_the_bar_and_the_keys() -> void:
	# PR #12 review fix 5: the tip sits above the quick bar and left of the action key group.
	var had_tips := FileAccess.file_exists(P0Ui.TIPS_PATH)
	var saved := FileAccess.get_file_as_string(P0Ui.TIPS_PATH) if had_tips else ""
	ui._taught = {"_": true}   # non-empty: teach() won't load saved tips over it
	ui.teach("probe_tip", "Pick a seed, walk up to a bed and press Sow. Hold to keep sowing.")
	await await_idle_frame()
	await await_idle_frame()
	var tip := ui._teach.get_global_rect()
	assert_float(tip.end.y).is_less_equal(ui._bar.get_global_rect().position.y)
	assert_float(tip.end.x).is_less_equal(ui._keys.get_global_rect().position.x)
	assert_bool(tip.intersects(ui._keys.get_global_rect())).is_false()
	if had_tips:
		var f := FileAccess.open(P0Ui.TIPS_PATH, FileAccess.WRITE)
		f.store_string(saved)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(P0Ui.TIPS_PATH))

func test_a_seed_sown_to_zero_is_deselected_and_a_zero_slot_cannot_be_picked() -> void:
	# 李白 q(44) ③ / PR #12 review fix 2: the pinned slot stays at 0, the key goes back to Sow · Pick a seed.
	ui.set_view(_view())
	ui._on_pin_toggled("seed_radish", true)
	assert_str(ui.selected_seed).is_equal("seed_radish")
	var v := _view()
	v.bag.slots = v.bag.slots.filter(func(s): return s.id != "seed_radish")
	ui.set_view(v)
	assert_array(ui._bar.slots.map(func(s): return s.id)).contains(["seed_radish"])
	assert_str(ui.selected_seed).is_empty()
	ui._on_slot_tapped("seed_radish")
	assert_str(ui.selected_seed).is_empty()   # a 0 slot can't be picked
	assert_str(ui._toast.text).is_equal("Buy at Homestead Stall")

func test_a_bar_without_the_action_family_shows_its_ghost_in_the_first_empty_slot() -> void:
	# A-08: Seeds on the farm, Bait at the pond; a tap opens the Bag.
	var v := _view()
	v.bag.slots = [{"id": "crop_radish", "qty": 3}]
	ui.set_view(v)
	assert_int(ui._bar.slots.size()).is_equal(1)
	assert_bool(ui._bar.slots[0].get("ghost", false)).is_true()
	assert_str(ui._bar.slots[0].title).is_equal("Seeds")
	assert_int(ui._bar.cells()[0].state).is_equal(UiItemCell.State.GHOST)
	assert_int(ui._bar.cells()[1].state).is_equal(UiItemCell.State.EMPTY)
	ui.set_mode("fish")
	ui.set_view(v)
	assert_str(ui._bar.slots[0].title).is_equal("Bait")
	ui._bar.cells()[0].tapped.emit()
	assert_str(ui.modal_kind).is_equal("bag")
	ui.set_mode("farm")
	ui.set_view(_view())   # seeds back in the bag: the ghost goes
	assert_bool(ui._bar.slots.any(func(s): return s.get("ghost", false))).is_false()

func test_the_last_bait_on_a_hook_empties_the_hook_with_a_toast() -> void:
	# 李白 q(44) ④: casting goes on without bait.
	var v := _view()
	v.bag.slots.append({"id": "bait_worm", "qty": 1})
	v.names["bait_worm"] = "Worm Bait"
	ui.set_mode("fish")
	ui.set_view(v)
	ui._on_slot_tapped("bait_worm")
	assert_str(ui.selected_bait).is_equal("bait_worm")
	ui._on_pin_toggled("bait_worm", true)
	v.bag.slots = v.bag.slots.filter(func(s): return s.id != "bait_worm")
	ui.set_view(v)
	assert_str(ui.selected_bait).is_empty()
	assert_str(ui._toast.text).is_equal("Out of Worm Bait · no bait on the hook")

func test_a_card_tap_cannot_start_a_double_tap() -> void:
	# PR #12 re-review: a tap elsewhere right after a card tap is a plain tap, not a recenter.
	ui.tag("stall", "Tap to shop", Vector2(180, 300), true)
	await await_idle_frame()
	var recentred := [0]
	ui.recenter.connect(func(): recentred[0] += 1)
	var on_card: Vector2 = (ui._cards.stall as UiTapCard).hit_rect().get_center()
	for e in [[on_card, true], [on_card, false], [Vector2(60, 560), true], [Vector2(60, 560), false]]:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.position = e[0]
		m.pressed = e[1]
		ui.pad._gui_input(m)
	assert_int(recentred[0]).is_equal(0)
