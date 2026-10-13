class_name UiDialogueCard
extends PanelContainer
## Portrait + name strip (SGODOT-225): the head shared by the resident dialogue bar (ResidentDialogue 1213:83392,
## LOCK-18, UiResidentBar) and the keeper greeting (KeeperGreeting 1205:83238, LOCK-16, built in 2A).
## A rounded portrait on the left, then on the right, top to bottom:
##   identity  `Name` + `· Role` (+ `›` when it opens the profile), or one `Role · Name` line with a place line
##             under it (keepers)
##   extra     an optional row under the identity (the resident's affinity)
##   bubble    the one line, in a white speech bubble whose tail points at the portrait
##   content   the options (Gift / Request, or Trade / ask; a keeper's card closes by the ✕ above it, q(154))
## With `profile_link` on, tapping the portrait or the identity emits `identity_pressed` (the RES-* profile is a
## secondary page, never the first screen, LOCK-18).

signal identity_pressed

const RESIDENT_PORTRAIT := Vector2(92, 178)   # ResidentDialogue: portrait 92 × 178
const KEEPER_PORTRAIT := Vector2(100, 220)    # KeeperGreeting: KeeperPortrait Card 100 × 220
# Inside the two mains (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _PAD := 12.0               # card padding and portrait → content gap
const _COL_GAP := 6.0            # content column
const _ID_GAP := 4.0             # Name · Role › row
const _PLACE_GAP := 1.0          # keeper: Role · Name, then the place line
const _PORTRAIT_RADIUS := 12.0
const _BUBBLE_RADIUS := 10.0
const _BUBBLE_PAD := Vector2(10, 6)
const _TAIL := Vector2(5, 8)     # bubble tail: 5 out to the left, 8 tall, its top 10 below the bubble's top
const _TAIL_TOP := 10.0

var portrait: Texture2D: set = set_portrait
var portrait_size := RESIDENT_PORTRAIT: set = set_portrait_size
var title := "": set = set_title
## Shown after the name in the secondary colour: `· Café Owner`. Keepers put the role in `title` instead.
var role := "": set = set_role
## Keeper place line under the title: `Keeps the stall · Mission Market Square`.
var place := "": set = set_place
var line := "": set = set_line
var profile_link := false: set = set_profile_link
## Row between the identity and the bubble (resident: affinity). Empty = hidden.
var extra: VBoxContainer
## Options under the bubble.
var content: VBoxContainer

var _portrait: _Tap
var _picture: TextureRect
var _identity: _Tap
var _title: Label
var _role: Label
var _chevron: Label
var _place: Label
var _bubble: _Bubble
var _line: Label

func _init(portrait_: Texture2D = null, title_ := "", role_ := "", line_ := "") -> void:
	add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD)
		.with_margins(_PAD, _PAD, _PAD, _PAD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(_PAD))
	add_child(row)
	_portrait = _Tap.new()
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_portrait.pressed.connect(_on_identity)
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	frame.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _PORTRAIT_RADIUS))
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.add_child(frame)
	_picture = TextureRect.new()
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(_picture)
	row.add_child(_portrait)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", int(_COL_GAP))
	row.add_child(col)
	_identity = _Tap.new()
	_identity.pressed.connect(_on_identity)
	var id_col := VBoxContainer.new()
	id_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	id_col.add_theme_constant_override(&"separation", int(_PLACE_GAP))
	_identity.add_child(id_col)
	var id_row := HBoxContainer.new()
	id_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	id_row.add_theme_constant_override(&"separation", int(_ID_GAP))
	id_col.add_child(id_row)
	_title = UiKit.label("", UiTokens.STYLE_C14_XB)   # one line: `Hana`, `Market Keeper · Mei`
	id_row.add_child(_title)
	_role = UiKit.label("", UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	_role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	id_row.add_child(_role)
	_chevron = UiKit.label("›", UiTokens.STYLE_C14_XB, UiTokens.COLOR_SECONDARY)
	id_row.add_child(_chevron)
	_place = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	_place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	id_col.add_child(_place)
	col.add_child(_identity)
	extra = VBoxContainer.new()
	extra.add_theme_constant_override(&"separation", int(_COL_GAP))
	col.add_child(extra)
	_bubble = _Bubble.new()
	_bubble.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _BUBBLE_RADIUS)
		.with_margins(_BUBBLE_PAD.x, _BUBBLE_PAD.y, _BUBBLE_PAD.x, _BUBBLE_PAD.y))
	_line = UiKit.label("", UiTokens.STYLE_C12_B)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.add_child(_line)
	col.add_child(_bubble)
	content = VBoxContainer.new()
	content.add_theme_constant_override(&"separation", int(_COL_GAP))
	col.add_child(content)
	extra.child_entered_tree.connect(func(_n): extra.visible = true)
	extra.visible = false

	portrait_size = portrait_size
	portrait = portrait_
	title = title_
	role = role_
	place = place
	line = line_
	profile_link = profile_link

func set_portrait(v: Texture2D) -> void:
	portrait = v
	if _picture != null: _picture.texture = v

func set_portrait_size(v: Vector2) -> void:
	portrait_size = v
	if _portrait != null: _portrait.custom_minimum_size = v

func set_title(v: String) -> void:
	title = v
	if _title != null: _title.text = v

func set_role(v: String) -> void:
	role = v
	if _role != null:
		_role.text = "· " + v if v != "" else ""
		_role.visible = v != ""

func set_place(v: String) -> void:
	place = v
	if _place != null:
		_place.text = v
		_place.visible = v != ""

func set_line(v: String) -> void:
	line = v
	if _line != null:
		_line.text = v
		_bubble.visible = v != ""

func set_profile_link(v: bool) -> void:
	profile_link = v
	if _chevron != null:
		_chevron.visible = v
		_portrait.disabled = not v
		_identity.disabled = not v

func _on_identity() -> void:
	if profile_link: identity_pressed.emit()

## A tap area around display-only content (portrait, identity row); its hit rect reaches 44 tall even when the
## row is 18. A container, so it sizes to its content; emits `pressed` on a release inside after a press inside.
class _Tap extends MarginContainer:
	signal pressed
	var disabled := false
	var _down := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		for side in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
			add_theme_constant_override(side, 0)

	func _gui_input(e: InputEvent) -> void:
		if disabled: return
		var touch := DisplayServer.is_touchscreen_available()
		var is_button: bool = (touch and e is InputEventScreenTouch) or \
			(not touch and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT)
		if not is_button: return
		if e.pressed:
			_down = true
		elif _down:
			_down = false
			if _has_point(e.position): pressed.emit()
		accept_event()

	func _has_point(p: Vector2) -> bool:
		var grow := maxf(0.0, (UiTokens.SIZE_TOUCH - size.y) * 0.5)
		return Rect2(Vector2(0.0, -grow), size + Vector2(0.0, grow * 2.0)).has_point(p)

## The speech bubble: a white box plus a small tail pointing left at the portrait.
class _Bubble extends PanelContainer:
	func _draw() -> void:
		var t := UiDialogueCard._TAIL
		var top := UiDialogueCard._TAIL_TOP
		draw_colored_polygon(PackedVector2Array([Vector2(1.0, top), Vector2(-t.x, top + t.y * 0.5), Vector2(1.0, top + t.y)]),
			UiTokens.COLOR_SURFACE_RAISED)
