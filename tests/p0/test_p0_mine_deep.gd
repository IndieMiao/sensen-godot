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
	rt.session.busy = true   # a command on the wire: a new hit queues behind it (296 #16), nothing posts
	var sent: Array = []
	rt.session.sent.connect(func(cmd): sent.append(cmd))
	mine._hurt_pending = true
	mine._hurt_sent_ms = Time.get_ticks_msec() - 1000
	mine._on_contact("slime_1")
	assert_array(sent).is_empty()   # the hit before is still awaited: this one waits
	var stale: int = Time.get_ticks_msec() - P0Mine.HURT_STALE_MS - 1
	mine._hurt_sent_ms = stale
	mine._on_contact("slime_1")
	assert_int(sent.size()).is_equal(1)   # freed after the stale time: the next hit goes
	assert_int(mine._hurt_sent_ms).is_greater(stale)
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

# ---- landing on a floor with monsters (李元芳 R5 on SGODOT-288)

## Express straight to Floor 5 met the elite with the key on `Mine · No rocks here`: a floor with a monster up lands on
## Combat; a cleared one, and floors 1–2, on Mining.
func test_a_floor_with_monsters_up_lands_on_combat() -> void:
	var floors := _five([true, true, true, true, true])
	assert_str(P0MaterialLogic.landing_mode(_view(_run(floors)), 5)).is_equal("combat")
	assert_str(P0MaterialLogic.landing_mode(_view(_run(floors)), 3)).is_equal("combat")
	assert_str(P0MaterialLogic.landing_mode(_view(_run(floors)), 2)).is_equal("mine")
	floors[2].mobs = [{"kind": "mob_slime", "hp": 0, "max": 9}]
	assert_str(P0MaterialLogic.landing_mode(_view(_run(floors)), 3)).is_equal("mine")
	assert_int(P0MaterialLogic.mobs_up(_view(_run(floors)), 4)).is_equal(3)
	assert_str(P0MaterialLogic.landing_mode(_view(null), 5)).is_equal("mine")   # no run: nothing to fight

## The monsters hold still 2 s on arrival (the old mine's grace was 1.5 s).
func test_monsters_hold_still_on_arrival() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	mover.position = load("res://modules/mining/mine_layout.gd").SPAWN
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	c.sync_p0(_view(_run(_five([true, true, true, true, true]))), 5, mover)
	assert_float(c.grace).is_equal(Combat.LANDING_GRACE_S)
	assert_float(Combat.LANDING_GRACE_S).is_greater_equal(2.0)

# ---- the lunge band (不知火舞 785a6a5b, 上官婉儿 c8a7507a, 李白 on SGODOT-288)

## A wind-up lays the band along the locked direction, sweeping from the feet to the lunge's reach; Body squashes, the
## root (bars, shadow, band) does not; the leap follows the band.
func test_a_wind_up_lays_the_band_along_the_locked_lunge() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	mover.position = load("res://modules/mining/mine_layout.gd").SPAWN
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	c.sync_p0(_view(_run(_five([true, true, true, true, true]))), 5, mover)
	c.grace = 0.0
	var e: Dictionary = c.enemies.values()[0]
	(e.mover as PlayerMover).position = mover.position + Vector3(0, 0, -2.0)   # within the elite's 2.4 m reach
	e.node.position = e.mover.position
	c.step(0.016, mover, false)
	assert_str(str(e.phase)).is_equal("windup")
	var band: Node3D = e.node.get_node("Band")
	assert_bool(band.visible).is_true()
	assert_vector(e.band_dir).is_equal_approx(Vector3(0, 0, 1), Vector3(0.01, 0.01, 0.01))   # towards the player
	assert_vector((e.node.get_node("Body") as Node3D).scale).is_equal(Combat.SQUASH)
	assert_vector(e.node.scale).is_equal(Vector3.ONE)
	var early: float = (band.get_node("Strip") as Node3D).scale.z
	# the band itself points at the player, not only band_dir (苏烈 on #239): its local +z, in the world, is the lunge
	var along: Vector3 = band.global_transform.basis.z.normalized()
	assert_vector(along).is_equal_approx(Vector3(0, 0, 1), Vector3(0.01, 0.01, 0.01))
	mover.position += Vector3(3, 0, 0)   # the player steps aside: the band keeps its line
	for i in 30: c.step(0.016, mover, false)
	assert_vector(e.band_dir).is_equal_approx(Vector3(0, 0, 1), Vector3(0.01, 0.01, 0.01))
	assert_float((band.get_node("Strip") as Node3D).scale.z).is_greater(early)
	assert_vector(band.global_transform.basis.z.normalized()).is_equal_approx(Vector3(0, 0, 1), Vector3(0.01, 0.01, 0.01))
	while str(e.phase) == "windup": c.step(0.016, mover, false)
	assert_str(str(e.phase)).is_equal("dash")
	assert_bool(band.visible).is_true()   # through the lunge (不知火舞 7d4f0231)
	var laid: Vector3 = band.global_position
	while str(e.phase) == "dash": c.step(0.016, mover, false)
	assert_vector(band.global_position).is_equal_approx(laid, Vector3(0.001, 0.001, 0.001))   # where the wind-up laid it
	assert_bool(band.visible).is_true()   # fading
	for i in 12: c.step(0.016, mover, false)   # past the 0.15 s fade
	assert_bool(band.visible).is_false()

func test_the_band_reaches_as_far_as_the_lunge_hits() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var c: Node3D = auto_free(Combat.new())
	var elite: Dictionary = c.band_of("elite_slime")
	assert_float(elite.reach).is_equal_approx(6.2 * 0.42 + 0.65 + 0.35, 0.001)
	assert_float(elite.width).is_equal_approx(2.0, 0.001)
	assert_float(c.band_of("slime").reach).is_less(elite.reach)   # a slime's is shorter

## Every way onto a floor with a monster up — the mouth's Continue run / Enter mine (_ready), stairs, the elevator,
## Express (_go_floor) — lands on Attack with the monsters held still: both come from the floor's view, not the way
## in (李元芳 R5 retest on SGODOT-288). The scene's own _ready / _go_floor call landing_mode and sync_p0 sets the grace.
func test_continue_run_lands_like_express() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_mine.gd")
	var ready_at := src.find("func _ready()")
	var go_at := src.find("func _go_floor(")
	assert_int(src.find("landing_mode(", ready_at)).is_between(ready_at, src.find("\nfunc ", ready_at + 5))
	assert_int(src.find("landing_mode(", go_at)).is_between(go_at, src.find("\nfunc ", go_at + 5))
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	var v := _view(_run(_five([true, true, true, true, true])))
	c.sync_p0(v, 5, mover)   # a fresh mine scene's first frame (Continue run lands here)
	assert_float(c.grace).is_equal(Combat.LANDING_GRACE_S)
	c.grace = 0.5
	c.sync_p0(v, 5, mover)   # the same floor's later frames keep counting down
	assert_float(c.grace).is_equal(0.5)
	assert_str(P0MaterialLogic.landing_mode(v, 5)).is_equal("combat")

## A lunge across the room: the band points where the player stood when the wind-up began, whichever way that is.
func test_the_band_points_along_the_lunge_in_any_direction() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	c.sync_p0(_view(_run(_five([true, true, true, true, true]))), 5, mover)
	c.grace = 0.0
	var e: Dictionary = c.enemies.values()[0]
	mover.position = load("res://modules/mining/mine_layout.gd").SPAWN
	(e.mover as PlayerMover).position = mover.position + Vector3(1.4, 0, -1.4)   # diagonal to the player, inside the room
	e.node.position = e.mover.position
	c.step(0.016, mover, false)
	assert_str(str(e.phase)).is_equal("windup")
	var want: Vector3 = (mover.position - (e.node as Node3D).position).normalized()
	assert_vector(e.node.get_node("Band").global_transform.basis.z.normalized()).is_equal_approx(want, Vector3(0.02, 0.02, 0.02))

## The elite whose fall completes the run (李元芳 B6, 283 86d07bd5): that reply's view has no run left to sync from, so
## the defeat itself puts it down — its last number rises and it is gone, its HUD card with it — instead of standing at
## its last HP under the Run complete banner until the mine is left.
func test_the_elite_goes_down_when_its_fall_completes_the_run() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	var floors := _five([true, true, true, true, true])
	floors[4] = _floor(5, true, [ELITE.merged({"hp": 3}, true)], 0)
	c.sync_p0(_view(_run(floors)), 5, mover)
	assert_dict(c.elite_hp()).is_equal({"hp": 3, "max": 36})
	var node: Node3D = c.enemies.values()[0].node
	c.down(0)
	assert_dict(c.elite_hp()).is_empty()
	assert_bool(node.visible).is_false()
	assert_array(c._numbers.map(func(n): return n.label.text)).is_equal(["3"])
	var y: float = c._numbers[0].label.position.y
	c.fade(0.1)   # what the scene runs while the banner holds the fight
	assert_float(c._numbers[0].label.position.y).is_greater(y)
	for i in 8: c.fade(0.1)
	assert_array(c._numbers).is_empty()
	c.down(0)   # it is down already: nothing more
	assert_array(c._numbers).is_empty()
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_mine.gd")
	assert_str(src.substr(src.find("\"defeat\":", src.find("func _on_state(")), 220)).contains("combat.down(")
	assert_str(src.substr(src.find("if _completing:", src.find("func p0_frame(")), 160)).contains("combat.fade(dt)")
	var complete := src.substr(src.find("func _run_complete("), 400)
	assert_str(complete).contains("rt.ui.set_hp(_hp_shown, _hp_max)")
	assert_str(complete).contains("rt.ui.set_status_line(\"\")")

## q(116): the second elite of the day says `Quartz · first kill each day`; a reply with both the elite's fall (complete)
## and the player's (knocked_out) is a win — the scene only handles knocked_out without a complete beside it.
func test_quartz_line_and_the_win_over_a_fall() -> void:
	assert_str(P0MaterialLogic.QUARTZ_ONCE).is_equal("Quartz · first kill each day")
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_mine.gd")
	var at := src.find("\"knocked_out\":   # the elite's last blow", src.find("func _on_state("))
	assert_int(at).is_greater(0)
	assert_str(src.substr(at, 240)).contains("\"complete\"")

## q(116) ③ on the client: a fall while a swing is still in flight waits for it; the swing that completes the run makes
## the fall a win (no Knocked out); a fall after Run complete started is ignored.
func test_a_fall_waits_for_a_swing_in_flight_and_loses_to_run_complete() -> void:
	var P0Mine = load("res://scenes/p0/p0_mine.gd")
	var mine = auto_free(P0Mine.new())
	mine._swings_out["mine_swing_0"] = true
	mine._knocked_out()
	assert_bool(mine._ko_waiting).is_true()   # held: nothing left the mine yet
	mine._completing = true                    # that swing's reply carried complete
	mine._on_settled("mine_swing_0", true, "")
	assert_bool(mine._ko_waiting).is_false()
	assert_bool(mine._leaving).is_false()      # no Knocked out after Run complete
	mine._knocked_out()                        # and a late fall is ignored
	assert_bool(mine._ko_waiting).is_false()
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_mine.gd")   # no new swing while a fall waits
	var at := src.find("func _swing()")
	assert_str(src.substr(at, 120)).contains("_ko_waiting")

## Knocked out (不知火舞 on 288 78d0f863): the server refills HP for the run at once, but the moment keeps the bar at 0 %,
## the slimes still and no new hit sent until the player is out.
func test_the_knock_out_moment_holds_the_fight_at_zero() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_mine.gd")
	var fight := src.substr(src.find("func _fight("), 900)
	assert_str(fight).contains("_completing or _ko)")
	assert_str(fight).contains("(0 if _ko else")
	var contact := src.substr(src.find("func _on_contact("), 300)
	assert_str(contact).contains("or _ko: return")
	assert_str(src.substr(src.find("func _swing()"), 160)).contains("or _ko:")
	var P0Mine = load("res://scenes/p0/p0_mine.gd")
	var mine = auto_free(P0Mine.new())
	mine._completing = true
	mine._knocked_out()
	assert_bool(mine._ko).is_false()   # Run complete wins; no KO moment

## The Old Tree (§13.3.6, 刘邦 / 不知火舞 on 288): a farm gathering spot at (2, 10) — off the beds (x 4–18, rows 3–11),
## in the spots' left column, blocked for walking and for décor, three rows from the Clay Bank (their strips never meet).
func test_the_old_tree_stands_in_the_left_column_off_the_beds() -> void:
	assert_bool(P0FarmMaterials.SPOTS.has("spot_old_tree")).is_true()
	var cell: Vector2i = P0Garden.ANCHORS["spot_old_tree"]
	assert_that(cell).is_equal(Vector2i(2, 10))
	assert_that(P0Garden.FOOTPRINTS["spot_old_tree"]).is_equal(Rect2i(2, 10, 1, 1))
	assert_bool(cell.x < 4).is_true()   # left of the beds
	assert_int(absi(cell.y - (P0Garden.ANCHORS["spot_clay_bank"] as Vector2i).y)).is_greater_equal(3)
	var yard: Dictionary = P0Logic.content().get("decor", {}).get("yard", {})
	assert_bool((yard.get("objects", []) as Array).any(func(r): return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).has_point(cell))).is_true()

## The slash (SGODOT-291, 不知火舞 on 291 72917be2): the swing plays attack_slash, then attack_slash_b while Attack is
## pressed on, back to attack_slash after a pause over 0.8 s; no labour clip. The sword is in the right hand only from the
## slash's wrist peak to its end, gripped on the hand bone as the clip poses it.
func _slashing_mine() -> Node:
	var P0Mine = load("res://scenes/p0/p0_mine.gd")
	var mine = auto_free(P0Mine.new())
	var bp := Layout_bp()
	var actor: P0Actor = auto_free(P0Actor.new())
	add_child(actor)
	actor.setup(bp, BlueprintGrid.new(bp), null, load("res://modules/mining/mine_layout.gd").SPAWN)
	mine.actor = actor
	mine.combat = auto_free(load("res://modules/mining/p0_mine_combat.gd").new())
	return mine

func test_the_slashes_alternate_and_start_again_after_a_pause() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_mine.gd")
	var at := src.find("func _swing()")
	var swing := src.substr(at, src.find("\nfunc ", at + 1) - at)   # the body up to the next func (苏烈 on #270)
	assert_str(swing).contains("combat.swing(")
	assert_str(swing).not_contains("labour(")
	var mine = _slashing_mine()
	await get_tree().process_frame
	var played := []
	var press := func(after: float) -> void:
		mine._slash_t += after
		mine.combat.cooldown = 0.0
		mine.actor._attack_left = 0.0
		mine._swing()
		played.append(mine.SLASHES[mine._slash][0])
	press.call(0.0)
	press.call(0.53)   # held at the weapon's tempo
	press.call(0.53)
	press.call(0.9)    # paused: the chop again
	press.call(0.53)
	assert_array(played).is_equal(["attack_slash", "attack_slash_b", "attack_slash", "attack_slash", "attack_slash_b"])
	assert_float(mine.combat.fx_delay).is_equal_approx(0.27, 0.0001)   # the sweep's peak (0.30 s), the arc 0.03 s early
	# within the tempo nothing swings and no clip starts
	mine.combat.cooldown = 0.2
	var before: int = mine._slash
	mine._slash_t = 0.1
	mine._swing()
	assert_int(mine._slash).is_equal(before)
	assert_float(mine._slash_t).is_equal(0.1)

func test_the_sword_is_in_hand_for_the_whole_slash() -> void:
	var mine = _slashing_mine()
	await get_tree().process_frame
	mine._hold_sword("sword_wooden")
	assert_object(mine._sword.get_parent()).is_same(mine.actor)
	assert_bool(mine.sword_shown()).is_false()          # between swings
	mine._swing()
	mine._hold_sword("sword_wooden")
	assert_bool(mine.actor.attacking()).is_true()
	assert_bool(mine.sword_shown()).is_true()           # B (不知火舞 on 291): in hand from the wind-up
	var sk: Skeleton3D = mine.actor.rig.skeleton
	if sk and sk.find_bone(mine.HAND_BONE) >= 0:         # on the hand: its grip within a hand's length of the wrist
		var wrist: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(mine.HAND_BONE))).origin
		var grip: Vector3 = mine._sword.global_transform * Vector3(0, mine.SWORD_GRIP_Y, 0)
		assert_float(grip.distance_to(wrist)).is_less(0.15)
	mine.actor._attack_left = 0.0                       # the clip is over
	mine._hold_sword("sword_wooden")
	assert_bool(mine.sword_shown()).is_false()
	mine._hold_sword("")                                # no Combat slot weapon: no sword
	assert_object(mine._sword).is_null()

## On the move (不知火舞 on 291): the slash holds the body still to its strike (the chop 0.22 s, the sweep 0.30 s)
## whatever the stick says; past it the stick cancels the follow-through and the body moves at once, while with the stick
## let go the clip plays out.
func test_a_slash_holds_still_to_its_strike_then_the_stick_cancels_it() -> void:
	var mine = _slashing_mine()
	var cam := Camera3D.new()
	add_child(auto_free(cam))
	cam.look_at_from_position(Vector3(0, 10, 10), Vector3.ZERO)
	mine.actor.cam = cam
	await get_tree().process_frame
	mine.actor.set_input(Vector2(1, 0))
	for i in 10: mine.actor.step(1.0 / 30.0)
	assert_bool(mine.actor.mover.is_moving()).is_true()   # walking
	mine._swing()
	var at: Vector3 = mine.actor.mover.position
	for i in 6: mine.actor.step(1.0 / 30.0)            # 0.2 s: before the chop's strike
	assert_vector(mine.actor.mover.position).is_equal(at)
	assert_bool(mine.actor.attacking()).is_true()
	for i in 2: mine.actor.step(1.0 / 30.0)            # past 0.22 s, the stick still pushed: moving again
	assert_bool(mine.actor.mover.is_moving()).is_true()
	assert_bool(mine.actor.attacking()).is_false()
	# the stick let go: the clip plays out
	mine.actor.set_input(Vector2.ZERO)
	for i in 4: mine.actor.step(1.0 / 30.0)
	mine.combat.cooldown = 0.0
	mine._swing()                                       # the sweep (0.30 s to its strike)
	for i in 12: mine.actor.step(1.0 / 30.0)            # 0.4 s
	assert_bool(mine.actor.attacking()).is_true()
	assert_bool(mine.actor.mover.is_moving()).is_false()
	# a walk tapped during the hold (a ladder's) is kept and goes once the strike is past (苏烈 on #299)
	mine.actor._attack_left = 0.0
	mine.combat.cooldown = 0.0
	mine._slash_t = 1.0
	mine._swing()                                       # the chop: held 0.22 s
	var held: Vector3 = mine.actor.mover.position
	var goal := held + Vector3(-1.3, 0, 0)
	assert_bool(mine.actor.mover.set_target_position(goal)).is_true()
	for i in 5: mine.actor.step(1.0 / 30.0)
	assert_vector(mine.actor.mover.position).is_equal(held)   # still held
	assert_bool(mine.actor.attacking()).is_true()
	for i in 20: mine.actor.step(1.0 / 30.0)
	assert_float(mine.actor.mover.position.distance_to(held)).is_greater(0.3)   # walked on after the strike

## The strike shows at the wrist's peak: the arc, the slime's flash and knockback wait fx_delay; who was hit and its
## stun come at the press (the command and the server's tempo as before).
func test_the_strike_shows_at_the_peak_the_hit_counts_at_the_press() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	mover.position = load("res://modules/mining/mine_layout.gd").SPAWN
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	c.sync_p0(_view(_run(_five([true, true, true, true, true]))), 4, mover)
	c.grace = 0.0
	var id: String = c.enemies.keys()[0]
	var e: Dictionary = c.enemies[id]
	(e.mover as PlayerMover).position = mover.position + Vector3(0, 0, -1.2)   # open floor north of the spawn
	e.node.position = e.mover.position
	mover.facing = Vector3(0, 0, -1)
	var at: Vector3 = e.node.position
	c.fx_delay = 0.22
	var hit: Array = c.swing({}, mover)
	assert_array(hit).contains([id])                    # judged at the press
	assert_str(str(e.phase)).is_equal("stunned")
	assert_bool(is_instance_valid(c._swing)).is_false()  # no arc yet
	assert_vector(e.node.position).is_equal(at)          # not knocked back yet
	assert_float(float(e.flash)).is_equal(0.0)
	for i in 10: c.step(0.016, mover, false)            # 0.16 s
	assert_bool(is_instance_valid(c._swing)).is_false()
	for i in 5: c.step(0.016, mover, false)             # past 0.22 s
	assert_bool(is_instance_valid(c._swing) and c._swing.visible).is_true()
	assert_float(e.node.position.distance_to(mover.position)).is_greater(at.distance_to(mover.position))
	c.fx_delay = 0.0                                     # without a clip: at once, as before
	c.cooldown = 0.0
	var arc = c._swing
	c.swing({}, mover)
	assert_bool(c._swing != arc).is_true()

## The swing measures to a monster's body (不知火舞 on 288, measured 10-10): the elite (0.65 m) waits 2.4 m centre to
## centre behind the player before its lunge; the player turns to it and the swing reaches its body's edge.
func test_the_swing_turns_to_the_elite_and_reaches_its_body() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	c.sync_p0(_view(_run(_five([true, true, true, true, true]))), 5, mover)
	var elite: Dictionary = c.enemies.values()[0]
	assert_float(float(elite.spec.radius)).is_equal(0.65)
	var at := Vector3(4.75, 0, -0.55)
	mover.position = at
	mover.facing = Vector3(0, 0, 1)                         # facing the camera, the elite behind
	elite.node.position = at + Vector3(0, 0, -2.39)          # its wind-up spot (the 10-10 run)
	elite.mover.position = elite.node.position
	assert_float(Combat.edge_distance(at, elite)).is_equal_approx(1.74, 0.001)
	c.cooldown = 0.0
	var hit: Array = c.swing({}, mover)
	assert_vector(mover.facing).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.001)   # turned to it
	assert_array(hit).has_size(1)                          # B: the arc reaches its body there (1.74 ≤ 1.65 + 0.15)
	assert_bool(Combat.within_swing(at, mover.facing, elite.node.position, Combat.REACH, 120.0)).is_false()   # the legacy centre test missed it
	elite.node.position = at + Vector3(0, 0, -2.6)          # its recovery spot: edge 1.95 m
	elite.mover.position = elite.node.position
	mover.facing = Vector3(0, 0, 1)
	c.cooldown = 0.0
	assert_array(c.swing({}, mover)).is_empty()            # turned to it, a step in still needed
	assert_vector(mover.facing).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.001)

## The elite's lunge stops where its body meets the player's (不知火舞 288 ce070cd7: it ran on through, the player sank
## into it to the head) and still lands its touch; a lunge the player stepped out of runs its whole length.
func test_the_lunge_stops_at_the_players_body() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	mover.position = load("res://modules/mining/mine_layout.gd").SPAWN
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	c.sync_p0(_view(_run(_five([true, true, true, true, true]))), 5, mover)
	c.grace = 0.0
	var touched: Array = []
	c.contact.connect(func(id): touched.append(id))
	var e: Dictionary = c.enemies.values()[0]
	var radius := float(e.spec.radius)
	(e.mover as PlayerMover).position = mover.position + Vector3(0, 0, -2.0)
	e.node.position = e.mover.position
	var closest := INF
	c.step(0.016, mover, false)
	while str(e.phase) in ["windup", "dash"]:
		c.step(0.016, mover, false)
		closest = minf(closest, Vector2(e.mover.position.x - mover.position.x, e.mover.position.z - mover.position.z).length())
	assert_float(closest).is_between(radius + Combat.PLAYER_RADIUS - Combat.CONTACT_INSIDE - 0.005, radius + Combat.PLAYER_RADIUS)
	assert_int(touched.size()).is_equal(1)   # it still lands
	# stepped aside during the wind-up: the lunge runs on along its band, past where the player stood
	var c2: Node3D = auto_free(Combat.new())
	add_child(c2)
	c2.sync_p0(_view(_run(_five([true, true, true, true, true]))), 5, mover)
	c2.grace = 0.0
	var e2: Dictionary = c2.enemies.values()[0]
	var start := mover.position + Vector3(0, 0, -2.0)
	(e2.mover as PlayerMover).position = start
	e2.node.position = start
	c2.step(0.016, mover, false)
	var aside := mover.position
	mover.position += Vector3(3, 0, 0)
	while str(e2.phase) in ["windup", "dash"]: c2.step(0.016, mover, false)
	assert_float((e2.mover.position as Vector3).z - start.z).is_greater(2.0)   # past where the player stood (stopped there: ~1.0)
	mover.position = aside
