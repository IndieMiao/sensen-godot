extends SceneTree
## Coffee-only evidence adapter. Read live physics shapes from the shared fixture.
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	assert(DisplayServer.get_name() != "headless")
	var room = load("res://tools/dev/scene_bench/scene_bench.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	var deadline := Time.get_ticks_msec() + 20000
	while not room.ready_for_capture and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(room.ready_for_capture)
	room.controls.hide()
	for i in 30:
		await process_frame
	room.show_colliders()
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, wireframe, depth_test_disabled; void fragment() { ALBEDO = vec3(0.02, 0.25, 0.50); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	for mesh in room.collision_overlay.get_children():
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 6:
		await process_frame
	await room.capture("collisions.png")
	print("COFFEE_COLLISION_WIREFRAME ", room.collision_overlay.get_child_count())
	quit()
