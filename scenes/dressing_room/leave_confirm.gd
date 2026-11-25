extends Control
## Leaving the dressing room with changes not saved (C-108; C-85 ②-C, a new function the owner approved in Q-124):
## over a `scrim/modal` scrim, a 280 wide `surface/paper` card (radius 20, e2), 22 / 20 / 20 in, with C-86's hanger
## object (72) standing out over its top edge, `Save your new look?` (18 ExtraBold) and two full-width 44 buttons 8
## apart: Save (primary) and Discard (white, danger text). ✕ at the top right, a tap on the scrim or Android Back keep
## the player in the room (`stay`). M-04 in, M-05 out (from the card's centre). No line of explanation (V-241 ③).

signal save
signal discard
signal stay

const WIDTH := 280.0
const PAD := Vector4(20, 22, 20, 20)   # left, top, right, bottom
const HERO := 72.0
const HERO_OVER := 62.0 - 6.0          # the object's top above the card's (its foot 6 above the title)
const TITLE := "Save your new look?"

var scrim: ColorRect
var card: PanelContainer
var save_button: Button
var discard_button: Button
var close_button: Button
var closing := false

func _init() -> void:
	name = "LeaveConfirm"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim = ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UiTokens.COLOR_SCRIM_MODAL
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = UiTokens.COLOR_SURFACE_PAPER
	box.set_corner_radius_all(UiTokens.RADIUS_XL)
	box.shadow_color = UiTokens.ELEVATION_E2_COLOR
	box.shadow_size = 16
	box.shadow_offset = Vector2(0, 8)
	box.content_margin_left = PAD.x
	box.content_margin_top = PAD.y
	box.content_margin_right = PAD.z
	box.content_margin_bottom = PAD.w
	box.anti_aliasing = true
	card.add_theme_stylebox_override(&"panel", box)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5 - 0.04
	card.anchor_bottom = 0.5 - 0.04
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size.x = WIDTH
	add_child(card)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", UiTokens.SPACE_S4)
	card.add_child(col)
	var title := UiKit.label(TITLE, UiTokens.STYLE_TYPE_HEADLINE)
	title.name = "Title"
	title.add_theme_font_size_override(&"font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 30.0
	col.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.y = UiTokens.SPACE_S1
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	save_button = _button("Save", UiTokens.BUTTON_CMD_PRIMARY)
	save_button.name = "Save"
	save_button.pressed.connect(func(): if not closing: save.emit())
	col.add_child(save_button)
	discard_button = _button("Discard", UiTokens.BUTTON_CMD_SECONDARY)
	discard_button.name = "Discard"
	for slot in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		discard_button.add_theme_color_override(slot, UiTokens.COLOR_ACTION_DANGER)
	discard_button.pressed.connect(func(): if not closing: discard.emit())
	col.add_child(discard_button)
	var hero := UiKit.icon(preload("res://assets/ui/v3/hero/hero_dressing.png"), HERO)
	hero.name = "Hero"
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hero)
	close_button = UiModalPanel._Close.new()
	close_button.name = "Close"
	close_button.pressed.connect(func(): if not closing: stay.emit())
	card.add_child(close_button)
	card.sort_children.connect(_place_parts)

func _button(text: String, variation: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_TOUCH_MIN)
	UiMotion.press_feedback(b)
	return b

## The hero and ✕ sit on the card, outside its column (PanelContainer lays every child out; put them back).
func _place_parts() -> void:
	var hero := card.get_node("Hero") as Control
	hero.size = Vector2(HERO, HERO)
	hero.position = Vector2((card.size.x - HERO) * 0.5, -HERO_OVER)
	var hit := UiTokens.SIZE_TOUCH_MIN
	close_button.size = Vector2(hit, hit)
	close_button.position = Vector2(card.size.x - 12.0 - 7.0 - hit * 0.5, 12.0 + 7.0 - hit * 0.5)

## M-04. Call once it is in the tree.
func open() -> void:
	UiMotion.panel_in(card, scrim)

## M-05, then frees itself; touches go through at once.
func close() -> void:
	if closing: return
	closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b in [save_button, discard_button, close_button]: (b as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_inside_tree():
		queue_free()
		return
	UiMotion.panel_out(card, scrim, queue_free)

func _on_scrim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		scrim.accept_event()
		if not closing: stay.emit()
