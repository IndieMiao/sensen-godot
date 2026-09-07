class_name GameUi
extends RefCounted
## Shared, compact game chrome. World-space hints use the same Lucide symbols.

## 取值只在 DesignTokens（A7 单一来源）；这里的名字是壳代码里的短别名。
const INK := DesignTokens.UI_INK
const MUTED := DesignTokens.UI_MUTED
const GREEN := DesignTokens.UI_GREEN
const MINT := DesignTokens.UI_MINT
const PAPER := DesignTokens.UI_PAPER
const BORDER := DesignTokens.UI_BORDER
const GOLD := DesignTokens.UI_GOLD
const CORAL := DesignTokens.UI_CORAL
const BLUE := DesignTokens.UI_BLUE

static func icon(id: String) -> Texture2D:
	var path := "res://assets/ui/icons/lucide/%s.svg" % id
	return load(path) if ResourceLoader.exists(path) else null

static func crop_art(crop: String, seed := false) -> Texture2D:
	var names := {"R": "radish", "L": "lettuce", "C": "carrot", "H": "chamomile"}
	var path := "res://assets/ui/farm/%s/%s.png" % ["seeds" if seed else "crops", names.get(crop, "radish")]
	return load(path) if ResourceLoader.exists(path) else icon("sprout")

static func picture(texture: Texture2D, side := 44.0) -> TextureRect:
	var p := TextureRect.new()
	p.texture = texture
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
	return "timer"

static func surface(color := PAPER, pad := DesignTokens.UI_PAD, radius := DesignTokens.UI_RADIUS) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	return sb

static func theme() -> Theme:
	var t := (load("res://assets/ui/app_theme.tres") as Theme).duplicate() as Theme
	var font := FontVariation.new()
	font.base_font = load("res://assets/ui/fonts/Nunito.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650.0}
	# Nunito 没有 CJK 字形；zh_CN 下靠 Noto Sans SC 回退（A2 i18n）。
	font.fallbacks = [load("res://assets/ui/fonts/NotoSansSC-Regular.otf")]
	t.default_font = font
	t.default_font_size = DesignTokens.UI_FONT_BODY
	t.set_color("font_color", "Label", INK)
	t.set_constant("line_spacing", "Label", 0)
	for variant in ["Button", "AccentButton", "SecondaryButton", "ChoiceButton", "ChoiceSelectedButton", "GhostButton", "RailButton"]:
		var accent: bool = variant == "AccentButton"
		var selected: bool = variant == "ChoiceSelectedButton"
		var base: Color = GREEN if accent else (MINT if selected else PAPER)
		t.set_color("font_color", variant, PAPER if accent else INK)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var bg := base
			if state == "hover": bg = base.lightened(0.06)
			if state == "pressed": bg = base.darkened(0.08)
			if state == "disabled": bg = DesignTokens.UI_SURFACE_DISABLED
			var sb := surface(bg, DesignTokens.UI_RADIUS)
			if accent: sb.border_color = GREEN
			if selected: sb.border_color = GREEN
			t.set_stylebox(state, variant, sb)
		var focus := surface(Color.TRANSPARENT, 0)
		focus.border_color = GOLD
		focus.set_border_width_all(2)
		t.set_stylebox("focus", variant, focus)
		for state in ["normal", "hover", "pressed", "focus"]:
			t.set_color("font_%s_color" % state, variant, PAPER if accent else INK)
			t.set_color("icon_%s_color" % state, variant, PAPER if accent else INK)
		t.set_color("font_disabled_color", variant, MUTED)
		t.set_color("icon_disabled_color", variant, MUTED)
		t.set_font_size("font_size", variant, DesignTokens.UI_FONT_BODY)
		t.set_constant("icon_max_width", variant, DesignTokens.UI_ICON_MAX)
		t.set_constant("h_separation", variant, 6)
	for variant in ["PanelContainer", "ChipPanel", "BottomSheet"]:
		t.set_stylebox("panel", variant, surface())
	for variant in ["ThumbChoiceButton", "ThumbChoiceSelectedButton"]:
		var selected: bool = variant == "ThumbChoiceSelectedButton"
		var sb := surface(PAPER if selected else DesignTokens.UI_SURFACE_SUNK, DesignTokens.UI_RADIUS)
		sb.border_color = GREEN if selected else BORDER
		for state in ["normal", "hover", "pressed", "disabled"]:
			t.set_stylebox(state, variant, sb)
		for state in ["normal", "hover", "pressed", "focus"]:
			t.set_color("font_%s_color" % state, variant, GREEN if selected else INK)
			t.set_color("icon_%s_color" % state, variant, Color.WHITE)
	for variant in ["TabButton", "TabSelectedButton"]:
		var selected: bool = variant == "TabSelectedButton"
		var sb := surface(Color.TRANSPARENT, 6, 0)
		sb.set_border_width_all(0)
		if selected:
			sb.border_width_bottom = 2
			sb.border_color = GREEN
		for state in ["normal", "hover", "pressed", "disabled"]:
			t.set_stylebox(state, variant, sb)
		for state in ["normal", "hover", "pressed", "focus"]:
			t.set_color("font_%s_color" % state, variant, GREEN if selected else MUTED)
			t.set_color("icon_%s_color" % state, variant, GREEN if selected else MUTED)
		t.set_font_size("font_size", variant, DesignTokens.UI_FONT_TAB)
		t.set_constant("icon_max_width", variant, DesignTokens.UI_TAB_ICON_MAX)
		t.set_constant("h_separation", variant, 3)
	# LineEdit：引擎默认是深色底，纸色主题里像一块黑砖（真机截图）。浅底 + 细边，聚焦描绿。
	var edit := surface(DesignTokens.UI_FIELD, 10, DesignTokens.UI_RADIUS)
	edit.border_color = BORDER
	edit.set_border_width_all(1)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("read_only", "LineEdit", surface(DesignTokens.UI_SURFACE_SUNK, 10, DesignTokens.UI_RADIUS))
	var edit_focus := surface(DesignTokens.UI_FIELD, 10, DesignTokens.UI_RADIUS)
	edit_focus.border_color = GREEN
	edit_focus.set_border_width_all(2)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", MINT)
	t.set_font_size("font_size", "LineEdit", DesignTokens.UI_FONT_BODY)
	t.set_stylebox("panel", "ToastPanel", surface(INK, 12))
	t.set_stylebox("background", "ProgressBar", surface(BORDER, 0, 3))
	t.set_stylebox("fill", "ProgressBar", surface(GREEN, 0, 3))
	return t

static func button(symbol: String, text: String, tip: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = icon(symbol) if not symbol.is_empty() else null
	# tip 是给开发者看的注记（接口名 / 卡号），只在桌面当 tooltip；触屏上 Godot 会把它画在
	# 视口左上角（2026-09-07 真机截图抓到），用户看到的是一串英文内部名。
	b.tooltip_text = tip if OS.has_feature("pc") else ""
	b.theme_type_variation = &"AccentButton" if accent else &"SecondaryButton"
	b.custom_minimum_size = Vector2(DesignTokens.UI_TOUCH_MIN, DesignTokens.UI_TOUCH_MIN)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if text.is_empty() else HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	return b

static func label(text: String, font_size := DesignTokens.UI_FONT_BODY, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
