class_name UiResidentProfile
extends VBoxContainer
## A resident's profile sheet content (SGODOT-225; RES-PIP 482:586 / RES-KAI 482:592, opened from the name on the
## dialogue bar, LOCK-18). Scrollable column: ProfileIdentity (80 round face centred, name, role) · StateBadge (stage) ·
## Fact `Friendship 52/90` · ItemRow `Favourite dishes` / style · NavigationRow `Details` (hidden when the host has
## no page behind it: nothing dead-ends) — then the fixed decision area with the Dismiss `Back`.
## data: {face (Texture2D), name, role, stage, friendship, likes, likes_icon (Texture2D), details (bool)}.
## Put it in a UiDrawer (pad 16, height 443) with a Close above it. Emits details_pressed / back_pressed.

signal details_pressed
signal back_pressed

# RES-PIP main (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _FACE := 80.0           # ProfileIdentity: Icon/i-face-player 80
const _IDENTITY_GAP := 6.0    # ProfileIdentity: face → name → role
const _GAP := 8.0             # Scrollable content: identity → badge → fact → row → navigation
const _BADGE_W := 150.0       # StateBadge instance width in the sheet
const _DECISION_GAP := 12.0   # Fixed decision area: 12 above Back

var data := {}
var _details: UiNavButton

func _init(data_: Dictionary = {}) -> void:
	data = data_
	add_theme_constant_override(&"separation", 0)
	var scroll := TouchScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", int(_GAP))
	scroll.add_child(col)
	var identity := VBoxContainer.new()
	identity.add_theme_constant_override(&"separation", int(_IDENTITY_GAP))
	# The face cropped round (不知火舞 on 235 B1): the same portrait as the dialogue bar, so one resident looks the same
	# in both places; the host passes the face square of it.
	var face := Panel.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.custom_minimum_size = Vector2(_FACE, _FACE)
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	face.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	face.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_TILE_CORE, _FACE * 0.5))
	var img := TextureRect.new()
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.texture = data.get("face", null)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.add_child(img)
	identity.add_child(face)
	identity.add_child(UiKit.label(str(data.get("name", "")), UiTokens.STYLE_TITLE_XB20))
	var role := UiKit.label(str(data.get("role", "")), UiTokens.STYLE_BODY_R14, UiTokens.COLOR_SECONDARY)
	role.visible = role.text != ""
	identity.add_child(role)
	col.add_child(identity)
	var badge := UiBadge.new(str(data.get("stage", "")))
	badge.custom_minimum_size.x = _BADGE_W
	badge.visible = badge.text != ""
	col.add_child(badge)
	var fact := UiFactRow.new("Friendship", str(data.get("friendship", "")))
	fact.visible = str(data.get("friendship", "")) != ""
	col.add_child(fact)
	var likes := UiItemRow.new({icon = data.get("likes_icon", null), title = "Favourite dishes", effect = str(data.get("likes", ""))})
	likes.visible = str(data.get("likes", "")) != ""
	col.add_child(likes)
	_details = UiNavButton.new("Details")
	_details.visible = bool(data.get("details", false))
	_details.pressed.connect(func(): details_pressed.emit())
	col.add_child(_details)
	var gap := Control.new()
	gap.custom_minimum_size.y = _DECISION_GAP
	add_child(gap)
	var back := UiDismissButton.new("Back")
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)

func details_button() -> UiNavButton: return _details
