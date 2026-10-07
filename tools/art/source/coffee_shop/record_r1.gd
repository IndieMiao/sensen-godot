extends SceneTree
## Per-scene real-time viewport recorder. The shared movement harness is read-only.
var benchmark: Node3D
var output: String
var frames: Array = []
var active := false
var pending := false
var started := 0
var last_frame := -1.0
func _initialize() -> void: call_deferred("start")
func start() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--output": output=args[i+1]
	assert(not output.is_empty() and DisplayServer.get_name() != "headless")
	DirAccess.make_dir_recursive_absolute(output+"/frames")
	benchmark=(load("res://tools/dev/scene_bench/scene_bench.tscn") as PackedScene).instantiate()
	root.add_child(benchmark);current_scene=benchmark
	process_frame.connect(capture_frame)
func capture_frame() -> void:
	if pending: return
	if not active:
		if benchmark.phase != "record-ready":return
		started=Time.get_ticks_usec();active=true
	elif (Time.get_ticks_usec()-started)/1000000.0-last_frame<.049: return
	pending=true
	await RenderingServer.frame_post_draw
	var now:float=(Time.get_ticks_usec()-started)/1000000.0
	if now>15.05:
		pending=false;return
	var im:=root.get_texture().get_image()
	var file_name:="frames/%05d.jpg"%frames.size()
	assert(im.save_jpg(output+"/"+file_name,.94)==OK)
	frames.append({"file":file_name,"seconds":now})
	last_frame=now
	var manifest:=FileAccess.open(output+"/viewport-frames.json",FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"source":"real rendered Godot viewport","clock":"Time.get_ticks_usec wall clock","accelerated":false,"resolution":[im.get_width(),im.get_height()],"frames":frames},"  "))
	if frames.size()==1:
		var go:=FileAccess.open(output+"/record-go",FileAccess.WRITE);go.store_string(str(OS.get_process_id()))
	pending=false
