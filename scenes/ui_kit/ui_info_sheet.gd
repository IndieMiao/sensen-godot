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

signal action_requested(action: StringName, item_id: String, payload: Dictionary)
signal unavailable_requested(action: StringName, item_id: String, reason: String)
signal info_requested(item_id: String)
signal closed

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
var _facts: VBoxContainer
var _effect: Label
var _last_fact := ""      # goes beside the buttons when it fits there, otherwise on its own fact line
var _overflow: Label      # that own line (last in _facts, hidden while the fact fits beside the buttons)
var _buttons: HBoxContainer

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # taps on the card never reach the grid or the world behind it
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER, UiTokens.STROKE_CELL_HAIRLINE)
	box.with_margins(_PAD_L, _PAD_T, _PAD_R, 0.0)
	add_theme_stylebox_override(&"panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(_GAP))
	add_child(row)
	var medallion := Panel.new()
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medallion.custom_minimum_size = Vector2(_MEDALLION, _MEDALLION)
	medallion.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	_effect = UiKit.label("", UiTokens.STYLE_C12_XB)
	_effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effect.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_effect.clip_text = true   # a fact too long for this slot moves to the fact lines (_place_last_fact)
	bottom.add_child(_effect)
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
	var stars := " ★".repeat(int(_spec.get("quality", 0)))
	_state.text = str(_spec.get("rarity_text", "")) + stars
	_state.visible = _state.text != ""
	var facts: Array = _spec.get("facts", [])
	for c in _facts.get_children():
		c.hide()
		c.queue_free()
	for i in maxi(0, facts.size() - 1): _add_fact_line(str(facts[i]))
	_overflow = _add_fact_line("")
	_last_fact = str(facts[-1]) if not facts.is_empty() else ""
	for c in _buttons.get_children():
		c.hide()
		c.queue_free()
	for b in _spec.get("buttons", []):
		_buttons.add_child(_button(b))
	_place_last_fact()

## The last fact sits beside the buttons when it fits the room they leave ("+20 Energy", as in the main), otherwise
## on its own fact line. The 44 touch row overlaps the text above it so it starts at y 38 of the card without fact
## lines; under fact lines only its padding above the visible 34 px command overlaps. Runs again on every resize.
func _place_last_fact() -> void:
	if _overflow == null: return
	var row: Control = _effect.get_parent()
	var room := row.size.x - _buttons.get_combined_minimum_size().x - _GAP
	var font := _effect.get_theme_font(&"font")
	var w := font.get_string_size(_last_fact, HORIZONTAL_ALIGNMENT_LEFT, -1, _effect.get_theme_font_size(&"font_size")).x
	var beside := _last_fact != "" and row.size.x > 0.0 and w <= room
	_effect.text = _last_fact if beside else ""
	_overflow.text = "" if beside else _last_fact
	_overflow.visible = _overflow.text != ""
	var lines := _facts.get_children().filter(func(c): return (c as Control).visible).size()
	var text_h: float = (_title.get_parent() as Control).get_combined_minimum_size().y + (_state.get_combined_minimum_size().y if _state.visible else 0.0)
	var overlap := maxf(0.0, _PAD_T + text_h - _BUTTON_ROW_Y)
	if lines > 0: overlap = (UiTokens.SIZE_TOUCH - UiTokens.SIZE_COMMAND_COMPACT) * 0.5
	_lift.add_theme_constant_override(&"margin_top", -int(overlap))

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
		nav.pressed.connect(func(): action_requested.emit(id, _item, payload))
		return nav
	var cb := UiCommandButton.new(text, UiCommandButton.Kind.PRIMARY if kind == &"primary" else UiCommandButton.Kind.SECONDARY, true)
	if kind == &"unavailable": cb.reason = text
	cb.activated.connect(func(): action_requested.emit(id, _item, payload))
	cb.unavailable_pressed.connect(func(reason: String): unavailable_requested.emit(id, _item, reason))
	return cb
