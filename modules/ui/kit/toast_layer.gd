class_name ToastLayer
extends Control
## Non-modal toast queue (SGODOT-211, WP7-B F-08 §3). Never blocks input except the toast itself (tap to
## dismiss early); sits under the HUD so it never covers the main action key, quick bar or recovery
## entries. Duration = MOTION_TOAST_BASE_MS + MOTION_TOAST_PER20_CHARS_MS per 20 characters, capped at
## MOTION_TOAST_MAX_MS. One visible at a time; identical text within 1 s merges into "×2"; refusals and
## errors jump ahead of successes; at most MAX_QUEUE waiting, oldest dropped.
## Final placement and colours follow WP2 (D-01); confirmation-type feedback uses an info sheet instead.

signal shown(text: String, severity: Severity)

enum Severity { SUCCESS, INFO, REFUSED, ERROR }

const MAX_QUEUE := 3
const MERGE_MS := 1000

## Distance from the top of the layer; default sits 8 px under the HUD.
var top_margin: float = UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + UiTokens.SPACE_WITHIN + 2.0

var _queue: Array[Dictionary] = []
var _current := {}
var _left := 0.0
var _clock_ms := 0
var _panel: PanelContainer
var _label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.theme_type_variation = UiTokens.PANEL_TOAST_PANEL
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	_label = UiKit.label("", UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SURFACE_RAISED)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_label)
	add_child(_panel)

static func duration_ms(text: String) -> float:
	var ms := UiTokens.MOTION_TOAST_BASE_MS + UiTokens.MOTION_TOAST_PER20_CHARS_MS * floorf(text.length() / 20.0)
	return minf(ms, UiTokens.MOTION_TOAST_MAX_MS)

func show_toast(text: String, severity := Severity.INFO) -> void:
	if text == "": return
	# Merge repeats of what is showing or waiting.
	var live: Array = _queue.duplicate()
	if not _current.is_empty(): live.push_front(_current)
	for item in live:
		if item.text == text and _clock_ms - int(item.at) <= MERGE_MS:
			item.count += 1
			item.at = _clock_ms
			if is_same(item, _current):
				_left = duration_ms(text) / 1000.0
				_render()
			return
	var entry := {text = text, severity = severity, count = 1, at = _clock_ms}
	if severity >= Severity.REFUSED:
		var i := 0
		while i < _queue.size() and int(_queue[i].severity) >= Severity.REFUSED: i += 1
		_queue.insert(i, entry)
	else:
		_queue.append(entry)
	while _queue.size() > MAX_QUEUE:
		# Drop the oldest entry of the least important kind.
		var victim := 0
		for i in _queue.size():
			var a: Dictionary = _queue[i]
			var v: Dictionary = _queue[victim]
			if int(a.severity) < int(v.severity) or (int(a.severity) == int(v.severity) and int(a.at) < int(v.at)): victim = i
		_queue.remove_at(victim)
	if _current.is_empty(): _next()

func dismiss() -> void:
	_current = {}
	_next()

func current_text() -> String:
	if _current.is_empty(): return ""
	return _current.text if int(_current.count) == 1 else "%s ×%d" % [_current.text, _current.count]

func queued() -> Array[Dictionary]: return _queue

func _process(delta: float) -> void: advance(delta)

## Drive time explicitly (tests call this directly).
func advance(delta: float) -> void:
	_clock_ms += int(delta * 1000.0)
	if _current.is_empty(): return
	_left -= delta
	if _left <= 0.0: dismiss()

func _next() -> void:
	if _queue.is_empty():
		_current = {}
		if _panel: _panel.visible = false
		return
	_current = _queue.pop_front()
	_current.at = _clock_ms
	_left = duration_ms(_current.text) / 1000.0
	_render()
	shown.emit(_current.text, _current.severity)

func _render() -> void:
	if _panel == null: return
	_label.text = current_text()
	_panel.visible = true
	var w := minf(UiTokens.SIZE_TOAST_W, size.x - UiTokens.SPACE_PAGE * 2.0)
	_panel.custom_minimum_size = Vector2(w, UiTokens.SIZE_TOAST_MIN_H)
	_panel.size = Vector2(w, 0)
	_panel.position = Vector2((size.x - w) * 0.5, top_margin)

func _on_panel_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		dismiss()
		accept_event()
