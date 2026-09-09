extends Node

func _enter_tree() -> void:
	Net.booting = true
	Net.booted_once = true

func _ready() -> void:
	var base := OS.get_environment("SENSEN_JOURNEY_BASE")
	if OS.is_debug_build() and OS.has_feature("journey_device_qa"):
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--journey-base="): base = arg.trim_prefix("--journey-base=")
	var emulator_loopback := OS.is_debug_build() and OS.has_feature("journey_device_qa") and base.begins_with("http://10.0.2.2:")
	if not base.begins_with("http://127.0.0.1:") and not emulator_loopback:
		push_error("Launch using node tools/dev/run_journey.mjs")
		get_tree().quit(2)
		return
	var http := ApiClient.make_http_transport(Net)
	if "--journey-smoke" in OS.get_cmdline_user_args():
		var identity := Crypto.new().generate_random_bytes(16).hex_encode()
		Net.use_transport(func(method, url, headers, body):
			if str(url).ends_with("/auth/anonymous"): body = JSON.stringify({"install_key": identity})
			return await http.call(method, url, headers, body), base)
	else:
		Net.use_transport(http, base)
	Net.booting = false
	if not await Net.boot():
		push_error("Journey playtest server could not be reached")
		get_tree().quit(1)
		return
	if OS.is_debug_build() and OS.has_feature("journey_device_qa"):
		var observer := load("res://tools/dev/journey_device_observer.gd").new() as Node
		get_tree().root.add_child(observer)
	if "--journey-smoke" in OS.get_cmdline_user_args():
		var probe := load("res://tools/dev/journey_smoke.gd").new() as Node
		get_tree().root.add_child(probe)
		return
	if not Net.session.farm_id.is_empty():
		FarmRegions.save_choice(Net.session.region_id)
		FarmChoice.save(Net.session.layout_patch_id, Net.session.blueprint_revision, Net.session.location)
		AppRouter.go_to_map()
		return
	AppRouter._go_to(AppRouter.CITY_SELECT)
