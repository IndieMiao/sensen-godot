class_name UiKeeperBar
extends PanelContainer
## KeeperBar 1143:102525, Layout=Titled (SGODOT-224, LOCK-16): the top of an outpost counter drawer (NPC-2 / 2-2 /
## 6 / 7-P0). 336 wide, role tint, radius 14:
##   header (44 high, y 1)  40 px portrait ring in the role colour with the 36 px keeper head inside · the shop
##                          title (C14 XB) + `· Place` (C10 B, secondary) over `Role · Name` (C11 XB, role colour) ·
##                          Close 44 at the right
##   bubble (y 45)          one white line that changes with what the player does (selected item, sold, limit),
##                          C11 B, wraps; a tail at x 33 points up at the portrait
##   note                   optional C10 B secondary line under the bubble ("Shares the 3 cups a day with tea")
## The unattended Homestead Stall (FARM-6) has no keeper bar. Names and places are data (the outpost's ctx), never
## written here. `close_pressed` from the Close button.

signal close_pressed

enum Role { MARKET, TACKLE, TEA, POST }

const ROLE_COLORS := {
	Role.MARKET: [UiTokens.COLOR_ROLE_MARKET, UiTokens.COLOR_ROLE_MARKET_TINT],
	Role.TACKLE: [UiTokens.COLOR_ROLE_TACKLE, UiTokens.COLOR_ROLE_TACKLE_TINT],
	Role.TEA: [UiTokens.COLOR_ROLE_TEA, UiTokens.COLOR_ROLE_TEA_TINT],
	Role.POST: [UiTokens.COLOR_ROLE_POST, UiTokens.COLOR_ROLE_POST_TINT],
}

# Titled layout (1188:82578 and siblings): 336 × 67, header row at y 1, ring 40 at (6, 3), text at x 54, Close 44 at
# x 288, bubble at (6, 45) 326 × 18 with the line inset 8, note 9 under the bubble.
const _RADIUS := 14.0
const _PAD := Vector4(6, 1, 4, 4)   # left, top, right, bottom
const _RING := 40.0
const _HEAD := 36.0
const _TEXT_GAP := 8.0
const _BUBBLE_RADIUS := 8.0
const _BUBBLE_PAD := Vector2(8, 1)   # Figma insets the 14 px line box by 2; Nunito C11 B is 16 here, so 1 keeps 18
const _TAIL_X := 27.0               # tail centre at x 33 of the bar (rotated 10 × 10 square at x 28), bubble at x 6
const _TAIL := Vector2(10, 6)
const _NOTE_GAP := 9.0

var role: Role = Role.TACKLE: set = set_role
var portrait: Texture2D: set = set_portrait
## Shop title: `Finn's Tackle`.
var title := "": set = set_title
## Place after the title: `Mission Tackle Shop` (drawn as `· Mission Tackle Shop`).
var place := "": set = set_place
## `Tackle Keeper · Finn`.
var keeper := "": set = set_keeper
var line := "": set = set_line
var note := "": set = set_note

var _ring: Panel
var _head: TextureRect
var _title: Label
var _place: Label
var _keeper: Label
var _bubble: _Bubble
var _line: Label
var _note_gap: Control
var _note: Label

func _init(role_: Role = Role.TACKLE) -> void:
	custom_minimum_size.x = UiTokens.SIZE_QUICK_BAR_W
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 0)
	add_child(col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", int(_TEXT_GAP))
	header.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	col.add_child(header)
	_ring = Panel.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.custom_minimum_size = Vector2(_RING, _RING)
	_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_ring)
	var clip := Panel.new()   # the head, cropped to a circle inside the ring
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _HEAD * 0.5))
	clip.position = Vector2.ONE * (_RING - _HEAD) * 0.5
	clip.size = Vector2(_HEAD, _HEAD)
	_ring.add_child(clip)
	_head = TextureRect.new()
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_head.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.add_child(_head)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", 0)
	header.add_child(text)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	text.add_child(title_row)
	_title = UiKit.label("", UiTokens.STYLE_C14_XB)
	title_row.add_child(_title)
	_place = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	_place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_place.size_flags_vertical = Control.SIZE_FILL
	title_row.add_child(_place)
	_keeper = UiKit.label("", UiTokens.STYLE_C11_XB)
	text.add_child(_keeper)
	var close := UiCloseButton.new()
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): close_pressed.emit())
	header.add_child(close)
	_bubble = _Bubble.new()
	_bubble.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _BUBBLE_RADIUS)
		.with_margins(_BUBBLE_PAD.x, _BUBBLE_PAD.y, _BUBBLE_PAD.x, _BUBBLE_PAD.y))
	col.add_child(_bubble)
	_line = UiKit.label("", UiTokens.STYLE_C11_B)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.add_child(_line)
	_note_gap = Control.new()
	_note_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note_gap.custom_minimum_size.y = _NOTE_GAP
	col.add_child(_note_gap)
	_note = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_note)
	role = role_
	note = ""

func set_role(v: Role) -> void:
	role = v
	var c: Array = ROLE_COLORS[v]
	add_theme_stylebox_override(&"panel", UiStyleBox.make(c[1], _RADIUS).with_margins(_PAD.x, _PAD.y, _PAD.z, _PAD.w))
	_ring.add_theme_stylebox_override(&"panel", UiStyleBox.make(c[0], _RING * 0.5))
	_keeper.add_theme_color_override(&"font_color", c[0])

func set_portrait(v: Texture2D) -> void:
	portrait = v
	_head.texture = v

func set_title(v: String) -> void:
	title = v
	_title.text = v

func set_place(v: String) -> void:
	place = v
	_place.text = ("· " + v) if v != "" else ""

func set_keeper(v: String) -> void:
	keeper = v
	_keeper.text = v

func set_line(v: String) -> void:
	line = v
	_line.text = v
	_bubble.visible = v != ""

func set_note(v: String) -> void:
	note = v
	_note.text = v
	_note.visible = v != ""
	_note_gap.visible = v != ""

## Role for a counter id ("market", "tackle", "tea", "post").
static func role_of(id: String) -> Role:
	return {"market": Role.MARKET, "tea": Role.TEA, "post": Role.POST}.get(id, Role.TACKLE)

## The speech bubble: a white rounded box with a small tail at its top-left, pointing up at the portrait.
class _Bubble extends PanelContainer:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var x := _TAIL_X
		draw_colored_polygon(PackedVector2Array([Vector2(x - _TAIL.x * 0.5, 0.5), Vector2(x, -_TAIL.y), Vector2(x + _TAIL.x * 0.5, 0.5)]),
			UiTokens.COLOR_SURFACE_RAISED)
