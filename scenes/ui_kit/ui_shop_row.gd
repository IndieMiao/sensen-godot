class_name UiShopRow
extends Control
## Compact/Shop product row (FARM-6 482:46; Compact/ShopProduct 702:80447 detailed + Compact/Stepper 1245:108953 +
## Compact/Shop action; SGODOT-224, F-07 counter_buy, C1-01): 336 × 58 with a hairline under it.
##   32 px icon medallion · title (C14 XB) ›, effect line, the gate / stock line · price (C12 XB, right)
##   right half, from y 16: Stepper + outlined Buy (secondary), or one grey command whose label is the reason.
## Draws a P0ItemInfo spec for &"counter_buy" (price, facts, buttons); `bought(item_id, qty)` on Buy and
## `info_requested(item_id)` on the title's ›. One-off items (rods) take no stepper.

signal bought(item_id: String, qty: int)
signal info_requested(item_id: String)
signal quantity_changed(item_id: String, qty: int)

# ShopProduct detailed: icon 32 at (0, 13), text column at x 40, title y 2, effect y 21, gate y 38;
# price right-aligned in a 76 px box at x 260; › at x 240; stepper at (180, 16); Buy 76 × 44 at (260, 16).
const _H := 58.0
const _ICON := 32.0
const _ICON_GLYPH := 28.0
const _TEXT_X := 40.0
const _PRICE_W := 76.0
const _ACTION_Y := 16.0

var item_id := ""
var stepper: UiStepper
var buy: UiCommandButton

var _icon: TextureRect
var _title: Label
var _chevron: Label
var _effect: Label
var _gate: Label
var _price: Label
var _actions: HBoxContainer
var _spec := {}

func _init() -> void:
	custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_BAR_W, _H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var medallion := Panel.new()
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medallion.position = Vector2(0, (_H - _ICON) * 0.5 - 0.0)
	medallion.size = Vector2(_ICON, _ICON)
	medallion.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, _ICON * 0.5))
	add_child(medallion)
	_icon = UiKit.icon(null, _ICON_GLYPH)
	_icon.position = Vector2.ONE * (_ICON - _ICON_GLYPH) * 0.5
	medallion.add_child(_icon)
	_title = _text(UiTokens.STYLE_C14_XB, UiTokens.COLOR_TEXT, Vector2(_TEXT_X, 2))
	_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.gui_input.connect(func(e: InputEvent): if _released(e): info_requested.emit(item_id))
	_chevron = _text(UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY, Vector2(0, 3))
	_chevron.text = "›"
	_effect = _text(UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY, Vector2(_TEXT_X, 21))
	_gate = _text(UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY, Vector2(_TEXT_X, 38))
	_price = _text(UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT, Vector2(0, 4))
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_actions = HBoxContainer.new()
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actions.alignment = BoxContainer.ALIGNMENT_END
	_actions.add_theme_constant_override(&"separation", int(UiTokens.SPACE_QUICK_BAR_GAP))
	add_child(_actions)
	var divider := ColorRect.new()
	divider.color = UiTokens.COLOR_BORDER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	divider.offset_top = -UiTokens.STROKE_DEFAULT
	add_child(divider)
	resized.connect(_layout)

func _text(style: StringName, color: Color, at: Vector2) -> Label:
	var l := UiKit.label("", style, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = at
	add_child(l)
	return l

static func _released(e: InputEvent) -> bool:
	return (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed) \
		or (e is InputEventScreenTouch and not e.pressed and not DisplayServer.is_touchscreen_available())

## Draws `spec` (P0ItemInfo.spec(view, id, &"counter_buy", {counter, qty})). `once` = a one-off item (no stepper).
## `stock` caps the stepper (left today / what the wallet covers); keeps the chosen count across refreshes.
func show_spec(spec: Dictionary, once := false, stock := 99) -> void:
	_spec = spec
	item_id = str(spec.get("id", ""))
	_icon.texture = spec.get("icon", null)
	_title.text = str(spec.get("title", ""))
	var facts: Array = spec.get("facts", [])
	# F-07 buy row: line 2 the use, line 3 the stock / gate; with the stepper above 1, line 2 says "2 × 15 coins".
	var price: Dictionary = spec.get("price", {})
	_effect.text = str(price.get("line", "")) if str(price.get("line", "")) != "" else (str(facts[0]) if facts.size() > 1 else "")
	_gate.text = str(facts[-1]) if not facts.is_empty() else ""
	_price.text = str(price.get("text", ""))
	_chevron.visible = bool(spec.get("info", false))
	var qty := stepper.value if stepper else 1
	for c in _actions.get_children():
		c.hide()   # out of the layout now, freed at the end of the frame (still in the tree: no orphan)
		c.queue_free()
	stepper = null
	buy = null
	var b: Dictionary = (spec.get("buttons", []) as Array).front() if not (spec.get("buttons", []) as Array).is_empty() else {}
	var available := not b.is_empty() and StringName(b.get("kind", &"")) != &"unavailable"
	if available and not once:
		stepper = UiStepper.new(maxi(1, stock))
		stepper.value = qty
		stepper.changed.connect(func(v: int): quantity_changed.emit(item_id, v))
		_actions.add_child(stepper)
	buy = UiCommandButton.new(str(b.get("label", "Buy")) if available else "", UiCommandButton.Kind.SECONDARY, true)
	if not available: buy.reason = str(b.get("label", ""))
	buy.custom_minimum_size.x = _PRICE_W if available else 0.0
	buy.activated.connect(func(): bought.emit(item_id, stepper.value if stepper else 1))
	_actions.add_child(buy)
	_layout()

func _layout() -> void:
	var w := size.x if size.x > 0.0 else custom_minimum_size.x
	_price.size = Vector2(_PRICE_W, 0)
	_price.position.x = w - _PRICE_W
	_chevron.position.x = w - _PRICE_W - 20.0
	_title.size.x = maxf(0.0, w - _PRICE_W - 28.0 - _TEXT_X)
	_actions.position = Vector2(0, _ACTION_Y)
	_actions.size = Vector2(w, UiTokens.SIZE_TOUCH)
	# The effect and gate lines end where the row's commands begin (Product details 252 wide in the main).
	var text_w := maxf(0.0, w - _actions.get_combined_minimum_size().x - UiTokens.SPACE_OVERLAY_BODY - _TEXT_X)
	for l in [_effect, _gate]:
		l.size.x = text_w
		l.clip_text = true
