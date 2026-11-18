extends SceneTree
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
var scene
var checks := 0
var failures := 0
var backs := 0
var complete := false

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	var paths := OS.get_cmdline_user_args()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(paths[0]))
	var packed := load(SCENE_PATH) as PackedScene
	scene = packed.instantiate()
	scene.setup({"farm":raw,"dataset":raw.dataset_version,"block_id":raw.block_id,"preview_only":true})
	scene.back_requested.connect(func(): backs += 1)
	scene.preview_error.connect(func(message):
		push_error(message)
		quit(1))
	scene.preview_ready.connect(func(_summary): _verify.call_deferred())
	root.add_child(scene)
	await create_timer(35).timeout
	if not complete: quit(1)

func _verify() -> void:
	_check(scene._camera.keep_aspect == Camera3D.KEEP_WIDTH,"existing farm width framing")
	var controller = scene._controls
	var touch := InputEventScreenTouch.new()
	touch.index=0
	touch.pressed=true
	touch.position=Vector2(140,230)
	controller._unhandled_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index=0
	drag.position=Vector2(165,250)
	controller._input(drag)
	_check(not scene._movement.is_zero_approx(),"world gesture supplies movement")
	touch.pressed=false
	touch.position=Vector2(320,20)
	controller._input(touch)
	_check(scene._movement.is_zero_approx() and controller.touches.is_empty(),"release over UI always stops movement")
	var before: Vector3 = scene._actor.position
	scene.suspend()
	_check(not scene._canvas.visible and scene._environment.environment == null,"suspend yields canvas and environment")
	await process_frame
	await process_frame
	_check(scene._actor.position == before,"suspended actor stays still")
	scene.resume()
	_check(scene._canvas.visible and scene._environment.environment != null,"resume restores owned scene state")
	_check(scene._movement.is_zero_approx(),"resume has no stuck movement")
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not scene._focused and controller.touches.is_empty(),"background cancels gesture")
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(scene._focused and scene._movement.is_zero_approx(),"foreground does not restart movement")
	_check(scene.is_back_navigation_locked(),"Back delegated to host")
	scene.is_back_navigation_locked()
	_check(backs == 1,"Back emitted once for host single pop")
	complete=true
	scene.queue_free()
	await process_frame
	print("DYNAMIC_LIFECYCLE_TESTS checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
