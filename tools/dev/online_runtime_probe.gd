extends Node

var scene: Node3D
var online: OnlineSpace
var account_index := 0
var space := "mine"
var duration := 18.0
var elapsed := 0.0
var connected_seconds := 0.0
var maximum_peers := 0
var frames := 0
var start_position := Vector3.ZERO
var maximum_motion := 0.0
var _move_at := 0.0
var _saved := false
var output := "user://online-probe"
var _disconnected_once := false
var _resume_room := ""
var _resume_verified := false

func _ready() -> void:
	Engine.max_fps = 60
	TranslationServer.set_locale("zh_CN")
	space = str(ProjectSettings.get_setting("sensen/network/probe_space", "mine"))
	account_index = int(ProjectSettings.get_setting("sensen/network/probe_account", 0))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--account="): account_index = arg.trim_prefix("--account=").to_int()
		if arg.begins_with("--space="): space = arg.trim_prefix("--space=")
		if arg.begins_with("--duration="): duration = arg.trim_prefix("--duration=").to_float()
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var bundled := "res://online_account_%d.json" % account_index
	var file := bundled if FileAccess.file_exists(bundled) else "res://output/online-2026-09-16/account-%d.json" % account_index
	var account: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	var base := "http://10.0.2.2:3163/v1" if OS.get_name() == "Android" else "http://127.0.0.1:3163/v1"
	Net.use_transport(ApiClient.make_http_transport(self), base)
	Net.client.token = str(account.token)
	Net.session.player_id = str(account.player)
	Net.online_available = true
	if not await Net.session.refresh():
		push_error("ONLINE_PROBE_REFRESH_FAILED")
		get_tree().quit(1)
		return
	var target := AppRouter.ONLINE_MINE if space == "mine" else AppRouter.STREET if space == "street" else AppRouter.FARM
	scene = AppRouter.push_instance(target, {"session": Net.session,
		"blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2))})
	online = scene.get("online")
	if space == "farm":
		var host_file := "res://online_host.json" if FileAccess.file_exists("res://online_host.json") else "res://output/online-2026-09-16/account-0.json"
		var host: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(host_file))
		online.join_args.farm_id = str(host.farm.id)
	online.start()
	start_position = (scene.get("mover") as PlayerMover).position
	print("ONLINE_PROBE_STARTED ", space, " ", account_index)

func _process(delta: float) -> void:
	if online == null or _saved: return
	elapsed += delta
	frames += 1
	if online.joined and not online.world.is_empty():
		if _disconnected_once and online.room == _resume_room: _resume_verified = true
		connected_seconds += delta
		maximum_peers = maxi(maximum_peers, online.members.size())
		var mover: PlayerMover = scene.get("mover")
		maximum_motion = maxf(maximum_motion, mover.position.distance_to(start_position))
		if account_index == 1 and space == "mine" and elapsed > 6 and not _disconnected_once and bool(ProjectSettings.get_setting("sensen/network/probe_reconnect", false)):
			_disconnected_once = true
			_resume_room = online.room
			online._disconnected("QA_TRANSPORT_DROP")
			return
		if elapsed >= _move_at:
			_move_at = elapsed + 2.0
			if space == "mine":
				# Real scene interactions: walk to a rock and let the shared one-second dig settle.
				var targets: Dictionary = scene.get("targets")
				var rocks := targets.keys().filter(func(id): return str(id).begins_with("rock_"))
				if not rocks.is_empty(): scene.call("select_target", str(rocks[0]))
				elif int(scene.call("current_floor")) < 3: scene.call("select_target", "down")
				else: scene.call("_attack")
			else:
				var target := start_position + Vector3(1.5 if int(elapsed / 2) % 2 == 0 else .2, 0, 0)
				mover.set_target_position(target)
	if elapsed >= duration: _finish()

func _finish() -> void:
	_saved = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var report := {"space": space, "account": account_index, "elapsed": elapsed, "connected_seconds": connected_seconds,
		"maximum_remote_players": maximum_peers, "maximum_motion_m": maximum_motion, "room": online.room,
		"hp": online.self_state.get("hp", -1), "frames": frames, "crowd_rigs": online.crowd.rigs.size(),
		"floor": online.floor_number, "bag_sequence": Net.session.state.get("bag", {}).get("sequence", -1),
		"average_process_fps": frames / maxf(elapsed, .001),
		"reconnect_attempted": _disconnected_once, "reconnect_restored_instance": _resume_verified,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	var report_path := output.path_join("%s-%d.json" % [space, account_index])
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ONLINE_PROBE_RESULT ", JSON.stringify(report))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join("%s-%d.png" % [space, account_index]))
	online.stop()
	get_tree().quit(0 if connected_seconds > 3 and maximum_peers > 0 and maximum_motion > .25 else 1)
