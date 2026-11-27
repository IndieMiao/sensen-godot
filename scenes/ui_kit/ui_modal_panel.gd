class_name UiModalPanel
extends Control
## UI v3 modal panel (C-P1–C-P4, C-L4; C-105): the bag-type panel over a `scrim/modal` scrim, full screen.
##   panel   288 wide, `surface/paper`, radius xl 20, e2 shadow; centred, its middle 4 % above the screen's
##   header  a `surface/header` band 40 high (top corners only)
##   hero    an 80 × 80 object 12 in from the left, over the band's top edge (C-86 art; an existing icon meanwhile)
##   tag     the panel's name in a UiTagPill right of the hero, centred on the band
##   close   ✕ 14 in #555550, 44 hit area, 12 from the right, centred on the band
##   body    the caller's content, 28 / 20 / 24 in (top / sides / bottom)
## A scrim tap or ✕ emits `close_requested`; the caller calls close(), which plays M-05 and frees the node (input is
## released at once). open() plays M-04 (scrim 200 linear, panel ×0.88 → 1 in 260, back out, from its centre).

signal close_requested
signal closed

const _HERO_OVER := 32.0      # the hero's top above the panel's (its bottom 8 under the band)
const _HERO_LEFT := 12.0
const _CLOSE_GLYPH := 14.0
const _CLOSE_STROKE := 2.5
const _CENTRE_ABOVE := 0.04   # C-L4: 4 % above the middle (the NPC card's 8 % is UiNpcCard's)
## M-06 stagger (C-185 P-01, C-186): the hero at 80, the name tag at 140, the slots from 120 each a grid step
## (MOTION_STAGGER_MS_GRID, 20) later, none after 200; each fades in over 120.
const STAGGER_HERO_MS := 80.0
const STAGGER_TAG_MS := 140.0
const STAGGER_ITEMS_FROM_MS := 120.0
const STAGGER_LAST_MS := 200.0

var title := "": set = set_title
var hero: Texture2D: set = set_hero
## The caller's content (inside the 28 / 20 / 24 margins).
var body: VBoxContainer
var scrim: ColorRect
## Panel frame (scaled by the motion); hero, tag and close sit on it.
var frame: Control
var closing := false

var _box: PanelContainer
var _header: PanelContainer
var _hero: TextureRect
var _tag: UiTagPill
var _close: Button

func _init(title_ := "", hero_: Texture2D = null) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim = ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UiTokens.COLOR_SCRIM_MODAL
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)
	frame = Control.new()
	frame.name = "Panel"
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5 - _CENTRE_ABOVE
	frame.anchor_bottom = 0.5 - _CENTRE_ABOVE
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(frame)
	_box = PanelContainer.new()
	_box.theme_type_variation = UiTokens.PANEL_MODAL_PANEL
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.minimum_size_changed.connect(_fit)
	frame.add_child(_box)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 0)
	_box.add_child(col)
	_header = PanelContainer.new()
	_header.theme_type_variation = UiTokens.PANEL_PANEL_HEADER
	_header.custom_minimum_size.y = UiTokens.SIZE_PANEL_HEADER_H
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_header)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override(&"margin_top", int(UiTokens.SIZE_PANEL_PAD_TOP))
	pad.add_theme_constant_override(&"margin_left", int(UiTokens.SIZE_PANEL_PAD))
	pad.add_theme_constant_override(&"margin_right", int(UiTokens.SIZE_PANEL_PAD))
	pad.add_theme_constant_override(&"margin_bottom", int(UiTokens.SPACE_S8))
	col.add_child(pad)
	body = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S5))
	pad.add_child(body)
	_hero = UiKit.icon(null, UiTokens.SIZE_PANEL_HERO)
	_hero.name = "Hero"
	frame.add_child(_hero)
	_tag = UiTagPill.new()
	_tag.name = "Tag"
	frame.add_child(_tag)
	_tag.minimum_size_changed.connect(_place_parts)
	_close = _Close.new()
	_close.name = "Close"
	_close.pressed.connect(func(): if not closing: close_requested.emit())
	frame.add_child(_close)
	title = title_
	hero = hero_
	_fit()

func set_title(v: String) -> void:
	title = v
	if _tag != null: _tag.text = v

func set_hero(v: Texture2D) -> void:
	hero = v
	if _hero != null:
		_hero.texture = v
		_hero.visible = v != null
		_place_parts()

func close_button() -> Button: return _close
func tag() -> UiTagPill: return _tag
func hero_rect() -> TextureRect: return _hero
func header() -> Control: return _header

## M-04. Call once it is in the tree.
func open() -> void:
	UiMotion.panel_in(frame, scrim)

## M-06, with open(): the hero, the tag and `items` (the body's slots) fade in one after another (STAGGER_*). Reduced:
## they are simply there. Container children keep their layout; only their opacity moves.
func stagger(items: Array = []) -> void:
	if not is_inside_tree() or UiMotion.reduced: return
	var parts: Array = [[_hero, STAGGER_HERO_MS], [_tag, STAGGER_TAG_MS]]
	for i in items.size():
		parts.append([items[i], minf(STAGGER_ITEMS_FROM_MS + UiTokens.MOTION_STAGGER_MS_GRID * i, STAGGER_LAST_MS)])
	for part in parts:
		var c := part[0] as CanvasItem
		if c == null or not is_instance_valid(c): continue
		c.modulate.a = 0.0
		var tw := UiMotion.tween(c, UiTokens.MOTION_EASING_STANDARD)
		tw.tween_interval(UiMotion.secs(float(part[1])))
		tw.tween_property(c, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))

## M-05, then `closed` and the node frees itself. Touches go through at once.
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
	UiMotion.panel_out(frame, scrim, func():
		closed.emit()
		queue_free())

func _set_input(n: Node, on: bool) -> void:
	for c in n.get_children():
		if c is Control: (c as Control).mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
		_set_input(c, on)

func _fit() -> void:
	if _box == null: return
	var want := _box.get_combined_minimum_size()
	frame.custom_minimum_size = Vector2(UiTokens.SIZE_PANEL_W, want.y)
	_place_parts()

func _place_parts() -> void:
	if frame == null or _close == null: return
	var band := UiTokens.SIZE_PANEL_HEADER_H
	var left := _HERO_LEFT
	if _hero.visible:
		_hero.position = Vector2(_HERO_LEFT, band + UiTokens.SPACE_S4 - UiTokens.SIZE_PANEL_HERO)
		left = _HERO_LEFT + UiTokens.SIZE_PANEL_HERO
	else: left = UiTokens.SIZE_PANEL_PAD
	var tag_size := _tag.get_combined_minimum_size()
	_tag.size = tag_size
	_tag.position = Vector2(left, (band - tag_size.y) * 0.5)
	var hit := UiTokens.SIZE_TOUCH_MIN
	_close.size = Vector2(hit, hit)
	_close.position = Vector2(UiTokens.SIZE_PANEL_W - UiTokens.SPACE_S5 - _CLOSE_GLYPH * 0.5 - hit * 0.5, band * 0.5 - hit * 0.5)

func _on_scrim_input(e: InputEvent) -> void:
	var released: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed) \
		or (e is InputEventScreenTouch and not e.pressed and not DisplayServer.is_touchscreen_available())
	if not released: return
	scrim.accept_event()
	if not closing: close_requested.emit()

## ✕ 14 drawn in #555550 (C-I5: a glyph, not generated art) in a 44 transparent hit area.
class _Close extends Button:
	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		flat = true
		for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		UiMotion.press_feedback(self)

	func _draw() -> void:
		var c := size * 0.5
		var h := UiModalPanel._CLOSE_GLYPH * 0.5
		draw_line(c + Vector2(-h, -h), c + Vector2(h, h), UiTokens.COLOR_CLOSE_GLYPH, UiModalPanel._CLOSE_STROKE, true)
		draw_line(c + Vector2(-h, h), c + Vector2(h, -h), UiTokens.COLOR_CLOSE_GLYPH, UiModalPanel._CLOSE_STROKE, true)
