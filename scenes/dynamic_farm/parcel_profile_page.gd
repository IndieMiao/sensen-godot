class_name ParcelProfilePage
extends Control
## The dynamic farm's profile in UI v3 (C-108; C-85 page ①, owner-approved D-201/D-202 in Q-124; LOCK-22 lifted in
## C-82#19). The approved dynamic-farm version (①-D): only the blocks this package has data for. Full screen:
##   hero      330 high at the top: the saved outfit rendered live and large (BagCharacterPreview; a sideways drag
##             turns it), `Edit look ›` as a white pill (32 high, the shirt glyph) 16 from the right, its top at 252
##   top bar   over the hero, fixed: a glass ‹ Back, the `Profile` name tag, a glass gear (Settings) at the right
##   paper     from y 300 over the hero's foot, radius 20 at the top, 20 / 16 in: the name (20 ExtraBold), the home line
##             (12 Bold muted) when there is one, `My farm` (16 ExtraBold) and the farm card when there is a home
## No skills, collections or voice: no data for them here (①-D ⑦, a new function the owner approved).
## Motion (① 动效): the paper rises 40 and fades in over 260 (cubic out) while the figure eases from ×1.04 to ×1 over 320;
## scrolling moves the figure at half the speed (parallax) and, past 200, puts the strong glass behind the top bar
## (fades in over 120). `Look saved` (back from the dressing room's Done) is a toast under the top bar (UiBarToast).
## Emits back_pressed, settings_pressed, edit_look_pressed, farm_pressed.

signal back_pressed
signal settings_pressed
signal edit_look_pressed
signal farm_pressed

const HERO_H := 330.0
const PAPER_TOP := 300.0
const FIGURE := Vector2(156, 264)
const FIGURE_BOTTOM := 296.0       # the feet, just above where the paper starts
const EDIT_PILL_TOP := 252.0
const EDIT_PILL_H := 32.0
const PAPER_PAD := Vector2(16, 20)
const SECTION_GAP := 18.0          # .h3: 18 above a section title, 8 under it
const SECTION_TITLE_GAP := 8.0
const BAR_FILL_AFTER := 200.0
const PARALLAX := 0.5
const TOAST_TOP := 84.0
const LOOK_SAVED_HOLD_S := 2.5
const FARM_THUMB := preload("res://assets/ui/v3/hero/hero_home.png")
const SHIRT := preload("res://assets/ui/icons/lucide/shirt.svg")
## The hero's sky over the garden (the design's light lime-to-mint backdrop, until C-86 draws a scene for it).
## The card's › (the design's #B3B0A6).
const CHEVRON := Color("B3B0A6")
const SKY_TOP := Color("F1F0D2")
const SKY_BOTTOM := Color("CFE3B4")

## {profile: {name, home_line?}, home: {name, status?, ready?}}; a missing block is left out.
var view := {}
var safe_top := 0.0
var preview: BagCharacterPreview
var spin: P0ProfilePage._Spin
var scroll: ScrollContainer
var top_bar: HBoxContainer
var name_label: Label
var farm_card: Button
var edit_look_button: Button
var toast: UiBarToast
var _bar_fill: Panel
var _paper: PanelContainer
var _figure_box: Control
var _bar_filled := false

func _init(view_: Dictionary = {}, safe_top_ := 0.0) -> void:
	view = view_
	safe_top = safe_top_
	name = "ParcelProfilePage"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UiTokens.COLOR_SURFACE_PAPER
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	scroll = TouchScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var content := Control.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(content)
	content.add_child(_hero())
	_paper = _build_paper()
	content.add_child(_paper)
	_paper.minimum_size_changed.connect(_layout_content.bind(content))
	content.resized.connect(_layout_content.bind(content))
	scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	_bar_fill = Panel.new()
	_bar_fill.name = "TopBarFill"
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_fill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_GLASS_FILL_STRONG, 0.0))
	_bar_fill.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_fill.modulate.a = 0.0
	add_child(_bar_fill)
	add_child(_top_bar())

func _ready() -> void:
	_bar_fill.offset_bottom = top_bar.offset_bottom + UiTokens.SPACE_S2
	_enter_motion()

## Back from the dressing room with Done (KEEP-P0-2): `Look saved` under the top bar for 2.5 s.
func show_look_saved() -> UiBarToast:
	if is_instance_valid(toast): toast.queue_free()
	toast = UiBarToast.new("Look saved", UiBarToast.Kind.SUCCESS)
	return toast.pop(self, TOAST_TOP + safe_top, LOOK_SAVED_HOLD_S)

func _top_bar() -> HBoxContainer:
	top_bar = HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_theme_constant_override(&"separation", UiTokens.SPACE_S4)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var inset := (UiTokens.SIZE_TOUCH_MIN - UiTokens.SIZE_HUD_SIDE_BUTTON) * 0.5
	top_bar.offset_left = UiTokens.SIZE_SCREEN_EDGE - inset
	top_bar.offset_right = -(UiTokens.SIZE_SCREEN_EDGE - inset)
	top_bar.offset_top = UiTokens.SIZE_SCREEN_SAFE_INSET + safe_top
	top_bar.offset_bottom = top_bar.offset_top + UiTokens.SIZE_TOUCH_MIN
	var back := UiGlassButton.new(null, UiGlassButton.Glyph.BACK)
	back.name = "Back"
	back.tooltip_text = "Back"
	back.pressed.connect(func(): back_pressed.emit())
	top_bar.add_child(back)
	var tag := UiTagPill.new("Profile")
	tag.name = "Title"
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_bar.add_child(tag)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	var gear := UiGlassButton.new(null, UiGlassButton.Glyph.GEAR)
	gear.name = "Settings"
	gear.tooltip_text = "Settings"
	gear.pressed.connect(func(): settings_pressed.emit())
	top_bar.add_child(gear)
	return top_bar

func _hero() -> Control:
	var hero := Control.new()
	hero.name = "Hero"
	hero.mouse_filter = Control.MOUSE_FILTER_PASS
	hero.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hero.custom_minimum_size.y = HERO_H + safe_top
	hero.offset_bottom = HERO_H + safe_top
	var sky := TextureRect.new()
	sky.name = "Sky"
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.set_color(0, SKY_TOP)
	g.set_color(1, SKY_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 4
	tex.height = 64
	sky.texture = tex
	hero.add_child(sky)
	# The figure in a box of its own: the box moves for the parallax and scales for the entry, the preview inside it
	# keeps its size (it renders at its own size).
	_figure_box = Control.new()
	_figure_box.name = "Figure"
	_figure_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_figure_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_figure_box.offset_left = -FIGURE.x * 0.5
	_figure_box.offset_right = FIGURE.x * 0.5
	_figure_box.offset_top = FIGURE_BOTTOM + safe_top - FIGURE.y
	_figure_box.offset_bottom = FIGURE_BOTTOM + safe_top
	hero.add_child(_figure_box)
	preview = BagCharacterPreview.new()
	preview.custom_minimum_size = FIGURE
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_figure_box.add_child(preview)
	spin = P0ProfilePage._Spin.new()
	spin.preview = preview
	spin.set_anchors_preset(Control.PRESET_FULL_RECT)
	hero.add_child(spin)   # under `Edit look`, which stays a button
	edit_look_button = _edit_pill()
	edit_look_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	edit_look_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	edit_look_button.offset_right = -UiTokens.SPACE_PAGE
	# The pill is 32 high; its 44 hit area reaches 6 above and below it.
	var hit_pad := (UiTokens.SIZE_TOUCH_MIN - EDIT_PILL_H) * 0.5
	edit_look_button.offset_top = EDIT_PILL_TOP + safe_top - hit_pad
	edit_look_button.offset_bottom = EDIT_PILL_TOP + safe_top + EDIT_PILL_H + hit_pad
	hero.add_child(edit_look_button)
	hero.ready.connect(func(): preview.set_active(true))
	return hero

## `Edit look ›`: a white pill 32 high (E1, 12 in, the shirt glyph 16, 13 ExtraBold) in a 44 high hit area.
func _edit_pill() -> Button:
	var b := Button.new()
	b.name = "EditLook"
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var pill := PanelContainer.new()
	pill.name = "Pill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, EDIT_PILL_H * 0.5)
	box.content_margin_left = UiTokens.SPACE_S5
	box.content_margin_right = UiTokens.SPACE_S5
	box.shadow_color = UiTokens.ELEVATION_E1_COLOR
	box.shadow_size = UiTokens.ELEVATION_E1_BLUR
	box.shadow_offset = Vector2(0, UiTokens.ELEVATION_E1_OFFSET_Y)
	pill.add_theme_stylebox_override(&"panel", box)
	box.content_margin_top = 0.0
	box.content_margin_bottom = 0.0
	pill.custom_minimum_size.y = EDIT_PILL_H
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", UiTokens.SPACE_S3)
	pill.add_child(row)
	var icon := UiKit.icon(SHIRT, 16)
	icon.modulate = UiTokens.COLOR_TEXT_PRIMARY
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := UiKit.label("Edit look ›", UiTokens.STYLE_TYPE_LABEL)
	text.name = "Text"
	text.add_theme_font_override(&"font", load("res://assets/ui/fonts/nunito_w800.tres"))
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)
	b.add_child(pill)
	b.custom_minimum_size = Vector2(0, UiTokens.SIZE_TOUCH_MIN)
	# The pill 32 high in the middle of the 44 hit area, as wide as its row (a Button lays out no children).
	var fit := func():
		var w := pill.get_combined_minimum_size().x
		b.custom_minimum_size.x = w
		pill.position = Vector2(0.0, (b.size.y - EDIT_PILL_H) * 0.5)
		pill.size = Vector2(maxf(w, b.size.x), EDIT_PILL_H)
		pill.pivot_offset = pill.size * 0.5
	pill.minimum_size_changed.connect(fit)
	b.resized.connect(fit)
	fit.call()
	b.pressed.connect(func(): edit_look_pressed.emit())
	b.button_down.connect(func(): UiMotion.press(pill, true))
	b.button_up.connect(func(): UiMotion.press(pill, false))
	return b

func _build_paper() -> PanelContainer:
	var paper := PanelContainer.new()
	paper.name = "Paper"
	paper.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := StyleBoxFlat.new()
	box.bg_color = UiTokens.COLOR_SURFACE_PAPER
	box.corner_radius_top_left = UiTokens.RADIUS_XL
	box.corner_radius_top_right = UiTokens.RADIUS_XL
	box.content_margin_left = PAPER_PAD.x
	box.content_margin_right = PAPER_PAD.x
	box.content_margin_top = PAPER_PAD.y
	box.content_margin_bottom = PAPER_PAD.y + UiTokens.SPACE_SECTION
	box.anti_aliasing = true
	paper.add_theme_stylebox_override(&"panel", box)
	var col := VBoxContainer.new()
	col.name = "Column"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 0)
	paper.add_child(col)
	var p: Dictionary = view.get("profile", {})
	var shown_name := str(p.get("name", ""))
	name_label = UiKit.label(shown_name if shown_name != "" else "You", UiTokens.STYLE_TYPE_TITLE)
	name_label.name = "Name"
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # a chosen name is never translated
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_label)
	var home_line := str(p.get("home_line", ""))
	if home_line != "":
		_gap(col, UiTokens.SPACE_S3)
		var line := UiKit.label(home_line, UiTokens.STYLE_TYPE_CAPTION, UiTokens.COLOR_TEXT_MUTED)
		line.name = "HomeLine"
		col.add_child(line)
	var home: Dictionary = view.get("home", {})
	if not home.is_empty():
		_section(col, "My farm")
		farm_card = _farm_card(home)
		col.add_child(farm_card)
	return paper

func _section(col: VBoxContainer, title: String) -> void:
	_gap(col, SECTION_GAP)
	var t := UiKit.label(title, UiTokens.STYLE_TYPE_HEADLINE)
	t.name = "Section" + title.replace(" ", "")
	col.add_child(t)
	_gap(col, SECTION_TITLE_GAP)

## The farm card (①-A ④): a white card, radius 16, E1, 10 in: the 64 thumbnail (radius 12), the home's name
## (15 Bold) and its status line (12 Bold; deep green when something is ready), ›. Tapping it goes home.
func _farm_card(home: Dictionary) -> Button:
	var b := Button.new()
	b.name = "FarmCard"
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var card := PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, UiTokens.RADIUS_LG)
	box.set_content_margin_all(10)
	box.content_margin_right = UiTokens.SPACE_S6
	box.shadow_color = UiTokens.ELEVATION_E1_COLOR
	box.shadow_size = UiTokens.ELEVATION_E1_BLUR
	box.shadow_offset = Vector2(0, UiTokens.ELEVATION_E1_OFFSET_Y)
	card.add_theme_stylebox_override(&"panel", box)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", UiTokens.SPACE_S5)
	card.add_child(row)
	var thumb := _Thumb.new()
	thumb.texture = FARM_THUMB
	thumb.custom_minimum_size = Vector2(64, 64)
	row.add_child(thumb)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override(&"separation", UiTokens.SPACE_S3)
	row.add_child(lines)
	var title := UiKit.label(str(home.get("name", "")) if str(home.get("name", "")) != "" else "Your Home", UiTokens.STYLE_TYPE_BODY_BOLD)
	title.name = "FarmName"
	title.add_theme_font_size_override(&"font_size", 15)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lines.add_child(title)
	var status := str(home.get("status", ""))
	if status != "":
		var s := UiKit.label(status, UiTokens.STYLE_TYPE_CAPTION,
			UiTokens.COLOR_PRIMARY_INK if bool(home.get("ready", false)) else UiTokens.COLOR_TEXT_MUTED)
		s.name = "FarmStatus"
		s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lines.add_child(s)
	var chevron := UiKit.label("›", UiTokens.STYLE_TYPE_HEADLINE, CHEVRON)
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chevron)
	b.add_child(card)
	b.custom_minimum_size.y = 84.0
	b.pressed.connect(func(): farm_pressed.emit())
	b.button_down.connect(func(): UiMotion.press(card, true))
	b.button_up.connect(func(): UiMotion.press(card, false))
	return b

func _gap(col: Control, h: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = h
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(g)

## The paper starts at 300 and reaches at least the screen's foot; the content is as tall as both.
func _layout_content(content: Control) -> void:
	var w := scroll.size.x if scroll.size.x > 0.0 else size.x
	var paper_h := maxf(_paper.get_combined_minimum_size().y, size.y - PAPER_TOP - safe_top)
	_paper.position = Vector2(0, PAPER_TOP + safe_top)
	_paper.size = Vector2(w, paper_h)
	content.custom_minimum_size = Vector2(0, PAPER_TOP + safe_top + paper_h)

func _on_scrolled(value: float) -> void:
	if _figure_box != null: _figure_box.position.y = FIGURE_BOTTOM + safe_top - FIGURE.y + value * PARALLAX
	var filled := value > BAR_FILL_AFTER
	if filled == _bar_filled: return
	_bar_filled = filled
	var tw := UiMotion.tween(_bar_fill, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_property(_bar_fill, "modulate:a", 1.0 if filled else 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))

func bar_filled() -> bool: return _bar_filled

## ① 动效 1: the paper rises 40 and fades in (260, cubic out); the figure eases from ×1.04 to ×1 (320).
func _enter_motion() -> void:
	if UiMotion.reduced:
		modulate.a = 0.0
		UiMotion.tween(self, UiTokens.MOTION_EASING_LINEAR).tween_property(self, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		return
	_paper.modulate.a = 0.0
	var rest := PAPER_TOP + safe_top
	_paper.position.y = rest + 40.0
	var tw := UiMotion.tween(_paper, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_property(_paper, "position:y", rest, UiMotion.secs(UiTokens.MOTION_DURATION_MODERATE_MS))
	tw.parallel().tween_property(_paper, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_MODERATE_MS))
	_figure_box.pivot_offset = Vector2(FIGURE.x * 0.5, FIGURE.y)
	_figure_box.scale = Vector2.ONE * 1.04
	var fig := UiMotion.tween(_figure_box, UiTokens.MOTION_EASING_STANDARD)
	fig.tween_property(_figure_box, "scale", Vector2.ONE, UiMotion.secs(UiTokens.MOTION_DURATION_EMPHASIS_MS))

## The 64 farm thumbnail, cut to radius 12.
class _Thumb extends Control:
	var texture: Texture2D
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = UiTokens.COLOR_SURFACE_SUNKEN
		box.set_corner_radius_all(12)
		box.anti_aliasing = true
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		if texture != null: draw_texture_rect(texture, Rect2(Vector2(4, 4), size - Vector2(8, 8)), false)
