extends GdUnitTestSuite
## B5：map_poc 关掉演示内容后只剩自己 + 好友；set_friends 增量增删改，好友是绝对坐标不跟 home 纠正搬。

func _map(demo: bool) -> Node:
	var scene := (load("res://scenes/map_poc/map_poc.tscn") as PackedScene).instantiate()
	scene.demo_cohorts = demo
	add_child(auto_free(scene))
	return scene

func _friend(id: String, lat: float, lng: float, avatar: Variant = null) -> Dictionary:
	return {"user_id": id, "display_name": id, "handle": id, "avatar": avatar, "lat": lat, "lng": lng}

func test_non_demo_map_has_no_fixture_cohorts_and_expects_only_self() -> void:
	var m := _map(false)
	await get_tree().process_frame
	for spec in m._spawn_queue:
		assert_str(str(spec.cohort)).is_not_equal("la")
		assert_str(str(spec.cohort)).is_not_equal("near")
	assert_int(m._expected_role_count()).is_equal(1)
	assert_bool(m.marker_layer.visible).is_false()
	assert_bool(m.travel_btn.get_parent().visible).is_false()
	var demo := _map(true)
	await get_tree().process_frame
	assert_int(demo._expected_role_count()).is_equal(demo.INITIAL_ROLE_COUNT)
	assert_bool(demo.travel_btn.get_parent().visible).is_true()

func test_set_friends_queues_updates_and_removes_by_user_id() -> void:
	var m := _map(false)
	await get_tree().process_frame
	m.set_friends([_friend("u-a", 31.2, 121.5), _friend("u-b", 31.3, 121.6, {"version": 1, "slots": {}})])
	assert_int(m.friend_count()).is_equal(2)
	assert_bool(not m._queued_for("friend:u-a").is_empty()).is_true()
	# 同一个人再来一次只改坐标，不重复排队。
	m.set_friends([_friend("u-a", 31.25, 121.55), _friend("u-b", 31.3, 121.6)])
	assert_int(m.friend_count()).is_equal(2)
	assert_float(float(m._queued_for("friend:u-a").lat)).is_equal(31.25)
	# 让队列出队变成真 pawn，再删掉 u-b。
	for i in 6:
		await get_tree().process_frame
	var had_pawn: bool = not m._pawn_for("friend:u-a").is_empty()
	m.set_friends([_friend("u-a", 31.25, 121.55)])
	assert_int(m.friend_count()).is_equal(1)
	assert_bool(m._pawn_for("friend:u-b").is_empty()).is_true()
	assert_bool(m._queued_for("friend:u-b").is_empty()).is_true()
	if had_pawn:
		assert_bool(m._pawn_for("friend:u-a").is_empty()).is_false()
	m.set_friends([])
	assert_int(m.friend_count()).is_equal(0)

func test_home_correction_moves_self_but_not_friends() -> void:
	var m := _map(false)
	await get_tree().process_frame
	m._resolve_home(31.0, 121.0, true) # 回落点
	m.set_friends([_friend("u-a", 31.5, 121.5)])
	var self_spec: Dictionary = {}
	for spec in m._spawn_queue:
		if spec.cohort == "self":
			self_spec = spec
	assert_bool(self_spec.is_empty()).is_false()
	m._resolve_home(32.0, 122.0, false) # 真定位到了：纠正一次
	assert_float(float(self_spec.lat)).is_equal(32.0)
	assert_float(float(m._queued_for("friend:u-a").lat)).is_equal(31.5)
	assert_bool(m._absolute_cohort("friend:x")).is_true()
	assert_bool(m._absolute_cohort("la")).is_true()
	assert_bool(m._absolute_cohort("near")).is_false()
