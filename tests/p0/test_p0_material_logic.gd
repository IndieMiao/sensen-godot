extends GdUnitTestSuite
## SGODOT-231 P0MaterialLogic: mine mouth and floors (LOCK-21, q(44)), gathering marks, workbench cards (B2-06).

func _floor(n: int, paid := true, broken := [false, false, false, false, false, false], lit := false, bag_ok := true, preview = null) -> Dictionary:
	var left := broken.filter(func(b): return not b).size()
	return {"floor": n, "paid": paid, "cleared": left == 0, "left": left, "broken": broken, "lit": lit, "preview": preview, "bag_ok": bag_ok}

func _view(run = null, energy := 200, used := 0) -> Dictionary:
	return {
		"energy": {"value": energy, "max": 200},
		"names": {"stone": "Stone", "copper_ore": "Copper Ore", "wood": "Timber", "torch": "Torch"},
		"bag": {"capacity": 25, "slots": []},
		"mine": {"runs": {"used": used, "limit": 2, "resets_in": 33120000}, "ended": null, "floor_energy": 2, "rock_energy": 2, "rocks": 6,
			"stone_per_rock": 1, "run": run},
	}

func _run(floors: Array, block = "clear_floor_2") -> Dictionary:
	return {"id": 1, "deepest": 1, "can_new_run": block == null, "new_run_block": block, "floors": floors}

const CLEARED := [true, true, true, true, true, true]

func test_mine_mouth_key_follows_lock_21() -> void:
	var enter := P0MaterialLogic.mine_entry_action(_view())
	assert_str("%s · %s" % [enter.verb, enter.sub]).is_equal("Enter mine · 2 Energy")
	assert_that(enter.cmd).is_equal({"type": "mine_enter"})
	var cont := P0MaterialLogic.mine_entry_action(_view(_run([_floor(1), _floor(2, false)])))
	assert_str("%s · %s" % [cont.verb, cont.sub]).is_equal("Continue run · Free")
	var short := P0MaterialLogic.mine_entry_action(_view(null, 1))
	assert_str(str(short.sub)).is_equal("Need 2 Energy")
	assert_bool(bool(short.amber)).is_true()
	assert_that(short.cmd).is_equal({"type": "energy_card"})
	var none := P0MaterialLogic.mine_entry_action(_view(null, 200, 2))
	assert_str("%s · %s" % [none.verb, none.sub]).is_equal("Enter mine · No runs left")
	assert_bool(bool(none.enabled)).is_false()
	assert_str(str(none.toast)).is_equal("Mine runs today 2/2 · Resets in 9h 12m")
	var full := _view()
	full.mine["entry_bag_ok"] = false
	var gated := P0MaterialLogic.mine_entry_action(full)
	assert_str("%s · %s" % [gated.verb, gated.sub]).is_equal("Enter mine · Bag full")
	assert_bool(bool(gated.enabled)).is_false()

func test_entry_card_offers_new_run_only_after_floor_2() -> void:
	assert_bool(bool(P0MaterialLogic.mine_entry_card(_view()).show)).is_false()
	var blocked := P0MaterialLogic.mine_entry_card(_view(_run([_floor(1), _floor(2, false)])))
	assert_str(str(blocked.label)).is_equal("New run · Clear Floor 2 first")
	assert_bool(bool(blocked.enabled)).is_false()
	var open := P0MaterialLogic.mine_entry_card(_view(_run([_floor(1, true, CLEARED), _floor(2, true, CLEARED)], null), 200, 1))
	assert_str(str(open.label)).is_equal("New run · 2 Energy")
	assert_str(str(open.line2)).is_equal("Current run will end · Runs today 1/2")
	assert_that(open.cmd).is_equal({"type": "mine_new_run"})
	var spent := P0MaterialLogic.mine_entry_card(_view(_run([_floor(1, true, CLEARED), _floor(2, true, CLEARED)], "no_runs"), 200, 2))
	assert_str(str(spent.label)).is_equal("Mine runs today 2/2 · Resets in 9h 12m")
	var full := _view(_run([_floor(1, true, CLEARED), _floor(2, true, CLEARED)], null), 200, 1)
	full.mine["entry_bag_ok"] = false
	assert_str(str(P0MaterialLogic.mine_entry_card(full).label)).is_equal("New run · Bag full")

func test_rock_key_costs_two_and_greys_on_a_full_bag() -> void:
	var v := _view(_run([_floor(1), _floor(2, false)]))
	var mine := P0MaterialLogic.mine_action(v, {"floor": 1, "target": "rock", "rock": 2})
	assert_str("%s · %s" % [mine.verb, mine.sub]).is_equal("Mine · 2 Energy")
	assert_that(mine.cmd).is_equal({"type": "mine_rock", "floor": 1, "rock": 2})
	var full := P0MaterialLogic.mine_action(_view(_run([_floor(1, true, [false, false, false, false, false, false], false, false), _floor(2, false)])),
		{"floor": 1, "target": "rock", "rock": 2})
	assert_str("%s · %s" % [full.verb, full.sub]).is_equal("Mine · Bag full")
	assert_bool(bool(full.enabled)).is_false()
	assert_str(str(full.toast)).is_equal("Bag full · free a slot to mine")
	var low := P0MaterialLogic.mine_action(_view(_run([_floor(1), _floor(2, false)]), 1), {"floor": 1, "target": "rock", "rock": 0})
	assert_bool(bool(low.amber)).is_true()
	assert_str(str(low.sub)).is_equal("Need 2 Energy")
	var gone := P0MaterialLogic.mine_action(_view(_run([_floor(1, true, [true, false, false, false, false, false]), _floor(2, false)])),
		{"floor": 1, "target": "rock", "rock": 0})
	assert_bool(bool(gone.enabled)).is_false()

func test_stairs_need_the_floor_cleared_then_cost_two() -> void:
	var v := _view(_run([_floor(1), _floor(2, false)]))
	var stairs := P0MaterialLogic.mine_action(v, {"floor": 1, "target": "stairs"})
	assert_str("%s · %s" % [stairs.verb, stairs.sub]).is_equal("Floor 2 · Clear Floor 1")
	assert_bool(bool(stairs.enabled)).is_false()
	var open := P0MaterialLogic.mine_action(_view(_run([_floor(1, true, CLEARED), _floor(2, false)])), {"floor": 1, "target": "stairs"})
	assert_str("%s · %s" % [open.verb, open.sub]).is_equal("Floor 2 · 2 Energy")
	assert_that(open.cmd).is_equal({"type": "mine_floor", "floor": 2})
	var gated := P0MaterialLogic.mine_action(_view(_run([_floor(1, true, CLEARED), _floor(2, false, [false, false, false, false, false, false], false, false)])), {"floor": 1, "target": "stairs"})
	assert_str("%s · %s" % [gated.verb, gated.sub]).is_equal("Floor 2 · Bag full")
	var gate_rows := P0MaterialLogic.elevator_rows(_view(_run([_floor(1, true, CLEARED), _floor(2, false, [false, false, false, false, false, false], false, false)])), 1)
	assert_str(str(gate_rows[2].label)).is_equal("Floor 2 · Bag full")
	var paid := P0MaterialLogic.mine_action(_view(_run([_floor(1, true, CLEARED), _floor(2)])), {"floor": 1, "target": "stairs"})
	assert_str(str(paid.sub)).is_equal("Free")
	var elevator := P0MaterialLogic.mine_action(v, {"floor": 1, "target": "elevator"})
	assert_str("%s · %s" % [elevator.verb, elevator.sub]).is_equal("Elevator · Free")
	var out := P0MaterialLogic.mine_action(v, {"floor": 1, "target": "exit"})
	assert_str("%s · %s" % [out.verb, out.sub]).is_equal("Exit mine · Free")
	assert_that(out.cmd).is_equal({"type": "mine_exit"})
	var up := P0MaterialLogic.mine_action(_view(_run([_floor(1, true, CLEARED), _floor(2)])), {"floor": 2, "target": "up"})
	assert_str("%s · %s" % [up.verb, up.sub]).is_equal("Floor 1 · Free")
	assert_that(up.cmd).is_equal({"type": "mine_floor", "floor": 1})

func test_torch_lights_once_per_floor() -> void:
	var lit := P0MaterialLogic.mine_action(_view(_run([_floor(1), _floor(2, false)])), {"floor": 1, "item": "torch"})
	assert_str("%s · %s" % [lit.verb, lit.sub]).is_equal("Light Torch · Free")
	assert_that(lit.cmd).is_equal({"type": "mine_torch", "floor": 1})
	var again := P0MaterialLogic.mine_action(_view(_run([_floor(1, true, [false, false, false, false, false, false], true), _floor(2, false)])),
		{"floor": 1, "item": "torch"})
	assert_str(str(again.sub)).is_equal("Lit")
	assert_bool(bool(again.enabled)).is_false()

func test_elevator_rows_follow_the_run() -> void:
	var rows := P0MaterialLogic.elevator_rows(_view(_run([_floor(1), _floor(2, false)])), 1)
	assert_array(rows.map(func(r): return r.label)).is_equal(["Entrance · Free", "Floor 1 · Here", "Floor 2 · Clear Floor 1 first"])
	assert_that(rows[0].cmd).is_equal({"type": "mine_leave"})
	rows = P0MaterialLogic.elevator_rows(_view(_run([_floor(1, true, CLEARED), _floor(2, false)])), 1)
	assert_str(str(rows[2].label)).is_equal("Floor 2 · 2 Energy")
	assert_that(rows[2].cmd).is_equal({"type": "mine_floor", "floor": 2})
	rows = P0MaterialLogic.elevator_rows(_view(_run([_floor(1, true, CLEARED), _floor(2)])), 2)
	assert_array(rows.map(func(r): return r.label)).is_equal(["Entrance · Free", "Floor 1 · Free", "Floor 2 · Here"])
	for r in rows: assert_int(str(r.label).length()).is_less_equal(26)
	assert_str(str(rows[1].name)).is_equal("Floor 1")
	assert_str(str(rows[1].state)).is_equal("Free")
	assert_str(str(rows[2].state)).is_equal("Here")

func test_rock_marks_and_floats() -> void:
	var marks := P0MaterialLogic.rock_marks(_view(_run([_floor(1, true, [true, false, false, false, false, false], true, true,
		["copper_ore", null, "rock_salt", null, null, "clay"]), _floor(2, false)])), 1)
	assert_bool(bool(marks[0].broken)).is_true()
	assert_str(str(marks[0].preview)).is_equal("copper_ore")
	assert_str(str(marks[1].preview)).is_equal("")
	assert_str(P0MaterialLogic.mine_event_text({"kind": "mine", "action": "floor", "floor": 2, "cost": 2})).is_equal("Floor 2 · −2 Energy")
	assert_str(P0MaterialLogic.mine_event_text({"kind": "mine", "action": "floor", "floor": 1, "cost": 0})).is_equal("")
	assert_str(P0MaterialLogic.mine_event_text({"kind": "mine", "action": "cleared", "floor": 1})).is_equal("Floor 1 cleared · Elevator stop")

func test_reset_and_stored_notices_show_once() -> void:
	var v := _view()
	v.mine.ended = {"reason": "reset", "at": 1000.0}
	assert_str(P0MaterialLogic.reset_notice(v, 0.0)).is_equal("Run ended at daily reset")
	assert_str(P0MaterialLogic.reset_notice(v, 1000.0)).is_equal("")
	v["storage"] = {"items": [], "auto": {"at": 2000.0, "items": [["stone", 12], ["copper_ore", 3]]}}
	assert_str(P0MaterialLogic.stored_notice(v, 0.0)).is_equal("Stored · 12 Stone · 3 Copper Ore")
	assert_str(P0MaterialLogic.stored_notice(v, 2000.0)).is_equal("")

func test_gather_marks_and_today_line() -> void:
	var v := {"names": {"wood": "Timber"}, "gather": {"gloves": false, "spots": [
		{"id": "spot_grove", "name": "Timber Grove", "open": true, "homestead": 1, "ready": false, "ready_in": 7800000, "yield": [["wood", 6]]},
		{"id": "spot_clay_bank", "name": "Clay Bank", "open": false, "homestead": 2, "ready": false, "ready_in": 0, "yield": [["clay", 2]]},
	]}}
	var marks := P0MaterialLogic.gather_marks(v)
	assert_str(str(marks[0].caption)).is_equal("Timber Grove · Ready in 2h 10m")
	assert_str(str(marks[0].badge)).is_equal("countdown")
	assert_str(str(marks[1].caption)).is_equal("Clay Bank · Homestead Lv2")
	assert_str(P0MaterialLogic.today_gather_line(v)).is_equal("Timber Grove · Ready in 2h 10m")
	v.gather.spots[0].ready = true
	assert_str(str(P0MaterialLogic.gather_marks(v)[0].caption)).is_equal("Timber Grove · Tap to gather")
	assert_str(P0MaterialLogic.today_gather_line(v)).is_equal("")
	assert_array(P0MaterialLogic.gather_floats(v, {"items": [["wood", 6, "storage"], ["bait_worm", 2, "bag"]]})).is_equal(["+6 Timber · Stored"])

func _recipe(id: String, tab: String, item: String, name: String, to: String, cost: Array, block = null, owned := false, equipped := false) -> Dictionary:
	return {"id": id, "tab": tab, "item": item, "name": name, "qty": 2 if to == "bag" else 1, "to": to, "have": 6 if to == "bag" else null,
		"cost": cost, "gate": null, "owned": owned, "equipped": equipped, "can_craft": block == null and not owned, "block": block}

func test_workbench_cards_write_gaps_on_the_button() -> void:
	var ore := {"id": "copper_ore", "name": "Copper Ore", "need": 5, "have": 4, "storage": 4, "bag": 0}
	var wood := {"id": "wood", "name": "Timber", "need": 4, "have": 4, "storage": 4, "bag": 0}
	var v := {"workbench": {"tabs": ["tools", "supplies"], "recipes": [
		_recipe("craft_copper_pickaxe", "tools", "pick_copper", "Copper Pickaxe", "gear", [ore, wood],
			{"code": "need_material", "detail": {"item": "copper_ore", "need": 5, "have": 4}}),
		_recipe("craft_gather_gloves", "tools", "gather_gloves", "Gather Gloves", "owned", [], null, true),
		_recipe("craft_torch", "supplies", "torch", "Torch", "bag", [wood]),
		_recipe("craft_compost", "supplies", "fert_compost", "Compost", "bag", [], {"code": "locked", "detail": {"skill": "farming", "level": 3}}),
	]}}
	var tools := P0MaterialLogic.workbench_model(v, "tools")
	assert_int(tools.size()).is_equal(2)
	assert_str(str(tools[0].effect)).is_equal("2 Stone per rock")
	assert_that(tools[0].button).is_equal({"label": "Need 1 more Copper Ore", "kind": "unavailable", "cmd": {}})
	assert_str(str(tools[1].effect)).is_equal("+1 at every gathering spot")
	assert_str(str(tools[1].button.label)).is_equal("Owned · always on")
	var supplies := P0MaterialLogic.workbench_model(v, "supplies")
	assert_that(supplies[0].button).is_equal({"label": "Craft", "kind": "primary", "cmd": {"type": "craft", "recipe": "craft_torch"}})
	assert_str(str(supplies[0].yield)).is_equal("You get 2")
	assert_str(str(supplies[0].have)).is_equal("You have 6")
	assert_str(str(supplies[1].button.label)).is_equal("Farming Lv3")

func test_workbench_pickaxe_equip_and_bag_full() -> void:
	var v := {"workbench": {"tabs": ["tools", "supplies"], "recipes": [
		_recipe("craft_copper_pickaxe", "tools", "pick_copper", "Copper Pickaxe", "gear", [], {"code": "owned"}, true, false),
		_recipe("craft_torch", "supplies", "torch", "Torch", "bag", [], {"code": "bag_full", "detail": {"room": 0}}),
	]}}
	assert_that(P0MaterialLogic.workbench_model(v, "tools")[0].button).is_equal({"label": "Equip", "kind": "secondary", "cmd": {"type": "equip", "item": "pick_copper"}})
	v.workbench.recipes[0].equipped = true
	assert_str(str(P0MaterialLogic.workbench_model(v, "tools")[0].button.label)).is_equal("Equipped")
	assert_str(str(P0MaterialLogic.workbench_model(v, "supplies")[0].button.label)).is_equal("No room · free a slot first")

func test_mining_quick_bar_holds_torches_only() -> void:
	var v := _view()
	assert_array(P0MaterialLogic.mine_candidates(v)).is_empty()
	v.bag.slots = [{"id": "torch", "qty": 3}, {"id": "seed_radish", "qty": 20}]
	assert_array(P0MaterialLogic.mine_candidates(v)).is_equal(["torch"])

func test_mine_mouth_badge_sheet_and_status() -> void:
	assert_str(P0MaterialLogic.mine_badge(_view())).is_equal("Explore")
	assert_str(P0MaterialLogic.mine_badge(_view(_run([_floor(1), _floor(2, false)]), 200, 1))).is_equal("Run 1/2")
	var sheet := P0MaterialLogic.mine_sheet(_view())
	assert_str(str(sheet.line)).is_equal("Explore two floors and gather materials.")
	assert_that(sheet.facts).is_equal([["Runs today", "0/2"]])
	var spent := P0MaterialLogic.mine_sheet(_view(null, 200, 2))
	assert_str(str(spent.subtitle)).is_equal("No run · Runs today 2/2")
	assert_that(spent.button).is_equal({"label": "Mine runs today 2/2 · Resets in 9h 12m", "enabled": false})
	var confirm := P0MaterialLogic.new_run_sheet(_view(_run([_floor(1, true, CLEARED), _floor(2, true, CLEARED)], null), 200, 1))
	assert_that(confirm.facts).is_equal([["Runs today", "1/2 → 2/2"]])
	assert_that(confirm.confirm.cmd).is_equal({"type": "mine_new_run"})
	assert_str(str(confirm.keep)).is_equal("Keep current run")
	var v := _view(_run([_floor(1, true, [true, true, false, false, false, false]), _floor(2, false)]), 200, 1)
	assert_str(P0MaterialLogic.mine_status(v, 1)).is_equal("Rocks 2/6")
	assert_str(P0MaterialLogic.mine_status(v, 1, true)).is_equal("Run 1/2 today")

func test_locked_spot_sheet_and_gloves_moment() -> void:
	var v := {"names": {"clay": "Clay"}, "gather": {"gloves": true, "spots": [
		{"id": "spot_grove", "name": "Timber Grove", "open": true, "homestead": 1, "ready": true, "ready_in": 0, "yield": [["wood", 7]]},
		{"id": "spot_clay_bank", "name": "Clay Bank", "open": false, "homestead": 2, "ready": false, "ready_in": 0, "yield": [["clay", 2]]},
	]}}
	var locked := P0MaterialLogic.locked_spot_sheet(v, "spot_clay_bank")
	assert_str(str(locked.line)).is_equal("Gather Clay from this spot once unlocked.")
	assert_that(locked.facts).is_equal([["Unlock", "Homestead Lv2"]])
	var moment := P0MaterialLogic.gloves_moment(v)
	assert_str(str(moment.fact)).is_equal("Next Timber harvest: 7")
	assert_str(str(moment.note)).is_equal("Passive · no gear slot needed")

func test_mine_keys_carry_the_equipped_pickaxe_badge() -> void:
	var v := _view(_run([_floor(1), _floor(2, false)]))
	v["gear"] = {"slots": {"mining": "pick_copper"}}
	assert_str(str(P0MaterialLogic.mine_action(v, {"floor": 1, "target": "rock", "rock": 0}).tool)).is_equal("pick_copper")
	assert_str(str(P0MaterialLogic.mine_entry_action(_view()).tool)).is_equal("pickaxe")

## The gathering spots and the workbench share the yard with other cards' facilities (the rest bench took the
## workbench's first cell in 2B): no two footprints may overlap, none may cover a plot, all stay in the yard.
func test_material_footprints_overlap_nothing() -> void:
	var owner := {}
	for key in P0Garden.FOOTPRINTS:
		var r: Rect2i = P0Garden.FOOTPRINTS[key]
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				var c := Vector2i(x, y)
				assert_bool(owner.has(c)).override_failure_message("%s overlaps %s at %s" % [key, owner.get(c, ""), c]).is_false()
				assert_int(P0Garden.id_of(c)).override_failure_message("%s covers a plot at %s" % [key, c]).is_equal(-1)
				if str(key).begins_with("spot_") or key == "workbench":
					assert_bool(P0Garden.WALK_RECT.has_point(c)).override_failure_message("%s leaves the yard" % key).is_true()
					# Row 18's back edge is the Lv3 fence line (z −12.35 m, SGODOT-228; 苏烈 on 231): nothing past row 17.
					assert_int(c.y).override_failure_message("%s sits on the back fence" % key).is_less_equal(17)
				owner[c] = key

## Grove trunks block the cells they stand in, canopies don't (不知火舞 on 231): the way from the field's right edge
## to the workbench front stays open.
func test_grove_trunks_block_and_the_way_to_the_workbench_stays_open() -> void:
	var bp := P0Garden.blueprint()
	var at := bp.cell_to_world(bp.anchor("spot_grove"))
	var trunks := P0SpotArt.solid_points("spot_grove", at)
	assert_int(trunks.size()).is_equal(3)
	P0Garden.block_points(bp, trunks)
	for p in trunks: assert_bool(bp.is_walkable(bp.world_to_cell(p))).is_false()
	# Breadth-first walk from the field's right edge (15, 11) to the cell in front of the workbench (17, 15).
	var start := Vector2i(15, 11)
	var goal := Vector2i(17, 15)
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if seen.has(n) or not bp.is_walkable(n): continue
			seen[n] = true
			queue.append(n)
	assert_bool(seen.has(goal)).is_true()
