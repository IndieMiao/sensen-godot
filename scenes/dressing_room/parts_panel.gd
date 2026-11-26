extends Control
## The dressing room's sheet in UI v3 (C-108; C-85 page ②-A/B, owner-approved in Q-124; LOCK-22 lifted in C-82#19).
## Only slots with a real choice show; part ids are internal values and never reach the screen.
##   sheet   `surface/paper` to the screen's foot, radius 20 at the top, a soft shadow upwards
##   band    the `surface/header` band, 52 high: the hero object (72, C-86's hanger) out over its top edge at the left;
##           the slot tabs from x 96 to 12 from the right, Ø44 chips (white 55 %; the open one white with a 3 lime ring),
##           each a C-86 tab icon 22 (the open one in colour, the others desaturated and darker, C-I4)
##   title   the open slot's name (Hair, Outfits, …) 16 ExtraBold, 20 in, 6 under the band
##   grid    Ø72 round cells, four to a row 12 apart (rows 14 apart), 18 in, from 34 under the band: the part's
##           rendered thumbnail on #ECEBE5, its name in 12 Bold under it; the worn one white with a 3 lime ring and
##           its name in deep green ExtraBold; while it loads, a lime arc turns on it over the dimmed thumbnail (②-B)
## Motion (② 动效): the sheet rises 40 and fades in over 260 (cubic out), the hero object drops in from 12 lower at
## ×0.6 after 80 (M-06, 320 back out); a tab switch slides the grid 16 in the switch's direction as it fades in (M-09,
## 120); choosing a part grows its ring in (M-03, 120); cells press with M-01.

signal selection_failed(message: String)
signal selection_started
## Only when the player taps a tab: setup()'s first slot and direct calls from tests or previews do not emit it — the
## room should open on the whole figure, not zoomed on the head.
signal slot_changed(slot: StringName)

const BAND_H := 52.0
const HERO := 72.0
const HERO_LEFT := 12.0
const HERO_OVER := 34.0
const TABS_LEFT := 96.0
const TABS_RIGHT := 12.0
const CHIP := 44.0
const CHIP_RING := 3.0
const CHIP_ICON := 22.0
const TITLE_TOP := 6.0          # under the band
const GRID_TOP := 34.0          # under the band
const GRID_SIDE := 18.0
const CELL := 72.0
const CELL_GAP_X := 12.0
const CELL_GAP_Y := 14.0
const CELL_LABEL_GAP := 4.0
const CELL_RING := 3.0
const COLUMNS := 4
## The cell's thumbnail box inside the circle (the design's 56 × 46, kept square for the renders: 52).
const THUMB := 52.0
const SHEET_SHADOW := Color(0.102, 0.078, 0.039, 0.18)
const SLOT_TINT := Color("ECEBE5")
const SELECTED_INK := Color("3F5A12")
const CHIP_IDLE := Color(1, 1, 1, 0.55)
const ICON_NONE := preload("res://assets/ui/icons/none.svg")
const HERO_ART := preload("res://assets/ui/v3/hero/hero_dressing.png")
const _DESATURATE := preload("res://scenes/dressing_room/tab_icon.gdshader")

const SLOT_LABELS := {
	&"hairHat": "Hair",
	&"cloth": "Outfits",
	&"shoes": "Shoes",
	&"messengerBag": "Bags",
	&"glass": "Glasses",
}
## C-86's tab icons (UiArt color/icon_dress_*).
const SLOT_ICONS := {&"hairHat": "dress_hair", &"cloth": "dress_cloth", &"shoes": "dress_shoes", &"messengerBag": "dress_bag", &"glass": "dress_glasses"}

const PART_LABELS := {
	"hairhat0": "Silver Crop",
	"hairhat20": "Playful Hood",
	"hairhat41": "Chestnut Long",
	"hairhat43": "Blonde Bob",
	"hairhat51": "Straw Bucket",
	"hairhat70": "Propeller Cap",
	"cloth0": "Mint Casual",
	"cloth1": "Cream Suit",
	"cloth1_1": "Blue Stripe",
	"cloth11": "Garden Apron",
	"cloth28": "Navy Utility",
	"cloth42": "Blue Overalls",
	"shoes0": "Gray Sneakers",
	"shoes1": "Cream Loafers",
	"shoes2": "Coral Sneakers",
	# A cell's name line is 72 + 12 wide at 12 Bold (about 14 characters); a longer name cuts with …. Keep new names
	# within 14 characters.
	"shoes3": "Black Runners",
	"shoes4": "Graffiti Tops",
	"shoes5": "Sand Boots",
	"messengerbag1": "Coral Satchel",
	"messengerbag2": "Court Sling",
	"messengerbag3": "Explorer Kit",
	"messengerbag4": "Playful Pack",
	"glass0": "Classic Black",
	"glass1": "Minimal Square",
	"glass3": "Gold Rounds",
	"glass5": "Lime Frames",
	"glass8": "Sharp Shades",
}

var rig: AvatarRig
var thumbnailer: PartThumbnailer
var current_slot: StringName = &""
var sheet: Panel
var band: Panel
var hero: TextureRect
var tabs: Control
var title: Label
var scroll: ScrollContainer
var grid: GridContainer
var _interaction_enabled := true
var _compact := false
var _tab_buttons: Dictionary = {}
var _choice_buttons: Dictionary = {}
var _slot_order: Array[StringName] = []
## Bumped by every _show_slot; a thumbnail arriving late checks it is still for the slot on screen, or a quick run
## of tab taps would put the last slot's pictures on the new buttons.
var _slot_generation := 0
## The slot's cells were just made: its worn cell shows its ring at once, without M-03.
var _first_state := true

func _init() -> void:
	name = "Drawer"
	mouse_filter = Control.MOUSE_FILTER_STOP
	sheet = Panel.new()
	sheet.name = "Sheet"
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = UiTokens.COLOR_SURFACE_PAPER
	box.corner_radius_top_left = UiTokens.RADIUS_XL
	box.corner_radius_top_right = UiTokens.RADIUS_XL
	box.shadow_color = SHEET_SHADOW
	box.shadow_size = 24
	box.shadow_offset = Vector2(0, -6)
	box.anti_aliasing = true
	sheet.add_theme_stylebox_override(&"panel", box)
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sheet)
	band = Panel.new()
	band.name = "Band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bb := StyleBoxFlat.new()
	bb.bg_color = UiTokens.COLOR_SURFACE_HEADER
	bb.corner_radius_top_left = UiTokens.RADIUS_XL
	bb.corner_radius_top_right = UiTokens.RADIUS_XL
	bb.anti_aliasing = true
	band.add_theme_stylebox_override(&"panel", bb)
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = BAND_H
	add_child(band)
	title = UiKit.label("", UiTokens.STYLE_TYPE_HEADLINE)
	title.name = "SlotTitle"
	title.position = Vector2(20, BAND_H + TITLE_TOP)
	add_child(title)
	scroll = TouchScrollContainer.new()
	scroll.name = "PartsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = BAND_H + GRID_TOP - CELL_RING   # the worn cell's ring is not cut at the top
	add_child(scroll)
	var pad := MarginContainer.new()
	pad.name = "GridPad"
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override(&"margin_left", int(GRID_SIDE))
	pad.add_theme_constant_override(&"margin_right", int(GRID_SIDE))
	pad.add_theme_constant_override(&"margin_top", int(CELL_RING))
	pad.add_theme_constant_override(&"margin_bottom", int(UiTokens.SPACE_PAGE))
	scroll.add_child(pad)
	grid = GridContainer.new()
	grid.name = "PartsGrid"
	grid.columns = COLUMNS
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", int(CELL_GAP_X))
	grid.add_theme_constant_override(&"v_separation", int(CELL_GAP_Y))
	pad.add_child(grid)
	tabs = Control.new()
	tabs.name = "SlotTabs"
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tabs.offset_left = TABS_LEFT
	tabs.offset_right = -TABS_RIGHT
	tabs.offset_top = (BAND_H - CHIP) * 0.5
	tabs.offset_bottom = tabs.offset_top + CHIP
	tabs.resized.connect(_place_tabs)
	add_child(tabs)
	hero = UiKit.icon(HERO_ART, HERO)
	hero.name = "Hero"
	hero.position = Vector2(HERO_LEFT, -HERO_OVER)
	hero.size = Vector2(HERO, HERO)
	add_child(hero)
	resized.connect(_fit_columns)

func setup(p_rig: AvatarRig) -> void:
	rig = p_rig
	for c in tabs.get_children():
		tabs.remove_child(c)
		c.queue_free()
	_tab_buttons.clear()
	_slot_order.clear()
	for slot_def in Avatar.slot_table.slots:
		var parts: Array = Avatar.catalog.parts_for_slot(slot_def.slot_name)
		var choice_count := parts.size() + (0 if slot_def.required else 1)
		if choice_count <= 1:
			continue
		var chip := _SlotChip.new(UiArt.color(str(SLOT_ICONS.get(slot_def.slot_name, "dress_cloth"))), _DESATURATE)
		chip.name = "Tab_" + String(slot_def.slot_name)
		chip.tooltip_text = _slot_label(slot_def.slot_name)
		chip.pressed.connect(_show_slot.bind(slot_def.slot_name, true))
		tabs.add_child(chip)
		_tab_buttons[slot_def.slot_name] = chip
		_slot_order.append(slot_def.slot_name)
	_place_tabs()
	rig.slot_applied.connect(_on_slot_applied)
	rig.part_load_failed.connect(_on_part_load_failed)
	rig.busy_changed.connect(_on_busy_changed)
	if not _tab_buttons.is_empty():
		_show_slot(_tab_buttons.keys()[0])

## ② 动效 1: the sheet rises 40 and fades in (260, cubic out); the hero object drops in after 80 (M-06).
func play_enter() -> void:
	if UiMotion.reduced:
		modulate.a = 0.0
		UiMotion.tween(self, UiTokens.MOTION_EASING_LINEAR).tween_property(self, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		return
	var rest := position.y
	position.y = rest + 40.0
	modulate.a = 0.0
	var tw := UiMotion.tween(self, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_property(self, "position:y", rest, UiMotion.secs(UiTokens.MOTION_DURATION_MODERATE_MS))
	tw.parallel().tween_property(self, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_MODERATE_MS))
	hero.pivot_offset = Vector2(HERO * 0.5, HERO)
	hero.scale = Vector2.ONE * 0.6
	hero.position.y = -HERO_OVER + 12.0
	var hw := UiMotion.tween(hero, UiTokens.MOTION_EASING_POP)
	hw.tween_interval(UiMotion.secs(80))
	hw.tween_property(hero, "scale", Vector2.ONE, UiMotion.secs(UiTokens.MOTION_DURATION_EMPHASIS_MS))
	hw.parallel().tween_property(hero, "position:y", -HERO_OVER, UiMotion.secs(UiTokens.MOTION_DURATION_EMPHASIS_MS))

func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	_refresh_state()

## Shorter screens: nothing changes in the cells (they stay Ø72); the sheet is shorter and its grid scrolls sooner.
func set_compact(compact: bool) -> void:
	_compact = compact

func refresh() -> void:
	_refresh_state()

func visible_slot_names() -> Array[StringName]:
	var result: Array[StringName] = []
	for slot in _tab_buttons:
		result.append(slot)
	return result

func choice_buttons() -> Dictionary: return _choice_buttons

## The cells' gaps share the width left on a wider screen, four to a row at least 12 apart.
func _fit_columns() -> void:
	var inner := size.x - GRID_SIDE * 2.0
	var gap := maxf(CELL_GAP_X, floorf((inner - CELL * COLUMNS) / float(COLUMNS - 1)))
	grid.add_theme_constant_override(&"h_separation", int(gap))

func _place_tabs() -> void:
	var n := tabs.get_child_count()
	if n == 0: return
	var w := tabs.size.x
	var step := (w - CHIP) / float(maxi(1, n - 1)) if n > 1 else 0.0
	for i in n:
		var chip := tabs.get_child(i) as Control
		chip.size = Vector2(CHIP, CHIP)
		chip.position = Vector2(roundf(step * i) if n > 1 else (w - CHIP) * 0.5, 0.0)

func _show_slot(slot: StringName, user_initiated := false) -> void:
	if not _tab_buttons.has(slot):
		return
	var previous := current_slot
	current_slot = slot
	if user_initiated:
		slot_changed.emit(slot)
	title.text = _slot_label(slot)
	title.size = title.get_minimum_size()
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	_choice_buttons.clear()
	_first_state = true
	_slot_generation += 1
	var slot_def := Avatar.slot_table.slot(slot)
	if slot_def and not slot_def.required:
		_add_choice("", _none_label(slot))
	var index := 0
	for meta in Avatar.catalog.parts_for_slot(slot):
		_add_choice(meta.id, _part_label(slot, meta.id, index))
		index += 1
	_refresh_state()
	scroll.scroll_vertical = 0
	if user_initiated and previous != &"" and previous != slot: _slide_grid(_slot_order.find(slot) > _slot_order.find(previous))
	_fill_thumbnails(_slot_generation)

## M-09 (tabs): the new grid comes 16 in from the side the switch went towards and fades in, 120.
func _slide_grid(forward: bool) -> void:
	if UiMotion.reduced: return
	var pad := grid.get_parent() as Control
	var from := 16.0 if forward else -16.0
	pad.modulate.a = 0.0
	var tw := UiMotion.tween(pad, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_method(func(t: float):
		pad.modulate.a = t
		grid.position.x = (1.0 - t) * from, 0.0, 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))

func _add_choice(part_id: String, label: String) -> void:
	var cell := _PartCell.new(label)
	cell.focus_mode = Control.FOCUS_NONE
	# A short press is the cell's; a drag goes on to the ScrollContainer.
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.tooltip_text = label
	if part_id.is_empty():
		cell.thumb = ICON_NONE
		cell.none = true
	cell.set_meta(&"part_id", part_id)
	cell.pressed.connect(_select_part.bind(current_slot, part_id))
	grid.add_child(cell)
	_choice_buttons[part_id] = cell

## Renders the thumbnails one by one and fills them in. Serial on purpose: one SubViewport is shared, and one part a
## frame keeps the frame time in hand (a slot opened for the first time fills in over a few frames).
func _fill_thumbnails(generation: int) -> void:
	if thumbnailer == null:
		return
	for part_id in _choice_buttons.keys():
		if part_id.is_empty():
			continue
		var texture: Texture2D = await thumbnailer.thumbnail(part_id)
		# The player may have switched slots meanwhile: then this batch is dropped.
		if generation != _slot_generation or not is_inside_tree():
			return
		var cell := _choice_buttons.get(part_id) as _PartCell
		if texture != null and is_instance_valid(cell):
			cell.thumb = texture

func _select_part(slot: StringName, part_id: String) -> void:
	if not _interaction_enabled or rig == null:
		return
	selection_started.emit()
	if part_id.is_empty():
		rig.unequip(slot)
	else:
		rig.equip(slot, part_id)
	_refresh_state()

func _refresh_state() -> void:
	for slot in _tab_buttons:
		var chip := _tab_buttons[slot] as _SlotChip
		chip.disabled = not _interaction_enabled
		chip.selected = slot == current_slot
	if rig == null or current_slot == &"":
		return
	var selected := rig.desired_part(current_slot)
	var loading := rig.is_busy()
	for part_id in _choice_buttons:
		var cell := _choice_buttons[part_id] as _PartCell
		cell.disabled = not _interaction_enabled
		var on: bool = part_id == selected
		cell.loading = on and loading
		if on != cell.worn: cell.select(on, on and not _first_state)
	_first_state = false
	# The `Selected: X` line is gone for good: the worn cell has its ring, the figure wears it, and a busy Done shows
	# its three dots.

func _on_slot_applied(_slot: StringName, _part_id: String) -> void:
	_refresh_state()

func _on_busy_changed(_busy: bool) -> void:
	_refresh_state()

func _on_part_load_failed(slot: StringName, part_id: String, _err: int) -> void:
	var label := _part_label(slot, part_id)
	selection_failed.emit(L10n.format_text("Couldn't load %s. Previous look kept.", label))
	# AvatarRig rolls `desired` back only after the signal; read the final target on the next frame.
	call_deferred("_refresh_state")

func _slot_label(slot: StringName) -> String:
	return String(SLOT_LABELS.get(slot, L10n.text("Other")))

func _part_label(slot: StringName, part_id: String, fallback_index := -1) -> String:
	if PART_LABELS.has(part_id):
		return String(PART_LABELS[part_id])
	if fallback_index < 0:
		var parts: Array = Avatar.catalog.parts_for_slot(slot)
		for i in parts.size():
			if parts[i].id == part_id:
				fallback_index = i
				break
	return L10n.format_text("%s Style %d", [_slot_label(slot), maxi(fallback_index + 1, 1)])

func _none_label(slot: StringName) -> String:
	match slot:
		&"glass":
			return L10n.text("No Glasses")
		&"messengerBag":
			return L10n.text("No Bag")
		_:
			return L10n.text("None")

## A slot tab: a Ø44 chip on the band, white 55 % with the icon desaturated and darker (C-I4); the open one white,
## its icon in colour, a 3 `action/primary` ring round it. Presses with M-01; selecting plays M-03 (120).
class _SlotChip extends Button:
	var selected := false: set = set_selected
	var _icon: TextureRect
	var _ring := 0.0

	func _init(tex: Texture2D, shader: Shader) -> void:
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(CHIP, CHIP)
		for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		_icon = UiKit.icon(tex, CHIP_ICON)
		_icon.name = "Icon"
		_icon.position = Vector2.ONE * (CHIP - CHIP_ICON) * 0.5
		_icon.size = Vector2.ONE * CHIP_ICON
		_icon.pivot_offset = _icon.size * 0.5
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter(&"amount", 1.0)
		_icon.material = m
		add_child(_icon)
		UiMotion.press_feedback(self)

	func set_selected(v: bool) -> void:
		if v == selected and is_inside_tree(): return
		selected = v
		(_icon.material as ShaderMaterial).set_shader_parameter(&"amount", 0.0 if v else 1.0)
		if not is_inside_tree() or UiMotion.reduced:
			_ring = 1.0 if v else 0.0
			queue_redraw()
			return
		var tw := UiMotion.tween(self, UiTokens.MOTION_EASING_STANDARD if v else UiTokens.MOTION_EASING_EXIT)
		tw.tween_method(func(t: float):
			_ring = t
			queue_redraw(), _ring, 1.0 if v else 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		if v:
			var pop := UiMotion.tween(_icon, UiTokens.MOTION_EASING_POP)
			pop.tween_property(_icon, "scale", Vector2.ONE * 1.06, UiMotion.secs(60))
			pop.tween_property(_icon, "scale", Vector2.ONE, UiMotion.secs(60))

	func icon_rect() -> TextureRect: return _icon
	func ring() -> float: return _ring

	func _draw() -> void:
		var c := size * 0.5
		var r := CHIP * 0.5
		draw_circle(c, r, CHIP_IDLE.lerp(Color.WHITE, _ring), true, -1.0, true)
		if _ring > 0.0:
			var ring_col := UiTokens.COLOR_ACTION_PRIMARY
			ring_col.a *= _ring
			draw_arc(c, r + CHIP_RING * 0.5, 0.0, TAU, 48, ring_col, CHIP_RING, true)

## A part: the Ø72 circle (#ECEBE5; worn: white with a 3 lime ring) with the thumbnail, the name under it in 12 Bold
## (worn: deep green ExtraBold), … when it does not fit. `loading`: the thumbnail at 45 % and a lime arc turning on it.
class _PartCell extends Button:
	var thumb: Texture2D: set = set_thumb
	var none := false
	var loading := false: set = set_loading
	var worn := false
	var name_label: Label
	var _ring := 0.0
	var _spin := 0.0
	var _thumb_scale := 1.0

	func _init(label: String) -> void:
		flat = true
		for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		custom_minimum_size = Vector2(CELL, CELL + CELL_LABEL_GAP + 17.0)
		clip_contents = false
		name_label = UiKit.label(label, UiTokens.STYLE_TYPE_CAPTION, UiTokens.COLOR_TEXT_SECONDARY)
		name_label.name = "Name"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.position = Vector2(-CELL_GAP_X * 0.5, CELL + CELL_LABEL_GAP)
		name_label.size = Vector2(CELL + CELL_GAP_X, 17.0)
		name_label.clip_text = true
		add_child(name_label)
		button_down.connect(func(): UiMotion.press(self, true))
		button_up.connect(func(): UiMotion.press(self, false))

	func set_thumb(v: Texture2D) -> void:
		thumb = v
		queue_redraw()

	func set_loading(v: bool) -> void:
		if v == loading: return
		loading = v
		set_process(v)
		queue_redraw()

	func _ready() -> void:
		set_process(loading)

	func _process(delta: float) -> void:
		_spin = fmod(_spin + delta * TAU / 0.6, TAU)   # one turn in 600 ms (② 动效 2), linear
		queue_redraw()

	## Worn or not; `animate` plays M-03 (the ring 0 → 1 and the thumbnail ×1.06, 120).
	func select(v: bool, animate: bool) -> void:
		worn = v
		name_label.add_theme_color_override(&"font_color", SELECTED_INK if v else UiTokens.COLOR_TEXT_SECONDARY)
		if v: name_label.add_theme_font_override(&"font", load("res://assets/ui/fonts/nunito_w800.tres"))
		else: name_label.remove_theme_font_override(&"font")
		if not animate or not is_inside_tree() or UiMotion.reduced:
			_ring = 1.0 if v else 0.0
			_thumb_scale = 1.0
			queue_redraw()
			return
		var tw := UiMotion.tween(self, UiTokens.MOTION_EASING_STANDARD if v else UiTokens.MOTION_EASING_EXIT)
		tw.tween_method(func(t: float):
			_ring = t
			_thumb_scale = 1.0 + 0.06 * t * (1.0 - t) * 4.0 if v else 1.0
			queue_redraw(), _ring, 1.0 if v else 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))

	func ring() -> float: return _ring

	func _draw() -> void:
		var c := Vector2(CELL * 0.5, CELL * 0.5)
		var r := CELL * 0.5
		draw_circle(c, r, SLOT_TINT.lerp(Color.WHITE, _ring), true, -1.0, true)
		if _ring > 0.0:
			var ring_col := UiTokens.COLOR_ACTION_PRIMARY
			ring_col.a *= _ring
			draw_arc(c, r + CELL_RING * 0.5, 0.0, TAU, 64, ring_col, CELL_RING, true)
		if thumb != null:
			var side := (THUMB * 0.62 if none else THUMB) * _thumb_scale
			var tint := Color(1, 1, 1, 0.45 if loading else 1.0)
			draw_texture_rect(thumb, Rect2(c - Vector2.ONE * side * 0.5, Vector2.ONE * side), false, tint)
		if loading:
			draw_arc(c, 11.0, _spin, _spin + TAU * 0.62, 24, UiTokens.COLOR_ACTION_PRIMARY, 3.0, true)
