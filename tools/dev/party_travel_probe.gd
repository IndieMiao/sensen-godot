extends Node

var current: Node
var original: Node
var session: FarmSession
var base := ""
var checks: Array[String] = []
var destination_root := "user://party-travel-proof"

func _ready() -> void:
	get_tree().create_timer(90).timeout.connect(func():
		push_error("PARTY_TRAVEL_QA_TIMEOUT")
		get_tree().quit(1))
	call_deferred("_run")

func _run() -> void:
	ProjectSettings.set_setting("sensen/network/online_qa", true)
	TranslationServer.set_locale("zh_CN")
	base = "http://10.0.2.2:3165" if OS.get_name() == "Android" else "http://127.0.0.1:3165"
	var account_path := "res://party_account.json" if FileAccess.file_exists("res://party_account.json") else "res://output/party-travel-2026-09-16/private/account.json"
	var account: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(account_path))
	Net.use_transport(ApiClient.make_http_transport(self), base + "/v1")
	Net.client.token = str(account.token)
	session = Net.session
	session.player_id = str(account.player)
	Net.online_available = true
	assert(await session.refresh())
	await _phase("farm")
	await _phase("deny")
	FarmRegions.save_choice("los_angeles")
	original = AppRouter.push_instance(AppRouter.FARM, {"session": session})
	current = original
	await _connected()
	var choice_before := FarmChoice.load().duplicate(true)
	var farm_before := session.farm_id
	var region_before := session.region_id
	await current.online._open_party()
	await current.online.request_travel("", "leader")
	assert(current.online.error == "PARTY_ACCESS_REQUIRED")
	checks.append("private farm requires owner opt-in")
	assert(AppRouter.top_instance() == original)
	await _phase("allow")
	await current.online._refresh_party()
	await current.online.request_travel("", "leader")
	await _arrived("farm")
	assert(current.visitor and current.bp.layout_patch_id == "sh_b")
	assert(int(current.online.join_args.channel) == 3)
	assert(session.farm_id == farm_before and session.region_id == region_before)
	assert(FarmChoice.load() == choice_before)
	checks.append("cross-region private farm, owner identity and choices preserved")
	await _capture("farm")
	await _phase("street")
	await current.online._open_party()
	await current.online.request_travel("", "leader")
	await _arrived("street")
	assert(current.layout.source.layout_patch_id == "sh_b")
	assert(int(current.online.join_args.channel) == 7)
	checks.append("leader street layout and channel loaded")
	await _capture("street")
	AppRouter.pop_instance()
	current = original
	await _connected()
	assert(AppRouter.top_instance() == original and original.visible)
	assert(current.online.room.begins_with("farm:" + farm_before))
	assert(FarmChoice.load() == choice_before)
	checks.append("return to own farm reconnects and restores view")
	await _phase("fresh_member")
	AppRouter.open_instance(AppRouter.ONLINE_MINE, {"session": session})
	await _arrived("mine")
	var former := str(current.online.room)
	await _phase("mine3")
	await current.online._open_party()
	current.online.request_travel("", "leader")
	var limit := Time.get_ticks_msec() + 10000
	while is_instance_valid(current) and current.online._travel_confirmation == null and Time.get_ticks_msec() < limit:
		await get_tree().process_frame
	assert(current.online._travel_confirmation != null)
	await _capture("confirmation")
	current.online._travel_confirmation.confirmed.emit()
	await _arrived("mine")
	assert(current.online.room != former and current.online.floor_number == 3)
	assert(current.online.count == 2)
	checks.append("explicit re-entry joins leader floor three and replaces former mine")
	await _capture("mine3")
	AppRouter.pop_instance()
	current = original
	await _connected()
	await _phase("farm")
	await current.online._open_party()
	await current.online.request_travel("", "leader")
	await _arrived("farm")
	await _phase("deny")
	limit = Time.get_ticks_msec() + 10000
	while AppRouter.top_instance() != original and Time.get_ticks_msec() < limit: await get_tree().process_frame
	assert(AppRouter.top_instance() == original)
	current = original
	await _connected()
	assert(FarmChoice.load() == choice_before)
	checks.append("revoked farm permission returns visitor safely")
	await _capture("returned")
	var result := {"passed": true, "checks": checks, "farm_id": farm_before, "region": session.region_id}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination_root))
	FileAccess.open(destination_root.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("PARTY_TRAVEL_PROBE_OK ", JSON.stringify(result))
	while AppRouter.instance_depth() > 0: AppRouter.pop_instance()
	get_tree().quit()

func _connected() -> void:
	var limit := Time.get_ticks_msec() + 15000
	while is_instance_valid(current) and (current.online == null or not current.online.joined or current.online.world.is_empty()) and Time.get_ticks_msec() < limit:
		await get_tree().process_frame
	assert(current.online.joined and not current.online.world.is_empty())

func _arrived(kind: String) -> void:
	var source := current
	var limit := Time.get_ticks_msec() + 15000
	while (AppRouter._navigation_pending or AppRouter.top_instance() == source) and Time.get_ticks_msec() < limit:
		await get_tree().process_frame
	current = AppRouter.top_instance()
	assert(current != source)
	await _connected()
	assert(current.online.kind == kind)

func _phase(phase: String) -> void:
	var request := ApiClient.new(base, ApiClient.make_http_transport(self))
	var response := await request.request("POST", "/qa/phase", {"phase": phase})
	assert(response.is_success())

func _capture(label: String) -> void:
	assert(current.cam.current and get_viewport().get_camera_3d() == current.cam)
	assert(current.cam.position.is_finite())
	assert(current.cam.is_position_in_frustum(current.player.global_position))
	if DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination_root))
	get_viewport().get_texture().get_image().save_png(destination_root.path_join(label + ".png"))
