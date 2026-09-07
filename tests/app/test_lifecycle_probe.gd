extends GdUnitTestSuite
## A6 探针页：通知计数、落盘、清空。

func before_test() -> void:
	if FileAccess.file_exists("user://lifecycle_probe.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://lifecycle_probe.json"))

func after_test() -> void:
	before_test()

func test_counts_watched_notifications_and_persists() -> void:
	var p := (load(AppRoutes.LIFECYCLE_PROBE) as PackedScene).instantiate()
	add_child(auto_free(p))
	p.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	p.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	p.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	p.notification(Node.NOTIFICATION_PROCESS) # 不关心的通知不计
	assert_int(int(p.counts.get("APPLICATION_PAUSED", 0))).is_equal(1)
	assert_int(int(p.counts.get("APPLICATION_RESUMED", 0))).is_equal(2)
	assert_bool(p.summary.text.contains("APP_RESUMED: 2")).is_true()
	assert_bool(FileAccess.file_exists("user://lifecycle_probe.json")).is_true()
	var again := (load(AppRoutes.LIFECYCLE_PROBE) as PackedScene).instantiate()
	add_child(auto_free(again))
	assert_int(int(again.counts.get("APPLICATION_RESUMED", 0))).is_equal(2)
	again._clear()
	assert_int(again.counts.size()).is_equal(0)

func test_settings_exposes_probe_only_in_debug_builds() -> void:
	var s := (load(AppRoutes.SETTINGS) as PackedScene).instantiate()
	add_child(auto_free(s))
	assert_bool(s.find_child("LifecycleProbe", true, false) != null).is_equal(OS.is_debug_build())

## A5 iOS 键盘：镜像操作时不弹软键盘，人手点一次后靠落盘的最大高度判定。高度只升不降，清空归零。
class KeyboardBox extends RefCounted:
	var height := 0
	func get_height() -> int:
		return height

func test_records_max_keyboard_height_and_persists_it() -> void:
	var box := KeyboardBox.new()
	var p := (load(AppRoutes.LIFECYCLE_PROBE) as PackedScene).instantiate()
	p.keyboard_height_provider = box.get_height
	add_child(auto_free(p))
	p._process(0.0)
	assert_int(p.keyboard_max_px).is_equal(0)
	box.height = 320
	p._process(0.0)
	box.height = 100
	p._process(0.0)
	assert_int(p.keyboard_max_px).is_equal(320)
	assert_bool(p.keyboard_label.text.contains("(max 320)")).is_true()
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://lifecycle_probe.json"))
	assert_int(int(saved.keyboard_max_px)).is_equal(320)
	var again := (load(AppRoutes.LIFECYCLE_PROBE) as PackedScene).instantiate()
	add_child(auto_free(again))
	assert_int(again.keyboard_max_px).is_equal(320)
	again._clear()
	assert_int(again.keyboard_max_px).is_equal(0)
