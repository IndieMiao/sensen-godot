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

## 点地图上的好友角色 → 发 friend_tapped。用一个空 Node3D 冒充角色：真部件是异步装配的，
## 会让用例跟着资源加载抖，而这里要验的是命中判定与事件，不是装配。
func _fake_pawn(map: Node, cohort: String, world: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Fake_%s" % cohort
	map.rigs.add_child(holder)
	holder.position = world
	map._pawns.append({"lat": 0.0, "lng": 0.0, "node": holder, "rig": null, "activity": null,
		"ready": true, "cohort": cohort})
	return holder

func test_friend_at_hits_the_nearest_friend_and_ignores_self_and_far_taps() -> void:
	var m := _map(false)
	await get_tree().process_frame
	var friend := _fake_pawn(m, "friend:u-a", Vector3.ZERO)
	# 自己放远一点：屏幕上离好友几十像素以内的话，点自己也会命中旁边的好友（判定半径 56 px）。
	_fake_pawn(m, "self", Vector3(500.0, 0.0, 0.0))
	var screen: Vector2 = m.cam.unproject_position(friend.position + Vector3(0.0, friend.scale.y * 0.9, 0.0))
	assert_str(m.friend_at(screen)).is_equal("u-a")
	assert_str(m.friend_at(screen + Vector2(600, 600))).is_empty()
	# 自己不算：点在自己身上没有目标。
	var self_node := m._pawn_for("self").node as Node3D
	assert_str(m.friend_at(m.cam.unproject_position(self_node.position + Vector3(0.0, 0.9, 0.0)))).is_empty()
	# 隐藏 / 未就绪的角色不参与命中。
	friend.visible = false
	assert_str(m.friend_at(screen)).is_empty()
	friend.visible = true
	m._pawn_for("friend:u-a").ready = false
	assert_str(m.friend_at(screen)).is_empty()

func test_tapping_a_friend_emits_friend_tapped_and_empty_space_does_not() -> void:
	var m := _map(false)
	await get_tree().process_frame
	var friend := _fake_pawn(m, "friend:u-b", Vector3.ZERO)
	var screen: Vector2 = m.cam.unproject_position(friend.position + Vector3(0.0, friend.scale.y * 0.9, 0.0))
	var seen: Array = []
	m.friend_tapped.connect(func(uid: String): seen.append(uid))
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = screen
	press.pressed = true
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = screen
	m._unhandled_input(press)
	m._unhandled_input(release)
	assert_array(seen).is_equal(["u-b"])
	# 点空地：不发信号，走原来的「记一次单击」路径（留给双击判定）。
	var far := screen + Vector2(600, 600)
	var press2 := InputEventScreenTouch.new()
	press2.index = 0
	press2.position = far
	press2.pressed = true
	var release2 := InputEventScreenTouch.new()
	release2.index = 0
	release2.position = far
	m._unhandled_input(press2)
	m._unhandled_input(release2)
	assert_array(seen).is_equal(["u-b"])
	assert_int(m._last_tap_ms).is_greater(0)

## 社交主线的地图不该带农场那套 UI：设备上只要留着旧的 farm_choice.json 就会被拉起来
## （2026-09-08 安卓真机：底图之上盖了「My Farm / Nearby Farmers / Sample A」）。
func test_social_map_has_no_farm_ui() -> void:
	var map: Node = auto_free((load("res://scenes/map_poc/map_poc.tscn") as PackedScene).instantiate())
	map.demo_cohorts = false
	add_child(map)
	await get_tree().process_frame
	assert_object(map.my_farm_btn).is_null()
	assert_object(map.nearby_panel).is_null()
	assert_bool(map.top_panel.visible).is_false()
	map.suspend()
