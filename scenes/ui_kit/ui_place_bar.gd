class_name UiPlaceBar
extends Control
## Placement mode's bottom bar (P1, SGODOT-241; plan q(23) LOCK-01 / 02 exception, the modal edit shell the sprinkler,
## Decorate and Plot Marks share): a caption pill over a card with Cancel and the main key. Placeholder look from kit
## parts (Card surface, CommandButton) until 安其拉's frame; nothing here knows what is being placed.
##   caption      "Coverage preview · 8 plots" (the pill hides when "")
##   confirm      the main key's verb, "Build" / "Move" / "Place"
##   reason       non-empty = the spot is not valid: the main key shows it in the blocked look ("Plot occupied")
##   secondary    an optional middle key in the secondary look ("Rotate" for 2×1 / 3×2 decor, 不知火舞 on 284
##                ee15926a): Cancel · Rotate · Place share the width equally; "" = the two-key bar (sprinklers).
##                Three keys leave no room for a reason on the main key (fcbd30a7): it greys keeping its verb and the
##                reason takes the caption pill's place until the spot is valid again
##   cancel       the left key's word; "" leaves the main key alone across the bar (Decorate with nothing picked:
##                one `Done`, 不知火舞 on 284 49b11f91)
## Signals: confirmed (the main key on a valid spot), cancelled, secondary_pressed; a tap on a blocked main key says
## why (unavailable).

signal confirmed
signal cancelled
signal secondary_pressed
signal unavailable(reason: String)

const BAR_H := 76.0                 # card: 12 + 48 button + 16 over the safe bottom
const _GAP := 8.0
const _MAIN_RATIO := 1.4             # the two-key bar's main key is wider; with a middle key all three are equal

var caption := "": set = set_caption
var confirm := "Build": set = set_confirm
var reason := "": set = set_reason
var secondary := "": set = set_secondary
var cancel := "Cancel": set = set_cancel
var safe_bottom := 0.0: set = set_safe_bottom

var _pill: PanelContainer
var _caption: Label
var _card: PanelContainer
var _cancel: UiCommandButton
var _second: UiCommandButton
var _ok: UiCommandButton

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP   # the bar takes its touches; the scene above it places
	_card.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD)
		.with_margins(UiTokens.SPACE_PAGE, UiTokens.SPACE_ROW, UiTokens.SPACE_PAGE, UiTokens.SPACE_PAGE))
	add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(_GAP))
	_card.add_child(row)
	_cancel = UiCommandButton.new("Cancel", UiCommandButton.Kind.SECONDARY)
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel.activated.connect(func(): cancelled.emit())
	row.add_child(_cancel)
	_second = UiCommandButton.new("", UiCommandButton.Kind.SECONDARY)
	_second.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_second.activated.connect(func(): secondary_pressed.emit())
	_second.visible = false
	row.add_child(_second)
	_ok = UiCommandButton.new(confirm, UiCommandButton.Kind.PRIMARY)
	_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ok.size_flags_stretch_ratio = _MAIN_RATIO
	_ok.activated.connect(func(): confirmed.emit())
	_ok.unavailable_pressed.connect(func(r: String): unavailable.emit(r))
	row.add_child(_ok)
	_pill = PanelContainer.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, 12.0).with_margins(12, 4, 12, 4))
	_caption = UiKit.label("", UiTokens.STYLE_C12_B)
	_pill.add_child(_caption)
	add_child(_pill)
	_pill.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _layout()

func _layout() -> void:
	var w := size.x - UiTokens.SPACE_PAGE * 2.0
	var h := BAR_H + safe_bottom
	_card.position = Vector2(UiTokens.SPACE_PAGE, size.y - h - UiTokens.SPACE_PAGE * 0.5)
	_card.size = Vector2(w, h)
	var p := _pill.get_combined_minimum_size()
	_pill.size = p
	_pill.position = Vector2((size.x - p.x) * 0.5, _card.position.y - _GAP - p.y)

func set_caption(v: String) -> void:
	caption = v
	_show_caption()

## The pill: the caption, or with three keys the reason the spot is not valid.
func _show_caption() -> void:
	if _caption == null: return
	var t := reason if secondary != "" and reason != "" else caption
	_caption.text = t
	_pill.visible = t != ""
	_layout()

func set_confirm(v: String) -> void:
	confirm = v
	if _ok != null: _ok.label = v

func set_reason(v: String) -> void:
	reason = v
	if _ok != null: _ok.reason = v
	_show_caption()

func set_secondary(v: String) -> void:
	secondary = v
	if _second == null: return
	_second.label = v
	_second.visible = v != ""
	_ok.size_flags_stretch_ratio = 1.0 if v != "" else _MAIN_RATIO
	_ok.reason_beside = v != ""
	_show_caption()

func set_cancel(v: String) -> void:
	cancel = v
	if _cancel == null: return
	_cancel.label = v
	_cancel.visible = v != ""

func set_safe_bottom(v: float) -> void:
	safe_bottom = v
	_layout()

## The bar's card in this control's coordinates (the scene's touches stop at its top).
func card_rect() -> Rect2: return Rect2(_card.position, _card.size)
