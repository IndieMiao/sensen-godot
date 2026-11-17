extends Control
const Session = preload("res://session.gd")
const Broker = preload("res://broker.gd")
const IOS = preload("res://modules/net/voice_backend_ios.gd")
var session
var status: Label
var code: LineEdit
var join_button: Button
var mic_button: Button
var listen_button: Button
var peers: OptionButton
var mute_button: Button
var block_button: Button
var settings_button: Button
var lease_button: CheckButton
var identities: Array[String] = []
var config: Dictionary = {}
var _refresh_at := 0

func _ready() -> void:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string("res://harness_config.json")) == OK and parser.data is Dictionary:
		config = parser.data
	if (OS.get_name() == "iOS" and config.get("client") != "ios-a") or (OS.get_name() == "Android" and config.get("client") != "android-b"):
		config["validation_only"] = true
	var background := ColorRect.new()
	background.color = Color("F5F2E8"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(background)
	var margins := MarginContainer.new(); margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margins.add_theme_constant_override("margin_top", 230 if OS.get_name() == "iOS" else 24); margins.add_theme_constant_override("margin_left", 16)
	margins.add_theme_constant_override("margin_right", 16); margins.add_theme_constant_override("margin_bottom", 18); add_child(margins)
	var scroll := ScrollContainer.new(); margins.add_child(scroll)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8); scroll.add_child(box)
	var title := Label.new(); title.text = "Voice media QA"; title.add_theme_color_override("font_color", Color("243B30")); box.add_child(title)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("243B30")); box.add_child(status)
	code = LineEdit.new(); code.secret = true; code.placeholder_text = "Test code"; code.max_length = 128; box.add_child(code)
	if OS.get_name() == "Android": _button(box, "Start media QA", func(): session.arm_android())
	join_button = _button(box, "Join", func(): session.join(code.text))
	_button(box, "Leave", func(): session.leave())
	mic_button = _button(box, "Mic: off", func(): session.set_microphone(not session.microphone))
	listen_button = _button(box, "Listen: on", func(): session.set_listening(not session.listening))
	peers = OptionButton.new(); peers.item_selected.connect(func(_index): _refresh()); box.add_child(peers)
	mute_button = _button(box, "Mute selected peer", func(): session.set_muted(_peer(), not session.muted.has(_peer())))
	block_button = _button(box, "Block selected peer", func(): session.set_blocked(_peer(), not session.blocked.has(_peer())))
	settings_button = _button(box, "Microphone settings", func(): session.open_settings())
	lease_button = CheckButton.new(); lease_button.text = "Renew test lease"; lease_button.button_pressed = true
	lease_button.toggled.connect(func(on): session.renew_enabled = on); box.add_child(lease_button)
	_button(box, "Test native expiry (5s)", func(): session.test_native_expiry())
	var note := Label.new(); note.text = "GENSEN_VOICE_MEDIA_QA_V1\nTest code and voice grants stay in memory.\nNo game account or recording."; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.add_theme_color_override("font_color", Color("243B30")); box.add_child(note)
	var transport = Broker.new(); transport.origin = str(config.get("broker_origin", "")); transport.validation_only = bool(config.get("validation_only", true)); add_child(transport)
	session = Session.new()
	var backend: Object = IOS.new() if OS.get_name() == "iOS" else null
	if OS.get_name() == "Android" and Engine.has_singleton("GodotVoice"): backend = Engine.get_singleton("GodotVoice")
	session.configure(config, backend, transport); add_child(session); session.changed.connect(_refresh)
	_refresh()

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new(); button.text = text; button.custom_minimum_size.y = 42; button.pressed.connect(action); parent.add_child(button); return button
func _peer() -> String:
	return identities[peers.selected] if peers.selected >= 0 and peers.selected < identities.size() else ""
func _process(_delta: float) -> void:
	if session and Time.get_ticks_msec() >= _refresh_at:
		_refresh_at = Time.get_ticks_msec() + 250; _refresh()
func _refresh() -> void:
	if session == null: return
	var old := _peer(); identities.clear(); peers.clear()
	for person in session.participants:
		if not person is Dictionary or person.get("local", false): continue
		var identity := str(person.get("id", ""))
		if identity.is_empty(): continue
		identities.append(identity); peers.add_item(str(person.get("name", "Peer")).substr(0,32))
	if identities.has(old): peers.select(identities.find(old))
	var supported: bool = session.supported()
	join_button.disabled = not supported or session.state != "idle" or session._inflight
	mic_button.disabled = session.state != "connected"; listen_button.disabled = mic_button.disabled
	mic_button.text = "Mic: on" if session.microphone else "Mic: off"
	listen_button.text = "Listen: on" if session.listening else "Listen: off"
	mute_button.disabled = _peer().is_empty() or session.state != "connected"
	block_button.disabled = mute_button.disabled
	mute_button.text = "Unmute selected peer" if session.muted.has(_peer()) else "Mute selected peer"
	block_button.text = "Unblock selected peer" if session.blocked.has(_peer()) else "Block selected peer"
	settings_button.disabled = not supported
	lease_button.set_pressed_no_signal(session.renew_enabled)
	if config.get("validation_only", true): status.text = "Build validation only. Join is disabled."
	elif not supported: status.text = "Use Start media QA above. Restart the app after Stop or expiry."
	else: status.text = "State: " + session.state + ("\n" + session.error if not session.error.is_empty() else "")
func _notification(what: int) -> void:
	if session == null: return
	if what == NOTIFICATION_APPLICATION_PAUSED: session.foreground(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED: session.foreground(true)
	elif what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST]: session.leave(); code.text = ""; get_tree().quit()
