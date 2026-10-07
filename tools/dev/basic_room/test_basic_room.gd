extends SceneTree
## Behavioural checks use the real CharacterBody3D, room colliders and AvatarRig.
var checks: Array = []
var room: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(name: String, passed: bool, details: Variant = null) -> void:
	checks.append({"name": name, "passed": passed, "details": details})
	print("PASS " if passed else "FAIL ", name, " ", details)

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func drive_world(direction: Vector3, seconds: float) -> void:
	var right: Vector3 = room.camera.global_basis.x
	var forward: Vector3 = -room.camera.global_basis.z
	right.y = 0; forward.y = 0
	room.test_input = Vector2(direction.dot(right.normalized()), -direction.dot(forward.normalized()))
	room.test_input_until = room.time + seconds
	await wait_seconds(seconds + .15)

func run() -> void:
	room = load("res://tools/dev/basic_room/basic_room.tscn").instantiate()
	root.add_child(room)
	await wait_seconds(2)
	check("Existing avatar fixture assembles", room.ready_for_capture and not room.rig.is_busy())
	check("22 reusable room kits load", room.assets.size() == 22)
	check("Player stands on floorboard height", room.player.is_on_floor() and absf(room.player.position.y - .08) < .04, room.player.position.y)
	var start: Vector3 = room.player.position
	await drive_world(Vector3(0, 0, 1), .22)
	check("Free floor movement changes position", room.player.position.distance_to(start) > .5, room.player.position.distance_to(start))
	check("Input release stops movement", Vector2(room.player.velocity.x, room.player.velocity.z).length() < .01)
	check("Idle clip resumes after movement", room.rig.get_node("AnimationPlayer").current_animation == "idle")
	room.player.position = Vector3(-.12, .10, 1.55)
	await drive_world(Vector3(0, 0, -1), 1.1)
	check("Dining table blocks passage", room.player.position.z > 1.40, room.player.position)
	room.player.position = Vector3(2.50, .10, 1.50)
	await drive_world(Vector3(1, 0, 0), .75)
	check("Open diorama edge is bounded", room.player.position.x < 3.00, room.player.position)
	room.player.position = Vector3(-2.6, .10, -.6)
	await drive_world(Vector3(-1, 0, 0), .6)
	check("Window wall prevents walking outside", room.player.position.x > -2.80, room.player.position)
	room.player.position = Vector3(1.5, .10, 2.1)
	await drive_world(Vector3(1, 0, -1).normalized(), .7)
	check("Blocked diagonal preserves free sliding", room.player.position.z < 1.0 and room.player.position.x < 3.0, room.player.position)
	room.player.position = Vector3(0, .10, 2.1)
	room.test_input = Vector2(.6, .1)
	room.test_input_until = room.time + 1
	await wait_seconds(.12)
	var player: AnimationPlayer = room.rig.get_node("AnimationPlayer")
	var t1 := player.current_animation_position
	await wait_seconds(.12)
	check("Run animation advances at distant camera", player.current_animation == "run" and absf(player.current_animation_position - t1) > .01, [t1, player.current_animation_position])
	room._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await wait_seconds(.1)
	check("Focus loss cancels active input", Vector2(room.player.velocity.x, room.player.velocity.z).length() < .01)
	room._reset()
	room._set_beauty(true)
	check("Reference view hides character", not room.player.visible and room.beauty)
	room._set_beauty(false)
	check("Movement view restores character", room.player.visible and not room.beauty)
	for index in [0, 1]:
		var press := InputEventScreenTouch.new()
		press.index = index
		press.pressed = true
		press.position = Vector2(100 + index * 160, 300)
		room.controls._input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(360, 300)
	room.controls._input(drag)
	check("Two-finger input reduces camera size", room.zoom < 9, room.zoom)
	for index in [0, 1]:
		var release := InputEventScreenTouch.new()
		release.index = index
		release.pressed = false
		room.controls._input(release)
	check("Pinch release leaves movement stopped", room.input_value == Vector2.ZERO)
	var passed := true
	for item in checks: passed = passed and bool(item.passed)
	var result := {"passed": passed, "checks": checks}
	var f := FileAccess.open("user://room-qa/native-result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	print("BASIC_ROOM_TEST_RESULT ", JSON.stringify(result))
	quit(0 if passed else 1)
