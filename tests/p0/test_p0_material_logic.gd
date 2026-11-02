extends GdUnitTestSuite
## SGODOT-231 P0MaterialLogic: the mine's floors (LOCK-21, q(44); 355 b1, contract-efg §7), gathering marks, workbench
## cards (B2-06).

const Fx := preload("res://tests/p0/fixtures/mine_b1_view.gd")

func _view(energy := 200) -> Dictionary:
	return {"energy": {"value": energy, "max": 200}, "names": {"stone": "Stone", "copper_ore": "Copper Ore", "wood": "Timber", "torch": "Torch"},
		"bag": {"capacity": 25, "slots": []}, "mine": {"floor_energy": 2, "rock_energy": 2, "at": null, "records": {}}}

func test_stored_notice_shows_once() -> void:
	var v := _view()
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

## The workbench shares the yard with other cards' facilities (the rest bench took the workbench's first cell in 2B; the
## gathering spots left the farm in SGODOT-355 b1): no two footprints may overlap, none may cover a plot, all stay in the yard.
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

## LOCK-07: one finger card, the nearest facility in its own reach; the showing card keeps it on a near-tie.
func test_one_finger_card_for_the_nearest_facility() -> void:
	var cands := [["stall", Vector3(0, 0, 0), 3.2], ["home", Vector3(-4, 0, 0), 4.2], ["workbench", Vector3(3, 0, 0), 3.0]]
	assert_str(P0Garden.pick_card(cands, Vector3(0.5, 0, 0), "")).is_equal("stall")
	assert_str(P0Garden.pick_card(cands, Vector3(2.4, 0, 0), "")).is_equal("workbench")
	assert_str(P0Garden.pick_card(cands, Vector3(9, 0, 0), "stall")).is_equal("")   # none in reach
	# Midway (1.5 m from both): whichever was showing stays; an exact tie with nothing showing goes to the first.
	assert_str(P0Garden.pick_card(cands, Vector3(1.5, 0, 0), "workbench")).is_equal("workbench")
	assert_str(P0Garden.pick_card(cands, Vector3(1.5, 0, 0), "stall")).is_equal("stall")
	assert_str(P0Garden.pick_card(cands, Vector3(1.5, 0, 0), "")).is_equal("stall")
	# Clearly nearer to the other: it takes over.
	assert_str(P0Garden.pick_card(cands, Vector3(1.9, 0, 0), "stall")).is_equal("workbench")
	# The showing facility left its reach: the nearest in reach takes over.
	assert_str(P0Garden.pick_card(cands, Vector3(-3.5, 0, 0), "stall")).is_equal("home")
	# Reach is measured on the ground: standing up a slope or on a bed does not push a facility out of reach.
	# 2.95 m away on the ground but 0.6 m up: in reach (a straight 3D distance would be 3.01, out of reach).
	assert_str(P0Garden.pick_card(cands, Vector3(5.95, 0.6, 0), "")).is_equal("workbench")
	assert_float(P0FarmMaterials.flat(Vector3(0, 2, 0), Vector3(3, 0, 4))).is_equal_approx(5.0, 0.0001)

func test_mine_bar_follows_pins_and_removals() -> void:
	var v := {"bag": {"slots": [{"id": "torch", "qty": 3}, {"id": "seed_radish", "qty": 5}]}}
	var none := {"bag": {"slots": []}}
	assert_array(P0MaterialLogic.mine_bar(v, [])).is_equal(["torch"])
	assert_array(P0MaterialLogic.mine_bar(none, [])).is_empty()
	assert_array(P0MaterialLogic.mine_bar(none, [], ["torch"])).is_equal(["torch"])          # pinned at 0
	assert_array(P0MaterialLogic.mine_bar(v, [], [], ["torch"])).is_empty()                  # flung off
	assert_array(P0MaterialLogic.mine_bar(v, [], ["seed_radish", "torch"])).is_equal(["torch"])   # only Mining's family

# --- 355 b1 E: the mine's floors from view.mine.at (contract-efg §7.1) ---

## The place chip names the mine and the floor (E2 323:181423).
func test_the_place_chip_names_the_mine_and_floor() -> void:
	assert_str(P0MaterialLogic.mine_place(Fx.view(3))).is_equal("Ironvale Vein · Floor 3")
	assert_str(P0MaterialLogic.mine_place(_view())).is_equal("")

## Rocks are the player's choice: 2 Energy each; a full bag greys them alone (`Mine · Bag full`, v4q(5) ⑫); a guard's
## floor has none; the key never names a facility and carries the equipped pickaxe.
func test_the_rock_key() -> void:
	var v := Fx.view(3)
	var k := P0MaterialLogic.mine_action(v, {"floor": 3, "target": "rock", "rock": 1})
	assert_str("%s · %s" % [k.verb, k.sub]).is_equal("Mine · 2 Energy")
	assert_that(k.cmd).is_equal({"type": "mine_rock", "floor": 3, "rock": 1})
	assert_str(str(P0MaterialLogic.mine_action(v, {"floor": 3, "target": "", "rock": -1}).sub)).is_equal("Walk to a rock")
	var full := Fx.view(3, {"bag_ok": false})
	k = P0MaterialLogic.mine_action(full, {"floor": 3, "target": "rock", "rock": 1})
	assert_str("%s · %s" % [k.verb, k.sub]).is_equal("Mine · Bag full")
	assert_bool(bool(k.enabled)).is_false()
	assert_str(str(k.toast)).is_equal(P0MaterialLogic.BAG_FULL)
	k = P0MaterialLogic.mine_action(Fx.view(3, {"energy": 1}), {"floor": 3, "target": "rock", "rock": 1})
	assert_str(str(k.sub)).is_equal("Need 2 Energy")
	assert_bool(bool(k.amber)).is_true()
	assert_str(str(P0MaterialLogic.mine_action(Fx.view(20, {"rocks": 0}), {"floor": 20, "target": "", "rock": -1}).sub)).is_equal("No rocks here")
	assert_str(str(P0MaterialLogic.mine_action(Fx.view(3, {"rocks": 2, "broken": [true, true]}), {"floor": 3, "target": "", "rock": -1}).sub)).is_equal("No rocks here")   # q(62)
	v["gear"] = {"slots": {"mining": "pick_copper"}}
	assert_str(str(P0MaterialLogic.mine_action(v, {"floor": 3, "target": "rock", "rock": 0}).tool)).is_equal("pick_copper")
	# a floor the view is not on (a move on the wire): nothing to mine yet
	assert_bool(bool(P0MaterialLogic.mine_action(v, {"floor": 4, "target": "rock", "rock": 0}).enabled)).is_false()

func test_the_torch_lights_the_floor_once() -> void:
	var k := P0MaterialLogic.mine_action(Fx.view(3), {"floor": 3, "item": "torch"})
	assert_that(k.cmd).is_equal({"type": "mine_torch", "floor": 3})
	assert_str(str(P0MaterialLogic.mine_action(Fx.view(3, {"lit": true, "deck": []}), {"floor": 3, "item": "torch"}).sub)).is_equal("Lit")

## v4q(5) ⑪ ⑫: the torch shows the floor's deck in one Info toast, Stone alone when no card holds more.
func test_the_torch_toast_reads_the_deck() -> void:
	assert_str(P0MaterialLogic.torch_toast(Fx.view(12, {"lit": true, "deck": [["copper_ore", 2], ["iron_ore", 1]]}), 12)) \
		.is_equal("Floor 12 · Copper Ore ×2 · Iron Ore ×1")
	assert_str(P0MaterialLogic.torch_toast(Fx.view(12, {"lit": true, "deck": []}), 12)).is_equal("Floor 12 · Stone only")
	assert_str(P0MaterialLogic.torch_toast(Fx.view(12), 12)).is_equal("")

## Combat on every floor (355 b1); the key lands on Combat while a monster stands.
func test_mining_and_combat_on_every_floor() -> void:
	assert_array(P0MaterialLogic.mine_actions()).is_equal(["mine", "combat"])
	assert_str(P0MaterialLogic.landing_mode(Fx.view(1), 1)).is_equal("combat")
	assert_str(P0MaterialLogic.landing_mode(Fx.view(1, {"mobs": [Fx.mob("mob_slime", 0, 9)]}), 1)).is_equal("mine")
	assert_int(P0MaterialLogic.mobs_up(Fx.view(1, {"mobs": [Fx.mob("mob_slime", 0, 9), Fx.mob("mob_slime", 4, 9)]}), 1)).is_equal(1)
	assert_str(str(P0MaterialLogic.combat_action(Fx.view(1), {"floor": 1}).verb)).is_equal("Attack")

## E5: a guard once hit gets the HUD card with its name (untouched, the status line names it); elites and a fallen
## guard none.
func test_the_guard_card() -> void:
	var v := Fx.view(20, {"rocks": 0, "mobs": [Fx.mob("boss_slime_king_iron", 96, 160, false, true, 2)]})
	assert_that(P0MaterialLogic.guard_card(v, 20)).is_equal({"name": "Iron Slime King", "hp": 96, "max": 160})
	assert_that(P0MaterialLogic.guard_card(Fx.view(20, {"rocks": 0, "mobs": [Fx.mob("boss_slime_king_iron", 160, 160, false, true, 2)]}), 20)).is_empty()
	assert_that(P0MaterialLogic.guard_card(Fx.view(5, {"mobs": [Fx.mob("mob_elite_slime", 36, 36, true)]}), 5)).is_empty()
	assert_that(P0MaterialLogic.guard_card(Fx.view(20, {"rocks": 0, "mobs": [Fx.mob("boss_slime_king_iron", 0, 160, false, true, 2)]}), 20)).is_empty()

## The stairs (355 b1: they open on the monsters): grey while one stands, `Not open yet` past the first batch, free once
## entered today, else the fee on the card — never on the tap.
func test_the_stairs_down() -> void:
	var standing := P0MaterialLogic.mine_facility(Fx.view(3), 3, "stairs")
	assert_bool(bool(standing.card)).is_true()
	assert_bool(bool(standing.enabled)).is_false()
	assert_str(str(standing.label)).is_equal("Floor 4 · Clear Floor 3 first")
	assert_str(str(standing.toast)).is_equal("Floor 4 · Clear Floor 3 first")
	var clear := {"mobs": [Fx.mob("mob_slime", 0, 9)]}
	var fee := P0MaterialLogic.mine_facility(Fx.view(3, clear), 3, "stairs")
	assert_str(str(fee.label)).is_equal("Floor 4 · 2 Energy")
	assert_that(fee.cmd).is_equal({"type": "mine_floor", "to": 4, "via": "ladder"})
	var short := P0MaterialLogic.mine_facility(Fx.view(3, clear.merged({"energy": 1})), 3, "stairs")
	assert_str(str(short.label)).is_equal("Floor 4 · Need 2 Energy")
	assert_bool(bool(short.amber)).is_true()
	var paid := P0MaterialLogic.mine_facility(Fx.view(3, clear.merged({"next": {"floor": 4, "paid": true, "fee": 0, "open": true, "locked": null}})), 3, "stairs")
	assert_bool(bool(paid.card)).is_false()
	assert_that(paid.cmd).is_equal({"type": "mine_floor", "to": 4, "via": "ladder"})
	var f41 := P0MaterialLogic.mine_facility(Fx.view(40, {"mobs": [], "next": {"floor": 41, "paid": false, "fee": 2, "open": false, "locked": "not_open"}}), 40, "stairs")
	assert_str(str(f41.label)).is_equal("Floor 41 · Not open yet")
	assert_bool(bool(f41.enabled)).is_false()
	assert_that(P0MaterialLogic.mine_facility(Fx.view(25, {"next": null}), 25, "stairs").cmd).is_empty()   # a quarry's last floor

## Up a floor costs too when it was not entered today (the elevator to Floor 20, then up to 19); Floor 1's way up is
## the Entrance, out of the mine.
func test_the_stairs_up_and_the_entrance() -> void:
	assert_that(P0MaterialLogic.mine_facility(Fx.view(5), 5, "up").cmd).is_equal({"type": "mine_floor", "to": 4, "via": "ladder"})
	var unpaid := P0MaterialLogic.mine_facility(Fx.view(20, {"prev": {"floor": 19, "paid": false, "fee": 2}}), 20, "up")
	assert_str(str(unpaid.label)).is_equal("Floor 19 · 2 Energy")
	var no_prev := Fx.view(5)
	no_prev.mine.at.erase("prev")   # a server before `prev`: up as a free move (the server charges what it must)
	assert_that(P0MaterialLogic.mine_facility(no_prev, 5, "up").cmd).is_equal({"type": "mine_floor", "to": 4, "via": "ladder"})
	assert_that(P0MaterialLogic.mine_facility(Fx.view(1), 1, "exit").cmd).is_equal({"type": "mine_exit"})
	assert_that(P0MaterialLogic.mine_facility(Fx.view(1), 1, "elevator").cmd).is_equal({"type": "elevator"})

## The strips (E2 323:181572): `Floor 4 · 2 Energy`, `Floor 4 · Free`, `Entrance`; labels only.
func test_the_facility_strips() -> void:
	var clear := {"mobs": [Fx.mob("mob_slime", 0, 9)]}
	var down := P0WorldPrompts.mine_facility(Fx.view(3, clear), 3, "stairs")
	assert_str("%s · %s" % [down.text, down.fact]).is_equal("Floor 4 · 2 Energy")
	down = P0WorldPrompts.mine_facility(Fx.view(3, clear.merged({"next": {"floor": 4, "paid": true, "fee": 0, "open": true, "locked": null}})), 3, "stairs")
	assert_str("%s · %s" % [down.text, down.fact]).is_equal("Floor 4 · Free")
	down = P0WorldPrompts.mine_facility(Fx.view(3), 3, "stairs")
	assert_str("%s · %s" % [down.text, down.fact]).is_equal("Floor 4 · Clear Floor 3 first")
	var f41 := P0WorldPrompts.mine_facility(Fx.view(40, {"mobs": [], "next": {"floor": 41, "paid": false, "fee": 2, "open": false, "locked": "not_open"}}), 40, "stairs")
	assert_str("%s · %s" % [f41.text, f41.fact]).is_equal("Floor 41 · Not open yet")
	assert_str(str(P0WorldPrompts.mine_facility(Fx.view(1), 1, "exit").text)).is_equal("Entrance")
	var up := P0WorldPrompts.mine_facility(Fx.view(5), 5, "up")
	assert_str("%s · %s" % [up.text, up.fact]).is_equal("Floor 4 · Free")
	assert_str(str(P0WorldPrompts.mine_facility(Fx.view(10), 10, "elevator").text)).is_equal("Elevator")

## The elevator stands on Floor 1 and the stops only (contract-efg §4 ⑤).
func test_the_elevator_stands_on_floor_1_and_the_stops() -> void:
	assert_bool(P0MaterialLogic.has_elevator(Fx.view(1), 1)).is_true()
	assert_bool(P0MaterialLogic.has_elevator(Fx.view(10), 10)).is_true()
	assert_bool(P0MaterialLogic.has_elevator(Fx.view(7), 7)).is_false()

## E3 326:181733: `Elevator · Ironvale Vein`, the Entrance and this mine's stops — Here, Free, 2 Energy, Need.
func test_the_elevator_rows() -> void:
	var v := Fx.view(10, {"stations": [{"floor": 10, "paid": true}, {"floor": 20, "paid": false}, {"floor": 30, "paid": true}]})
	assert_str(P0MaterialLogic.elevator_title(v)).is_equal("Elevator · Ironvale Vein")
	var rows := P0MaterialLogic.elevator_rows(v, 10)
	assert_array(rows.map(func(r): return str(r.label))).is_equal(["Entrance · Free", "Floor 10 · Here", "Floor 20 · 2 Energy", "Floor 30 · Free"])
	assert_array(rows.map(func(r): return str(r.kind))).is_equal(["free", "here", "cost", "free"])
	assert_that(rows[0].cmd).is_equal({"type": "mine_leave"})
	assert_that(rows[2].cmd).is_equal({"type": "mine_floor", "to": 20, "via": "elevator"})
	var short := P0MaterialLogic.elevator_rows(Fx.view(1, {"energy": 1, "stations": [{"floor": 10, "paid": false}]}), 1)
	assert_str(str(short[1].label)).is_equal("Floor 10 · Need 2 Energy")
	assert_str(str(short[1].kind)).is_equal("short")

## A full bag greys every rock of the floor; no rock carries a torch preview any more (the deck is the floor's).
func test_rock_marks() -> void:
	var marks := P0MaterialLogic.rock_marks(Fx.view(3, {"rocks": 3, "broken": [true, false, false], "bag_ok": false}), 3)
	assert_array(marks.map(func(m): return bool(m.broken))).is_equal([true, false, false])
	assert_bool(marks.all(func(m): return bool(m.grey))).is_true()
	assert_bool(marks[0].has("preview")).is_false()

## The floats and toasts of v4q(5) ⑪ ⑫ and E5.
func test_mine_floats_and_toasts() -> void:
	assert_str(P0MaterialLogic.floor_fee_line([{"kind": "energy", "delta": -2, "reason": "mine_floor"},
		{"kind": "mine_floor", "mine": "wd-254-114", "floor": 13, "cleared": false, "station": false}])).is_equal("Floor 13 · −2 Energy")
	assert_str(P0MaterialLogic.floor_fee_line([{"kind": "mine_floor", "mine": "wd-254-114", "floor": 12}])).is_equal("")
	assert_str(P0MaterialLogic.new_day_toast(12)).is_equal("New day · Floor 12 has changed")
	assert_str(str(P0MaterialLogic.first_kill_float("boss_slime_king_iron").text)).is_equal("First kill · Iron Slime King")
	assert_str(str(P0MaterialLogic.ground_float(Fx.view(12), "iron_ore").text)).is_equal("Bag full · Iron Ore left on the floor")

## E6: the knock-out card — Floors 1–10 keep everything; from Floor 11 half of the floor's finds go, listed.
func test_the_knock_out_card() -> void:
	var v := Fx.view(1, {"records": {Fx.MINE: {"deepest": 14, "guards": [10]}}})
	v.mine.at = null
	var low := P0MaterialLogic.ko_card(v, Fx.MINE, 7, [])
	assert_str(str(low.title)).is_equal("Knocked out")
	assert_array(low.lines).is_equal(["You're back at the entrance.", "You kept everything."])
	assert_array(low.lost).is_empty()
	assert_str(str(low.best)).is_equal("Your best here is still Floor 14.")
	var deep := P0MaterialLogic.ko_card(v, Fx.MINE, 12, [["iron_ore", 3], ["coal", 1]])
	assert_str(str(deep.lines[1])).is_equal("You dropped half of what you found on this floor:")
	assert_array(deep.lost.map(func(l): return str(l.text))).is_equal(["Iron Ore ×3", "Coal ×1"])
	assert_str(str(deep.button)).is_equal("Close")

## 苏烈's #39 review: mine / gathering refusals never surface as "Can't do that (tempo)"; a stale day is a quiet rebuild
## (v4q(5) ⑥, 后裔 on #620).
func test_material_refusals_are_quiet_or_say_why() -> void:
	var rock := {"type": "mine_rock", "floor": 3, "rock": 2, "day": "2026-11-02"}
	for code in ["tempo", "rock_gone", "lit", "new_day", "not_in_mine", "mob_gone", "bad_target", "bad_rock"]:
		assert_str(str(P0MaterialLogic.refusal_text(code, {}, rock))).override_failure_message(code).is_empty()
	assert_str(str(P0MaterialLogic.refusal_text("bag_full", {"floor": 3}, rock))).is_equal(P0MaterialLogic.BAG_FULL)
	assert_str(str(P0MaterialLogic.refusal_text("bag_full", {}, {"type": "mine_pick", "ground": 1}))).is_empty()
	assert_str(str(P0MaterialLogic.refusal_text("floor_locked", {"left": 2}, {"type": "mine_floor", "to": 4}))).is_equal("Floor 4 · Clear Floor 3 first")
	assert_str(str(P0MaterialLogic.refusal_text("bad_floor", {"max": 40, "not_open": true}, {"type": "mine_floor", "to": 41}))).is_equal("Floor 41 · Not open yet")
	assert_str(str(P0MaterialLogic.refusal_text("bad_floor", {"max": 40}, {"type": "mine_floor", "to": 7}))).is_empty()
	assert_str(str(P0MaterialLogic.refusal_text("not_open", {"homestead": 8}, {"type": "mine_enter", "mine": "wd-1-1"}))).is_equal("Homestead Lv8")
	assert_str(str(P0MaterialLogic.refusal_text("homestead_level", {"need": 2}, {"type": "gather", "spot": "spot_clay_bank"}))).is_equal("Homestead Lv2")
	assert_str(str(P0MaterialLogic.refusal_text("tempo", {}, {"type": "gather"}))).is_empty()
	# need_energy and other commands keep the runtime's own handling.
	assert_object(P0MaterialLogic.refusal_text("need_energy", {"need": 2}, rock)).is_null()
	assert_object(P0MaterialLogic.refusal_text("tempo", {}, {"type": "sow"})).is_null()
	assert_str(P0MaterialLogic.energy_verb(rock, "Sow ×1")).is_equal("Mine")
	assert_str(P0MaterialLogic.energy_verb({"type": "mine_floor", "to": 13}, "Sow ×1")).is_equal("Floor 13")
	assert_str(P0MaterialLogic.energy_verb({"type": "sow"}, "Sow ×1")).is_equal("Sow ×1")

## Where a material comes from (355 b1): the mine types whose mains include it, by the map's word; Stone from any rock.
func test_mine_types_yielding() -> void:
	assert_array(P0MaterialLogic.mine_types_yielding("copper_ore").map(func(t): return str(t.word))).is_equal(["Quarry"])
	assert_array(P0MaterialLogic.mine_types_yielding("iron_ore").map(func(t): return str(t.word))).is_equal(["Vein"])
	assert_array(P0MaterialLogic.mine_types_yielding("gem")).is_empty()   # a geode's, not open in the first batch

## The status line (不知火舞 on 355): rocks and the monsters left; a guard not yet hit by its name.
func test_the_status_line() -> void:
	assert_str(P0MaterialLogic.mine_status(Fx.view(3, {"rocks": 6, "broken": [true, true, false, false, false, false]}), 3)) \
		.is_equal("Rocks 2/6 · 2 monsters left")
	assert_str(P0MaterialLogic.mine_status(Fx.view(3, {"mobs": [Fx.mob("mob_slime", 0, 9), Fx.mob("mob_elite_slime", 30, 36, true)]}), 3)) \
		.is_equal("Rocks 0/5 · 1 monster left")
	assert_str(P0MaterialLogic.mine_status(Fx.view(3, {"mobs": [Fx.mob("mob_slime", 0, 9)]}), 3)).is_equal("Rocks 0/5")
	assert_str(P0MaterialLogic.mine_status(Fx.view(20, {"rocks": 0, "mobs": [Fx.mob("boss_slime_king_iron", 160, 160, false, true, 2)]}), 20)) \
		.is_equal("Iron Slime King")
	assert_str(P0MaterialLogic.mine_status(Fx.view(20, {"rocks": 0, "mobs": [Fx.mob("boss_slime_king_iron", 0, 160, false, true, 2)]}), 20)).is_equal("")
	assert_str(P0MaterialLogic.mine_status(Fx.view(3), 4)).is_equal("")

# --- A wild site's mine on its mouth card (E1 321:181190, v4q(5) ⑩ ⑪; 亚瑟's card draws the rows) ---

## A site as the viewport sends it (contract-c §2 §3): the catalogue's mine block and the player's best_floor.
static func _site(type: String, mine: Dictionary, best := 0, open := true) -> Dictionary:
	return {"id": "wd-254-114", "type": type, "name": "Ironvale Vein", "open": open, "best_floor": best, "mine": mine}

const VEIN := {"floors": 46, "main": "iron_ore", "main_from": 10, "side": 1, "open_to": 40}
const QUARRY := {"floors": 26, "main": null, "main_from": 1, "side": 3, "open_to": null}

## A vein not been down yet: its main ore from F10, the first 3 monster kinds by floor, each guardian on its floors (one
## line a kind), Not visited; no Also row (丁13). Floors 1–40 for the type line: F41 on is not open.
func test_a_veins_rows_on_its_mouth_card() -> void:
	var v := _view()
	v.names["iron_ore"] = "Iron Ore"
	assert_that(P0MaterialLogic.wild_mine_rows(v, _site("vein", VEIN))).is_equal([
		["Main ore", "Iron Ore · from F10"],
		["Monsters", "Slime · Rock Beetle · Shroomling"],
		["Boss", "Iron Slime King · F20\nQuartz Slime King · F40"],
		["You", "Not visited"]])
	assert_str(P0MaterialLogic.wild_mine_floors(_site("vein", VEIN))).is_equal("Floors 1–40")
	# been down to F12 (best_floor: records[id].deepest, #643)
	assert_that(P0MaterialLogic.wild_mine_rows(v, _site("vein", VEIN, 12)).back()).is_equal(["You", "Best here F12"])

## A quarry has no single main ore (#616: all five), so no Main ore row; its guardian on every floor it guards down to
## its last floor (26 here: F30's is past it).
func test_a_quarrys_rows_have_no_main_ore() -> void:
	assert_that(P0MaterialLogic.wild_mine_rows(_view(), _site("quarry", QUARRY, 7))).is_equal([
		["Monsters", "Slime · Cave Bat · Rock Beetle"],
		["Boss", "Slime King · F10, F20"],
		["You", "Best here F7"]])
	assert_str(P0MaterialLogic.wild_mine_floors(_site("quarry", QUARRY))).is_equal("Floors 1–26")

## A grey pin (a mine type not open yet, E4 329:182456) has no rows: the card says Not open yet itself.
func test_a_mine_not_open_yet_has_no_rows() -> void:
	var grey := _site("geode", {"floors": 60, "main": "gem", "main_from": 10, "side": null, "open_to": 0}, 0, false)
	assert_array(P0MaterialLogic.wild_mine_rows(_view(), grey)).is_empty()
	assert_str(P0MaterialLogic.wild_mine_floors(grey)).is_equal("")
	assert_array(P0MaterialLogic.wild_mine_rows(_view(), {"id": "wd-1-1", "type": "woodland", "open": true})).is_empty()   # no mine
