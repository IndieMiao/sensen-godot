class_name UiPhone
extends Control
## UI v3 in-game phone (C-M1–C-M5, M-08 / M-09; C-107, design C-85 ⑦ / ⑧): full screen, a `scrim/phone` scrim under a
## 224 × 436 phone: a 9 `phone/bezel` frame (radius 36, e2 shadow) round the `phone/screen` (radius 28), the 44 × 12
## notch, ✕ (12, `phone/textMuted`, 44 hit area), the page title (`type/headline`, an optional ‹ before it and a short
## note at its right), the page's `body` and the 48 tab bar at the bottom (`phone/row` pill, 8 in): each tab a 22 icon
## over its `type/micro` name, the selected one in colour and `phone/text`, the others greyed and `phone/textMuted`, a
## red count on a tab with something new.
## The caller places it (place(): its bottom right corner, C-L5) and fills `body` through show_page().
##   open()           M-08: scrim 0 → 0.5 (200 linear); the phone rises from its bottom right, y +40 → 0, ×0.9 → 1 and
##                    fades in (320, quart out); its screen's content fades in from 200 over 120
##   close()          M-09: y +24, ×0.96 and fades out (200, cubic in), the scrim with it; `closed`, then it frees itself
##   show_page(page, step)  M-09 tab switch: the old page fades out moving 16 the other way, the new one comes 16 in
##                    and fades in (120 each, cubic out); `step` is +1 moving right, −1 left, 0 in place
## A scrim tap or ✕ emits `close_requested`; tapping a tab `tab_selected(index)` (the selected icon pops 1 → 1.12 → 1,
## 200, back out); ‹ `back_pressed`. Reduced motion (UiMotion.reduced): 120 fades only.

signal close_requested
signal closed
signal tab_selected(index: int)
signal back_pressed

const _NOTCH := Vector2(44, 12)
const _NOTCH_TOP := 6.0
const _CLOSE_GLYPH := 12.0
const _CLOSE_STROKE := 2.0
const _CLOSE_TOP := 20.0
const _CLOSE_RIGHT := 22.0
const _TITLE_TOP := 30.0
const _TITLE_SIDE := 14.0
const _BODY_TOP := 58.0
const _BODY_SIDE := 8.0
const _TAB_ICON := 22.0
const _TAB_BADGE := 14.0
const _BACK_W := 24.0
const _ICON_POP := 1.12
const _ENTER_SCALE := 0.9
const _EXIT_SCALE := 0.96
const _EXIT_DROP := 24.0
const _PAGE_SHIFT := 16.0

var scrim: ColorRect
## The phone (bezel and screen); placed by place(), scaled by the motion.
var frame: Control
## The page's content area, between the title and the tab bar.
var body: Control
var selected := 0
var closing := false
var page: Control

var _content: Control
var _title: Label
var _note: Label
var _back: Button
var _close: Button
var _tabs: Array[_Tab] = []
var _tab_bar: HBoxContainer

func _init(tabs: Array = []) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim = ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UiTokens.COLOR_SCRIM_PHONE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)
	frame = PanelContainer.new()
	frame.name = "Phone"
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.size = Vector2(UiTokens.SIZE_PHONE_W, UiTokens.SIZE_PHONE_H)
	frame.custom_minimum_size = frame.size
	var bezel := UiStyleBox.make(UiTokens.COLOR_PHONE_BEZEL, UiTokens.RADIUS_DEVICE)
	bezel.shadow_color = UiTokens.ELEVATION_E2_COLOR
	bezel.shadow_size = UiTokens.ELEVATION_E2_BLUR * 0.5   # C-185 P-02: e2 as the modal panel draws it (shadow 12)
	bezel.shadow_offset = Vector2(0, UiTokens.ELEVATION_E2_OFFSET_Y)
	var b := float(UiTokens.SIZE_PHONE_BEZEL)
	frame.add_theme_stylebox_override(&"panel", bezel.with_margins(b, b, b, b))
	add_child(frame)
	var screen := PanelContainer.new()
	screen.name = "Screen"
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.clip_contents = true
	screen.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PHONE_SCREEN, UiTokens.RADIUS_XXL))
	frame.add_child(screen)
	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(_content)
	var notch := Panel.new()
	notch.name = "Notch"
	notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notch.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PHONE_NOTCH, UiTokens.RADIUS_PILL))
	notch.anchor_left = 0.5
	notch.anchor_right = 0.5
	notch.offset_left = -_NOTCH.x * 0.5
	notch.offset_right = _NOTCH.x * 0.5
	notch.offset_top = _NOTCH_TOP
	notch.offset_bottom = _NOTCH_TOP + _NOTCH.y
	_content.add_child(notch)
	# Title row: ‹ (only on a sub-page), the title, a short note at the right clear of ✕.
	var head := HBoxContainer.new()
	head.name = "Head"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S3))
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = _TITLE_SIDE
	head.offset_right = -_CLOSE_RIGHT - _CLOSE_GLYPH
	head.offset_top = _TITLE_TOP - UiTokens.SPACE_S2
	head.offset_bottom = _BODY_TOP - UiTokens.SPACE_S2
	_content.add_child(head)
	_back = _Glyph.new(_Glyph.Kind.BACK)
	_back.name = "BackPage"
	_back.visible = false
	_back.custom_minimum_size = Vector2(_BACK_W, 0)
	_back.pressed.connect(func(): if not closing: back_pressed.emit())
	head.add_child(_back)
	_title = UiKit.label("", UiTokens.STYLE_TYPE_TITLE, UiTokens.COLOR_PHONE_TEXT)   # C-185 P-02: `type/title` 20
	_title.name = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	head.add_child(_title)
	_note = UiKit.label("", UiTokens.STYLE_TYPE_MICRO, UiTokens.COLOR_PHONE_TEXT_MUTED)
	_note.name = "Note"
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_note)
	_close = _Glyph.new(_Glyph.Kind.CLOSE)
	_close.name = "Close"
	var hit := UiTokens.SIZE_TOUCH_MIN
	_close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_close.offset_left = -_CLOSE_RIGHT - hit * 0.5
	_close.offset_right = -_CLOSE_RIGHT + hit * 0.5
	_close.offset_top = _CLOSE_TOP - hit * 0.5
	_close.offset_bottom = _CLOSE_TOP + hit * 0.5
	_close.pressed.connect(func(): if not closing: close_requested.emit())
	_content.add_child(_close)
	body = Control.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.clip_contents = true
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = _BODY_SIDE
	body.offset_right = -_BODY_SIDE
	body.offset_top = _BODY_TOP
	body.offset_bottom = -UiTokens.SIZE_PHONE_TAB_H - _BODY_SIDE * 2
	_content.add_child(body)
	var bar := PanelContainer.new()
	bar.name = "Tabs"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PHONE_ROW, UiTokens.RADIUS_PILL))
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = _BODY_SIDE
	bar.offset_right = -_BODY_SIDE
	bar.offset_bottom = -_BODY_SIDE
	bar.offset_top = -_BODY_SIDE - UiTokens.SIZE_PHONE_TAB_H
	_content.add_child(bar)
	_tab_bar = HBoxContainer.new()
	_tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_bar.add_theme_constant_override(&"separation", 0)
	bar.add_child(_tab_bar)
	set_tabs(tabs)

## Tabs: [{title, icon: Texture2D}], left to right.
func set_tabs(tabs: Array) -> void:
	for t in _tabs: t.queue_free()
	_tabs.clear()
	for i in tabs.size():
		var t := _Tab.new(str(tabs[i].get("title", "")), tabs[i].get("icon"))
		t.name = "Tab_" + str(tabs[i].get("title", i))
		t.pressed.connect(func(): if not closing: tab_selected.emit(i))
		_tab_bar.add_child(t)
		_tabs.append(t)
	select(selected, false)

func tab(index: int) -> Button: return _tabs[index] if index >= 0 and index < _tabs.size() else null
func tab_count() -> int: return _tabs.size()

## Marks tab `index` selected (colour icon, `phone/text`); `pop` plays the icon's 1 → 1.12 → 1.
func select(index: int, pop := true) -> void:
	selected = index
	for i in _tabs.size(): _tabs[i].set_on(i == index, pop and i == index)

## The red count on a tab, 0 hides it.
func set_badge(index: int, count: int) -> void:
	if index >= 0 and index < _tabs.size(): _tabs[index].set_badge(count)

func badge(index: int) -> int: return _tabs[index].count if index >= 0 and index < _tabs.size() else 0

## The page head: its title, a ‹ before it on a sub-page, a short note at its right ("" none).
func set_head(text: String, back := false, note := "") -> void:
	_title.text = text
	_back.visible = back
	_note.text = note

func head_title() -> String: return _title.text
func back_button() -> Button: return _back
func close_button() -> Button: return _close

## The phone's bottom right corner at `corner` (this control's space), kept `margin` inside its top.
func place(corner: Vector2, top_margin := 0.0) -> void:
	var at := corner - frame.size
	at.y = maxf(at.y, top_margin)
	frame.position = at

## Puts `next` in the body (full size), replacing the page there; `step` gives the tab switch's direction.
func show_page(next: Control, step := 0) -> void:
	var old := page
	page = next
	next.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(next)
	if old != null and is_instance_valid(old):
		if step == 0 or not is_inside_tree():
			old.queue_free()
		else:
			old.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_set_input(old, false)
			var out := UiMotion.tween(old, UiTokens.MOTION_EASING_STANDARD)
			out.tween_property(old, "modulate:a", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
			if not UiMotion.reduced:
				out.parallel().tween_property(old, "position:x", -_PAGE_SHIFT * signf(step), UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
			out.tween_callback(old.queue_free)
	if step == 0 or not is_inside_tree(): return
	next.modulate.a = 0.0
	var tw := UiMotion.tween(next, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_property(next, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	if not UiMotion.reduced:
		next.position.x = _PAGE_SHIFT * signf(step)
		tw.parallel().tween_property(next, "position:x", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))

## M-08. Call once it is in the tree and placed.
func open() -> void:
	var to := scrim.modulate.a
	scrim.modulate.a = 0.0
	var st := UiMotion.tween(scrim, UiTokens.MOTION_EASING_LINEAR)
	st.tween_property(scrim, "modulate:a", to, UiMotion.secs(UiTokens.MOTION_DURATION_BASE_MS))
	frame.pivot_offset = frame.size
	frame.modulate.a = 0.0
	_content.modulate.a = 0.0
	var rest := frame.position.y
	var tw: Tween
	if UiMotion.reduced:
		tw = UiMotion.tween(frame, UiTokens.MOTION_EASING_LINEAR)
		tw.tween_property(frame, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		tw.parallel().tween_property(_content, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		return
	frame.position.y = rest + UiTokens.MOTION_PHONE_ENTER_OFFSET_Y
	frame.scale = Vector2.ONE * _ENTER_SCALE
	var ms := UiMotion.secs(UiTokens.MOTION_DURATION_EMPHASIS_MS)
	tw = UiMotion.tween(frame, UiTokens.MOTION_EASING_EMPHASIZED)
	tw.tween_property(frame, "position:y", rest, ms)
	tw.parallel().tween_property(frame, "scale", Vector2.ONE, ms)
	tw.parallel().tween_property(frame, "modulate:a", 1.0, ms)
	var ct := UiMotion.tween(_content, UiTokens.MOTION_EASING_STANDARD)
	ct.tween_interval(UiMotion.secs(UiTokens.MOTION_DURATION_BASE_MS))
	ct.tween_property(_content, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))

## M-09, then `closed` and the node frees itself. Touches go through at once.
func close() -> void:
	if closing: return
	closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_input(frame, false)
	if not is_inside_tree():
		closed.emit()
		queue_free()
		return
	var ms := UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS if UiMotion.reduced else UiTokens.MOTION_DURATION_BASE_MS)
	var st := UiMotion.tween(scrim, UiTokens.MOTION_EASING_LINEAR)
	st.tween_property(scrim, "modulate:a", 0.0, ms)
	frame.pivot_offset = frame.size
	var tw := UiMotion.tween(frame, UiTokens.MOTION_EASING_EXIT)
	tw.tween_property(frame, "modulate:a", 0.0, ms)
	if not UiMotion.reduced:
		tw.parallel().tween_property(frame, "position:y", frame.position.y + _EXIT_DROP, ms)
		tw.parallel().tween_property(frame, "scale", Vector2.ONE * _EXIT_SCALE, ms)
	tw.tween_callback(func():
		closed.emit()
		queue_free())

func _set_input(n: Node, on: bool) -> void:
	for c in n.get_children():
		if c is Control: (c as Control).mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
		_set_input(c, on)

func _on_scrim_input(e: InputEvent) -> void:
	var released: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed) \
		or (e is InputEventScreenTouch and not e.pressed and not DisplayServer.is_touchscreen_available())
	if not released: return
	scrim.accept_event()
	if not closing: close_requested.emit()

## Greys a tab's icon (C-M4: unselected tabs show a grey icon). The incoming COLOR is already the texture times the
## modulate (the caller's `phone/textMuted` and the phone's fades, as UiMapDestination._ink), so its luminance is the
## grey icon; sampling TEXTURE again and multiplying left the icon in colour, only darker.
const _GREY := "shader_type canvas_item;\nvoid fragment() {\n" \
	+ "\tCOLOR.rgb = vec3(dot(COLOR.rgb, vec3(0.299, 0.587, 0.114)));\n}\n"
static var _grey: ShaderMaterial

static func grey_material() -> ShaderMaterial:
	if _grey == null:
		var shader := Shader.new()
		shader.code = _GREY
		_grey = ShaderMaterial.new()
		_grey.shader = shader
	return _grey

## One tab: the 22 icon (in colour when selected, greyed otherwise) over its `type/micro` name, a red count on it.
class _Tab extends Button:
	var count := 0
	var on := false
	var _icon: TextureRect
	var _name: Label
	var _badge: Label

	func _init(text: String, texture: Texture2D) -> void:
		focus_mode = Control.FOCUS_NONE
		flat = true
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size.y = UiTokens.SIZE_PHONE_TAB_H
		for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S1))
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(col)
		# The icon sits in a plain holder so its pop scale is not reset by the column's layout.
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.custom_minimum_size = Vector2.ONE * UiPhone._TAB_ICON
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(holder)
		_icon = UiKit.icon(texture, UiPhone._TAB_ICON)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon.size = Vector2.ONE * UiPhone._TAB_ICON
		_icon.pivot_offset = _icon.size * 0.5
		holder.add_child(_icon)
		_name = UiKit.label(text, UiTokens.STYLE_TYPE_MICRO, UiTokens.COLOR_PHONE_TEXT_MUTED)
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(_name)
		_badge = UiKit.label("", UiTokens.STYLE_TYPE_MICRO_ON_DARK)
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_badge.add_theme_stylebox_override(&"normal", UiStyleBox.make(UiTokens.COLOR_BADGE_UNREAD, UiTokens.RADIUS_PILL)
			.with_margins(UiTokens.SPACE_S1 + 1, 0, UiTokens.SPACE_S1 + 1, 0))
		_badge.custom_minimum_size.y = UiPhone._TAB_BADGE
		_badge.visible = false
		add_child(_badge)
		UiMotion.press_feedback(self)

	func set_on(v: bool, pop: bool) -> void:
		on = v
		_name.add_theme_color_override(&"font_color", UiTokens.COLOR_PHONE_TEXT if v else UiTokens.COLOR_PHONE_TEXT_MUTED)
		_icon.material = null if v else UiPhone.grey_material()
		_icon.modulate = UiTokens.COLOR_TEXT_ON_DARK if v else UiTokens.COLOR_PHONE_TEXT_MUTED
		if not (v and pop and is_inside_tree()) or UiMotion.reduced: return
		var tw := UiMotion.tween(_icon, UiTokens.MOTION_EASING_POP)
		var half := UiMotion.secs(UiTokens.MOTION_DURATION_BASE_MS) * 0.5
		tw.tween_property(_icon, "scale", Vector2.ONE * UiPhone._ICON_POP, half)
		tw.tween_property(_icon, "scale", Vector2.ONE, half)

	func set_badge(n: int) -> void:
		count = n
		_badge.text = str(n)
		_badge.visible = n > 0
		_place_badge()

	func icon_rect() -> TextureRect: return _icon

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED: _place_badge()

	## Top 4, its left edge at 56 % of the tab (the design's `.bd`).
	func _place_badge() -> void:
		if _badge == null: return
		var s := _badge.get_combined_minimum_size()
		_badge.size = Vector2(maxf(s.x, s.y), s.y)
		_badge.position = Vector2(size.x * 0.56, UiTokens.SPACE_S2)

## ✕ and ‹ drawn in `phone/textMuted` (C-M1: a glyph, not art) in a 44 transparent hit area.
class _Glyph extends Button:
	enum Kind { CLOSE, BACK }
	var kind: Kind

	func _init(kind_: Kind) -> void:
		kind = kind_
		focus_mode = Control.FOCUS_NONE
		flat = true
		custom_minimum_size = Vector2.ONE * UiTokens.SIZE_TOUCH_MIN
		for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		UiMotion.press_feedback(self)

	func _draw() -> void:
		var c := size * 0.5
		var h := UiPhone._CLOSE_GLYPH * 0.5
		var ink := UiTokens.COLOR_PHONE_TEXT_MUTED
		if kind == Kind.CLOSE:
			draw_line(c + Vector2(-h, -h), c + Vector2(h, h), ink, UiPhone._CLOSE_STROKE, true)
			draw_line(c + Vector2(-h, h), c + Vector2(h, -h), ink, UiPhone._CLOSE_STROKE, true)
		else:
			draw_polyline(PackedVector2Array([c + Vector2(h * 0.4, -h), c + Vector2(-h * 0.4, 0), c + Vector2(h * 0.4, h)]),
				ink, UiPhone._CLOSE_STROKE, true)
