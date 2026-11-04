extends GdUnitTestSuite
## SGODOT-288 on the 355 b1 mine: Combat's key, the HP bar, and the monsters built from the view (view.mine.at); the
## slash, the swing and the lunge as they were; a monster down on mob_down; the knock-out moment.

const Fx := preload("res://tests/p0/fixtures/mine_b1_view.gd")

static func _slime(hp := 9) -> Dictionary: return Fx.mob("mob_slime", hp, 9)
static func _elite(hp := 36) -> Dictionary: return Fx.mob("mob_elite_slime", hp, 36, true)

## The floors these tests fight on: Floor 3 one slime, Floor 4 three, Floor 5 the elite alone with no rocks.
func _v(n: int) -> Dictionary:
	match n:
		3: return Fx.view(3, {"mobs": [_slime()], "rocks": 6})
		4: return Fx.view(4, {"mobs": [_slime(), _slime(), _slime()], "rocks": 6})
		5: return Fx.view(5, {"mobs": [_elite()], "rocks": 0})
	return Fx.view(n, {"mobs": [], "rocks": 6})

func test_attack_is_free_and_carries_the_sword() -> void:
	var k := P0MaterialLogic.combat_action(_v(3), {"floor": 3})
	assert_str(str(k.verb)).is_equal("Attack")
	assert_str(str(k.sub)).is_empty()
	assert_str(str(k.tool)).is_equal("sword")
	assert_that(k.cmd).is_equal({"type": "mine_swing", "floor": 3})

func test_a_floor_without_rocks_has_nothing_to_mine() -> void:
	var k := P0MaterialLogic.mine_action(_v(5), {"floor": 5, "target": ""})
	assert_str("%s · %s" % [k.verb, k.sub]).is_equal("Mine · No rocks here")
	assert_bool(bool(k.enabled)).is_false()

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
	c.sync_p0(_v(4), 4, mover)
	assert_int(c.enemies.size()).is_equal(3)
	var first: Vector3 = c.enemies["slime_1"].node.position
	c.sync_p0(Fx.view(4, {"mobs": [_slime(0), _slime(), _slime()], "rocks": 6}), 4, mover)
	assert_int(c.enemies.size()).is_equal(2)
	assert_bool(c.enemies.has("slime_1")).is_false()
	assert_vector(c.fallen_at(0)).is_equal(first)   # where its drop would lie (v4q(5) ⑫)
	c.sync_p0(_v(5), 5, mover)   # a new floor: the elite alone
	assert_int(c.enemies.size()).is_equal(1)
	assert_dict(c.fallen).is_empty()
	assert_int(c.weapon({}).damage).is_equal(3)
	# the same floor on a new day is a new floor (contract-efg §5 ⑩): its monsters spawned again
	c.sync_p0(Fx.view(5, {"mobs": [_elite(10)], "rocks": 0}), 5, mover)
	assert_int(int(c.enemies.values()[0].hp)).is_equal(10)
	c.grace = 0.0
	c.sync_p0(Fx.view(5, {"mobs": [_elite()], "rocks": 0, "day": "2026-11-03"}), 5, mover)
	assert_float(c.grace).is_equal(c.LANDING_GRACE_S)
	assert_int(int(c.enemies.values()[0].hp)).is_equal(36)

## A guard's HP is its HUD card (E5); every other monster, elites too, wears the Mob bar over its head once hit.
func test_a_guard_has_no_head_bar() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	c.sync_p0(Fx.view(5, {"mobs": [_elite()], "rocks": 0}), 5, mover)
	c.sync_p0(Fx.view(5, {"mobs": [_elite(30)], "rocks": 0}), 5, mover)
	assert_bool((c.enemies.values()[0].node.get_node("HealthFill") as Node3D).visible).is_true()
	var king := func(hp: int) -> Dictionary: return Fx.view(20, {"mobs": [Fx.mob("boss_slime_king_iron", hp, 160, false, true, 2)], "rocks": 0})
	c.sync_p0(king.call(160), 20, mover)
	c.sync_p0(king.call(150), 20, mover)
	assert_bool((c.enemies.values()[0].node.get_node("HealthFill") as Node3D).visible).is_false()

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
	var v := _v(4)
	v.mine["weapon"] = {"attack": 3, "speed": 2.0}
	c.sync_p0(v, 4, mover)
	assert_float(1.0 / float(c.weapon({}).speed)).is_equal_approx(0.5 + Combat.TEMPO_MARGIN_S, 0.0001)

# ---- landing on a floor with monsters (李元芳 R5 on SGODOT-288)

## Express straight to Floor 5 met the elite with the key on `Mine · No rocks here`: a floor with a monster up lands on
## Combat; a cleared one on Mining.
func test_a_floor_with_monsters_up_lands_on_combat() -> void:
	assert_str(P0MaterialLogic.landing_mode(_v(5), 5)).is_equal("combat")
	assert_str(P0MaterialLogic.landing_mode(_v(3), 3)).is_equal("combat")
	assert_str(P0MaterialLogic.landing_mode(_v(2), 2)).is_equal("mine")
	assert_str(P0MaterialLogic.landing_mode(Fx.view(3, {"mobs": [_slime(0)]}), 3)).is_equal("mine")
	assert_int(P0MaterialLogic.mobs_up(_v(4), 4)).is_equal(3)
	assert_str(P0MaterialLogic.landing_mode(_v(5), 6)).is_equal("mine")   # not on that floor: nothing to fight

## The monsters hold still 2 s on arrival (the old mine's grace was 1.5 s).
func test_monsters_hold_still_on_arrival() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	mover.position = load("res://modules/mining/mine_layout.gd").SPAWN
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	c.sync_p0(_v(5), 5, mover)
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
	c.sync_p0(_v(5), 5, mover)
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

## Every way onto a floor with a monster up — Enter mine (_ready), the stairs, the elevator, a new day (_go_floor) —
## lands on Attack with the monsters held still: both come from the floor's view, not the way in (李元芳 R5 retest on
## SGODOT-288). The scene's own _ready / _go_floor call landing_mode and sync_p0 sets the grace.
func test_every_way_onto_a_floor_lands_alike() -> void:
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
	var v := _v(5)
	c.sync_p0(v, 5, mover)   # a fresh mine scene's first frame
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
	c.sync_p0(_v(5), 5, mover)
	c.grace = 0.0
	var e: Dictionary = c.enemies.values()[0]
	mover.position = load("res://modules/mining/mine_layout.gd").SPAWN
	(e.mover as PlayerMover).position = mover.position + Vector3(1.4, 0, -1.4)   # diagonal to the player, inside the room
	e.node.position = e.mover.position
	c.step(0.016, mover, false)
	assert_str(str(e.phase)).is_equal("windup")
	var want: Vector3 = (mover.position - (e.node as Node3D).position).normalized()
	assert_vector(e.node.get_node("Band").global_transform.basis.z.normalized()).is_equal_approx(want, Vector3(0.02, 0.02, 0.02))

## A monster the server reports down (mob_down, 李元芳 B6 on 283 86d07bd5): it goes down at once — its last number rises
## and it is gone — whatever the reply's view still says.
func test_a_monster_goes_down_on_mob_down() -> void:
	var Combat = load("res://modules/mining/p0_mine_combat.gd")
	var bp := Layout_bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	c.sync_p0(Fx.view(5, {"mobs": [_elite(3)], "rocks": 0}), 5, mover)
	var node: Node3D = c.enemies.values()[0].node
	c.down(0)
	assert_bool(node.visible).is_false()
	assert_bool(c.fallen.has(0)).is_true()
	assert_array(c._numbers.map(func(n): return n.label.text)).is_equal(["3"])
	var y: float = c._numbers[0].label.position.y
	c.fade(0.1)
	assert_float(c._numbers[0].label.position.y).is_greater(y)
	for i in 8: c.fade(0.1)
	assert_array(c._numbers).is_empty()
	c.down(0)   # it is down already: nothing more
	assert_array(c._numbers).is_empty()
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_mine.gd")
	assert_str(src.substr(src.find("\"mob_down\":", src.find("func _on_state(")), 120)).contains("combat.down(")

## Knocked out (不知火舞 on 288 78d0f863): the server refills HP at once, but the moment keeps the bar at 0 %, the monsters
## still and no new hit sent until the player is out.
func test_the_knock_out_moment_holds_the_fight_at_zero() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_mine.gd")
	var fight := src.substr(src.find("func _fight("), 900)
	assert_str(fight).contains("rt.ui.has_modal() or _ko)")
	assert_str(fight).contains("0 if _ko else")
	var contact := src.substr(src.find("func _on_contact("), 300)
	assert_str(contact).contains("or _ko: return")
	assert_str(src.substr(src.find("func _swing()"), 160)).contains("or _ko:")

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
	mine._hold_sword("weapon_wooden_sword")
	assert_object(mine._sword.get_parent()).is_same(mine.actor)
	assert_bool(mine.sword_shown()).is_false()          # between swings
	mine._swing()
	mine._hold_sword("weapon_wooden_sword")
	assert_bool(mine.actor.attacking()).is_true()
	assert_bool(mine.sword_shown()).is_true()           # B (不知火舞 on 291): in hand from the wind-up
	var sk: Skeleton3D = mine.actor.rig.skeleton
	if sk and sk.find_bone(mine.HAND_BONE) >= 0:         # on the hand: its grip within a hand's length of the wrist
		var wrist: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(mine.HAND_BONE))).origin
		var grip: Vector3 = mine._sword.global_transform * Vector3(0, mine.SWORD_GRIP_Y, 0)
		assert_float(grip.distance_to(wrist)).is_less(0.15)
	mine.actor._attack_left = 0.0                       # the clip is over
	mine._hold_sword("weapon_wooden_sword")
	assert_bool(mine.sword_shown()).is_false()
	mine._hold_sword("")                                # no weapon: no sword
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
	c.sync_p0(_v(4), 4, mover)
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
	c.sync_p0(_v(5), 5, mover)
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
	c.sync_p0(_v(5), 5, mover)
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
	c2.sync_p0(_v(5), 5, mover)
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

## 李元芳's first F1 on preview A (232 34d109f4, 蒙恬's event log): Attack held down swung once at the touch-down and then
## stood there — ten hurts in 20 s, not one swing reached the server. Held, it keeps swinging as the weapon's tempo
## allows, as Mine keeps digging; let go, it stops.
func test_attack_held_keeps_swinging_until_let_go() -> void:
	P0Runtime.free_instance_for_tests()
	var rt := P0Runtime.ensure()
	rt.ui.quick_store = "user://test_p0_mine_deep_hold.json"
	rt.session.transport = func(_m, _p, _b, _c): pass
	var sent: Array = []
	rt.session.sent.connect(func(cmd): sent.append(cmd))
	await get_tree().process_frame
	rt.session.view = _v(4)
	var mine = load("res://scenes/p0/p0_mine.tscn").instantiate()
	mine.setup({"mine": Fx.MINE, "floor": 4})
	add_child(mine)
	for i in 3: await get_tree().process_frame
	assert_str(rt.ui.bar_mode).is_equal("combat")
	var slime: Dictionary = mine.combat.enemies.values()[0]
	mine.actor.teleport(slime.node.position + Vector3(0.9, 0, 0))   # right beside it, in reach
	await get_tree().process_frame
	var swings := [0]   # a swing sets the weapon's whole tempo (0.55 s): the cooldown jumping up counts one
	var held := func(seconds: float) -> void:
		var end := Time.get_ticks_msec() + int(seconds * 1000.0)
		var was := 0.0
		while Time.get_ticks_msec() < end:
			rt.session.busy = false   # no server here: each swing's command settles at once
			if mine.combat.cooldown > was + 0.3: swings[0] += 1
			was = mine.combat.cooldown
			await get_tree().process_frame
	rt.ui.fab_held = true
	rt.ui._fab_pressed()   # the touch-down: one swing
	await held.call(1.5)
	assert_int(swings[0]).is_greater_equal(2)   # and more while it is held (about one each 0.55 s)
	assert_int(sent.filter(func(c): return str(c.get("type", "")) == "mine_attack" and c.has("targets")).size()).is_greater_equal(2)
	rt.ui.fab_held = false
	var after: int = swings[0]
	await held.call(0.8)
	assert_int(swings[0]).is_equal(after)   # let go: no more
	mine.queue_free()
	P0Runtime.free_instance_for_tests()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_p0_mine_deep_hold.json"))
	await get_tree().process_frame
