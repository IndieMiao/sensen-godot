extends Node
var current: Node
var session: FarmSession
var elapsed := 0.0
var ready_for_input := false
var qa_travel: Button
var in_street := false
const OUTPUT := "user://voice-proof"
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	Localization.select_language("zh_CN")
	var account: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://voice_account.json"))
	Net.use_transport(ApiClient.make_http_transport(self), "http://10.0.2.2:3170/v1")
	Net.client.token = str(account.token)
	session = Net.session
	session.player_id = str(account.player)
	Net.online_available = true
	assert(await session.refresh())
	current = AppRouter.push_instance(AppRouter.FARM, {"session": session})
	await get_tree().create_timer(1.5).timeout
	await current.online._open_party()
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	qa_travel = GameUi.button("map-pin", "切换场景测试", "Switch QA scene")
	qa_travel.name = "VoiceQaTravel"
	qa_travel.position = Vector2(20, 66)
	qa_travel.size = Vector2(190, 36)
	qa_travel.pressed.connect(_travel)
	layer.add_child(qa_travel)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	ready_for_input = true
func _travel() -> void:
	if in_street: return
	current.online.consume_back()
	current = AppRouter.push_instance(AppRouter.STREET, {"session": session})
	in_street = true
	await get_tree().create_timer(1.5).timeout
	await current.online._open_party()
func _rect(c: Control) -> Array:
	var r := get_viewport().get_screen_transform() * c.get_global_rect()
	return [r.position.x, r.position.y, r.size.x, r.size.y]
func _process(delta: float) -> void:
	elapsed += delta
	if not ready_for_input or elapsed < .15: return
	elapsed = 0
	var controls := []
	for c in current.online.hud.find_children("*", "BaseButton", true, false):
		if c.is_visible_in_tree(): controls.append({"name": str(c.name), "text": c.text, "disabled": c.disabled, "rect": _rect(c)})
	controls.append({"name": str(qa_travel.name), "rect": _rect(qa_travel), "disabled": false})
	var diagnostic := {}
	if Engine.has_singleton("GodotVoice"): diagnostic = JSON.parse_string(Engine.get_singleton("GodotVoice").call("diagnostics"))
	var status := {"state": Voice.state, "error": Voice.error, "active": Voice.active(), "microphone": Voice.microphone, "listening": Voice.listening,
		"participants": Voice.participants, "controls": controls, "diagnostics": diagnostic, "street": in_street, "native_session": Voice._native_id}
	FileAccess.open(OUTPUT.path_join("state.json"), FileAccess.WRITE).store_string(JSON.stringify(status))
