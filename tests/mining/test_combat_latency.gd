extends GdUnitTestSuite

const Scene = preload("res://scenes/mine/mine.gd")
const Layout = preload("res://modules/mining/mine_layout.gd")
const Predictor = preload("res://modules/mining/combat_predictor.gd")

class DelayedTransport extends RefCounted:
	signal response_ready(response: Dictionary)
	var requests: Array[Dictionary] = []
	func transport() -> Callable:
		return func(method, _url, _headers, body):
			requests.append({"method": method, "body": JSON.parse_string(body) if not body.is_empty() else {}})
			var response: Dictionary = await response_ready
			return ApiClient.Response.new(true, int(response.get("status", 200)), response.get("json", {}))

func _state() -> Dictionary:
	return {"cells": {}, "beds_unlocked": 3, "wallet": 180, "tools": {"row_tool": false},
		"inventory": {"seeds": {}, "produce": {}, "dishes": {}}, "clock": {"chapter_index": 0, "field_condition": "sunny"},
		"xp": {"total": 0}, "chapters": [{"status": "active", "step_flags": {}}],
		"journey": {"version": 1, "facts": [], "unlocks": [], "completed": [], "wood": 0, "materials": {}, "exploration": {"round": 0, "collected": []}, "opportunities": {}},
		"character": {"version": 1, "hp": 100, "buffs": []},
		"bag": {"version": 2, "sequence": 0, "capacity": 24, "slots": [], "overflow": [], "equipped": {"main_hand": {"id": "bag_1", "item_id": "rusty_sword", "quantity": 1}, "tool": null, "gloves": null}},
		"mine": {"version": 1, "run": 0, "floor": 3, "broken": {"3": Layout.rocks(3).map(func(rock): return rock.id)}, "cleared_floors": [1, 2], "elevator_unlocked": false,
			"combat": {"version": 1, "sequence": 0, "monsters": {"1": [], "2": [], "3": [38], "4": [38, 38, 38], "5": [150]}}}}

func _session(transport: DelayedTransport) -> FarmSession:
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.transport()))
	session.farm_id = "latency-test"
	session.state = _state()
	session.version = 0
	return session

func _scene(session: FarmSession) -> Node3D:
	var mine := auto_free(Scene.new()) as Node3D
	mine.setup({"session": session})
	add_child(mine)
	for frame in 3: await get_tree().process_frame
	mine.set_process(false)
	mine.combat.grace = 0
	_near(mine)
	return mine

func _near(mine: Node3D) -> void:
	var enemy: Dictionary = mine.combat.enemies.slime_1
	enemy.node.position = mine.mover.position + Vector3(0, 0, -1.1)
	enemy.mover.position = enemy.node.position

func _reply(transport: DelayedTransport, state: Dictionary, version := 1) -> void:
	transport.response_ready.emit({"json": {"state": state, "version": version}})

func _result(hp: int, enemy_hp: int, sequence: int, rescued := false) -> Dictionary:
	var state := _state()
	state.character.hp = hp
	state.mine.combat.monsters["3"] = [enemy_hp]
	state.mine.combat.sequence = sequence
	state.mine.combat.last_result = {"hurt": 0, "damage": 14, "materials": {}, "rescued": rescued}
	if rescued: state.mine.floor = 0
	return state

func after_test() -> void:
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame

func test_latency_keeps_movement_ai_and_feedback_running_before_confirmation() -> void:
	var transport := DelayedTransport.new()
	var session := _session(transport)
	var mine := await _scene(session)
	mine._attack()
	assert_bool(mine._combat_sending).is_true()
	assert_int(session.state.mine.combat.monsters["3"][0]).is_equal(38)
	assert_int(mine.combat.enemies.slime_1.hp).is_equal(24)
	assert_bool(mine.busy).is_false()
	assert_bool(mine.attack.disabled).is_false()
	var before: Vector3 = mine.mover.position
	mine.stick.vector = Vector2.RIGHT
	for frame in 12: mine._process(0.05)
	assert_float(mine.mover.position.distance_to(before)).is_greater(1.0)
	assert_float(mine.combat.cooldown).is_zero()
	assert_float(mine.combat._swing_left).is_zero()
	assert_str(mine.combat.enemies.slime_1.phase).is_not_equal("stunned")
	_reply(transport, _result(100, 24, 1))
	assert_bool(mine._combat_draining).is_false()
	assert_int(mine.combat.enemies.slime_1.hp).is_equal(24)
	assert_int(session.state.mine.combat.sequence).is_equal(1)

func test_multiple_predicted_hits_settle_in_order_without_double_damage() -> void:
	var transport := DelayedTransport.new()
	var session := _session(transport)
	var mine := await _scene(session)
	mine._attack()
	mine.combat.cooldown = 0
	_near(mine)
	mine._attack()
	assert_int(transport.requests.size()).is_equal(1)
	assert_int(mine.prediction.pending.size()).is_equal(2)
	assert_int(mine.combat.enemies.slime_1.hp).is_equal(10)
	_reply(transport, _result(100, 24, 1))
	assert_int(mine.combat.enemies.slime_1.hp).is_equal(10)
	var deadline := Time.get_ticks_msec() + 2000
	while transport.requests.size() < 2 and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(2)
	assert_int(int(transport.requests[1].body.payload.sequence)).is_equal(1)
	_reply(transport, _result(100, 10, 2), 2)
	assert_int(mine.prediction.pending.size()).is_zero()
	assert_int(mine.combat.enemies.slime_1.hp).is_equal(10)
	assert_int(session.state.mine.combat.monsters["3"][0]).is_equal(10)

func test_uncertain_reply_restores_predicted_kill_and_keeps_one_journal_request() -> void:
	var transport := DelayedTransport.new()
	var session := _session(transport)
	session.state.mine.combat.monsters["3"] = [10]
	var mine := await _scene(session)
	mine._attack()
	assert_int(mine.combat.enemies.size()).is_zero()
	transport.response_ready.emit({"status": 504})
	assert_int(mine.combat.enemies.size()).is_equal(1)
	assert_int(mine.combat.enemies.slime_1.hp).is_equal(10)
	assert_bool(session.has_unconfirmed_command()).is_true()
	assert_int(mine.prediction.pending.size()).is_zero()
	assert_int(session.state.mine.combat.monsters["3"][0]).is_equal(10)

func test_pending_hurt_is_visible_now_and_is_not_applied_again_on_ack() -> void:
	var transport := DelayedTransport.new()
	var session := _session(transport)
	var mine := await _scene(session)
	mine._pending_hurt = "slime_1"
	mine._resolve_combat([])
	assert_float(mine.health_bar.value).is_equal(90.0)
	assert_int(session.state.character.hp).is_equal(100)
	var point: Vector3 = mine.mover.position
	_reply(transport, _result(90, 38, 1))
	assert_float(mine.health_bar.value).is_equal(90.0)
	assert_vector(mine.mover.position).is_equal(point)

func test_departure_waits_for_pending_settlement_then_returns_once() -> void:
	var transport := DelayedTransport.new()
	var session := _session(transport)
	var underneath := AppRouter.push_instance("res://tests/fixtures/scenes/stack_probe.tscn")
	var mine := AppRouter.push_instance(AppRouter.MINE, {"session": session})
	await get_tree().process_frame
	mine.set_process(false)
	_near(mine)
	mine._attack()
	mine._leave()
	assert_bool(mine._exit_after_combat).is_true()
	assert_object(AppRouter.top_instance()).is_equal(mine)
	_reply(transport, _result(100, 24, 1))
	await get_tree().process_frame
	assert_str(transport.requests[-1].body.type).is_equal("leave_mine")
	var outside := _result(100, 24, 1)
	outside.mine.floor = 0
	_reply(transport, outside, 2)
	await get_tree().process_frame
	assert_object(AppRouter.top_instance()).is_equal(underneath)

func test_confirmed_defeat_automatically_returns_to_farm_and_opens_rest() -> void:
	var transport := DelayedTransport.new()
	var session := _session(transport)
	session.state.character.hp = 5
	var farm := AppRouter.push_instance(AppRouter.FARM, {"session": session,
		"blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2))})
	await get_tree().process_frame
	var mine := AppRouter.push_instance(AppRouter.MINE, {"session": session})
	await get_tree().process_frame
	mine.set_process(false)
	mine._pending_hurt = "slime_1"
	mine._resolve_combat([])
	assert_bool(mine._predicted_defeat()).is_true()
	assert_object(AppRouter.top_instance()).is_equal(mine)
	_reply(transport, _result(1, 38, 1, true))
	for frame in 4: await get_tree().process_frame
	assert_object(AppRouter.top_instance()).is_equal(farm)
	assert_bool(farm.hud.modal_open()).is_true()
	assert_str(farm.life_sheet.active.page).is_equal("character")
	assert_bool(farm.life_sheet.find_child("RestCharacter", true, false).disabled).is_false()
	assert_int(transport.requests.size()).is_equal(1)

func test_prediction_never_grants_items_and_obeys_elite_defense_and_lethal_priority() -> void:
	var predictor := Predictor.new()
	var state := _state()
	state.mine.floor = 5
	state.mine.combat.monsters["5"] = [10]
	state.character.hp = 5
	var original := state.duplicate(true)
	predictor.pending.append({"run": 0, "floor": 5, "targets": ["slime_1"], "hurt_by": "slime_1"})
	var view := predictor.view(state)
	assert_int(view.mine.combat.monsters["5"][0]).is_zero()
	assert_int(view.character.hp).is_equal(5)
	assert_that(view.bag).is_equal(original.bag)
	assert_that(view.journey).is_equal(original.journey)
	assert_that(state).is_equal(original)
	state.mine.combat.monsters["5"] = [150]
	view = predictor.view(state)
	assert_int(view.mine.combat.monsters["5"][0]).is_equal(139)
	assert_int(view.character.hp).is_zero()

func test_legacy_clearance_does_not_spawn_monsters_in_the_prediction_view() -> void:
	var state := _state()
	state.mine.erase("combat")
	state.mine.cleared_floors = [1, 2, 3]
	var predictor := Predictor.new()
	assert_that(predictor.view(state).mine.combat.monsters["3"]).is_equal([0])
	state.mine.cleared_floors = [1, 2]
	predictor.pending.append({"run": 0, "floor": 3, "targets": ["slime_1"]})
	assert_that(predictor.payload(state).targets).is_equal(["slime_1"])
	assert_that(predictor.view(state).mine.combat.monsters["3"]).is_equal([24])

func test_long_network_stall_freezes_then_recovers_without_replaying_visual_damage() -> void:
	var transport := DelayedTransport.new()
	var session := _session(transport)
	var mine := await _scene(session)
	mine._attack()
	mine.prediction.pending[0].created_ms = Time.get_ticks_msec() - 3000
	mine.stick.vector = Vector2.RIGHT
	var position: Vector3 = mine.mover.position
	mine._process(0.1)
	assert_vector(mine.mover.position).is_equal(position)
	assert_bool(mine._combat_stalled()).is_true()
	_reply(transport, _result(100, 24, 1))
	mine._process(0.1)
	assert_bool(mine._combat_stalled()).is_false()
	assert_float(mine.mover.position.distance_to(position)).is_greater(0.2)
