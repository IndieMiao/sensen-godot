extends Control
## Observe actual party UI while the host supplies Android touch input.

var online: OnlineSpace
var world_clicks := 0
var commands := 0
var elapsed := 0.0
var directory := {"protocol": 1, "travel_version": 1, "party": {"code": "COPY-QA-123", "leader": "self", "members": ["self", "other"]}, "roster": []}
var open_button: Button
const OUTPUT := "user://party-panel-proof"

func _draw() -> void:
	draw_rect(get_viewport_rect(), GameUi.MINT)

func _ready() -> void:
	Localization.select_language("zh_CN")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var world := Button.new()
	world.name = "WorldSurface"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.flat = true
	world.pressed.connect(func(): world_clicks += 1)
	add_child(world)
	open_button = GameUi.button("users-round", "打开队伍面板", "Open party")
	open_button.position = Vector2(24, 28)
	open_button.size = Vector2(230, 44)
	add_child(open_button)
	online = OnlineSpace.new()
	online.kind = "farm"
	online.session = FarmSession.new(ApiClient.new("https://example.invalid/v1", func(method, _path, _headers, _body):
		if method != "GET": commands += 1
		return ApiClient.Response.new(true, 200, directory)))
	online.session.player_id = "self"
	add_child(online)
	online.set_process(false)
	online.badge.hide()
	open_button.pressed.connect(online._open_party)
	DisplayServer.clipboard_set("unchanged")
	online._open_party()

func _rect(control: Control) -> Array:
	var rect := get_viewport().get_screen_transform() * control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < .1: return
	elapsed = 0
	var data := {"open": is_instance_valid(online.panel), "open_button": _rect(open_button), "world_clicks": world_clicks, "commands": commands,
		"clipboard": DisplayServer.clipboard_get(), "toast": is_instance_valid(online._copy_toast) and online._copy_toast.visible}
	if data.open:
		var close := online.panel.find_child("CloseParty", true, false) as Control
		var copy := online.panel.find_child("CopyInviteCode", true, false) as Control
		var scroll := online.panel.find_child("PartyScroll", true, false) as ScrollContainer
		if close == null or copy == null or scroll == null: return
		data.close = _rect(close)
		data.copy = _rect(copy)
		data.panel = _rect(online.panel)
		data.scroll = scroll.scroll_vertical
		data.outside = _rect(self)
	if data.toast:
		data.toast_text = (online._copy_toast.get_child(0) as Label).text
		data.toast_rect = _rect(online._copy_toast)
	FileAccess.open(OUTPUT.path_join("state.json"), FileAccess.WRITE).store_string(JSON.stringify(data))
