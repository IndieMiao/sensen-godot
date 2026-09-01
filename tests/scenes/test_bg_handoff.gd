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
