extends GdUnitTestSuite

func test_farm_badges_follow_delayed_safe_area_layout_and_later_insets() -> void:
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = Vector2i(360, 780)
	add_child(viewport)
	var host := Node3D.new()
	viewport.add_child(host)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	host.add_child(hud)
	var safe := SafeAreaMargin.new()
	safe.name = "SafeArea"
	hud.add_child(safe)
	var root := Control.new()
	root.name = "Root"
	safe.add_child(root)
	var online := OnlineSpace.attach(host, null, "farm", {}, Callable(), Callable())
	online.set_process(false)
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
	assert_bool(bounds.encloses(online.badge.get_global_rect())).is_true()
	# Reproduce CanvasLayer children entering before the safe-area container settles.
	safe.set_deferred("size", Vector2(360, 780))
	for frame in 4: await get_tree().process_frame
	assert_bool(online.badge.visible).is_true()
	assert_bool(root.get_global_rect().encloses(online.badge.get_global_rect())).is_true()
	assert_float(online.badge.get_global_rect().end.x).is_equal_approx(root.get_global_rect().end.x, 0.01)
	safe.apply_margins(Rect2i(24, 52, 312, 684), Vector2i(360, 780), Vector2(360, 780))
	for frame in 4: await get_tree().process_frame
	assert_bool(root.get_global_rect().encloses(online.badge.get_global_rect())).is_true()
	assert_bool(root.get_global_rect().encloses(online._voice_badge.get_global_rect())).is_true()
	assert_float(online.badge.position.y).is_equal_approx(root.global_position.y + 56, 0.01)
	assert_float(online.badge.get_global_rect().end.x).is_equal_approx(root.get_global_rect().end.x, 0.01)

func _online(space_kind := "mine") -> OnlineSpace:
	var host := Node3D.new()
	add_child(auto_free(host))
	var bp := FarmBlueprint.new()
	bp.grid = Vector2i(10, 10)
	bp.cell_m = .5
	bp.masks = {"walkable": []}
	for index in 10: bp.masks.walkable.append("1111111111")
	bp.anchors = {"spawn": Vector2i(1, 1)}
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	var online := OnlineSpace.attach(host, null, space_kind, {}, func(): return mover, func(): return "idle")
	online.epoch = 2
	online.self_id = 1
	return online

func _frame(epoch: int, tick: int, hp: int) -> PackedByteArray:
	var packet := PackedByteArray()
	packet.resize(38)
	packet.encode_u16(0, 1)
	packet.encode_u32(2, tick)
	packet.encode_u32(6, epoch)
	packet.encode_u16(10, 1)
	packet.encode_u16(12, 1)
	packet.encode_float(14, .75)
	packet.encode_float(18, -.75)
	packet.encode_u16(26, hp)
	packet.encode_u16(28, 100)
	return packet

func test_old_floor_and_old_tick_cannot_replace_character_state() -> void:
	var online := _online()
	online._frame(_frame(2, 20, 70))
	assert_int(online.self_state.hp).is_equal(70)
	online._frame(_frame(1, 22, 100))
	online._frame(_frame(2, 18, 100))
	assert_int(online.self_state.hp).is_equal(70)
	online._frame(_frame(2, 22, 60))
	assert_int(online.self_state.hp).is_equal(60)

func test_floor_transition_keeps_the_in_flight_stair_acknowledgement() -> void:
	var online := _online()
	online._pending[8] = null
	online._message({"t": "floor", "epoch": 3, "floor": 4, "spawn": [4.75, -.75]})
	online._message({"t": "result", "seq": 8, "ok": true})
	assert_bool(online._pending[8].ok).is_true()
	assert_int(online.floor_number).is_equal(4)

func test_crowd_keeps_299_players_with_bounded_animated_rigs() -> void:
	var online := _online()
	var members := {}
	for index in range(2, 301): members[index] = {"id": index, "player": str(index), "floor": 1}
	online.crowd.roster(members)
	for id in members:
		online.crowd.sample(id, {"position": Vector3((id % 20) * .5, 0, -float(id / 20) * .5), "yaw": 0,
			"hp": 80, "max_hp": 100, "action": 1, "serial": 0})
	for index in 10: online.crowd.step(.51, Vector3.ZERO)
	await get_tree().create_timer(.5).timeout
	online.crowd.step(0, Vector3.ZERO)
	assert_int(online.crowd.actors.size()).is_equal(299)
	assert_int(online.crowd.rigs.size()).is_equal(8)
	assert_int(online.crowd.bodies.multimesh.visible_instance_count).is_equal(291)
	await get_tree().create_timer(.5).timeout

func _look(cloth: String, hair := "hairhat20", bag := "") -> Dictionary:
	var config := Avatar.slot_table.default_config()
	config.slots[&"cloth"] = cloth
	config.slots[&"hairHat"] = hair
	config.slots[&"messengerBag"] = bag
	return OnlineAppearance.payload(config)

func _sample_peer(online: OnlineSpace, id: int) -> void:
	online.crowd.sample(id, {"position": Vector3.ZERO, "yaw": 0, "hp": 100, "max_hp": 100, "action": 0, "serial": 0})
	online.crowd.step(.51, Vector3.ZERO)
	await get_tree().create_timer(.5).timeout
	online.crowd.step(0, Vector3.ZERO)

func test_remote_saved_clothes_update_and_recycled_rig_never_keeps_previous_player_accessories() -> void:
	var own := Avatar.load_outfit().to_json_text()
	var online := _online()
	online._message({"t": "peer", "count": 2, "member": {"id": 2, "player": "remote-a", "appearance": _look("cloth1", "hairhat20", "messengerbag1")}})
	await _sample_peer(online, 2)
	var rig: AvatarRig = online.crowd.rigs[0].rig
	assert_str(rig.current_config().slots.cloth).is_equal("cloth1")
	assert_str(rig.current_config().slots.messengerBag).is_equal("messengerbag1")
	online._message({"t": "peer", "count": 2, "member": {"id": 2, "player": "remote-a", "appearance": _look("cloth11")}})
	await _sample_peer(online, 2)
	assert_str(rig.current_config().slots.cloth).is_equal("cloth11")
	assert_str(rig.current_config().slots.messengerBag).is_empty()
	online._message({"t": "left", "count": 1, "id": 2})
	online._message({"t": "peer", "count": 2, "member": {"id": 3, "player": "remote-b", "appearance": _look("cloth28", "hairhat41")}})
	await _sample_peer(online, 3)
	assert_int(online.crowd.rigs.size()).is_equal(1)
	assert_str(rig.current_config().slots.cloth).is_equal("cloth28")
	assert_str(rig.current_config().slots.hairHat).is_equal("hairhat41")
	assert_str(Avatar.load_outfit().to_json_text()).is_equal(own)

func test_unknown_parts_and_mismatched_slots_fall_back_without_loading_wire_paths() -> void:
	var raw := _look("res://untrusted", "shoes1", "missing-bag")
	var config := OnlineAppearance.config(raw)
	assert_str(config.slots.cloth).is_equal("cloth0")
	assert_str(config.slots.hairHat).is_equal("hairhat0")
	assert_str(config.slots.messengerBag).is_empty()
	assert_str(OnlineAppearance.config(null).slots.body).is_equal("body00")

func test_bad_packet_cannot_create_avatars_or_modify_health() -> void:
	var online := _online()
	var packet := _frame(2, 1, 100)
	packet.encode_u16(10, 301)
	online._frame(packet)
	assert_bool(online.self_state.is_empty()).is_true()
	assert_bool(online.crowd.actors.is_empty()).is_true()

func test_transport_retry_keeps_recovery_but_explicit_exit_discards_it() -> void:
	var online := _online()
	online._resume_ticket = "server-signed-ticket"
	online._disconnected("TEST_CONNECTION_LOSS")
	assert_str(online._resume_ticket).is_equal("server-signed-ticket")
	online.stop()
	assert_str(online._resume_ticket).is_empty()

func test_departure_keeps_home_reconnect_intent_through_scene_suspension() -> void:
	var online := _online()
	online._suspended = true
	online.suspend()
	assert_bool(online._suspended).is_true()
	online.stop()
	assert_bool(online._suspended).is_false()

func test_party_destination_uses_visitor_data_and_does_not_change_home_choice() -> void:
	var before := FarmChoice.load().duplicate(true)
	var session := FarmSession.new(ApiClient.new())
	session.farm_id = "my-farm"
	session.region_id = "los_angeles"
	session.layout_patch_id = "la_a"
	var manifest := {"kind": "farm", "farm_id": "their-farm", "layout_patch_id": "sh_b", "blueprint_revision": 2,
		"channel": 7, "ticket": "signed-admission", "snapshot": {"farm_id": "their-farm"}}
	var args := PartyTravel.scene_args(manifest, session)
	assert_bool(args.visitor).is_true()
	assert_str(args.blueprint.layout_patch_id).is_equal("sh_b")
	assert_int(args.online_join.channel).is_equal(7)
	assert_str(args.online_join.travel_ticket).is_equal("signed-admission")
	assert_str(session.region_id).is_equal("los_angeles")
	assert_that(FarmChoice.load()).is_equal(before)

func test_legacy_street_admission_keeps_current_farm_and_connection() -> void:
	var online := _online("farm")
	var manifest := {"kind": "street", "farm_id": "their-farm", "layout_patch_id": "sh_b", "blueprint_revision": 2,
		"channel": 7, "ticket": "legacy-street-admission", "room": "street:shanghai:sh_b:2:7", "floor": 0,
		"snapshot": {"farm_id": "their-farm"}}
	var transport := FakeTransport.new([{"status": 200, "json": manifest}])
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.farm_id = "my-farm"
	session.version = 47
	session.state = {"wallet": 321, "cells": {"28,35": {"state": "growing", "ready_at": 123456}}}
	var state_before := session.state.duplicate(true)
	var choice_before := FarmChoice.load().duplicate(true)
	var depth_before := AppRouter.instance_depth()
	online.session = session
	online.room = "farm:my-farm:1"
	online.joined = true
	var mover: PlayerMover = online.mover_source.call()
	var position_before := mover.position
	await online.request_travel("their-player", "follow")
	assert_str(online.error).is_equal("FARM_UPDATE_REQUIRED")
	assert_bool(online.travel_busy).is_false()
	assert_bool(online.joined).is_true()
	assert_str(online.room).is_equal("farm:my-farm:1")
	assert_int(AppRouter.instance_depth()).is_equal(depth_before)
	assert_str(session.farm_id).is_equal("my-farm")
	assert_int(session.version).is_equal(47)
	assert_that(session.state).is_equal(state_before)
	assert_that(FarmChoice.load()).is_equal(choice_before)
	assert_that(mover.position).is_equal(position_before)
	assert_int(transport.requests.size()).is_equal(1)
	assert_str(transport.requests[0].url).is_equal("https://example.test/v1/online/travel")
	assert_str(PartyTravel.scene_path(manifest)).is_empty()
	assert_that(PartyTravel.scene_args(manifest, session)).is_empty()
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	assert_str(OnlineSpace.error_text(online.error)).is_equal("当前服务尚未更新农场功能，暂时无法前往该队友。")
	TranslationServer.set_locale(locale)

## 私有农场不回滚自身位置。街道与矿井是共享空间，服务端驱动移动、回传权威位置，
## 预测-校正才成立；农场是单人空间，服务端那边的位置基本不动，校正就变成和本地寻路
## 对着拉——2026-09-17 真机实测本地每帧推进 0.031m，每个快照又把人按 25% 拉回，
## 净位移只剩约 3%，路径永远走不完，劳作队列永久卡在「正在前往…」。
func test_private_farm_ignores_server_position_correction_but_shared_spaces_keep_it() -> void:
	for space_kind in ["mine", "farm"]:
		var online := _online(space_kind)
		var mover: PlayerMover = online.mover_source.call()
		mover.position = Vector3(2.5, 0, -2.5)        # 本地已经走出去一段
		var before := mover.position
		online._frame(_frame(2, 30, 100))             # 服务端仍认为我们在 (0.75, -0.75)
		var pulled := not mover.position.is_equal_approx(before)
		assert_bool(pulled).override_failure_message(
			"%s 空间：位置%s该被服务端拉动" % [space_kind, "" if space_kind == "mine" else "不"]
		).is_equal(space_kind == "mine")

func test_remote_fishing_ends_on_roster_removal_and_pool_reuse() -> void:
	var online := _online("farm")
	var camera := Camera3D.new()
	online.get_parent().add_child(camera)
	camera.make_current()
	online._message({"t": "peer", "count": 2, "member": {"id": 2, "player": "fisher"}})
	await _sample_peer(online, 2)
	online._message({"t": "fishing", "epoch": 2, "members": [{"id": 2, "site": "farm_pond", "sequence": 1, "target": [9, -29], "phase": "waiting", "cast_age": 3}]})
	online.crowd.step(0, Vector3.ZERO)
	var entry: Dictionary = online.crowd.rigs[0]
	var view: FishingPresentation = entry.fishing_view
	assert_bool(is_instance_valid(view)).is_true()
	online._message({"t": "left", "id": 2, "count": 1})
	await get_tree().process_frame
	assert_bool(is_instance_valid(view)).is_false()
	online._message({"t": "peer", "count": 2, "member": {"id": 3, "player": "walker"}})
	await _sample_peer(online, 3)
	assert_int(online.crowd.rigs.size()).is_equal(1)
	assert_bool(is_instance_valid(entry.get("fishing_view"))).is_false()
	assert_bool(entry.rig.get_node("AnimationPlayer").is_playing()).is_true()

func test_relocated_farm_stops_once_clears_stale_join_and_cannot_restart_it() -> void:
	for via_message in [false, true]:
		var online := _online("farm")
		online.set_process(false)
		online.session = FarmSession.new(ApiClient.new())
		online.session.client.token = "token"
		online.active = true
		online.joined = true
		online.join_args = {"farm_id": "relocated", "travel_ticket": "stale-admission"}
		online._prediction_history[1] = {"seq": 1}
		online._pending[2] = null
		var notifications := [0]
		online.farm_relocated.connect(func(): notifications[0] += 1)
		if via_message: online._message({"t": "error", "code": "FARM_RELOCATED"})
		else: online._disconnected("FARM_RELOCATED")
		online._handle_farm_relocated()
		assert_int(notifications[0]).is_equal(1)
		assert_bool(online.active).is_false()
		assert_bool(online.joined).is_false()
		assert_bool(online.join_args.has("travel_ticket")).is_false()
		assert_bool(online._prediction_history.is_empty()).is_true()
		assert_bool(online._pending.is_empty()).is_true()
		assert_str(online.error).is_equal("FARM_RELOCATED")
		online.suspend()
		online.resume()
		online.start()
		assert_bool(online.active).is_false()
		assert_object(online.socket).is_null()
