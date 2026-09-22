extends GdUnitTestSuite

const Combat = preload("res://modules/mining/mine_combat.gd")
const Layout = preload("res://modules/mining/mine_layout.gd")
const Scene = preload("res://scenes/mine/mine.gd")

func _state(floor_number := 3) -> Dictionary:
	return {"inventory": {"produce": {}, "dishes": {}}, "journey": {"wood": 0, "materials": {}},
		"character": {"version": 1, "hp": 100, "buffs": []},
		"bag": {"version": 2, "sequence": 0, "capacity": 24, "slots": [], "overflow": [], "equipped": {"main_hand": {"id": "bag_1", "item_id": "rusty_sword", "quantity": 1}, "tool": null, "gloves": null}},
		"mine": {"version": 1, "run": 0, "floor": floor_number, "broken": {}, "cleared_floors": [], "elevator_unlocked": false,
			"combat": {"version": 1, "sequence": 0, "monsters": {"1": [], "2": [], "3": [38], "4": [38, 38, 38], "5": [150]}}}}

func _mover(empty := false) -> PlayerMover:
	var nav := Layout.navigation(3, Layout.rocks(3).map(func(rock): return rock.id) if empty else [])
	return PlayerMover.new(nav, BlueprintGrid.new(nav))

func _combat(state: Dictionary, mover: PlayerMover) -> Node3D:
	var fight := auto_free(Combat.new()) as Node3D
	add_child(fight)
	fight.sync(state, mover, "test")
	return fight

func test_floor_population_hp_and_spawn_navigation() -> void:
	for number in range(1, 6):
		var mover := _mover()
		var fight := _combat(_state(number), mover)
		assert_int(fight.enemies.size()).is_equal([0, 0, 1, 3, 1][number - 1])
		for enemy in fight.enemies.values():
			assert_bool(mover.bp.is_walkable(mover.bp.world_to_cell(enemy.node.position))).is_true()
			assert_float(enemy.node.position.distance_to(Layout.SPAWN)).is_greater_equal(3.0)
			assert_bool(mover.grid.point_path(Layout.SPAWN, enemy.node.position).is_empty()).is_false()
			assert_int(enemy.hp).is_equal(150 if number == 5 else 38)

func test_attack_arc_rejects_distant_and_rear_targets() -> void:
	assert_bool(Combat.within_swing(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -1.5), 1.65, 120)).is_true()
	assert_bool(Combat.within_swing(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -2), 1.65, 120)).is_false()
	assert_bool(Combat.within_swing(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, 1), 1.65, 120)).is_false()
	assert_bool(Combat.within_swing(Vector3.ZERO, Vector3.FORWARD, Vector3(1, 0, 0), 1.65, 120)).is_false()

func test_swing_uses_equipped_weapon_and_cooldown_without_locally_spending_hp() -> void:
	var state := _state()
	var mover := _mover(true)
	var fight := _combat(state, mover)
	var enemy: Dictionary = fight.enemies.slime_1
	enemy.mover.position = mover.position + Vector3(0, 0, -1.2)
	enemy.node.position = enemy.mover.position
	assert_array(fight.swing(state, mover)).is_equal(["slime_1"])
	assert_int(enemy.hp).is_equal(38)
	assert_array(fight.swing(state, mover)).is_empty()
	assert_str(enemy.phase).is_equal("stunned")
	for frame in 8: fight.step(0.1, mover, false)
	state.bag.equipped.main_hand = null
	assert_array(fight.swing(state, mover)).is_empty()

func test_rocks_block_attacks_and_knockback() -> void:
	var state := _state()
	var mover := _mover()
	var fight := _combat(state, mover)
	var rock: Vector3 = Layout.rocks(3)[0].position
	mover.position = rock + Vector3(-0.8, 0, 0)
	mover.facing = Vector3.RIGHT
	var enemy: Dictionary = fight.enemies.slime_1
	enemy.node.position = rock + Vector3(0.8, 0, 0)
	enemy.mover.position = enemy.node.position
	assert_array(fight.swing(state, mover)).is_empty()
	var before := mover.position
	fight._slide(mover, Vector3(2, 0, 0))
	assert_float(mover.position.x).is_less(rock.x)
	assert_float(before.distance_to(mover.position)).is_less(1.0)

func test_elite_keeps_windup_when_hit_and_resists_knockback() -> void:
	var state := _state(5)
	var mover := _mover(true)
	var fight := _combat(state, mover)
	var enemy: Dictionary = fight.enemies.slime_1
	enemy.mover.position = mover.position + Vector3(0, 0, -1.2)
	enemy.node.position = enemy.mover.position
	enemy.phase = "windup"
	enemy.timer = 0.4
	enemy.direction = Vector3.BACK
	var before: Vector3 = enemy.node.position
	assert_array(fight.swing(state, mover)).is_equal(["slime_1"])
	assert_str(enemy.phase).is_equal("windup")
	assert_float(enemy.timer).is_equal(0.4)
	assert_float(enemy.node.position.distance_to(before)).is_between(0.31, 0.32)
	assert_float(enemy.spec.hp).is_equal(300.0)
	assert_float(enemy.spec.move_speed).is_equal(2.8)
	fight.grace = 0
	for frame in 5: fight.step(0.1, mover, false)
	assert_str(enemy.phase).is_equal("dash")

func test_pause_freezes_ai_cooldowns_and_attack_windup() -> void:
	var mover := _mover(true)
	var fight := _combat(_state(), mover)
	var enemy: Dictionary = fight.enemies.slime_1
	enemy.node.position = mover.position + Vector3(0, 0, -1.1)
	enemy.mover.position = enemy.node.position
	fight.grace = 0
	fight.step(0.1, mover, false)
	assert_str(enemy.phase).is_equal("windup")
	var before := float(enemy.timer)
	fight.cooldown = 0.4
	for frame in 100: fight.step(0.1, mover, true)
	assert_float(enemy.timer).is_equal(before)
	assert_float(fight.cooldown).is_equal(0.4)

func test_windup_locks_direction_and_moving_aside_dodges_contact() -> void:
	var mover := _mover(true)
	var fight := _combat(_state(), mover)
	var hits: Array = []
	fight.contact.connect(func(id): hits.append(id))
	var enemy: Dictionary = fight.enemies.slime_1
	enemy.node.position = mover.position + Vector3(0, 0, -1.1)
	enemy.mover.position = enemy.node.position
	fight.grace = 0
	fight.step(0.01, mover, false)
	assert_str(enemy.phase).is_equal("windup")
	var direction: Vector3 = enemy.direction
	mover.position += Vector3(1.8, 0, 0)
	for frame in 12: fight.step(0.1, mover, false)
	assert_vector(enemy.direction).is_equal(direction)
	assert_array(hits).is_empty()

func test_contact_has_global_invulnerability_and_only_one_hit_per_dash() -> void:
	var mover := _mover(true)
	var fight := _combat(_state(4), mover)
	var hits: Array = []
	fight.contact.connect(func(id): hits.append(id))
	fight.grace = 0
	for enemy in fight.enemies.values():
		enemy.node.position = mover.position
		enemy.mover.position = mover.position
		enemy.phase = "dash"
		enemy.timer = 0.5
		enemy.direction = Vector3.ZERO
	for frame in 3: fight.step(0.1, mover, false)
	assert_int(hits.size()).is_equal(1)

func test_saved_damage_and_defeat_survive_rock_rebuilds_without_resetting_ai() -> void:
	var state := _state()
	var mover := _mover(true)
	var fight := _combat(state, mover)
	var enemy: Dictionary = fight.enemies.slime_1
	enemy.phase = "windup"
	state.mine.combat.monsters["3"] = [24]
	fight.sync(state, mover, "test")
	assert_str(enemy.phase).is_equal("windup")
	assert_int(enemy.hp).is_equal(24)
	state.mine.combat.monsters["3"] = [0]
	fight.sync(state, mover, "test")
	assert_int(fight.enemies.size()).is_equal(0)
	fight.sync(JSON.parse_string(JSON.stringify(state)), mover, "test")
	assert_int(fight.enemies.size()).is_equal(0)

func test_scene_attack_cancels_dig_and_freezes_when_command_is_unconfirmed() -> void:
	var state := _state()
	state.mine.broken["3"] = Layout.rocks(3).map(func(rock): return rock.id)
	var transport := FakeTransport.new([{"status": 504, "json": {}}])
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.farm_id = "combat-test"
	session.state = state
	var mine := auto_free(Scene.new()) as Node3D
	mine.setup({"session": session})
	add_child(mine)
	for frame in 3: await get_tree().process_frame
	mine.set_process(false)
	var enemy: Dictionary = mine.combat.enemies.slime_1
	enemy.node.position = mine.mover.position + Vector3(0, 0, -1)
	enemy.mover.position = enemy.node.position
	mine._dig_target = "rock_1"
	mine._attack()
	for frame in 3: await get_tree().process_frame
	assert_str(mine._dig_target).is_empty()
	assert_str(transport.last_body().type).is_equal("mine_combat")
	assert_bool(session.has_unconfirmed_command()).is_true()
	var before: Vector3 = enemy.node.position
	mine._process(1.0)
	assert_vector(enemy.node.position).is_equal(before)
	assert_bool(mine.attack.disabled).is_true()
	assert_int(state.character.hp).is_equal(100)

func test_saving_keeps_the_attack_button_enabled_for_a_held_swing() -> void:
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", FakeTransport.new([]).callable()))
	session.farm_id = "combat-test"
	session.state = _state()
	var mine := auto_free(Scene.new()) as Node3D
	mine.setup({"session": session})
	add_child(mine)
	for frame in 3: await get_tree().process_frame
	mine.set_process(false)
	mine.busy = true
	mine._attack_held = true
	mine._refresh()
	assert_bool(mine.attack.disabled).is_false()
	assert_bool(mine._attack_held).is_true()
	mine.busy = false
	mine.pause_button.button_pressed = true
	assert_bool(mine.attack.disabled).is_true()
	assert_bool(mine._attack_held).is_false()
