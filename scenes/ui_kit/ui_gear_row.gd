class_name UiGearRow
extends PanelContainer
## One candidate on the Gear side (SGODOT-225; "Gear candidate" rows of BAG-2 · Gear, LOCK-13; F-07 rod/gear):
## icon · name · state · effect, with at most one action on the right.
##   note   a line of its own under the effect, as muted (q(278) a rod's tier: `Legendary needs Fishing Lv7–9`).
##   state  &"equipped" draws the green `✓ Equipped` badge; &"owned" reads `Owned`; anything else is the gate and
##          source of an item the player does not own yet (`Fishing Lv3 · Tackle Shop`), and the row is greyed.
##   action {id, label, kind} from the item-info spec (Equip is a compact secondary; nothing for the equipped one,
##          nothing for one not owned yet: LOCK-08, no jump to the shop). Emits `action_pressed(id)`.

signal action_pressed(id: StringName)

# Gear candidate row (BAG-2 · Gear; WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _ICON := 24.0
const _ICON_LEFT := 5.0
const _TEXT_LEFT := 38.0          # name / state / effect start 38 in
const _ROW_H := 65.0
const _BADGE_PAD := Vector2(8, 2) # `✓ Equipped` pill
const _BADGE_RADIUS := 10.0

var data := {}

var _icon: TextureRect
var _action: Control

func _init(data_: Dictionary = {}) -> void:
	data = data_
	custom_minimum_size.y = _ROW_H
	add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(_TEXT_LEFT - _ICON_LEFT - _ICON))
	add_child(row)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", int(_ICON_LEFT))
	_icon = UiKit.icon(data.get("icon", null), _ICON)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pad.add_child(_icon)
	row.add_child(pad)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override(&"separation", 2)
	row.add_child(col)
	col.add_child(UiKit.label(str(data.get("title", "")), UiTokens.STYLE_C12_XB,
		UiTokens.COLOR_TEXT if owned() else UiTokens.COLOR_SECONDARY))   # not owned yet: greyed (F-07)
	var state := StringName(data.get("state", &""))
	if state == &"equipped": col.add_child(equipped_badge())
	elif state == &"owned": col.add_child(UiKit.label("Owned", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
	elif str(state) != "": col.add_child(UiKit.label(str(state), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
	for key in ["effect", "note"]:
		if str(data.get(key, "")) == "": continue
		var line := UiKit.label(str(data[key]), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
		line.name = key.capitalize()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(line)
	var a: Dictionary = data.get("action", {})
	if not a.is_empty():
		var b := UiCommandButton.new(str(a.get("label", "")),
			UiCommandButton.Kind.PRIMARY if StringName(a.get("kind", &"")) == &"primary" else UiCommandButton.Kind.SECONDARY, true)
		if StringName(a.get("kind", &"")) == &"unavailable": b.reason = str(a.get("label", ""))
		b.sends = bool(a.get("sends", true))   # Equip: a server command (§10.7.1 Offline)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var id := StringName(a.get("id", &""))
		b.activated.connect(func(): action_pressed.emit(id))
		row.add_child(b)
		_action = b
	if not owned(): _icon.modulate.a = UiTokens.OPACITY_UNAVAILABLE_ICON

func owned() -> bool: return StringName(data.get("state", &"")) in [&"equipped", &"owned"]
func action_button() -> UiCommandButton: return _action as UiCommandButton

## The `✓ Equipped` pill (also the heading over the six slots on BAG-2 · Gear).
static func equipped_badge() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, _BADGE_RADIUS)
		.with_margins(_BADGE_PAD.x, _BADGE_PAD.y, _BADGE_PAD.x, _BADGE_PAD.y))
	p.add_child(UiKit.label("✓ Equipped", UiTokens.STYLE_C11_XB, UiTokens.COLOR_PRIMARY_INK))
	return p
