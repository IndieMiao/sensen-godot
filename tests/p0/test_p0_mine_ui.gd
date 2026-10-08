extends GdUnitTestSuite
## SGODOT-231 Mining in the P0 HUD (#12 world controls): the key group and bar in the mine, the status line, the
## equipped pickaxe in the key's badge, a torch chosen on purpose, and unavailable keys that say why.

const STORE := "user://test_p0_mine_quickbar.json"

var ui: P0Ui

func _view(torches := 2) -> Dictionary:
	var slots := [{"id": "seed_radish", "qty": 20}, {"id": "bait_worm", "qty": 4}]
	if torches > 0: slots.append({"id": "torch", "qty": torches})
	return {
		"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000},
		"crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2}],
		"names": {"seed_radish": "Radish Seeds", "bait_worm": "Worm Bait", "torch": "Torch"},
		"bag": {"capacity": 25, "free": 22, "slots": slots},
		"plots": [], "rest": {"used": 0, "limit": 1, "resets_in": 3600000}, "coins": 40, "skills": {},
	}

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	ui = P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	ui.layer = 128
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_mode("mine")
	ui.set_surface("mine")

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func test_the_mine_is_an_action_space() -> void:
	assert_bool(ui._keys.visible).is_true()
	assert_bool(ui._bar.visible).is_true()
	assert_bool(ui._creel.visible).is_false()
	assert_object(ui._keys.tool_icon).is_equal(P0Logic.icon("pickaxe"))

func test_mining_bar_holds_torches_and_picks_none() -> void:
	assert_array(ui._bar_ids).is_equal(["torch"])   # no seeds, no bait underground
	assert_str(ui.selected_seed).is_empty()          # a torch is chosen on purpose, like bait
	assert_bool(ui._bar.slots.any(func(s): return s.get("ghost", false))).is_false()
	ui.set_view(_view(0))
	assert_array(ui._bar_ids).is_empty()
	# q(44): an empty Mining bar shows the "Torch" ghost (a noun only), which opens the bag.
	var ghost: Array = ui._bar.slots.filter(func(s): return s.get("ghost", false))
	assert_int(ghost.size()).is_equal(1)
	assert_str(str(ghost[0].title)).is_equal("Torch")

func test_mining_pins_and_refill_hint() -> void:
	ui._set_pin("torch", true)
	ui.set_view(_view(0))
	assert_array(ui._bar_ids).is_equal(["torch"])   # pinned stays at 0 (LOCK-05)
	ui._on_slot_tapped("torch")
	assert_str(ui._toast.text).is_equal("Craft at Workbench")   # q(44): torches are made, not bought
	ui._on_slot_removed("torch")
	ui.set_view(_view(3))
	assert_array(ui._bar_ids).is_empty()   # flung off: stays off until pinned again

func test_farming_still_picks_its_first_seed() -> void:
	ui.set_mode("farm")
	ui.set_surface("farm")
	assert_str(ui.selected_seed).is_equal("seed_radish")

func test_status_line_shows_in_the_mine_and_clears_on_the_next_action() -> void:
	ui.set_status_line("Rocks 2/6")
	assert_bool(ui._status.visible).is_true()
	assert_str(ui._status_text.text).is_equal("Rocks 2/6")
	ui.set_status_line("")
	assert_bool(ui._status.visible).is_false()
	ui.set_status_line("Run 1/2 today")
	ui.set_mode("farm")
	ui.set_surface("farm")
	assert_bool(ui._status.visible).is_false()

func test_key_badge_shows_the_equipped_pickaxe() -> void:
	ui.set_action({"verb": "Mine", "sub": "2 Energy", "enabled": true, "amber": false, "cmd": {"type": "mine_rock"}, "need": 2, "tool": "pick_copper"})
	assert_object(ui._keys.tool_icon).is_equal(P0Logic.icon("pick_copper"))
	ui.set_mode("farm")
	assert_object(ui._keys.tool_icon).is_equal(P0Logic.icon("hoe"))

## Walkthrough bug: at the mine mouth the farm key carries the pickaxe; walking back to a bed the Sow key must
## show the hoe again, not keep the pickaxe.
func test_a_key_without_tool_shows_the_actions_own_tool() -> void:
	ui.set_mode("farm")
	ui.set_action({"verb": "Enter mine", "sub": "2 Energy", "enabled": true, "amber": false, "cmd": {"type": "mine_enter"}, "need": 2, "tool": "pick_starter"})
	assert_object(ui._keys.tool_icon).is_equal(P0Logic.icon("pick_starter"))
	ui.set_action({"verb": "Sow ×1", "sub": "2 Energy", "enabled": true, "amber": false, "cmd": {"type": "sow"}, "need": 2})
	assert_object(ui._keys.tool_icon).is_equal(P0Logic.icon("hoe"))

func test_mining_free_moves_keep_free_on_the_key() -> void:
	ui.set_action(P0MaterialLogic._key("elevator", "Elevator", "Free", {"type": "elevator"}))
	assert_str(ui._keys.key().cost).is_equal("Free")   # LOCK-21 Elevator · Free
	ui.set_action({"verb": "Till", "sub": "Free", "enabled": true, "amber": false, "cmd": {"type": "till"}, "need": 0})
	assert_str(ui._keys.key().cost).is_empty()         # LOCK-02 elsewhere: 0 Energy carries no price

func test_an_unavailable_key_toasts_its_reason() -> void:
	var sent := []
	ui.action_pressed.connect(func(cmd): sent.append(cmd))
	ui.set_action({"verb": "Enter mine", "sub": "Bag full", "enabled": false, "amber": false, "cmd": {}, "need": 0,
		"toast": "Bag full · free a slot to mine"})
	ui._fab_pressed()
	assert_array(sent).is_empty()
	assert_bool(ui._toast.visible).is_true()
	assert_str(ui._toast.text).is_equal("Bag full · free a slot to mine")
