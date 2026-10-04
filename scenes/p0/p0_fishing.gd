class_name P0Fishing
extends Control
## One cast at the homestead pond (plan §6.5.1): wait → Bite! + Hook ring → tension reel → report.
## The server already drew the fish; this overlay only knows its rarity and whether it will break free.
## Emits `reel(outcome)` exactly once: "cancel" (line in), "escaped", or "landed" (the server turns a
## gated fish into "broke_free").

signal reel(outcome: String)
signal phase_changed(phase: String)

const GAUGE := preload("res://scenes/fishing/fishing_gauge.gd")
const BREAK_MS := {2: 1500.0, 3: 2000.0, 4: 3000.0}   # §6.5.2 broke-free moment by rarity

var ui: P0Ui
var phase := ""
var rarity := 1
var breaks := false
var _t := 0.0                 # ms in the current phase
var _bite_ms := 0.0
var _hook_ms := 2200.0
var _held := false
var _model: Dictionary = {}
var _tier: Dictionary = {}
var _acc := 0.0
var _gauge: Control
var _title: Label
var _sub: Label
var _btn: Button
var _ring: Control
var _done := false
## Dev playtests (P0_AUTO=1 / scripted shots): hook on the bite and keep the band on the fish.
static var auto_play := false

func _init(owner_ui: P0Ui, cast_event: Dictionary, view: Dictionary) -> void:
	ui = owner_ui
	rarity = int(cast_event.get("rarity", 1))
	breaks = cast_event.get("breaks", null) != null
	_bite_ms = float(cast_event.get("bite_in", 2000))
	_hook_ms = float(view.get("fishing", {}).get("cast", {}).get("hook_ms", 2200)) if view.get("fishing", {}).get("cast", null) is Dictionary else 2200.0
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.position = Vector2(-150, 100)
	card.custom_minimum_size = Vector2(300, 0)
	card.add_theme_stylebox_override("panel", ui._box(P0Ui.CARD, 14, P0Ui.EDGE, 1, Vector4(12, 8, 12, 8)))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = ui._label("Waiting for a bite…", 14, P0Ui.INK, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_sub = ui._label(P0Logic.protection_line(view), 9, P0Ui.INK2)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_sub)
	card.add_child(v)
	add_child(card)
	_btn = ui._pill_button("Line in · Energy back", false)
	_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_btn.position = Vector2(-95, -150)
	_btn.custom_minimum_size = Vector2(190, 40)
	_btn.pressed.connect(_on_button)
	add_child(_btn)
	_ring = _HookRing.new()
	_ring.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ring.position = Vector2(-60, -230)
	_ring.size = Vector2(120, 120)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	add_child(_ring)
	_set_phase("wait")

func _set_phase(p: String) -> void:
	phase = p
	_t = 0.0
	phase_changed.emit(p)

func _process(dt: float) -> void:
	if _done: return
	_t += dt * 1000.0
	match phase:
		"wait":
			if _t >= _bite_ms:
				_set_phase("bite")
				_title.text = "Bite!"
				_title.add_theme_font_size_override("font_size", 26)
				_title.add_theme_color_override("font_color", P0Ui.AMBER_D)
				_sub.text = "Tap Hook before the ring closes"
				_btn.text = "Hook"
				ui._style_button(_btn, P0Ui.AMBER, P0Ui.AMBER_D, 20)
				_btn.add_theme_color_override("font_color", Color.WHITE)
				_btn.add_theme_font_size_override("font_size", 16)
				_ring.visible = true
				Input.vibrate_handheld(60)
		"bite":
			if auto_play and _t > 400.0:
				_start_reel()
				return
			_ring.set_meta("pct", 1.0 - _t / _hook_ms)
			_ring.queue_redraw()
			if _t >= _hook_ms: _finish("escaped")
		"reel":
			_acc += dt * 1000.0
			var step_ms := float(FishingModel.data().step_ms)
			while _acc >= step_ms and _model.outcome == "playing":
				_acc -= step_ms
				if auto_play: _held = float(_model.fish) > float(_model.bar)
				FishingModel.step(_model, _held, _tier)
			_gauge.model = _model
			_gauge.feedback_active = true
			if breaks and _t >= float(BREAK_MS.get(rarity, 1500.0)):
				_finish("landed")   # the server answers broke_free (§6.1.2)
			elif _model.outcome == "caught":
				_finish("landed")
			elif _model.outcome == "escaped":
				_finish("escaped")

func _on_button() -> void:
	match phase:
		"wait": _finish("cancel")
		"bite": _start_reel()

func _start_reel() -> void:
	_set_phase("reel")
	_ring.visible = false
	_btn.visible = false
	_title.text = "Keep the fish in the green"
	_title.remove_theme_font_size_override("font_size")
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", P0Ui.INK)
	_sub.text = "Hold anywhere to lift the band · let go to drop"
	_tier = FishingModel.data().tiers[str(rarity)]
	_model = FishingModel.initial(randi())
	_gauge = GAUGE.new()
	_gauge.bar_size = float(_tier.bar_size)
	_gauge.fish_texture = P0Logic.icon("fish_sil")
	_gauge.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	# Anchored offsets (the overlay already has its full size here, so `position` would be absolute).
	_gauge.offset_left = -104
	_gauge.offset_right = -24
	_gauge.offset_top = -110
	_gauge.offset_bottom = 150
	add_child(_gauge)

func _gui_input(e: InputEvent) -> void:
	if phase != "reel": return
	if e is InputEventScreenTouch or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
		_held = e.pressed
		accept_event()

## Desktop / dev: space bar also holds the reel.
func _unhandled_key_input(e: InputEvent) -> void:
	if phase == "reel" and e is InputEventKey and e.keycode == KEY_SPACE: _held = e.pressed

func _finish(outcome: String) -> void:
	if _done: return
	_done = true
	reel.emit(outcome)
	queue_free()

class _HookRing extends Control:
	func _draw() -> void:
		var pct := clampf(float(get_meta("pct", 1.0)), 0.0, 1.0)
		var c := size * 0.5
		draw_arc(c, size.x * 0.5 - 4, 0, TAU, 64, Color(1, 1, 1, 0.5), 3.0, true)
		draw_arc(c, (size.x * 0.5 - 4) * (0.35 + 0.65 * pct), 0, TAU, 64, Color("e3b341"), 5.0, true)
