extends GdUnitTestSuite
## SGODOT-288: mine floors 3–5 on the client — Express on the mouth card and the elevator (q(108)), Combat's key and
## the radial, the status line with the monsters, the event lines (Floor 4's Express, Run complete, knocked out), the
## HP bar and the elite card, and the slimes built from the view.

func _floor(n: int, paid := true, mobs := [], rocks := 6, broken := [false, false, false, false, false, false]) -> Dictionary:
	var b: Array = broken.slice(0, rocks)
	var left := b.filter(func(x): return not x).size()
	return {"floor": n, "paid": paid, "cleared": left == 0 and rocks > 0, "rocks": rocks, "left": left, "broken": b,
		"lit": false, "preview": null, "bag_ok": true, "mobs": mobs}

func _view(run = null, express := false, used := 0, energy := 200) -> Dictionary:
	return {"energy": {"value": energy, "max": 200}, "names": {"quartz": "Quartz"}, "bag": {"capacity": 25, "slots": []},
		"mine": {"runs": {"used": used, "limit": 2, "resets_in": 33120000}, "ended": null, "floor_energy": 2,
			"rock_energy": 2, "rocks": 6, "stone_per_rock": 1, "floors": 5, "express": express, "hp_max": 100,
			"weapon": {"id": "sword_wooden", "attack": 3, "speed": 2.0}, "run": run}}

const CLEARED := [true, true, true, true, true, true]
const SLIME := {"kind": "mob_slime", "hp": 9, "max": 9}
const ELITE := {"kind": "mob_elite_slime", "hp": 36, "max": 36}

func _run(floors: Array, block = null, hp := 100) -> Dictionary:
	return {"id": 1, "deepest": 1, "hp": hp, "can_new_run": block == null, "new_run_block": block, "floors": floors}

func _five(paid := [true, false, false, false, false]) -> Array:
	return [_floor(1, paid[0]), _floor(2, paid[1]), _floor(3, paid[2], [SLIME]), _floor(4, paid[3], [SLIME, SLIME, SLIME]),
		_floor(5, paid[4], [ELITE], 0)]

# ---- the mouth card (q(108) ①)

func test_no_express_until_floor_4_is_cleared_once() -> void:
	var card := P0MaterialLogic.mine_mouth_card(_view())
	assert_bool(card.express.is_empty()).is_true()

func test_without_a_run_express_has_no_note() -> void:
	var card := P0MaterialLogic.mine_mouth_card(_view(null, true))
	assert_str(str(card.main.label)).is_equal("Enter mine · 2 Energy")
	assert_str(str(card.express.label)).is_equal("Floor 5 · Express · Free")
	assert_that(card.express.cmd).is_equal({"type": "mine_express"})
	assert_str(str(card.note)).is_empty()
	# 0 Energy and no fee: short of Energy for Enter mine, Express still goes (no Energy gate on it)
	var short := P0MaterialLogic.mine_mouth_card(_view(null, true, 0, 0))
	assert_bool(bool(short.main.amber)).is_true()
	assert_bool(bool(short.express.enabled)).is_true()

func test_with_a_run_express_stacks_under_new_run_over_one_note() -> void:
	var run := _run(_five([true, true, false, false, false]))
	run.floors[1].broken = CLEARED
	var card := P0MaterialLogic.mine_mouth_card(_view(run, true, 1))
	assert_str(str(card.main.label)).is_equal("Continue run · Free")
	assert_str(str(card.second.label)).is_equal("New run · 2 Energy")
	assert_str(str(card.express.label)).is_equal("Floor 5 · Express · Free")
	assert_str(str(card.note)).is_equal("Current run will end · Runs today 1/2")

func test_express_greys_with_new_run_for_the_same_reason() -> void:
	var card := P0MaterialLogic.mine_mouth_card(_view(_run(_five(), "clear_floor_2"), true, 1))
	assert_bool(bool(card.express.enabled)).is_false()
	assert_str(str(card.express.toast)).is_equal("New run · Clear Floor 2 first")
	var spent := P0MaterialLogic.mine_mouth_card(_view(_run(_five(), "no_runs"), true, 2))
	assert_bool(bool(spent.express.enabled)).is_false()
	assert_str(str(spent.express.toast)).starts_with("Mine runs today 2/2")

# ---- the elevator (row 58: `Floor 5` · `Express · Free`, no note)

func test_elevator_offers_express_to_an_unpaid_floor_5() -> void:
	var floors := _five([true, true, true, false, false])
	for i in 3: floors[i].broken = CLEARED
	floors[0].cleared = true
	floors[1].cleared = true
	floors[2].cleared = true
	var rows := P0MaterialLogic.elevator_rows(_view(_run(floors), true), 3)
	var last: Dictionary = rows[-1]
	assert_str("%s · %s" % [last.name, last.state]).is_equal("Floor 5 · Express · Free")
	assert_str(str(last.kind)).is_equal("express")
	assert_that(last.cmd).is_equal({"type": "mine_express"})
	assert_str(str(rows[4].label)).is_equal("Floor 4 · 2 Energy")
	# not unlocked: Floor 5 waits for Floor 4 as before
	var locked := P0MaterialLogic.elevator_rows(_view(_run(floors), false), 3)
	assert_str(str(locked[-1].label)).is_equal("Floor 5 · Clear Floor 4 first")

func test_a_paid_floor_5_is_a_free_stop_not_express() -> void:
	var floors := _five([true, true, true, true, true])
	var rows := P0MaterialLogic.elevator_rows(_view(_run(floors), true), 1)
	assert_str(str(rows[-1].label)).is_equal("Floor 5 · Free")

# ---- Combat, the radial, the key, the status line

func test_combat_is_offered_on_floors_3_to_5_only() -> void:
	assert_array(P0MaterialLogic.mine_actions(2)).is_equal(["mine"])
	assert_array(P0MaterialLogic.mine_actions(3)).is_equal(["mine", "combat"])
	assert_array(P0MaterialLogic.mine_actions(5)).is_equal(["mine", "combat"])

func test_attack_is_free_and_carries_the_sword() -> void:
	var k := P0MaterialLogic.combat_action(_view(_run(_five([true, true, true, false, false]))), {"floor": 3})
	assert_str(str(k.verb)).is_equal("Attack")
	assert_str(str(k.sub)).is_empty()
	assert_str(str(k.tool)).is_equal("sword")
	assert_that(k.cmd).is_equal({"type": "mine_swing", "floor": 3})

func test_floor_5_has_no_rocks_to_mine() -> void:
	var k := P0MaterialLogic.mine_action(_view(_run(_five([true, true, true, true, true]))), {"floor": 5, "target": ""})
	assert_str("%s · %s" % [k.verb, k.sub]).is_equal("Mine · No rocks here")
	assert_bool(bool(k.enabled)).is_false()

func test_status_line_names_the_monsters_still_standing() -> void:
	var floors := _five([true, true, true, true, true])
	floors[2].broken = [true, true, false, false, false, false]
	floors[2].left = 4
	var v := _view(_run(floors))
	assert_str(P0MaterialLogic.mine_status(v, 3)).is_equal("Rocks 2/6 · 1 Slime")
	assert_str(P0MaterialLogic.mine_status(v, 4)).is_equal("Rocks 0/6 · 3 Slimes")
	assert_str(P0MaterialLogic.mine_status(v, 5)).is_equal("Elite Slime")
	floors[2].mobs = [{"kind": "mob_slime", "hp": 0, "max": 9}]
	assert_str(P0MaterialLogic.mine_status(_view(_run(floors)), 3)).is_equal("Rocks 2/6")

# ---- the replies' lines

func test_floor_4s_first_clear_names_express_instead_of_the_stop() -> void:
	var ev := [{"kind": "mine", "action": "rock", "floor": 4}, {"kind": "mine", "action": "cleared", "floor": 4},
		{"kind": "mine", "action": "express_unlocked", "floor": 4}]
	var lines := P0MaterialLogic.mine_event_lines(ev)
	assert_array(lines.map(func(l): return l.text)).is_equal(["Floor 4 cleared · Floor 5 Express unlocked"])
	var later := P0MaterialLogic.mine_event_lines([{"kind": "mine", "action": "cleared", "floor": 4}])
	assert_array(later.map(func(l): return l.text)).is_equal(["Floor 4 cleared · Elevator stop"])

func test_run_complete_banner_and_no_floor_5_stop_line() -> void:
	var ev := [{"kind": "mine", "action": "defeat", "mob_kind": "mob_elite_slime", "loot": ["quartz", 2]},
		{"kind": "mine", "action": "cleared", "floor": 5}, {"kind": "mine", "action": "complete", "floor": 5}]
	assert_array(P0MaterialLogic.mine_event_lines(ev)).is_empty()
	var b := P0MaterialLogic.run_complete(_view(null, true, 1), ["quartz", 2])
	assert_str("%s / %s / %s" % [b.title, b.subtitle, b.detail]).is_equal("Run complete / Elite Slime defeated / Mine runs today 1/2")
	assert_array(b.rewards.map(func(r): return r.text)).is_equal(["+2 Quartz"])

func test_knocked_out_line_and_quiet_races() -> void:
	assert_str(P0MaterialLogic.mine_event_text({"kind": "mine", "action": "knocked_out"})).is_equal("Knocked out · back at the entrance")
	for code in ["mob_gone", "bad_target"]:
		assert_str(str(P0MaterialLogic.refusal_text(code, {}, {"type": "mine_attack"}))).is_empty()
	assert_str(str(P0MaterialLogic.refusal_text("express_locked", {"floor": 4}, {"type": "mine_express"}))).is_equal("Clear Floor 4 first")

# ---- HP

func test_hp_bar_reads_percent_and_turns_red_under_30() -> void:
	var bar: UiHpBar = auto_free(UiHpBar.new(UiHpBar.Kind.PLAYER))
	bar.set_hp(70, 100)
	assert_str(bar.percent_text()).is_equal("70%")
	assert_bool(bar.low()).is_false()
	bar.set_hp(29, 100)
	assert_bool(bar.low()).is_true()
	bar.set_hp(0, 100)
	assert_str(bar.percent_text()).is_equal("0%")
	var elite: UiHpBar = auto_free(UiHpBar.new(UiHpBar.Kind.ELITE))
	elite.title = "Elite Slime"
	elite.set_hp(21, 36)
	assert_str(elite.percent_text()).is_equal("58%")
	assert_bool(elite.low()).is_false()   # the elite card has no red state of its own; its fill is danger already

# ---- the slimes from the view

func test_slimes_come_from_the_floor_and_a_dead_one_stays_gone() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	mover.position = load("res://modules/mining/mine_layout.gd").SPAWN
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	var floors := _five([true, true, true, true, true])
	c.sync_p0(_view(_run(floors)), 4, mover)
	assert_int(c.enemies.size()).is_equal(3)
	assert_dict(c.elite_hp()).is_empty()
	floors[3].mobs = [{"kind": "mob_slime", "hp": 0, "max": 9}, SLIME, SLIME]
	c.sync_p0(_view(_run(floors)), 4, mover)
	assert_int(c.enemies.size()).is_equal(2)
	assert_bool(c.enemies.has("slime_1")).is_false()
	c.sync_p0(_view(_run(floors)), 5, mover)   # a new floor: the elite alone, its HP for the card
	assert_int(c.enemies.size()).is_equal(1)
	assert_dict(c.elite_hp()).is_equal({"hp": 36, "max": 36})
	assert_int(c.weapon({}).damage).is_equal(3)

func Layout_bp() -> FarmBlueprint:
	var L = load("res://modules/mining/mine_layout.gd")
	var nodes: Array = []
	for i in L.FALLBACK_POSITIONS.size(): nodes.append({"id": str(i), "position": L.FALLBACK_POSITIONS[i]})
	return L._navigation(nodes, nodes.map(func(n): return n.id))

# ---- a slime's hit never sticks (苏烈 on #223)

## The hit command's end — ok with no hurt event (the server's 1 s window), refused, or a failed request — frees the
## next hit; another command's end does not. A reply that never comes frees it after HURT_STALE_MS.
func test_a_quiet_reply_still_frees_the_next_hit() -> void:
	var P0Mine = load("res://scenes/p0/p0_mine.gd")
	var mine = auto_free(P0Mine.new())
	for end in [[true, ""], [false, "tempo"], [false, "network"]]:
		mine._hurt_pending = true
		mine._on_settled("{\"type\":\"mine_rock\"}", end[0], end[1])
		assert_bool(mine._hurt_pending).is_true()
		mine._on_settled(P0Mine.HURT_KEY, end[0], end[1])
		assert_bool(mine._hurt_pending).is_false()

func test_a_hit_with_no_reply_at_all_is_freed_after_the_stale_time() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var P0Mine = load("res://scenes/p0/p0_mine.gd")
	var mine = auto_free(P0Mine.new())   # not in the tree: only its contact
	mine.rt = rt
	rt.session.busy = true   # nothing is sent: only the pending flag is under test
	mine._hurt_pending = true
	mine._hurt_sent_ms = Time.get_ticks_msec() - 1000
	mine._on_contact("slime_1")
	assert_bool(mine._hurt_pending).is_true()
	mine._hurt_sent_ms = Time.get_ticks_msec() - P0Mine.HURT_STALE_MS - 1
	mine._on_contact("slime_1")
	assert_bool(mine._hurt_pending).is_false()
	rt.session.busy = false

## The swing waits a little past the server's tempo (0.5 s for speed 2), so jitter never has a shown swing refused.
func test_the_swing_waits_past_the_servers_tempo() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	var v := _view(_run(_five([true, true, true, true, true])))
	v.mine["weapon"] = {"attack": 3, "speed": 2.0}
	c.sync_p0(v, 4, mover)
	assert_float(1.0 / float(c.weapon({}).speed)).is_equal_approx(0.5 + Combat.TEMPO_MARGIN_S, 0.0001)
