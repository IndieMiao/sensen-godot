class_name UiInfoSheet
extends PanelContainer
## InfoSheet (SGODOT-224; F-07 confirmed table on SGODOT-207 168a4cc3; LOCK-10 / 12 / 13 / 15): the item detail
## card inside the bag drawer, the Gear side, a counter and the gift drawer, drawn like Compact/SelectedItem
## 633:41257 (BAG-1 482:10). It draws the spec its rules give it (P0ItemInfo.spec bound to the live view); it decides
## nothing itself.
##   medallion (40, primary tint) · title, pin badge, LockToggle, ×N pill, › · state line (rarity, ★) ·
##   fact lines · the last fact on the button row's left, buttons on its right (nav Gift ›, compact commands).
##
##   rules: Callable(item_id: String, context: StringName, opts: Dictionary) -> Dictionary (the spec). Owners bind
##          it once, e.g. func(id, ctx, o): return P0ItemInfo.spec(ui.view, id, ctx, o).
##   open(item_id, context, opts := {})  shows or switches the card (tap another cell = open again).
##   refresh()                           rebuilds from rules (call when the view changed while open).
##   close()                             hides it; `closed` fires once per open. No own close button (F-07 关闭):
##                                       the owner closes on a tap on blank space or when its drawer closes.
##   action_requested(action, item_id, payload)  a button or the lock icon (&"lock" / &"unlock") was tapped;
##                                       the owner sends the command. Unavailable buttons don't emit it.
##   unavailable_requested(action, item_id, reason)  a greyed button was tapped (they stay tappable, LOCK-10); the
##                                       owner may say why or where, e.g. a Toast for `Gift to a resident` (225).
##   info_requested(item_id)             the › in the title row: open the item's page (Fish-dex / Cookbook / about).
##   liked_by: String     Gift Clues (Fishing Lv7, q(167); 302 b308ee14): `Liked by Hana · Old Kai` under the state line,
##                        a coral ♥ first, in the fact lines' type; "" hides it
## Optional spec blocks (the gate card, SKILL-2 482:169 / §4.8.7, SGODOT-233), in this order under the state line:
##   lead: String          one ExtraBold line in text ink ("Farming Lv2 unlocks Carrot and Herb")
##   need: {name, have, need, icon, note}   a NeedTile M in its count state ("Farming XP 32/50") with the note
##                         beside it ("18 XP to go · harvest 9 radishes")
##   info_row: {title, qty, lines}          Compact/Information row ("Carrot Seeds ×5" / "Level-up gift" / "At Lv2")
##   needs: [{id, name, have, need, icon}]  a group of NeedTile M, as many a row as fit (the counter's › card: a buy's
##                         materials, `Hardwood 0/4`; 不知火舞 on 284); a tap on one emits need_pressed

signal action_requested(action: StringName, item_id: String, payload: Dictionary)
signal unavailable_requested(action: StringName, item_id: String, reason: String)
signal info_requested(item_id: String)
signal closed
## A tile of the `needs` group was tapped (LOCK-10: a tap on a NEED-TILE shows where the item comes from).
signal need_pressed(item_id: String, tile: UiNeedTile)

## LockToggle 1539:97939 (F-07, 安其拉 10-08): outline open lock in secondary ink / solid closed lock in text ink.
const LOCK_OPEN_GLYPH := preload("res://assets/ui/kit_icons/lock_open.svg")
const LOCK_CLOSED_GLYPH := preload("res://assets/ui/kit_icons/lock_closed.svg")
const PIN_GLYPH := preload("res://assets/ui/kit_icons/pin.svg")
# Compact/SelectedItem 633:41257 (336 × 82): insets 10 / 10 / 8 / 0, medallion 40 (radius 20) with a 27 icon,
# text column at x 58 (gap 8), quantity pill 18 high (radius 9), chevron 14, buttons in 44 touch rows.
const _PAD_L := 10.0
const _PAD_T := 10.0
const _PAD_R := 8.0
const _MEDALLION := 40.0
const _MEDALLION_ICON := 27.0
const _GAP := 8.0
const _PILL_H := 18.0
const _PILL_PAD := 4.0
const _GLYPH := 14.0
const _BUTTON_ROW_Y := 38.0   # the 44 touch row starts at y 38, over the end of the state line (y 42)
# SKILL-2 sheet content (482:169): blocks 8 apart, the NeedTile and its note 10 apart, the info row's lines 3 apart.
const _BLOCK_GAP := 8.0
const HEART_GLYPH := preload("res://assets/p0/icons/heart.svg")   # solid #E07A5F (StatusBadge Gift's coral)
const _LIKED_ICON := 12.0
const _LIKED_GAP := 4.0
const _NEED_GAP := 10.0
const _INFO_GAP := 3.0

var rules: Callable

var _item := ""
var _context: StringName = &""
var _opts := {}
var _spec := {}
var _icon: TextureRect
var _title: Label
var _badge: TextureRect
var _qty: Label
var _qty_pill: PanelContainer
var _lock: Control
var _chevron: Label
var _lift: MarginContainer
var _state: Label
var _liked: HBoxContainer   # Gift Clues: ♥ Liked by …
var _liked_label: Label
var _facts: VBoxContainer
var _blocks: VBoxContainer   # lead, need and info_row (gate card); empty for an item card
var _medallion: Panel
var _box: UiStyleBox
var _effect: Label
var _last_fact := ""      # goes beside the buttons when it fits there, otherwise on its own fact line
var _overflow: Label      # that own line (last in _facts, hidden while the fact fits beside the buttons)
var _effect_note: Label   # spec.fact_note under that fact, secondary (q(252) ③ `6 each` over `8 at home`)
var _overflow_note: Label # the note's own line under _overflow when the fact does not fit beside the buttons
var _buttons: HBoxContainer

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # taps on the card never reach the grid or the world behind it
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER, UiTokens.STROKE_CELL_HAIRLINE)
	box.with_margins(_PAD_L, _PAD_T, _PAD_R, 0.0)
	add_theme_stylebox_override(&"panel", box)
	_box = box
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(_GAP))
	add_child(row)
	var medallion := Panel.new()
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medallion.custom_minimum_size = Vector2(_MEDALLION, _MEDALLION)
	medallion.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_medallion = medallion
	medallion.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, _MEDALLION * 0.5))
	_icon = UiKit.icon(null, _MEDALLION_ICON)
	_icon.position = Vector2.ONE * (_MEDALLION - _MEDALLION_ICON) * 0.5
	medallion.add_child(_icon)
	row.add_child(medallion)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 0)
	row.add_child(col)
	col.add_child(_title_row())
	_state = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	col.add_child(_state)
	_liked = HBoxContainer.new()
	_liked.name = "LikedBy"
	_liked.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_liked.add_theme_constant_override(&"separation", int(_LIKED_GAP))
	var heart := UiKit.icon(HEART_GLYPH, _LIKED_ICON)
	heart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_liked.add_child(heart)
	_liked_label = UiKit.label("", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	_liked.add_child(_liked_label)
	col.add_child(_liked)
	_blocks = VBoxContainer.new()
	_blocks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocks.add_theme_constant_override(&"separation", int(_BLOCK_GAP))
	col.add_child(_blocks)
	_facts = VBoxContainer.new()
	_facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_facts.add_theme_constant_override(&"separation", 0)
	col.add_child(_facts)
	var lift := MarginContainer.new()
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lift)
	_lift = lift
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	bottom.add_theme_constant_override(&"separation", int(_GAP))
	lift.add_child(bottom)
	var effect_box := VBoxContainer.new()
	effect_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_box.alignment = BoxContainer.ALIGNMENT_CENTER
	effect_box.add_theme_constant_override(&"separation", 0)
	bottom.add_child(effect_box)
	_effect = UiKit.label("", UiTokens.STYLE_C12_XB)
	_effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effect.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_effect.clip_text = true   # a fact too long for this slot moves to the fact lines (_place_last_fact)
	effect_box.add_child(_effect)
	_effect_note = UiKit.label("", UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	_effect_note.clip_text = true
	_effect_note.visible = false
	effect_box.add_child(_effect_note)
	bottom.resized.connect(_place_last_fact)
	_buttons = HBoxContainer.new()
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons.add_theme_constant_override(&"separation", int(_GAP))
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(_buttons)
	visible = false

func _title_row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	_title = UiKit.label("", UiTokens.STYLE_C14_XB)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(_title)
	_badge = UiKit.icon(null, _GLYPH)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_badge)
	# LockToggle sits left of the count: `icon · name … 🔒 ×3 ›` (225 walkthrough 2fcfd08f).
	_lock = _lock_icon()
	h.add_child(_lock)
	_qty_pill = PanelContainer.new()
	_qty_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty_pill.custom_minimum_size.y = _PILL_H
	_qty_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_qty_pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, _PILL_H * 0.5).with_margins(_PILL_PAD, 0, _PILL_PAD, 0))
	_qty = UiKit.label("", UiTokens.STYLE_C11_XB)
	_qty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_qty_pill.add_child(_qty)
	h.add_child(_qty_pill)
	_chevron = UiKit.label("›", UiTokens.STYLE_C14_B, UiTokens.COLOR_SECONDARY)
	_chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_chevron)
	# "Details touch target" in the main covers the title area: tapping it (not the lock) opens the item's page.
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	h.gui_input.connect(func(e: InputEvent): if _tapped(e) and bool(_spec.get("info", false)): info_requested.emit(_item))
	return h

## The title-area LockToggle (1539:97939): a 14 px glyph with a 44 px touch area centred on it (F-07: 触区 44),
## outside the layout. Locked, the lock is the stack's Locked badge too; a locked stack whose lock can't be
## toggled here still shows it, without the touch area.
func _lock_icon() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(_GLYPH, _GLYPH)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var glyph := UiKit.icon(LOCK_OPEN_GLYPH, _GLYPH)
	glyph.name = "Glyph"
	c.add_child(glyph)
	var hit := Control.new()
	hit.name = "Hit"
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_TOUCH)
	hit.position = Vector2.ONE * (_GLYPH - UiTokens.SIZE_TOUCH) * 0.5
	hit.gui_input.connect(func(e: InputEvent):
		if _tapped(e): action_requested.emit(&"unlock" if _spec.get("lock", {}).get("locked", false) else &"lock", _item, {}))
	c.add_child(hit)
	return c

static func _tapped(e: InputEvent) -> bool:
	return (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed)

func open(item_id: String, context: StringName, opts := {}) -> void:
	_item = item_id
	_context = context
	_opts = opts
	visible = true
	refresh()

func refresh() -> void:
	if not visible or _item == "": return
	_spec = rules.call(_item, _context, _opts) if rules.is_valid() else {id = _item, title = _item}
	_icon.texture = _spec.get("icon", null)
	_title.text = str(_spec.get("title", ""))
	var qty := int(_spec.get("quantity", 0))
	_qty.text = "×%d" % qty
	_qty_pill.visible = qty > 0 or bool(_spec.get("quantity_shown", false))   # a request's item reads ×0 too (BOARD-1 Details)
	var badge := StringName(_spec.get("badge", &""))
	# Locked > Pinned > New: the lock is the Locked badge, so the pin badge shows only on an unlocked stack.
	_badge.visible = badge == &"pinned"
	_badge.texture = PIN_GLYPH
	_badge.self_modulate = UiTokens.COLOR_PIN_AMBER
	var lock: Dictionary = _spec.get("lock", {})
	var locked := bool(lock.get("locked", false)) or badge == &"locked"
	_lock.visible = bool(lock.get("shown", false)) or locked
	var glyph := _lock.get_node("Glyph") as TextureRect
	glyph.texture = LOCK_CLOSED_GLYPH if locked else LOCK_OPEN_GLYPH
	glyph.self_modulate = UiTokens.COLOR_TEXT if locked else UiTokens.COLOR_SECONDARY
	(_lock.get_node("Hit") as Control).mouse_filter = Control.MOUSE_FILTER_STOP if bool(lock.get("shown", false)) else Control.MOUSE_FILTER_IGNORE
	_chevron.visible = bool(_spec.get("info", false))
	var q := int(_spec.get("quality", 0))
	var stars := (" " + "★".repeat(q)) if q > 0 else ""   # `Fine ★★`, the stars together as dish_label (不知火舞 on #263)
	_state.text = str(_spec.get("rarity_text", "")) + stars
	_state.visible = _state.text != ""
	_liked_label.text = str(_spec.get("liked_by", ""))
	_liked.visible = _liked_label.text != ""
	_build_blocks()
	var facts: Array = _spec.get("facts", [])
	for c in _facts.get_children():
		c.hide()
		c.queue_free()
	for i in maxi(0, facts.size() - 1): _add_fact_line(str(facts[i]))
	_overflow = _add_fact_line("")
	_overflow_note = _add_fact_line("")
	_last_fact = str(facts[-1]) if not facts.is_empty() else ""
	for c in _buttons.get_children():
		c.hide()
		c.queue_free()
	for b in _spec.get("buttons", []):
		_buttons.add_child(_button(b))
	# No button and no last fact (a Fishing gate card): no empty 44 touch row under the content.
	_lift.visible = not _spec.get("buttons", []).is_empty() or _last_fact != ""
	_box.content_margin_bottom = 0.0 if _lift.visible else _PAD_T   # the touch row pads the bottom when it is there
	_place_last_fact()
	# New wrapping lines measure tall until they get their width, so the card can grow on the way while its minimum
	# ends where it was (Lettuce → Radish): the parent hears no change and would leave it tall, its medallion centred
	# out of sight and its bottom edge under the grid (int10c 256 ②). Have the parent fit it again.
	var host := get_parent() as Container
	if host != null: host.queue_sort()

## The last fact sits beside the buttons when it fits the room they leave ("+20 Energy", as in the main), otherwise
## on its own fact line. The 44 touch row overlaps the text above it so it starts at y 38 of the card without fact
## lines; under fact lines only its padding above the visible 34 px command overlaps. Runs again on every resize.
func _place_last_fact() -> void:
	if _overflow == null: return
	var row: Control = _buttons.get_parent()
	var room := row.size.x - _buttons.get_combined_minimum_size().x - _GAP
	var font := _effect.get_theme_font(&"font")
	var w := font.get_string_size(_last_fact, HORIZONTAL_ALIGNMENT_LEFT, -1, _effect.get_theme_font_size(&"font_size")).x
	var note := str(_spec.get("fact_note", "")) if _last_fact != "" else ""
	if note != "":
		w = maxf(w, _effect_note.get_theme_font(&"font").get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, _effect_note.get_theme_font_size(&"font_size")).x)
	var beside := _last_fact != "" and row.size.x > 0.0 and w <= room
	_effect.text = _last_fact if beside else ""
	_effect_note.text = note if beside else ""
	_effect_note.visible = _effect_note.text != ""
	_overflow.text = "" if beside else _last_fact
	_overflow.visible = _overflow.text != ""
	_overflow_note.text = "" if beside else note
	_overflow_note.visible = _overflow_note.text != ""
	var lines := _facts.get_children().filter(func(c): return (c as Control).visible).size() + _blocks.get_child_count()
	var text_h: float = (_title.get_parent() as Control).get_combined_minimum_size().y + (_state.get_combined_minimum_size().y if _state.visible else 0.0) \
		+ (_liked.get_combined_minimum_size().y if _liked.visible else 0.0)
	var overlap := maxf(0.0, _PAD_T + text_h - _BUTTON_ROW_Y)
	if lines > 0: overlap = (UiTokens.SIZE_TOUCH - UiTokens.SIZE_COMMAND_COMPACT) * 0.5
	_lift.add_theme_constant_override(&"margin_top", -int(overlap))

func _build_blocks() -> void:
	for c in _blocks.get_children():
		_blocks.remove_child(c)
		c.queue_free()
	if str(_spec.get("lead", "")) != "":
		var lead := UiKit.label(str(_spec.lead), UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT)
		lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_blocks.add_child(lead)
	var need: Dictionary = _spec.get("need", {})
	if not need.is_empty():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", int(_NEED_GAP))
		var tile := UiNeedTile.new(str(need.get("name", "")), int(need.get("have", 0)), maxi(1, int(need.get("need", 1))),
			UiNeedTile.Size.M, need.get("icon", null), true)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tile)
		var note := UiKit.label(str(need.get("note", "")), UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		note.visible = note.text != ""
		row.add_child(note)
		_blocks.add_child(row)
	var needs: Array = _spec.get("needs", [])
	if not needs.is_empty():   # a buy's materials (the counter's › card): NeedTile M each, as many a row as fit (5)
		var tiles: Array = []
		for n in needs:
			var t := UiNeedTile.new(str(n.get("name", "")), int(n.get("have", 0)), maxi(1, int(n.get("need", 1))), UiNeedTile.Size.M,
				n.get("icon", null))
			var id := str(n.get("id", ""))
			t.pressed.connect(func(): need_pressed.emit(id, t))   # the owner shows the source line (不知火舞 on 284 a5fd65e4)
			tiles.append(t)
		var group := UiNeedTile.group(tiles)
		group.name = "Needs"
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_blocks.add_child(group)
	var info: Dictionary = _spec.get("info_row", {})
	if not info.is_empty():
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override(&"separation", int(_INFO_GAP))
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_theme_constant_override(&"separation", int(_GAP))
		var t := UiKit.label(str(info.get("title", "")), UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var q := UiKit.label(str(info.get("qty", "")), UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(q)
		box.add_child(head)
		for line in info.get("lines", []):
			box.add_child(UiKit.label(str(line), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
		_blocks.add_child(box)
	_blocks.visible = _blocks.get_child_count() > 0
	# A gate card is taller than an item card: its medallion sits by the title, not halfway down.
	_medallion.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if _blocks.visible else Control.SIZE_SHRINK_CENTER

func _add_fact_line(text: String) -> Label:
	var line := UiKit.label(text, UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_facts.add_child(line)
	return line

func close() -> void:
	if not visible: return
	visible = false
	_item = ""
	closed.emit()

## The card laid over another panel (a request's Details, a gate card over a drawer; 不知火舞 on 224, §4.8.7): a
## color/scrimModal veil dims the panel below so the card reads as its own layer, the card sits at the bottom inside
## `inset` (sides, bottom), a tap on the veil closes it, and closing removes the whole layer. The caller sets `rules`
## (and connects the signals) before open().
static func layered(host: Control, inset: Vector2 = Vector2(12, 16)) -> UiInfoSheet:
	var layer := Control.new()
	layer.name = "InfoSheetLayer"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.name = "Scrim"
	veil.color = UiTokens.COLOR_SCRIM_MODAL
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)
	var foot := MarginContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for side in [&"margin_left", &"margin_right"]: foot.add_theme_constant_override(side, int(inset.x))
	foot.add_theme_constant_override(&"margin_bottom", int(inset.y))
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(foot)
	var sheet := UiInfoSheet.new()
	foot.add_child(sheet)
	host.add_child(layer)
	layer.gui_input.connect(func(e: InputEvent): if _tapped(e): sheet.close())
	sheet.closed.connect(func(): if is_instance_valid(layer): layer.queue_free())
	return sheet

## The veil under a layered() card, or null when the card is docked in a drawer.
func scrim() -> ColorRect:
	var layer := get_parent().get_parent() if get_parent() != null else null
	return layer.get_node_or_null("Scrim") as ColorRect if layer != null and layer.name == "InfoSheetLayer" else null

func is_open() -> bool: return visible
func item_id() -> String: return _item
func context() -> StringName: return _context
func spec() -> Dictionary: return _spec

func _button(b: Dictionary) -> Control:
	var kind := StringName(b.get("kind", &"secondary"))
	var id := StringName(b.get("id", &""))
	var payload: Dictionary = b.get("payload", {})
	var text := str(b.get("label", ""))
	if kind == &"nav":
		var nav := UiNavButton.new(text.trim_suffix(" ›").trim_suffix("›"), true)
		nav.chevron = bool(b.get("chevron", true))   # the gate card's `Show my plots` has none (SKILL-2 482:169)
		nav.pressed.connect(func(): action_requested.emit(id, _item, payload))
		return nav
	var cb := UiCommandButton.new(text, UiCommandButton.Kind.PRIMARY if kind == &"primary" else UiCommandButton.Kind.SECONDARY, true)
	if kind == &"unavailable": cb.reason = text
	cb.sends = bool(b.get("sends", false))   # a server command: Offline while offline (§10.7.1)
	cb.activated.connect(func(): action_requested.emit(id, _item, payload))
	cb.unavailable_pressed.connect(func(reason: String): unavailable_requested.emit(id, _item, reason))
	return cb
