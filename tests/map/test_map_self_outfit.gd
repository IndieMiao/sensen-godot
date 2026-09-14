extends GdUnitTestSuite
## 回归：地图上"我"的角色必须读换装房存档，而不是默认装扮。
## 历史缺陷：map_poc.gd 写死 Avatar.slot_table.default_config()，换装闭环是断的。

const MapPoc := preload("res://scenes/map_poc/map_poc.gd")
const TEST_USER := "test_map_self"
const SAVE_PATH := "user://avatar/outfit_%s.json" % TEST_USER
const MAP_SCENE := preload("res://scenes/map_poc/map_poc.tscn")
const REGION := {"id": "test_outfit", "name": "Test", "center": [31.2, 121.4]}

var _prev_user := ""

func before_test() -> void:
	_prev_user = Avatar.user_id
	Avatar.user_id = TEST_USER
	DirAccess.remove_absolute(SAVE_PATH)

func after_test() -> void:
	Avatar.user_id = _prev_user
	DirAccess.remove_absolute(SAVE_PATH)

func test_self_config_reads_saved_outfit() -> void:
	var pool := Avatar.catalog.parts_for_slot(&"hairHat")
	if pool.size() < 2:
		push_warning("转换产物缺失或部件不足，跳过")
		return
	var cfg := Avatar.slot_table.default_config()
	var want: String = pool[pool.size() - 1].id
	cfg.slots[&"hairHat"] = want
	assert_int(Avatar.save_outfit(cfg)).is_equal(OK)

	var node = auto_free(MapPoc.new())
	assert_str(str(node.self_config().slots[&"hairHat"])).is_equal(want)

func test_self_config_falls_back_when_no_save() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	var node = auto_free(MapPoc.new())
	assert_object(node.self_config()).is_not_null()

func _map_scene() -> Node:
	FarmChoice.clear()
	FarmRegions.clear_choice()
	var scene := MAP_SCENE.instantiate()
	scene.enter_street_mode(REGION)
	add_child(auto_free(scene))
	scene.set_process(false)
	return scene

func _changed_outfit() -> AvatarConfig:
	var cfg := Avatar.load_outfit()
	for part in Avatar.catalog.parts_for_slot(&"hairHat"):
		if part.id != cfg.slots.get(&"hairHat", ""):
			cfg.slots[&"hairHat"] = part.id
			return cfg
	assert_bool(false).override_failure_message("A second shipped hairstyle is required").is_true()
	return cfg

func _wait_for_rig(rig: AvatarRig) -> void:
	for frame in 600:
		if not rig.is_busy():
			break
		await get_tree().process_frame
	assert_bool(rig.is_busy()).is_false()

func _spawn_self(scene: Node) -> Dictionary:
	var spec: Dictionary = scene._spawn_queue.pop_front()
	assert_str(spec.cohort).is_equal("self")
	scene._add_pawn(spec.lat, spec.lng, spec.cfg, spec.anim, spec.cohort)
	return scene._pawns.back()

func test_resume_applies_saved_outfit_to_existing_self_without_moving_or_restarting_animation() -> void:
	var scene := _map_scene()
	var pawn := _spawn_self(scene)
	var rig := pawn.rig as AvatarRig
	await _wait_for_rig(rig)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var holder := pawn.node as Node3D
	holder.rotation.y = 0.4
	var original_transform := holder.transform
	var animation := rig.get_node("AnimationPlayer") as AnimationPlayer
	animation.play("idle")
	animation.advance(0.43)
	var animation_position := animation.current_animation_position
	scene.suspend()
	var saved := _changed_outfit()
	assert_int(Avatar.save_outfit(saved)).is_equal(OK)
	scene.resume()
	scene.set_process(false)
	assert_bool(saved.changed_slots(rig.desired_config()).is_empty()).is_true()
	if rig.is_busy():
		assert_bool(pawn.ready).is_false()
		assert_bool(holder.visible).is_false()
	await _wait_for_rig(rig)
	assert_bool(saved.changed_slots(rig.current_config()).is_empty()).is_true()
	assert_bool(pawn.ready).is_true()
	assert_object(pawn.node).is_same(holder)
	assert_bool(holder.transform.is_equal_approx(original_transform)).is_true()
	assert_str(animation.current_animation).is_equal("idle")
	assert_float(animation.current_animation_position).is_equal_approx(animation_position, 0.001)
	scene._update_cameras()
	scene._sync_farm_markers()
	assert_bool(holder.visible).is_true()

func test_resume_updates_self_outfit_while_spawn_is_still_queued() -> void:
	var scene := _map_scene()
	assert_int(scene._pawns.size()).is_equal(0)
	var position := Vector2(scene._spawn_queue[0].lat, scene._spawn_queue[0].lng)
	scene.suspend()
	var saved := _changed_outfit()
	assert_int(Avatar.save_outfit(saved)).is_equal(OK)
	scene.resume()
	scene.set_process(false)
	assert_bool(saved.changed_slots(scene._spawn_queue[0].cfg).is_empty()).is_true()
	assert_vector(Vector2(scene._spawn_queue[0].lat, scene._spawn_queue[0].lng)).is_equal(position)
	var pawn := _spawn_self(scene)
	var rig := pawn.rig as AvatarRig
	await _wait_for_rig(rig)
	assert_bool(saved.changed_slots(rig.current_config()).is_empty()).is_true()
	assert_bool(pawn.ready).is_true()

func test_resume_keeps_unchanged_saved_outfit_and_discards_unsaved_draft_without_rebuilding() -> void:
	var scene := _map_scene()
	var pawn := _spawn_self(scene)
	var rig := pawn.rig as AvatarRig
	await _wait_for_rig(rig)
	var original := rig.current_config()
	var mesh := (rig.skeleton.get_node("merged_mesh") as MeshInstance3D).mesh
	var updates: Array[StringName] = []
	rig.slot_applied.connect(func(slot, _part): updates.append(slot))
	for attempt in 2:
		scene.suspend()
		var draft := _changed_outfit()
		assert_bool(original.changed_slots(draft).is_empty()).is_false()
		scene.resume()
		scene.set_process(false)
		await get_tree().process_frame
		assert_bool(rig.is_busy()).is_false()
		assert_bool(pawn.ready).is_true()
		assert_bool(original.changed_slots(rig.current_config()).is_empty()).is_true()
		assert_object((rig.skeleton.get_node("merged_mesh") as MeshInstance3D).mesh).is_same(mesh)
	assert_array(updates).is_empty()
