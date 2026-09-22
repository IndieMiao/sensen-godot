extends Node

var current: Node
var session: FarmSession
var account: Dictionary
var base := ""
var checks: Array[String] = []
var output := "user://appearance-proof"

func _ready() -> void:
	get_tree().create_timer(100).timeout.connect(func():
		push_error("APPEARANCE_QA_TIMEOUT")
		get_tree().quit(1))
	call_deferred("_run")

func _run() -> void:
	TranslationServer.set_locale("zh_CN")
	ProjectSettings.set_setting("sensen/network/online_qa", true)
	base = "http://10.0.2.2:3166" if OS.get_name() == "Android" else "http://127.0.0.1:3166"
	account = JSON.parse_string(FileAccess.get_file_as_string("res://appearance_account.json"))
	var local := Avatar.slot_table.default_config()
	local.slots[&"cloth"] = "cloth28"
	local.slots[&"hairHat"] = "hairhat41"
	local.slots[&"shoes"] = "shoes3"
	assert(Avatar.save_outfit(local) == OK)
	Net.use_transport(ApiClient.make_http_transport(self), base + "/v1")
	Net.client.token = account.token
	session = Net.session
	session.player_id = account.player
	Net.online_available = true
	assert(await session.refresh())
	current = AppRouter.push_instance(AppRouter.FARM, {"session": session})
	await _connected()
	for phase in ["farm", "street", "mine3"]:
		await _request("POST", "/qa/phase", {"phase": phase})
		await _travel()
		await _outfit(account.leader, account.looks[0])
		checks.append(phase + " actual remote outfit")
		await _capture(phase)
	await _request("POST", "/qa/phase", {"phase": "change"})
	await _outfit(account.leader, account.looks[1])
	checks.append("live clothing/hair/shoes/accessories change and optional bag removal")
	await _capture("changed")
	local.slots[&"cloth"] = "cloth11"
	assert(Avatar.save_outfit(local) == OK)
	var until := Time.get_ticks_msec() + 8000
	var published := false
	while Time.get_ticks_msec() < until:
		var status := await _request("GET", "/qa/status")
		if status.get("appearance", {}).get("slots", {}).get("cloth") == "cloth11":
			published = true
			break
		await get_tree().create_timer(.2).timeout
	assert(published)
	assert(current.rig.current_config().slots.cloth == "cloth11")
	checks.append("saved local outfit updates local rig and server without re-entry")
	var room: String = current.online.room
	current.online._disconnected("QA_TRANSPORT_DROP")
	await _connected()
	assert(current.online.room == room and current.online.floor_number == 3)
	await _outfit(account.leader, account.looks[1])
	checks.append("reconnect restores outfit and original mine floor")
	await _request("POST", "/qa/phase", {"phase": "newcomer"})
	await _outfit(account.newcomer, account.looks[0])
	checks.append("later arrival has independent outfit")
	await _capture("newcomer")
	assert(Avatar.load_outfit().slots.cloth == "cloth11")
	var result := {"passed": true, "checks": checks, "remote_count": current.online.members.size()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("APPEARANCE_PROBE_OK ", JSON.stringify(result))
	while AppRouter.instance_depth() > 0: AppRouter.pop_instance()
	get_tree().quit()

func _travel() -> void:
	var old := current
	await current.online.request_travel("", "leader")
	var until := Time.get_ticks_msec() + 12000
	while (AppRouter._navigation_pending or AppRouter.top_instance() == old) and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	current = AppRouter.top_instance()
	assert(current != old)
	await _connected()

func _connected() -> void:
	var until := Time.get_ticks_msec() + 12000
	while (not current.online.joined or current.online.world.is_empty()) and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	assert(current.online.joined)

func _outfit(player: String, expected: Dictionary) -> void:
	var until := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < until:
		for entry in current.online.crowd.rigs:
			var actor: Dictionary = current.online.crowd.actors.get(entry.id, {})
			if actor.is_empty() or actor.member.player != player or entry.rig.is_busy(): continue
			var slots: Dictionary = entry.rig.current_config().slots
			if slots == OnlineAppearance.config(expected).slots:
				assert(entry.rig.visible)
				return
		await get_tree().process_frame
	assert(false, "Remote rig did not assemble the expected outfit")

func _request(method: String, path: String, body := {}) -> Dictionary:
	var response := await ApiClient.new(base, ApiClient.make_http_transport(self)).request(method, path, body)
	assert(response.is_success())
	return response.json

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await get_tree().create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
