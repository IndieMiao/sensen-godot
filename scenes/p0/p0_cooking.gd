class_name P0Cooking
extends Control
## One pot on the stove (plan §7.2.4, COOK-3): countdown ring around the pot, a heat ring with a needle
## that turns once from 12 o'clock; tap anywhere while the needle is in the gold arc. Only the first tap
## of each ring counts. Emits `finished(taps)` with tap times in ms since the fire started; leaving early
## emits `left()` (the pot keeps cooking and comes out Plain).

signal finished(taps: Array)
signal left()

var ui: P0Ui
var stove: Dictionary = {}
var dish_name := "?"
var teach := false
var _start_ms := 0
var _taps: Array = []
var _judged := {}            # heat index -> true / false
var _feedback: Label
var _feedback_left := 0.0
var _clock: Label
var _done := false
## Dev playtests: tap in the middle of each gold arc.
static var auto_play := false

func _init(owner_ui: P0Ui, stove_view: Dictionary, name_text: String, first_fire: bool) -> void:
	ui = owner_ui
	stove = stove_view
	dish_name = name_text
	teach = first_fire
	_start_ms = Time.get_ticks_msec() - int(float(stove.get("elapsed", 0)))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var pot := TextureRect.new()
	pot.texture = P0Logic.icon("pot")
	pot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pot.set_anchors_preset(Control.PRESET_CENTER)
	pot.position = Vector2(-46, -26)
	pot.size = Vector2(92, 92)
	pot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pot)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-150, 96)
	top.custom_minimum_size = Vector2(300, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := ui._label("Stove · Cooking", 10, P0Ui.PAPER, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(t)
	var dn := ui._label(dish_name, 16, P0Ui.PAPER, true)
	dn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(dn)
	add_child(top)
	_clock = ui._label("0:05", 14, P0Ui.INK, true)
	_clock.set_anchors_preset(Control.PRESET_CENTER)
	_clock.position = Vector2(-30, 110)
	_clock.custom_minimum_size = Vector2(60, 0)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.add_theme_stylebox_override("normal", ui._box(P0Ui.PAPER, 10, P0Ui.EDGE, 1, Vector4(6, 2, 6, 2)))
	add_child(_clock)
	_feedback = ui._label("", 16, P0Ui.AMBER_D, true)
	_feedback.set_anchors_preset(Control.PRESET_CENTER)
	_feedback.position = Vector2(-120, -200)
	_feedback.custom_minimum_size = Vector2(240, 0)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_color_override("font_outline_color", P0Ui.PAPER)
	_feedback.add_theme_constant_override("outline_size", 6)
	add_child(_feedback)
	if teach:
		var hint := ui._label("Tap when the needle hits gold!", 11, P0Ui.PAPER, true)
		hint.set_anchors_preset(Control.PRESET_CENTER)
		hint.position = Vector2(-120, 150)
		hint.custom_minimum_size = Vector2(240, 0)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(hint)
	var leave := ui._pill_button("Leave · it keeps cooking", false)
	leave.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	leave.position = Vector2(-100, -120)
	leave.custom_minimum_size = Vector2(200, 36)
	leave.pressed.connect(func():
		if _done: return
		_done = true
		left.emit()
		queue_free())
	add_child(leave)

func elapsed() -> float:
	return float(Time.get_ticks_msec() - _start_ms)

func _process(dt: float) -> void:
	if _done: return
	var e := elapsed()
	var total := float(stove.get("ms", 5000))
	_clock.text = P0Logic.duration(maxf(0.0, total - e))
	if _feedback_left > 0.0:
		_feedback_left -= dt
		if _feedback_left <= 0.0: _feedback.text = ""
	var heats: Array = stove.get("heats", [])
	if auto_play:
		for i in heats.size():
			var h: Dictionary = heats[i]
			if not _judged.has(i) and e >= float(h.at) + (float(h.gold) + float(h.width) * 0.5) * float(h.spin):
				var tap := InputEventMouseButton.new()
				tap.button_index = MOUSE_BUTTON_LEFT
				tap.pressed = true
				_gui_input(tap)
	# A ring that ran out without a tap is a miss.
	for i in heats.size():
		var h: Dictionary = heats[i]
		if not _judged.has(i) and e > float(h.at) + float(h.spin):
			_judged[i] = false
			_say("Missed · still cooking", P0Ui.INK2)
	queue_redraw()
	if e >= total + 250.0:
		_done = true
		finished.emit(_taps)
		queue_free()

func _gui_input(ev: InputEvent) -> void:
	var pressed: bool = P0Ui.is_tap(ev)
	if not pressed or _done: return
	accept_event()
	var e := elapsed()
	var heats: Array = stove.get("heats", [])
	for i in heats.size():
		var h: Dictionary = heats[i]
		if _judged.has(i) or e < float(h.at) or e > float(h.at) + float(h.spin): continue
		_taps.append(roundi(e))
		var hit := P0Logic.heat_hit(h, e)
		_judged[i] = hit
		if hit:
			_say("Nice heat! ★", P0Ui.AMBER_D)
			Input.vibrate_handheld(40)
		else:
			_say("Missed · still cooking", P0Ui.INK2)
		return

func _say(text: String, color: Color) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", color)
	_feedback_left = 1.2

func _draw() -> void:
	var c := size * 0.5 + Vector2(0, 20)
	var e := elapsed()
	var total := float(stove.get("ms", 5000))
	# dim the world, then the pot plate (the pot itself is a TextureRect child on top)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.184, 0.227, 0.2, 0.35))
	draw_circle(c + Vector2(0, 6), 74, Color(0.18, 0.23, 0.2, 0.18))
	draw_circle(c, 70, Color("fbf8f1"))
	draw_arc(c, 70, 0, TAU, 72, Color("e1dac8"), 2.0, true)
	# cooking countdown ring
	draw_arc(c, 82, 0, TAU, 96, Color(1, 1, 1, 0.35), 6.0, true)
	var pct := clampf(e / maxf(1.0, total), 0.0, 1.0)
	draw_arc(c, 82, -PI * 0.5, -PI * 0.5 + TAU * pct, 96, Color("7fc66a"), 6.0, true)
	# heat rings: show 1 s early (grow in), the needle turns once over `spin`
	for i in (stove.get("heats", []) as Array).size():
		var h: Dictionary = stove.heats[i]
		var at := float(h.at)
		var spin := float(h.spin)
		if e < at - 1000.0 or e > at + spin + 350.0: continue
		var rc := c + Vector2(0, -150)
		var r := 46.0 * clampf(1.0 - (at - e) / 1000.0, 0.4, 1.0)
		draw_circle(rc, r + 8, Color(0.98, 0.97, 0.94, 0.95))
		draw_arc(rc, r, 0, TAU, 64, Color("e1dac8"), 7.0, true)
		var g0 := -PI * 0.5 + TAU * float(h.gold)
		draw_arc(rc, r, g0, g0 + TAU * float(h.width), 48, Color("e3b341"), 9.0, true)
		if e >= at:
			var turn := clampf((e - at) / spin, 0.0, 1.0)
			var ang := -PI * 0.5 + TAU * turn
			draw_line(rc, rc + Vector2(cos(ang), sin(ang)) * (r + 4), Color("2f3a33"), 3.0, true)
			draw_circle(rc, 5, Color("2f3a33"))
		if _judged.has(i):
			draw_circle(rc + Vector2(r * 0.7, -r * 0.7), 9, Color("e3b341") if _judged[i] else Color("c4c2ba"))
