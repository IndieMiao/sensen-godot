class_name UiBoardCard
extends VBoxContainer
## Board request row (SGODOT-224; Compact/Information row on BOARD-READY 1498:96193, BOARD-SHORT 1498:96574 and
## BOARD-DONE 1498:96382, E-11; the Stall Board uses the same row). It sits on the sheet: no card surface and no edge
## (amber only marks a gap, on the NeedTile). Top to bottom, 3 apart:
##   title    C12 ExtraBold ink; with `info` a › after it, and a tap on the line opens the request (BOARD-1)
##   status   C10 Bold secondary: Open / Tracked / Ready to deliver / Done
##   facts    C11 Bold secondary, one line each: "4 Fine fish · any kind", "3 crops · 6 each"
##   Reward   C10 Bold secondary (70) + C11 ExtraBold ink, right-aligned (78), 152 wide
##   needs    UiNeedTile S in a wrap (gap 10 / 12), 4 above and below
##   command  one Compact/Command 152 wide: Deliver / Track, or unavailable with the gap (LOCK-10,
##            "Need 1 more Fine fish")
## Done (delivered while the drawer is open): status Done, the Reward line stays, no needs and no command; the coins
## float up from where the button was (UiFloatText, Coins tone, by the host — 不知火舞 on 224).

signal command_pressed
signal unavailable_pressed(reason: String)
signal info_pressed
signal need_pressed(item_id: String, tile: UiNeedTile)

const _GAP := 3
const _REWARD_LABEL_W := 70.0
const _REWARD_VALUE_W := 78.0
const _REWARD_GAP := 4
const _COMMAND_W := 152.0
const _NEEDS_PAD := 4

var request_id := ""

var _title_line: HBoxContainer
var _title: Label
var _chevron: Label
var _status: Label
var _facts: VBoxContainer
var _reward_row: HBoxContainer
var _reward: Label
var _needs: MarginContainer
var _command: UiCommandButton
var _info := false

func _init() -> void:
	add_theme_constant_override(&"separation", _GAP)
	_title_line = HBoxContainer.new()
	_title_line.add_theme_constant_override(&"separation", 4)
	_title_line.gui_input.connect(func(e: InputEvent): if _info and UiShopRow._released(e): info_pressed.emit())
	add_child(_title_line)
	_title = UiKit.label("", UiTokens.STYLE_C12_XB)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_line.add_child(_title)
	_chevron = UiKit.label("›", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_line.add_child(_chevron)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_line.add_child(fill)
	_status = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	add_child(_status)
	_facts = VBoxContainer.new()
	_facts.add_theme_constant_override(&"separation", _GAP)
	_facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_facts)
	_reward_row = HBoxContainer.new()
	_reward_row.add_theme_constant_override(&"separation", _REWARD_GAP)
	_reward_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reward_label := UiKit.label("Reward", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	reward_label.custom_minimum_size.x = _REWARD_LABEL_W
	reward_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reward_row.add_child(reward_label)
	_reward = UiKit.label("", UiTokens.STYLE_C11_XB)
	_reward.custom_minimum_size.x = _REWARD_VALUE_W
	_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reward_row.add_child(_reward)
	add_child(_reward_row)
	_needs = MarginContainer.new()
	_needs.add_theme_constant_override(&"margin_top", _NEEDS_PAD)
	_needs.add_theme_constant_override(&"margin_bottom", _NEEDS_PAD)
	add_child(_needs)
	_command = UiCommandButton.new("", UiCommandButton.Kind.PRIMARY, true)
	_command.sends = true   # Deliver / Track (§10.7.1 Offline)
	_command.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_command.activated.connect(func(): command_pressed.emit())
	_command.unavailable_pressed.connect(func(r: String): unavailable_pressed.emit(r))
	add_child(_command)

## Draw one request. `d`: {id, title, info (bool), status, facts (Array[String]), reward ("36 coins"), needs
## (Array of {id, name, have, need, icon}), command (label, "" for none), reason (the gap; "" when it can go),
## done (bool: delivered — status Done, no needs, no command)}.
func show_request(d: Dictionary) -> void:
	request_id = str(d.get("id", ""))
	_info = bool(d.get("info", false))
	_title.text = str(d.get("title", ""))
	_chevron.visible = _info
	_title_line.mouse_filter = Control.MOUSE_FILTER_STOP if _info else Control.MOUSE_FILTER_IGNORE
	_status.text = str(d.get("status", ""))
	for c in _facts.get_children():
		_facts.remove_child(c)
		c.free()   # out of the tree and nothing points at it: no orphan left until the next frame
	for f in d.get("facts", []):
		if str(f) != "": _facts.add_child(UiKit.label(str(f), UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY))
	_facts.visible = _facts.get_child_count() > 0
	_reward.text = str(d.get("reward", ""))
	_reward_row.visible = _reward.text != ""
	var done := bool(d.get("done", false))
	for c in _needs.get_children():
		_needs.remove_child(c)
		c.free()
	var tiles: Array = []
	if not done:
		for n in d.get("needs", []):
			var tile := UiNeedTile.new(str(n.get("name", "")), int(n.get("have", 0)), int(n.get("need", 1)), UiNeedTile.Size.S, n.get("icon", null))
			var id := str(n.get("id", ""))
			tile.pressed.connect(func(): need_pressed.emit(id, tile))
			tiles.append(tile)
	if not tiles.is_empty(): _needs.add_child(UiNeedTile.group(tiles))
	_needs.visible = not tiles.is_empty()
	var label := str(d.get("command", ""))
	_command.visible = not done and label != ""
	_command.label = label
	_command.reason = str(d.get("reason", ""))
	_command.custom_minimum_size.x = _COMMAND_W   # a compact command resets its size on each label; a longer gap grows it

func command_button() -> UiCommandButton: return _command

## A page fact above the rows (BOARD-READY `Requests today  4 of 6`): C11 Bold secondary label, C12 ExtraBold value
## right-aligned, 25 high.
static func fact_row(label: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 25
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(label, UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var v := UiKit.label(value, UiTokens.STYLE_C12_XB)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)
	return row
func need_tiles() -> Array: return _needs.find_children("*", "UiNeedTile", true, false)
