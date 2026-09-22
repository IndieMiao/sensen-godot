class_name GameUi
extends RefCounted
## Game UI art is generated through the selected Sensenjoy API; native controls
## retain editable text, real input targets and the existing game contracts.

## 全 app 与城市地图同一视觉语言（2026-09-23 设计稿 farm-restyle-mockup-v1）：
## 奶油白卡 + 墨色字 + 青柠主按钮，柔和阴影，不再用紫/青贴图边框。
const INK := Color("232b30")
const MUTED := Color("69716e")
const GREEN := Color("5d8f2e")
const MINT := Color("f1f6e6")
const PAPER := Color("fffdf8")
const BORDER := Color("e4e2d6")
const GOLD := Color("b57a1b")
const CORAL := Color("d8787a")
## 次强调色（图标着色、选中描边、摇杆）：深鼠尾草绿。
const BLUE := Color("4f7d32")
const VIOLET := Color("8cc85a")
const LIME := Color("cafa91")
const LIME_EDGE := Color("a6dc6c")
const CARD := Color(1, 1, 1, 0.97)
const MODAL_GROUP := &"game_ui_modal"

static var _art: Dictionary = {}
const MATERIAL_LOGICAL_SIZE := {
	"panel-frame.png": Vector2i(256, 254), "control-frame.png": Vector2i(128, 127),
	"button-teal.png": Vector2i(256, 68), "button-violet.png": Vector2i(256, 68),
	"control-teal.png": Vector2i(128, 34), "control-violet.png": Vector2i(128, 34),
}

static func _density_texture(path: String, logical_size: Vector2i) -> Texture2D:
	if _art.has(path): return _art[path]
	var source := load(path) as Texture2D
	var pixels := source.get_image()
	if pixels.is_compressed(): pixels.decompress()
	var result := ImageTexture.create_from_image(pixels)
	# Keep physical pixels while layout and nine-slice margins use logical units.
	result.set_size_override(logical_size)
	result.set_meta("ui_source", path)
	_art[path] = result
	return result

static func is_game_icon(texture: Texture2D) -> bool:
	return texture != null and str(texture.get_meta("ui_source", texture.resource_path)).begins_with("res://assets/ui/icons/game/")

static func icon(id: String) -> Texture2D:
	var game_path := "res://assets/ui/icons/game/%s.svg" % id
	if ResourceLoader.exists(game_path): return _density_texture(game_path, Vector2i(24, 24))
	var path := "res://assets/ui/icons/lucide/%s.svg" % id
	return load(path) if ResourceLoader.exists(path) else null

static func crop_art(crop: String, seed := false) -> Texture2D:
	var names := {"R": "radish", "L": "lettuce", "C": "carrot", "H": "chamomile"}
	var path := "res://assets/ui/farm/%s/%s.png" % ["seeds" if seed else "crops", names.get(crop, "radish")]
	return load(path) if ResourceLoader.exists(path) else icon("sprout")

static func picture(texture: Texture2D, side := 44.0) -> TextureRect:
	var p := TextureRect.new()
	p.texture = texture
	if is_game_icon(texture):
		p.modulate = BLUE
	p.custom_minimum_size = Vector2(side, side)
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func dish_art(dish: String) -> Texture2D:
	var path := "res://assets/ui/farm/dishes/%s.png" % dish
	return load(path) if ResourceLoader.exists(path) else icon("shopping-basket")

static func action_icon(action: String, weather := "sunny") -> String:
	match action:
		"clear": return "scissors"
		"till": return "shovel"
		"sow": return "sprout"
		"care": return "wind" if weather == "wind" else ("cloud-rain" if weather == "rain" else "droplet")
		"harvest": return "wheat"
		"stall": return "store"
		"explore": return "compass"
	return "timer"

static func surface(color := PAPER, pad := 12, radius := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	if color.a > 0.8:
		sb.shadow_color = Color(0.2, 0.23, 0.2, 0.1)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0, 2)
	return sb

## 地图页同款卡面：白底、无描边、大圆角、柔和投影。
static func card_surface(color := CARD, pad := 8, radius := 16) -> StyleBoxFlat:
	var sb := surface(color, pad, radius)
	sb.set_border_width_all(0)
	sb.shadow_color = Color(0.2, 0.23, 0.2, 0.1)
	sb.shadow_size = 3 if color.a > 0.1 else 0
	return sb

static func _texture_style(file: String, pad: int, slice: int, tint := Color.WHITE) -> StyleBox:
	var path := "res://assets/ui/game/" + file
	if not ResourceLoader.exists(path): return surface(PAPER, pad)
	var style := StyleBoxTexture.new()
	style.texture = _density_texture(path, MATERIAL_LOGICAL_SIZE.get(file, Vector2i(128, 128)))
	style.modulate_color = tint
	style.set_texture_margin_all(slice)
	style.set_content_margin_all(pad)
	return style

static func panel_style(pad := 12) -> StyleBox:
	return card_surface(CARD, pad, 14 if pad <= 8 else 20)

static func card_style(selected := false, pad := 8) -> StyleBoxFlat:
	var style := surface(Color("f6f5ef") if not selected else Color("eefbe0"), pad, 12)
	style.border_color = LIME_EDGE if selected else BORDER
	style.set_border_width_all(2 if selected else 1)
	style.shadow_size = 1
	style.shadow_offset = Vector2(0, 1)
	return style

static func _menu_radio(id: String) -> Texture2D:
	# PopupMenu draws check textures directly, unlike Button's icon color tint.
	# Keep the library silhouette and give this native menu a visible blue mark.
	var key := "menu-radio/" + id
	if _art.has(key): return _art[key]
	var source := icon(id)
	var pixels := source.get_image()
	if pixels.is_compressed(): pixels.decompress()
	pixels.convert(Image.FORMAT_RGBA8)
	for y in pixels.get_height():
		for x in pixels.get_width():
			pixels.set_pixel(x, y, Color(BLUE, pixels.get_pixel(x, y).a))
	_art[key] = ImageTexture.create_from_image(pixels)
	_art[key].set_size_override(Vector2i(24, 24))
	return _art[key]

static func register_modal(node: Node) -> void:
	if not node.is_in_group(MODAL_GROUP): node.add_to_group(MODAL_GROUP)

static func _visible_branch(node: Node) -> bool:
	var current: Node = node
	while current:
		if current.process_mode == Node.PROCESS_MODE_DISABLED: return false
		if current is Window and not current.visible: return false
		if current is CanvasLayer and not current.visible: return false
		if current is CanvasItem and not current.visible: return false
		if current is Node3D and not current.visible: return false
		current = current.get_parent()
	return node.is_inside_tree()

static func modal_is_open(context: Node, excluding: Node = null) -> bool:
	if not is_instance_valid(context) or not context.is_inside_tree(): return false
	for modal in context.get_tree().get_nodes_in_group(MODAL_GROUP):
		if modal != excluding and not modal.is_queued_for_deletion() and _visible_branch(modal): return true
	return false

static func theme() -> Theme:
	var t := (load("res://assets/ui/app_theme.tres") as Theme).duplicate() as Theme
	var font := FontVariation.new()
	font.base_font = load("res://assets/ui/fonts/Nunito.ttf")
	var chinese := FontVariation.new()
	chinese.base_font = load("res://assets/ui/fonts/NotoSansSC-Regular.otf")
	chinese.variation_embolden = 0.45
	font.fallbacks = [chinese]
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 750.0}
	t.default_font = font
	t.default_font_size = 14
	t.set_color("font_color", "Label", INK)
	t.set_constant("line_spacing", "Label", 0)
	for variant in ["Button", "OptionButton", "AccentButton", "SecondaryButton", "ChoiceButton", "ChoiceSelectedButton", "GhostButton", "RailButton", "IconButton", "DockButton", "ItemSlotButton", "ItemSlotSelectedButton"]:
		if variant not in ["Button", "OptionButton"]: t.set_type_variation(variant, "Button")
		var accent: bool = variant == "AccentButton"
		var selected: bool = variant in ["ChoiceSelectedButton", "ItemSlotSelectedButton"]
		t.set_color("font_color", variant, INK)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var tint := Color.WHITE
			if state == "hover": tint = Color(1.04, 1.04, 1.04)
			elif state in ["pressed", "hover_pressed"]: tint = Color(0.88, 0.9, 0.96)
			elif state == "disabled": tint = Color(0.82, 0.83, 0.88, 0.75)
			var sb: StyleBox = card_surface((LIME if accent else CARD) * tint, 8, 16)
			if state in ["pressed", "hover_pressed"] and not accent: sb = card_surface(LIME, 8, 16)
			if variant in ["ItemSlotButton", "ItemSlotSelectedButton"]: sb = card_style(selected, 4)
			elif selected: sb = card_style(true, 8)
			elif variant == "GhostButton": sb = surface(Color(0.94, 0.95, 1.0, 0.9), 6)
			t.set_stylebox(state, variant, sb)
		var focus := surface(Color.TRANSPARENT, 0)
		focus.border_color = GOLD
		focus.set_border_width_all(2)
		t.set_stylebox("focus", variant, focus)
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_color("font_%s_color" % state, variant, INK)
			t.set_color("icon_%s_color" % state, variant, INK)
		t.set_color("font_disabled_color", variant, MUTED)
		t.set_color("icon_disabled_color", variant, MUTED)
		t.set_font_size("font_size", variant, 14)
		t.set_constant("icon_max_width", variant, 20)
		t.set_constant("h_separation", variant, 6)
	t.set_icon("arrow", "OptionButton", icon("chevron-down"))
	t.set_constant("modulate_arrow", "OptionButton", 1)
	t.set_constant("arrow_margin", "OptionButton", 8)
	t.set_stylebox("panel", "PopupMenu", panel_style(10))
	t.set_stylebox("hover", "PopupMenu", surface(MINT, 4, 4))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", GREEN)
	t.set_color("font_disabled_color", "PopupMenu", MUTED)
	var radio_checked := _menu_radio("circle-check")
	var radio_unchecked := _menu_radio("circle")
	for key in ["radio_checked", "radio_checked_disabled"]:
		t.set_icon(key, "PopupMenu", radio_checked)
	for key in ["radio_unchecked", "radio_unchecked_disabled"]:
		t.set_icon(key, "PopupMenu", radio_unchecked)
	var row_height := maxi(ceili(font.get_height(14)), maxi(radio_checked.get_height(), radio_unchecked.get_height()))
	t.set_constant("v_separation", "PopupMenu", maxi(0, 44 - row_height))
	for variant in ["PanelContainer", "ChipPanel", "BottomSheet"]:
		t.set_stylebox("panel", variant, panel_style(8 if variant == "ChipPanel" else 12))
	for variant in ["ThumbChoiceButton", "ThumbChoiceSelectedButton"]:
		var selected: bool = variant == "ThumbChoiceSelectedButton"
		t.set_color("font_color", variant, GREEN if selected else INK)
		var sb := card_style(selected, 6)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(state, variant, sb)
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_color("font_%s_color" % state, variant, GREEN if selected else INK)
			t.set_color("icon_%s_color" % state, variant, Color.WHITE)
	for variant in ["TabButton", "TabSelectedButton"]:
		var selected: bool = variant == "TabSelectedButton"
		t.set_color("font_color", variant, INK)
		var sb: StyleBox = card_surface(LIME, 8, 14) if selected else card_style(false, 8)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(state, variant, sb)
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_color("font_%s_color" % state, variant, INK)
			t.set_color("icon_%s_color" % state, variant, INK)
		t.set_font_size("font_size", variant, 11)
		t.set_constant("icon_max_width", variant, 18)
		t.set_constant("h_separation", variant, 3)
	t.set_stylebox("panel", "ToastPanel", surface(INK, 12))
	t.set_stylebox("background", "ProgressBar", surface(Color("ebe9e0"), 0, 3))
	t.set_stylebox("fill", "ProgressBar", surface(LIME_EDGE, 0, 3))
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, card_style(false, 8))
		t.set_stylebox("focus", type, card_style(true, 8))
		t.set_color("font_color", type, INK)
		t.set_color("font_placeholder_color", type, MUTED)
		t.set_color("caret_color", type, BLUE)
	t.set_stylebox("panel", "AcceptDialog", panel_style(14))
	t.set_stylebox("panel", "Window", panel_style(14))
	return t

static func button(symbol: String, text: String, tip: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = icon(symbol) if not symbol.is_empty() else null
	b.tooltip_text = tip
	b.theme_type_variation = &"AccentButton" if accent else &"SecondaryButton"
	b.custom_minimum_size = Vector2(44, 44)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if text.is_empty() else HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	return b

static func label(text: String, font_size := 14, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
