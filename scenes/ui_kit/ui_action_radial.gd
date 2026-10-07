class_name UiActionRadial
extends Control
## Action radial (SGODOT-221, LOCK-03; RadialPetal 1122:79385, BAR-2 482:23): the switch key fans the four
## actions out from the character. Full-screen overlay: the modal scrim (color/scrimModal) dims the scene and
## blocks the joystick; tapping anywhere off a petal closes it (不知火舞 2026-10-07, WP7 Q7).
##   options: [{id, name, icon: Texture2D, available: bool, reason}] in fan order (Farming, Fishing, Mining,
##   Combat); `selected` is the current action. Available petal → picked(id) then closed. Unavailable petals stay
##   grey with the lock badge and their reason under the name (`Fishing · No water nearby`); tapping one does
##   nothing. open_at(point) places the fan around the character's screen point; it opens to the right and
##   mirrors to the left when the character is right of centre, so labels stay on screen.

signal picked(id: String)
signal closed

const LOCK_GLYPH := preload("res://assets/p0/icons/lock.svg")

# Fan geometry measured from BAR-2 482:23: petal centres on a 100 px arc around the character at -66°, -22°,
# 22° and 66° (screen y down), the selected petal joined to the character by a short connector.
const _FAN_RADIUS := 100.0
const _FAN_ANGLES := [-66.0, -22.0, 22.0, 66.0]
const _LABEL_GAP := 6.0            # RadialPetal: petal 52, then the label 6 px to its side
const _LABEL_PAD_X := 10.0         # label padding 5 / 10
const _LABEL_PAD_Y := 5.0
const _LOCK_AT := Vector2(36, -2)  # lock badge 18 at (36, -2) of the 52 px petal
const _CONNECTOR_W := 3.0          # BAR-2 connector from the selected petal towards the character

var options: Array = []: set = set_options
var selected := "": set = set_selected

var _scrim: ColorRect
var _layer: Control
var _petals: Array[Button] = []
var _labels: Array[PanelContainer] = []
var _anchor := Vector2.ZERO
var _mirrored := false

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = ColorRect.new()
	_scrim.color = UiTokens.COLOR_SCRIM_MODAL
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.draw.connect(_draw_connector)
	add_child(_layer)
	visible = false

func set_options(v: Array) -> void: options = v; _rebuild()
func set_selected(v: String) -> void: selected = v; _rebuild()

func petals() -> Array[Button]: return _petals
func is_mirrored() -> bool: return _mirrored

## Show the fan around `point` (this control's local coordinates, usually the character's screen position).
func open_at(point: Vector2) -> void:
	_anchor = point
	visible = true
	_layout()

func close() -> void:
	if not visible: return
	visible = false
	closed.emit()

func petal_center(i: int) -> Vector2:
	var a := deg_to_rad(float(_FAN_ANGLES[i]))
	var dir := Vector2(cos(a), sin(a))
	if _mirrored: dir.x = -dir.x
	return _anchor + dir * _FAN_RADIUS

# ------------------------------------------------------------------ build

func _rebuild() -> void:
	if _layer == null: return
	for p in _petals: p.queue_free()
	for l in _labels: l.queue_free()
	_petals.clear()
	_labels.clear()
	for i in mini(options.size(), _FAN_ANGLES.size()):
		var o: Dictionary = options[i]
		var on := str(o.get("id", "")) == selected
		var available := bool(o.get("available", true))
		_petals.append(_petal(o, on, available))
		_labels.append(_label(o, on, available))
	_layout()

func _petal(o: Dictionary, on: bool, available: bool) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var s := UiTokens.SIZE_RADIAL_PETAL
	b.size = Vector2(s, s)
	var fill := UiTokens.COLOR_PRIMARY_TINT if on else UiTokens.COLOR_SURFACE
	var box := UiStyleBox.make(fill, s * 0.5, UiTokens.COLOR_PRIMARY if on else UiTokens.COLOR_BORDER,
		UiTokens.STROKE_RADIAL_SELECTED if on else UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_PETAL
	box.shadow_size = UiTokens.SIZE_SHADOW_PETAL_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_PETAL_OFFSET_Y)
	for k in [&"normal", &"hover", &"focus", &"pressed", &"hover_pressed", &"disabled"]: b.add_theme_stylebox_override(k, box)
	var icon := UiKit.icon(o.get("icon", null), UiTokens.SIZE_RADIAL_ICON)
	icon.position = Vector2((s - UiTokens.SIZE_RADIAL_ICON) * 0.5, (s - UiTokens.SIZE_RADIAL_ICON) * 0.5)
	icon.size = Vector2(UiTokens.SIZE_RADIAL_ICON, UiTokens.SIZE_RADIAL_ICON)
	if not available: icon.modulate.a = UiTokens.OPACITY_UNAVAILABLE_ICON
	b.add_child(icon)
	if not available:
		var lb := UiTokens.SIZE_RADIAL_LOCK_BADGE
		var badge := Panel.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = _LOCK_AT
		badge.size = Vector2(lb, lb)
		badge.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, lb * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
		var lock := UiKit.icon(LOCK_GLYPH, UiTokens.SIZE_RADIAL_LOCK_ICON)
		lock.position = Vector2((lb - UiTokens.SIZE_RADIAL_LOCK_ICON) * 0.5, (lb - UiTokens.SIZE_RADIAL_LOCK_ICON) * 0.5)
		lock.size = Vector2(UiTokens.SIZE_RADIAL_LOCK_ICON, UiTokens.SIZE_RADIAL_LOCK_ICON)
		badge.add_child(lock)
		b.add_child(badge)
	var id := str(o.get("id", ""))
	b.pressed.connect(func():
		if not available: return
		picked.emit(id)
		close())
	_layer.add_child(b)
	return b

func _label(o: Dictionary, on: bool, available: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_RADIAL_LABEL, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_PETAL
	box.shadow_size = UiTokens.SIZE_SHADOW_PETAL_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_PETAL_OFFSET_Y)
	box.with_margins(_LABEL_PAD_X, _LABEL_PAD_Y, _LABEL_PAD_X, _LABEL_PAD_Y)
	p.add_theme_stylebox_override(&"panel", box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	p.add_child(v)
	var ink := UiTokens.COLOR_PRIMARY if on else (UiTokens.COLOR_TEXT if available else UiTokens.COLOR_SECONDARY)
	v.add_child(UiKit.label(str(o.get("name", "")), UiTokens.STYLE_BODY_XB14, ink))   # Name 14 ExtraBold, 19 high
	var reason := str(o.get("reason", ""))
	if not available and reason != "":
		v.add_child(UiKit.label(reason, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY))
	# Labels measure with the theme they inherit; re-place the fan whenever their size settles.
	p.minimum_size_changed.connect(_queue_layout)
	_layer.add_child(p)
	return p

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED: _queue_layout()

func _queue_layout() -> void:
	if is_inside_tree(): _layout.call_deferred()
	else: _layout()

func _layout() -> void:
	# Decided at layout time: the overlay may be opened before it has its full-screen size.
	_mirrored = size.x > 0.0 and _anchor.x > size.x * 0.5
	var s := UiTokens.SIZE_RADIAL_PETAL
	for i in _petals.size():
		var c := petal_center(i)
		_petals[i].position = c - Vector2(s, s) * 0.5
		var l := _labels[i]
		l.size = l.get_combined_minimum_size()
		var x := c.x + s * 0.5 + _LABEL_GAP if not _mirrored else c.x - s * 0.5 - _LABEL_GAP - l.size.x
		l.position = Vector2(x, c.y - l.size.y * 0.5)
	_layer.queue_redraw()

func _draw_connector() -> void:
	for i in _petals.size():
		if str(options[i].get("id", "")) != selected: continue
		var c := petal_center(i)
		var dir := (_anchor - c).normalized()
		var r := UiTokens.SIZE_RADIAL_PETAL * 0.5
		_layer.draw_line(c + dir * r, c + dir * (_FAN_RADIUS * 0.5), UiTokens.COLOR_SURFACE, _CONNECTOR_W, true)

func _on_scrim_input(e: InputEvent) -> void:
	var up: bool = (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed)
	if up:
		accept_event()
		close()
