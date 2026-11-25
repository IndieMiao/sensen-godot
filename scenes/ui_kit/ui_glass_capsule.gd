class_name UiGlassCapsule
extends PanelContainer
## UI v3 glass capsule (C-H4, S-2; C-105): a dark glass pill over the scene, no edge, no shadow, white text. One line
## (the coins: `1533` and a Ø18 coin at the right, 24 high, 10 in on the left and 3 on the right, at least 56 wide),
## or a title over a short status line (the parcel's name chip). Display only; never takes input.

## Coins (C-H4): 24 high, number then the Ø18 coin at the right.
static func coins(icon_: Texture2D) -> UiGlassCapsule:
	var c := UiGlassCapsule.new()
	c.icon = icon_
	return c

const _COIN_PAD_LEFT := 10.0   # C-H4: 10 in on the left …
const _COIN_PAD_RIGHT := 3.0   # … and the coin 3 from the right edge
const _COIN_MIN_W := 56.0

var text := "": set = set_text
## Second line under `text` (a status); empty hides it and the capsule is one 24 high line.
var detail := "": set = set_detail
var icon: Texture2D: set = set_icon

var _row: HBoxContainer
var _lines: VBoxContainer
var _label: Label
var _detail: Label
var _icon: TextureRect

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = UiTokens.PANEL_GLASS
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S2))
	add_child(_row)
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lines.add_theme_constant_override(&"separation", 0)
	_row.add_child(_lines)
	_label = UiKit.label("", UiTokens.STYLE_TYPE_HUD_NUMBER_ON_DARK)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lines.add_child(_label)
	_detail = UiKit.label("", UiTokens.STYLE_TYPE_CAPTION_ON_DARK, UiTokens.COLOR_TEXT_ON_DARK_MUTED)
	_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail.visible = false
	_lines.add_child(_detail)
	_icon = UiKit.icon(null, UiTokens.SIZE_HUD_COIN_ICON)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.visible = false
	_row.add_child(_icon)
	_restyle()

func set_text(v: String) -> void:
	text = v
	if _label != null: _label.text = v

func set_detail(v: String) -> void:
	detail = v
	if _detail != null:
		_detail.text = v
		_detail.visible = v != ""
		# Two lines take what room is left beside the other controls and cut with …; a one-line number never cuts.
		_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if v != "" else TextServer.OVERRUN_NO_TRIMMING
		_restyle()

func set_icon(v: Texture2D) -> void:
	icon = v
	if _icon != null:
		_icon.texture = v
		_icon.visible = v != null
		_restyle()

func label() -> Label: return _label
func detail_label() -> Label: return _detail
func icon_rect() -> TextureRect: return _icon

## Coins: 10 in on the left, the coin 3 from the right edge, 24 high, ≥ 56 wide. Two lines: the glass pill's 12 sides.
func _restyle() -> void:
	if _label == null: return
	var box := get_theme_stylebox(&"panel").duplicate() as StyleBox if has_theme_stylebox(&"panel") else null
	if box == null: return
	if icon != null and detail == "":
		box.content_margin_left = _COIN_PAD_LEFT
		box.content_margin_right = _COIN_PAD_RIGHT
		box.content_margin_top = 0.0
		box.content_margin_bottom = 0.0
		custom_minimum_size = Vector2(_COIN_MIN_W, UiTokens.SIZE_HUD_CAPSULE_H_V3)
	else:
		box.content_margin_top = UiTokens.SPACE_S2
		box.content_margin_bottom = UiTokens.SPACE_S2
		custom_minimum_size = Vector2(0.0, UiTokens.SIZE_HUD_CAPSULE_H_V3)
	var was := _styling
	_styling = true
	add_theme_stylebox_override(&"panel", box)
	_styling = was

var _styling := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and not _styling:
		_styling = true
		remove_theme_stylebox_override(&"panel")
		_restyle()
		_styling = false
