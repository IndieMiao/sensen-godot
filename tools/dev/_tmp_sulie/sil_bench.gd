extends Control
## Temporary (苏烈, SGODOT-328, not committed): N silhouette pins on a 360 × 800 screen, vsync off; average frame time.
func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var n := int(OS.get_environment("N"))
	var bg := ColorRect.new()
	bg.color = Color("a5a8a5")
	bg.size = Vector2(360, 800)
	add_child(bg)
	var icons := ["mine_hut", "travel", "pot", "board", "rod", "pond"]
	for i in n:
		var pin := UiMapDestination.new(P0Logic.icon(icons[i % icons.size()]), "")
		pin.theme = UiKit.theme()
		add_child(pin)
		pin.silhouette = true
		pin.position = Vector2(20 + (i % 6) * 56, 60 + int(i / 6) * 90)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await get_tree().create_timer(2.0).timeout
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_frames_drawn()
	var cpu := 0.0
	var k := 0
	while Time.get_ticks_usec() - t0 < 5_000_000:
		await get_tree().process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
		k += 1
	var frames := Engine.get_frames_drawn() - f0
	print("BENCH328 %s n=%d frames=%d frame_ms=%.4f render_cpu_ms=%.4f draws=%.0f" % [OS.get_environment("LABEL"), n, frames,
		(Time.get_ticks_usec() - t0) / 1000.0 / frames, cpu / k, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()
