class_name UiInfoSheet
extends PanelContainer
## InfoSheet (SGODOT-224; F-07 confirmed table on SGODOT-207 168a4cc3; LOCK-10 / 12 / 13 / 15): the item detail
## card inside the bag drawer, the Gear side, a counter and the gift drawer. It draws the spec its rules give it
## (P0ItemInfo.spec bound to the live view); it decides nothing itself.
##
## INTERFACE STUB (day 0): the API below is final for callers. The card already draws the title row, facts and
## buttons from the spec; its WP1b look (title badge, lock icon, ›, rarity line) and the rule table follow.
##
##   rules: Callable(item_id: String, context: StringName, opts: Dictionary) -> Dictionary (the spec). Owners bind
##          it once, e.g. func(id, ctx, o): return P0ItemInfo.spec(ui.view, id, ctx, o).
##   open(item_id, context, opts := {})  shows or switches the card (tap another cell = open again).
##   refresh()                           rebuilds from rules (call when the view changed while open).
##   close()                             hides it; `closed` fires once per open. No own close button (F-07 关闭):
##                                       the owner closes on a tap on blank space or when its drawer closes.
##   action_requested(action, item_id, payload)  a button or the lock icon (&"lock" / &"unlock") was tapped;
##                                       the owner sends the command. Unavailable buttons emit nothing.
##   info_requested(item_id)             the › in the title row: open the item's page (Fish-dex / Cookbook / about).

signal action_requested(action: StringName, item_id: String, payload: Dictionary)
signal info_requested(item_id: String)
signal closed

var rules: Callable

var _item := ""
var _context: StringName = &""
var _opts := {}
var _spec := {}
var _header: UiObjectHeader
var _facts: VBoxContainer
var _buttons: HBoxContainer

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # taps on the card never reach the grid or the world behind it
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.with_margins(UiTokens.SIZE_SHEET_PAD, UiTokens.SIZE_SHEET_PAD, UiTokens.SIZE_SHEET_PAD, UiTokens.SIZE_SHEET_PAD)
	add_theme_stylebox_override(&"panel", box)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	add_child(v)
	_header = UiObjectHeader.new()
	v.add_child(_header)
	_facts = VBoxContainer.new()
	_facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_facts)
	_buttons = HBoxContainer.new()
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
	v.add_child(_buttons)
	visible = false

func open(item_id: String, context: StringName, opts := {}) -> void:
	_item = item_id
	_context = context
	_opts = opts
	visible = true
	refresh()

func refresh() -> void:
	if not visible or _item == "": return
	_spec = rules.call(_item, _context, _opts) if rules.is_valid() else {id = _item, title = _item}
	_header.title = str(_spec.get("title", ""))
	var qty := int(_spec.get("quantity", 0))
	_header.quantity = "×%d" % qty if qty > 0 else ""
	for c in _facts.get_children(): c.queue_free()
	for line in _spec.get("facts", []):
		_facts.add_child(UiKit.label(str(line), UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY))
	for c in _buttons.get_children(): c.queue_free()
	for b in _spec.get("buttons", []):
		_buttons.add_child(_button(b))

func close() -> void:
	if not visible: return
	visible = false
	_item = ""
	closed.emit()

func is_open() -> bool: return visible
func item_id() -> String: return _item
func context() -> StringName: return _context
func spec() -> Dictionary: return _spec

func _button(b: Dictionary) -> UiCommandButton:
	var kind := StringName(b.get("kind", &"secondary"))
	var cb := UiCommandButton.new(str(b.get("label", "")),
		UiCommandButton.Kind.PRIMARY if kind == &"primary" else UiCommandButton.Kind.SECONDARY, true)
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if kind == &"unavailable": cb.reason = str(b.get("label", ""))
	var id := StringName(b.get("id", &""))
	var payload: Dictionary = b.get("payload", {})
	cb.activated.connect(func(): action_requested.emit(id, _item, payload))
	return cb
