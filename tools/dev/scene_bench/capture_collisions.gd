extends SceneTree
## Capture the current scene's actual collision wireframe without rerunning movement.
func _initialize()->void:call_deferred("capture")
func capture()->void:
	var room=load("res://tools/dev/scene_bench/scene_bench.tscn").instantiate()
	root.add_child(room)
	var deadline:=Time.get_ticks_msec()+20000
	while not room.ready_for_capture and Time.get_ticks_msec()<deadline:await process_frame
	await create_timer(.5).timeout
	room.show_colliders()
	await room.capture("collisions.png")
	quit()
