extends SceneTree
## Repeated map → 3D → map switches on the Godot side (C-111): opens the dynamic farm host the way the map does,
## waits for the farm to report ready, then pops it the way AppRouter.pop_instance does (remove_child + queue_free),
## and samples Godot's own memory and object counts after every round.
##   godot --headless --path . --script res://tools/dev/dynamic_farm/switch_memory_probe.gd -- <farm.json> [rounds]
## Headless uses the dummy renderer: GPU memory, Vulkan surfaces and the native Mapbox map are not exercised.
## Prints one DYNAMIC_SWITCH_ROUND line per round and a DYNAMIC_SWITCH_MEMORY summary; exits 1 if the object,
## node or orphan counts keep growing after the first two warm-up rounds.
const HOST := "res://scenes/dynamic_farm/dynamic_farm_host.tscn"
const SETTLE_FRAMES := 4
var rows: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <farm.json> [rounds]"); quit(2); return
	var raw = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var rounds := int(args[1]) if args.size() > 1 else 20
	create_timer(30.0 + rounds * 20.0).timeout.connect(func(): push_error("switch probe timed out"); quit(1))
	var packed := load(HOST) as PackedScene
	_sample(0, "before")
	for i in rounds:
		var host = packed.instantiate()
		host.setup({"farm":raw, "dataset":raw.dataset_version, "block_id":raw.block_id, "preview_only":true, "return_context":{}})
		var ready := [false]
		host.preview_ready.connect(func(_summary): ready[0] = true)
		host.preview_error.connect(func(message): push_error(message); quit(1))
		root.add_child(host)
		while not ready[0]: await process_frame
		_sample(i + 1, "farm")
		root.remove_child(host); host.queue_free()
		for f in SETTLE_FRAMES: await process_frame
		_sample(i + 1, "map")
	_report()

func _sample(round: int, stage: String) -> void:
	var row := {"round":round, "stage":stage,
		"static_mb":snappedf(OS.get_static_memory_usage() / 1048576.0, 0.01),
		"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))}
	rows.append(row)
	print("DYNAMIC_SWITCH_ROUND ", JSON.stringify(row))

func _report() -> void:
	var maps := rows.filter(func(r): return r.stage == "map")
	var farms := rows.filter(func(r): return r.stage == "farm")
	var peak := 0.0
	for r in rows: peak = maxf(peak, r.static_mb)
	# Rounds 1-2 warm static caches (palette, art, shaders); growth is judged from round 2 to the last.
	var first: Dictionary = maps[min(1, maps.size() - 1)]
	var last: Dictionary = maps[-1]
	var growth := {}
	for key in ["static_mb", "objects", "resources", "nodes", "orphans"]: growth[key] = last[key] - first[key]
	var leaking: bool = maps.size() > 2 and (growth.objects > 0 or growth.nodes > 0 or growth.orphans > 0)
	print("DYNAMIC_SWITCH_MEMORY ", JSON.stringify({"rounds":maps.size(), "peak_static_mb":peak,
		"farm_static_mb_last":farms[-1].static_mb, "map_static_mb_round2":first.static_mb, "map_static_mb_last":last.static_mb,
		"growth_after_round2":growth, "leaking":leaking}))
	quit(1 if leaking else 0)
