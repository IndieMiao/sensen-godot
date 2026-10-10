class_name UiPondThumb
extends Control
## PondThumb (Figma 14 · Gensen Refactor/PondThumb 2254:122909; 安其拉 / 不知火舞 on 283 f74fafae, a08d2a5c): a pond's
## template picture, clipped to radius 12 with a 1 px border inside the corner, and (on the Bite Board's pond rows only)
## a 22 px fish badge over its top-right corner. Two sizes: the Bite Board's row 72 × 56 with the badge, the pond card's
## title 56 × 44 without; the radius stays 12 at both (the component keeps it when scaled).
## The pictures are assets/p0/ponds/pond_thumb_<pond|river|coast>.png (144 × 112: tools/dev/pond_thumbs.gd bakes the
## Pond; River and Coast are the component's flat placeholders until their scenes land).

const RADIUS := 12
const ROW := Vector2(72, 56)
const CARD := Vector2(56, 44)
const BADGE := 22.0
const BADGE_ICON := 16.0
const PATH := "res://assets/p0/ponds/pond_thumb_%s.png"

var _frame: Panel
var _pic: TextureRect
var _border: Panel
var _badge: Panel
var _badge_icon: TextureRect

## `template` is a fishing site (pond / river / coast); `fish` an item id for the badge ("" for none).
func _init(template := "pond", size_ := ROW, fish := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = size_
	size = size_
	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_frame.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, RADIUS))
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)
	_pic = TextureRect.new()
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(_pic)
	_border = Panel.new()   # the 1 px border inside the rounded corner, over the picture
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.add_theme_stylebox_override(&"panel", UiStyleBox.make(Color.TRANSPARENT, RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
	_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_border)
	_badge = Panel.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, BADGE * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
	_badge.size = Vector2(BADGE, BADGE)
	add_child(_badge)
	_badge_icon = TextureRect.new()
	_badge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge_icon.position = Vector2((BADGE - BADGE_ICON) * 0.5, (BADGE - BADGE_ICON) * 0.5)
	_badge_icon.size = Vector2(BADGE_ICON, BADGE_ICON)
	_badge.add_child(_badge_icon)
	set_template(template)
	set_fish(fish)
	resized.connect(_place_badge)
	_place_badge()

func set_template(template: String) -> void:
	var path := PATH % template
	if not ResourceLoader.exists(path): path = PATH % "pond"
	_pic.texture = load(path)

## The badge's fish (the row's third line's fish, a08d2a5c); "" hides it.
func set_fish(fish: String) -> void:
	_badge.visible = fish != ""
	if fish != "": _badge_icon.texture = P0Logic.icon(fish)

func template_path() -> String: return _pic.texture.resource_path if _pic.texture else ""
func badge_shown() -> bool: return _badge.visible

## Over the top-right corner, as the component's (x 55, y −5 on a 72-wide thumb).
func _place_badge() -> void:
	_badge.position = Vector2(size.x - BADGE + 5.0, -5.0)
