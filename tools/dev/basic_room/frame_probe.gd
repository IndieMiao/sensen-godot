extends Node
## Optional isolated-QA autoload. Frame completion intervals, not GPU timestamps.
const DIR := "user://room-qa/"
var samples: Array[float] = []
var started: int = 0
var previous: int = 0
var duration: float = 30.0
var request_id: int = -1
var poll_time: float = 0.0

func _ready() -> void:
	RenderingServer.frame_post_draw.connect(_sample)

func _process(delta: float) -> void:
	poll_time += delta
	if poll_time < .2 or started != 0: return
	poll_time = 0
	if not FileAccess.file_exists(DIR + "performance-command.json"): return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "performance-command.json"))
	if not request is Dictionary or int(request.get("id", -1)) == request_id: return
	request_id = int(request.id)
	duration = clampf(float(request.get("seconds", 30)), 5, 120)
	samples.clear()
	started = Time.get_ticks_usec()
	previous = 0

func _sample() -> void:
	if started == 0: return
	var now := Time.get_ticks_usec()
	if previous != 0: samples.append(float(now - previous) / 1000.0)
	previous = now
	if float(now - started) / 1000000.0 < duration: return
	var result := {"id": request_id, "pid": OS.get_process_id(), "duration_seconds": float(now-started)/1000000.0, "frame_ms": samples}
	var file := FileAccess.open(DIR + "performance.pending", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	DirAccess.rename_absolute(DIR + "performance.pending", DIR + "performance.json")
	started = 0
