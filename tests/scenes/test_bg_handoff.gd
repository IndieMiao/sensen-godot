extends GdUnitTestSuite
## 复现：从地图进换装房时背景是黑的（单独跑换装房是 90% 白）。
## map_poc._ready() 把 transparent_bg 置 true 让 Mapbox 从底下透上来，
## _exit_tree() 负责还原。若还原失效，换装房就会继续透明 → 合成到黑底上。

func test_map_scene_restores_transparent_bg_on_exit() -> void:
	var vp := get_viewport()
	vp.transparent_bg = false
	var scene := (load("res://scenes/map_poc/map_poc.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	assert_bool(vp.transparent_bg).is_true() # 地图确实开了透明
	scene.free()
	await get_tree().process_frame
	assert_bool(vp.transparent_bg).is_false() # 切走必须还原

func test_farm_background_renders_opaque_after_a_transparent_map_surface() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 384)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(viewport))
	var map_scene := (load("res://scenes/map_poc/map_poc.tscn") as PackedScene).instantiate()
	viewport.add_child(map_scene)
	await get_tree().process_frame
	assert_bool(viewport.transparent_bg).is_true()
	map_scene.suspend()
	assert_bool(viewport.transparent_bg).is_false()
	var farm := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	farm.setup({"blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2)), "session": null})
	viewport.add_child(farm)
	farm.set_process(false)
	await get_tree().process_frame
	# 不等 frame_post_draw 而是 force_draw()：macOS 把被其他窗口完全遮住的 Godot 窗口判成
	# 不可见后就停止绘制，信号永远不来（2026-09-07 本地被 Edge 盖住时整条测试超时 5 分钟）。
	# force_draw 同步走一遍完整绘制，SubViewport(UPDATE_ALWAYS) 照样出图。
	RenderingServer.force_draw()
	var rendered := viewport.get_texture().get_image()
	assert_bool(rendered.is_empty()).is_false()
	for point in [Vector2i(1, 1), Vector2i(254, 1), Vector2i(1, 382), Vector2i(254, 382)]:
		assert_float(rendered.get_pixelv(point).a).override_failure_message("Farm background leaks at %s" % point).is_greater_equal(0.99)
	# Native map surfaces can retain alpha even after the normal viewport handoff.
	viewport.transparent_bg = true
	await get_tree().process_frame
	RenderingServer.force_draw()
	var retained_alpha := viewport.get_texture().get_image()
	for point in [Vector2i(1, 1), Vector2i(254, 1), Vector2i(128, 192), Vector2i(1, 382), Vector2i(254, 382)]:
		assert_float(retained_alpha.get_pixelv(point).a).override_failure_message("Farm final pass leaks on transparent surface at %s" % point).is_greater_equal(0.99)
	# A transparent negative control verifies that alpha readback is meaningful.
	for path in ["FarmBackground", "HUD", "Ground", "Props", "Crops", "Player", "OpaqueSceneLayer"]:
		farm.get_node(path).visible = false
	viewport.transparent_bg = true
	await get_tree().process_frame
	RenderingServer.force_draw()
	var transparent := viewport.get_texture().get_image().get_pixel(128, 192)
	assert_float(transparent.a).is_less_equal(0.01)
	farm.get_node("FarmBackground").visible = true
	farm.get_node("OpaqueSceneLayer").visible = true
	await get_tree().process_frame
	RenderingServer.force_draw()
	var lawn := viewport.get_texture().get_image().get_pixel(128, 192)
	assert_float(lawn.a).is_greater_equal(0.99)
	assert_float(lawn.g).is_greater(0.7)
