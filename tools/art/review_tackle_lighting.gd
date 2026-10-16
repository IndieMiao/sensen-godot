extends "review.gd"
## Fixed exposure/camera controls of the shipped room lights, Mobile/Vulkan.
func set_lamps(enabled: Array) -> void:
	for light in room.find_children("*", "Light3D", true, false):
		light.visible = String(light.name) in enabled

func run():
	output = ProjectSettings.globalize_path("res://../lighting/final")
	DirAccess.make_dir_recursive_absolute(output)
	layout = JSON.parse_string(FileAccess.get_file_as_string(KIT + "layout.json"))
	setup(); audit()
	check(room.get_node("WallLanternWarmth") is SpotLight3D, "Wall light directs its pool onto plaster")
	check(room.get_node("PendantWarmth") is SpotLight3D, "Pendant directs its pool onto worktop")
	check(room.get_node("CounterLanternWarmth") is OmniLight3D, "Counter lantern retains its local omni")
	for light in room.find_children("*", "Light3D", true, false):
		check(not light.shadow_enabled, "No extra shadow pass: " + String(light.name))
	pose(Vector3(0, 1.20, 0), 10.2)
	set_lamps([]); await capture("lamps-off")
	set_lamps(["WallLanternWarmth"]); await capture("wall-only")
	set_lamps(["PendantWarmth"]); await capture("pendant-only")
	set_lamps(["WallLanternWarmth", "PendantWarmth", "CounterLanternWarmth"])
	await capture("lamps-on")
	set_lamps([]); await capture("lamps-off-repeat")
	report.renderer = RenderingServer.get_current_rendering_method()
	report.adapter = RenderingServer.get_video_adapter_name()
	check(report.renderer == "mobile", "Controls rendered by the actual Mobile renderer")
	report.local_lights = layout.local_lights
	report.review_lighting = layout.review_lighting
	report.failures = report.checks.filter(func(c): return not c.passed)
	FileAccess.open(output + "/lighting-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("TACKLE_LIGHTING_QA ", report.checks.size(), " checks / ", report.failures.size(), " failures")
	get_tree().quit(0 if report.failures.is_empty() else 1)
