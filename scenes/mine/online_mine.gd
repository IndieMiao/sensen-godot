extends "res://scenes/mine/mine.gd"

var online: OnlineSpace
var _attack_pending := false
var _online_join: Dictionary = {}
var _connection_feedback := ""

func setup(args: Dictionary) -> void:
	super.setup(args)
	_online_join = args.get("online_join", {})

func _ready() -> void:
	super._ready()
	remove_child(combat)
	combat.queue_free()
	combat = preload("res://modules/mining/online_combat.gd").new()
	combat.name = "OnlineCombat"
	add_child(combat)
	online = OnlineSpace.attach(self, session, "mine", _online_join, func(): return mover, func(): return _anim,
		func(): return not _paused and _focused and not busy and not (bag_sheet and bag_sheet.visible))
	online.world_changed.connect(func(_world): _refresh())
	online.enemies_changed.connect(func(monsters): combat.apply_monsters(monsters))
	online.connection_changed.connect(_refresh)
	online.rescued.connect(_online_rescued)
	pause_button.tooltip_text = L10n.text("Pause your movement; the shared mine keeps running")
	_refresh()

func mine_state() -> Dictionary:
	if online == null or online.world.is_empty(): return {"floor": 0, "run": 0}
	var data := online.world
	var mined := {}
	var health := {}
	for id in data.get("floors", {}):
		mined[id] = data.floors[id].broken
		health[id] = data.floors[id].hp
	return {"version": 1, "run": int(data.get("run", 0)), "floor": 0 if _rescued else online.floor_number,
		"broken": mined, "cleared_floors": data.get("cleared", []),
		"elevator_unlocked": bool(data.get("elevator", false)) or bool(session.state.get("mine", {}).get("elevator_unlocked", false)),
		"combat": {"monsters": health, "sequence": 0}}

func _display_state() -> Dictionary:
	var state := session.state.duplicate(true) if session else {}
	state.mine = mine_state()
	if online and not online.self_state.is_empty():
		if not state.has("character"): state.character = {"version": 1, "buffs": []}
		state.character.hp = int(online.self_state.hp)
	return state

func _floor_spawn() -> Vector3:
	# joined/floor selects a collision-free seat before world rebuilds the scene.
	if online and online._arrival_pending: return online._arrival_position
	return super._floor_spawn()

func _camera_context_key() -> String:
	var key := super._camera_context_key()
	return online.room + ":" + key if online and not online.world.is_empty() and not key.is_empty() else ""

func _floor_navigation(number: int, run: int, farm_id: String) -> FarmBlueprint:
	if online == null or online.world.is_empty(): return super._floor_navigation(number, run, farm_id)
	var nav: Dictionary = online.world.navigation
	var bp := FarmBlueprint.new()
	bp.cell_m = float(nav.cell)
	bp.grid = Vector2i(str(nav.rows[0]).length(), nav.rows.size())
	bp.masks = {"walkable": nav.rows}
	bp.anchors = {"spawn": bp.world_to_cell(Vector3(float(nav.spawn[0]), 0, float(nav.spawn[1])))}
	return bp

func _floor_rocks(number: int, run: int, farm_id: String) -> Array:
	if online == null or online.world.is_empty(): return super._floor_rocks(number, run, farm_id)
	var rocks: Array = []
	for rock in online.world.get("rocks", []):
		rocks.append({"id": str(rock.id), "position": Vector3(float(rock.position[0]), 0, float(rock.position[1]))})
	return rocks

func _refresh() -> void:
	super._refresh()
	if ui == null: return
	restart.hide()
	if online:
		if online.joined:
			if not _connection_feedback.is_empty() and feedback.text == _connection_feedback: feedback.text = ""
			_connection_feedback = ""
			title.text = L10n.format_text("Mine - floor %d / 5", current_floor()) + " · " + online.room.trim_prefix("mine:").substr(0, 6)
		elif not online.error.is_empty():
			_connection_feedback = OnlineSpace.error_text(online.error)
			feedback.text = _connection_feedback

func _process(delta: float) -> void:
	if online and (online.travel_busy or is_instance_valid(online.panel)):
		combat.step(delta, mover, true)
		_update_camera()
		return
	super._process(delta)
	if online and not online.self_state.is_empty():
		health_bar.value = int(online.self_state.hp)
		health_label.text = "%d / %d" % [int(online.self_state.hp), int(online.self_state.max_hp)]

func _enter() -> void:
	if online: online.start()

func _arrived(id: String) -> void:
	if id.begins_with("rock_"):
		_mine_rock(id)
	else: super._arrived(id)

func _mine_rock(id: String) -> void:
	if online == null or busy: return
	busy = true
	mover.stop()
	_play("labour_drain")
	_refresh()
	var ok := await online.act("dig", id)
	busy = false
	if not is_inside_tree(): return
	feedback.text = L10n.text("Resources saved to your bag") if ok else OnlineSpace.error_text(online.error)
	_refresh()

func _command(type: String, _payload_data: Dictionary) -> bool:
	if online == null or not online.joined or busy: return false
	var action := str({"descend_mine": "down", "ascend_mine": "up", "use_mine_elevator": "elevator"}.get(type, ""))
	if action.is_empty(): return false
	busy = true
	mover.stop()
	var ok := await online.act(action)
	busy = false
	if not is_inside_tree(): return ok
	feedback.text = "" if ok else OnlineSpace.error_text(online.error)
	_refresh()
	return ok

func _attack(target_id := "") -> void:
	if _attack_pending or not _can_act() or online == null or not online.joined or combat.cooldown > 0: return
	if bag_sheet and bag_sheet.visible: return
	if combat.weapon(session.state).is_empty():
		feedback.text = L10n.text("Equip a weapon first")
		return
	_cancel_dig()
	combat.swing(session.state, mover, target_id)
	_sync_weapon_visibility()
	player.look_at(player.position + mover.facing, Vector3.UP)
	_attack_pending = true
	await online.act("attack")
	_attack_pending = false

func _resolve_combat(_hit: Array) -> void:
	pass

func _connection_blocked() -> bool:
	return online == null or not online.joined or online.world.is_empty()

func _has_combat_pending() -> bool:
	return false

func _combat_stalled() -> bool:
	return false

func _predicted_defeat() -> bool:
	return _rescued

func _recover() -> void:
	if online:
		online.stop()
		online.start()

func _leave() -> void:
	if online and online.consume_back(): return
	if bag_sheet and bag_sheet.visible:
		bag_sheet.close()
		return
	if _leaving: return
	_leaving = true
	if online: online.stop()
	if mover: mover.stop()
	AppRouter.pop_instance()

func _online_rescued() -> void:
	_rescued = true
	busy = false
	if online: online.stop()
	await session.refresh()
	if is_inside_tree(): _schedule_rescue()

func _restart() -> void:
	pass

func suspend() -> void:
	if online: online.suspend()
	super.suspend()

func resume() -> void:
	super.resume()
	if online: online.resume()

func is_back_navigation_locked() -> bool:
	if online and online.consume_back(): return true
	return super.is_back_navigation_locked()

func party_travel_ready() -> bool:
	return not busy and not _attack_pending and not _has_combat_pending()

func _input(event: InputEvent) -> void:
	if online and (online.travel_busy or is_instance_valid(online.panel)): return
	super._input(event)

func _unhandled_input(event: InputEvent) -> void:
	if online and (online.travel_busy or is_instance_valid(online.panel)): return
	super._unhandled_input(event)
