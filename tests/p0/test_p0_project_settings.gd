extends GdUnitTestSuite
## Project settings P0 depends on, guarded so a project.godot clean-up cannot quietly undo them.

## SGODOT-252: with too few worker threads, nested waits during a room's load each hold a worker and the room never
## opens (1-core emulator: Godot's default 1 thread hangs every time; 3 or 8 open, whatever the low-priority ratio;
## 2 cores hung at times, SGODOT-227 #82). Mobile keeps a floor of eight; desktop keeps Godot's default.
func test_mobile_keeps_its_worker_thread_floor() -> void:
	var key := "threading/worker_pool/max_threads.mobile"
	assert_bool(ProjectSettings.has_setting(key)).override_failure_message(key + " is gone (SGODOT-252)").is_true()
	assert_int(int(ProjectSettings.get_setting(key, 0))).override_failure_message(key + " below 3 (SGODOT-252)").is_greater_equal(3)
