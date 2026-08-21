extends GdUnitTestSuite
## 回归：压测场景首次 spawn 后主体动画必须开始播放
## （历史缺陷：config_applied 连接晚于 apply_config，首发信号被错过）

const STRESS_SCENE := "res://scenes/stress_test/stress_test.tscn"

func test_first_spawn_plays_main_animation() -> void:
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		push_warning("转换产物缺失，跳过")
		return
	var scene := (load(STRESS_SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	var rigs_root: Node3D = scene.get_node("Rigs")
	assert_int(rigs_root.get_child_count()).is_greater(0)
	# 等待任一 rig 的主 AnimationPlayer 进入播放（装配为异步，放宽轮询）
	var playing := 0
	for i in 900:
		playing = 0
		for rig in rigs_root.get_children():
			var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap and ap.is_playing():
				playing += 1
		if playing == rigs_root.get_child_count():
			break
		await get_tree().process_frame
	assert_int(playing).is_equal(rigs_root.get_child_count())
