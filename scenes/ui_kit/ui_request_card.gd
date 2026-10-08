class_name UiRequestCard
extends PanelContainer
## A resident's personal request, minimal (SGODOT-225; ResidentRequestCard 1211:83296, LOCK-18: the Request choice
## on the dialogue bar never dead-ends). Requester head (round avatar, `Pip's request`, `Pip · Courier Kid ·
## personal request`) + the request in their own words + `Bring` NEED-TILE(s) + Reward + Deliver to + one
## primary (Accept, or Deliver when ready; a reason makes it unavailable, LOCK-10) + `Not now`.
## The full lifecycle (Track, Drop, statuses) is WP4. data: {portrait (Texture2D), title, who, line, needs:
## [{name, have, need, icon}], reward, deliver_to, action, reason}. Emits `action_pressed` / `dismissed`.

signal action_pressed
signal dismissed

# ResidentRequestCard main (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _PAD := 14.0
const _GAP := 8.0
const _AVATAR := 40.0
const _HEAD_GAP := 10.0
const _ROW_LABEL_GAP := 8.0
const _BUBBLE_RADIUS := 10.0
const _BUBBLE_PAD := Vector2(10, 6)

var data := {}
var _action: UiCommandButton

func _init(data_: Dictionary = {}) -> void:
	data = data_
	add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD)
		.with_margins(_PAD, _PAD, _PAD, _PAD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", int(_GAP))
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", int(_HEAD_GAP))
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(_AVATAR, _AVATAR)
	avatar.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	avatar.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_TILE_CORE, _AVATAR * 0.5))
	var face := TextureRect.new()
	face.texture = data.get("portrait", null)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar.add_child(face)
	head.add_child(avatar)
	var titles := VBoxContainer.new()
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override(&"separation", 1)
	titles.add_child(UiKit.label(str(data.get("title", "")), UiTokens.STYLE_C14_XB))
	titles.add_child(UiKit.label(str(data.get("who", "")), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
	head.add_child(titles)
	col.add_child(head)
	if str(data.get("line", "")) != "":
		var bubble := PanelContainer.new()
		bubble.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _BUBBLE_RADIUS)
			.with_margins(_BUBBLE_PAD.x, _BUBBLE_PAD.y, _BUBBLE_PAD.x, _BUBBLE_PAD.y))
		var line := UiKit.label(str(data.line), UiTokens.STYLE_C12_B)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bubble.add_child(line)
		col.add_child(bubble)
	var needs: Array = data.get("needs", [])
	if not needs.is_empty():
		var req := HBoxContainer.new()
		req.add_theme_constant_override(&"separation", int(UiTokens.SPACE_ROW))
		var bring := UiKit.label("Bring", UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
		bring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		req.add_child(bring)
		var tiles := []
		for n in needs:
			tiles.append(UiNeedTile.new(str(n.get("name", "")), int(n.get("have", 0)), int(n.get("need", 1)), UiNeedTile.Size.M, n.get("icon", null)))
		req.add_child(UiNeedTile.group(tiles))
		col.add_child(req)
	for row in [["Reward", "reward"], ["Deliver to", "deliver_to"]]:
		if str(data.get(row[1], "")) == "": continue
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", int(_ROW_LABEL_GAP))
		h.add_child(UiKit.label(str(row[0]), UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY))
		var v := UiKit.label(str(data[row[1]]), UiTokens.STYLE_C12_XB)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(v)
		col.add_child(h)
	_action = UiCommandButton.new(str(data.get("action", "Accept")))
	_action.reason = str(data.get("reason", ""))
	_action.sends = bool(data.get("sends", false))   # Accept / Deliver to the server (§10.7.1 Offline)
	_action.fit_text = true
	_action.activated.connect(func(): action_pressed.emit())
	col.add_child(_action)
	var later := UiDismissButton.new("Not now")
	later.pressed.connect(func(): dismissed.emit())
	col.add_child(later)

func action_button() -> UiCommandButton: return _action
