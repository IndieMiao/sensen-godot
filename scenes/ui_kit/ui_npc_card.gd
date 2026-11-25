class_name UiNpcCard
extends Control
## UI v3 NPC dialogue card (C-N1–C-N7, C-105).
##   card      312 wide, `surface/paper`, radius lg 16, e2 shadow; the caller centres it 8 % above the middle
##             (place_centred) over a `scrim/modal` scrim
##   portrait  96 × 112, 4 in from the left, 28 over the card's top: the NPC's 3D-rendered head (C-30#36)
##   name tag  a UiTagPill (`title`, the caller's copy) on the card's top edge (12 over it), over the text column
##   relation  optional `type/caption` muted line with a 56 × 6 meter (`relation`, `relation_ratio`); hidden if empty
##   line      `type/body` bold in `text/secondary`, at most 3 lines, cut with …
##   content   the action bar: UiCommandButtons added here take the full-width 48 `CtaBar` look (C-N6)
##   close     ✕ 14 in #555550, 44 hit area, 12 from the right (C-N7) → `close_requested`
## Text column: 112 in on the left, 16 on the right, 18 above, 14 below, at least 96 tall so the portrait sits inside.

signal close_requested

const _PORTRAIT_LEFT := 4.0
const _PORTRAIT_OVER := 28.0
const _TAG_OVER := 12.0
const _TEXT_LEFT := 112.0
const _TEXT_RIGHT := 16.0
const _TEXT_TOP := 18.0
const _TEXT_BOTTOM := 14.0
const _TEXT_MIN_H := 96.0
const _LINE_MAX := 3
const _METER := Vector2(56, 6)
const _CENTRE_ABOVE := 0.08

var title := "": set = set_title
var line := "": set = set_line
var portrait: Texture2D: set = set_portrait
var relation := "": set = set_relation
var relation_ratio := 0.0: set = set_relation_ratio
var content: VBoxContainer

var _box: PanelContainer
var _portrait: TextureRect
var _tag: UiTagPill
var _relation_row: HBoxContainer
var _relation: Label
var _meter: _Meter
var _line: Label
var _close: Button

func _init(portrait_: Texture2D = null, title_ := "", line_ := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = PanelContainer.new()
	_box.theme_type_variation = UiTokens.PANEL_NPC_CARD
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.minimum_size_changed.connect(_fit)
	add_child(_box)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 0)
	_box.add_child(col)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.custom_minimum_size.y = _TEXT_MIN_H
	pad.add_theme_constant_override(&"margin_left", int(_TEXT_LEFT))
	pad.add_theme_constant_override(&"margin_right", int(_TEXT_RIGHT))
	pad.add_theme_constant_override(&"margin_top", int(_TEXT_TOP))
	pad.add_theme_constant_override(&"margin_bottom", int(_TEXT_BOTTOM))
	col.add_child(pad)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S3))
	pad.add_child(text)
	_relation_row = HBoxContainer.new()
	_relation_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relation_row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S3))
	_relation_row.visible = false
	text.add_child(_relation_row)
	_relation = UiKit.label("", UiTokens.STYLE_TYPE_CAPTION, UiTokens.COLOR_TEXT_MUTED)
	_relation_row.add_child(_relation)
	_meter = _Meter.new()
	_meter.custom_minimum_size = _METER
	_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_relation_row.add_child(_meter)
	_line = UiKit.label("", UiTokens.STYLE_TYPE_BODY_BOLD, UiTokens.COLOR_TEXT_SECONDARY)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.max_lines_visible = _LINE_MAX
	_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_line.custom_minimum_size.x = UiTokens.SIZE_NPC_W - _TEXT_LEFT - _TEXT_RIGHT
	text.add_child(_line)
	content = VBoxContainer.new()
	content.name = "Actions"
	content.add_theme_constant_override(&"separation", 0)
	content.child_entered_tree.connect(_on_action_added)
	col.add_child(content)
	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size = Vector2(UiTokens.SIZE_NPC_PORTRAIT_W, UiTokens.SIZE_NPC_PORTRAIT_H)
	_portrait.position = Vector2(_PORTRAIT_LEFT, -_PORTRAIT_OVER)
	add_child(_portrait)
	_tag = UiTagPill.new()
	_tag.name = "NameTag"
	add_child(_tag)
	_tag.minimum_size_changed.connect(_place_parts)
	_close = UiModalPanel._Close.new()
	_close.name = "Close"
	_close.pressed.connect(func(): close_requested.emit())
	add_child(_close)
	portrait = portrait_
	title = title_
	line = line_
	_fit()

func set_title(v: String) -> void:
	title = v
	if _tag != null:
		_tag.text = v
		_place_parts()

func set_line(v: String) -> void:
	line = v
	if _line != null:
		_line.text = v
		_line.visible = v != ""

## A full-length render (the keepers' 300 × 660 card portrait) shows its top, head and shoulders, in the 96 × 112.
func set_portrait(v: Texture2D) -> void:
	portrait = v
	if _portrait == null: return
	var area := Vector2(UiTokens.SIZE_NPC_PORTRAIT_W, UiTokens.SIZE_NPC_PORTRAIT_H)
	if v != null and v.get_width() > 0 and float(v.get_height()) / v.get_width() > area.y / area.x * 1.2:
		var top := AtlasTexture.new()
		top.atlas = v
		top.region = Rect2(0, 0, v.get_width(), v.get_width() * area.y / area.x)
		_portrait.texture = top
	else: _portrait.texture = v

func set_relation(v: String) -> void:
	relation = v
	if _relation != null:
		_relation.text = v
		_relation_row.visible = v != ""

func set_relation_ratio(v: float) -> void:
	relation_ratio = clampf(v, 0.0, 1.0)
	if _meter != null:
		_meter.ratio = relation_ratio
		_meter.queue_redraw()

func close_button() -> Button: return _close
func name_tag() -> UiTagPill: return _tag
func line_label() -> Label: return _line

## Centres the card in its full-screen parent, its middle 8 % above the screen's (C-N1 / C-L4).
func place_centred() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5 - _CENTRE_ABOVE
	anchor_bottom = 0.5 - _CENTRE_ABOVE
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

## M-04 from the card's bottom middle (§5); `scrim` fades in with it when given.
func play_in(scrim: CanvasItem = null) -> void:
	UiMotion.panel_in(self, scrim, Vector2(0.5, 1.0))

## Buttons added to `content` become the C-N6 bar: full width, 48 high, lime, white ExtraBold with its outline.
func _on_action_added(n: Node) -> void:
	if n is UiCommandButton: (n as UiCommandButton).bar = true

func _fit() -> void:
	if _box == null: return
	custom_minimum_size = Vector2(UiTokens.SIZE_NPC_W, _box.get_combined_minimum_size().y)
	_place_parts()

func _place_parts() -> void:
	if _tag == null or _close == null: return
	var s := _tag.get_combined_minimum_size()
	_tag.size = s
	_tag.position = Vector2(_TEXT_LEFT, -_TAG_OVER)
	var hit := UiTokens.SIZE_TOUCH_MIN
	_close.size = Vector2(hit, hit)
	# the glyph in the card's top margin, clear of the text column's first line
	_close.position = Vector2(UiTokens.SIZE_NPC_W - UiTokens.SPACE_S5 - UiModalPanel._CLOSE_GLYPH * 0.5 - hit * 0.5,
		_TEXT_TOP * 0.5 + 1.0 - hit * 0.5)

## The C-N4 relation meter: a 56 × 6 pill, `progress/fill` on `progress/track`.
class _Meter extends Control:
	var ratio := 0.0

	func _draw() -> void:
		var r := size.y * 0.5
		_pill(Rect2(Vector2.ZERO, size), r, UiTokens.COLOR_PROGRESS_TRACK)
		if ratio > 0.0: _pill(Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * ratio), size.y)), r, UiTokens.COLOR_PROGRESS_FILL)

	func _pill(rect: Rect2, r: float, color: Color) -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = color
		box.set_corner_radius_all(roundi(r))
		box.anti_aliasing = true
		draw_style_box(box, rect)
