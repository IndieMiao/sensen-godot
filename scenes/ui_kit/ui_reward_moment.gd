class_name UiRewardMoment
extends PanelContainer
## RewardMoment 1179:82271 (SGODOT-226; shared with the catch card and level banners, SGODOT-233): the lower half
## of a result moment, a compact centred card (280) under the in-scene reveal. The reveal itself (plate, glow,
## sparkles, the leaping fish) belongs to the caller; this card only lays out the result.
##   line 1  event: Caught! / New recipe! / Dish ready / Mystery Dish / Home Cook (tone colours it)
##   line 2  the item: icon disc, name, rarity dot + word, ★ quality badge (Plain shows none)
##   rewards repeat rewards as float pills (UiFloatText.pill controls built by the caller), at most two
##   strip   a one-time reward: First catch! +15 XP · First cooked · +20 Cooking XP · Cookbook 2/48
##   actions primary (Eat · +45 Energy) / secondary (Keep) / grey note (Gift later from your bag)
## Every empty field hides its part (Figma Show* switches). Catch cards have no buttons and fold away after 1.5 s:
## the caller times that. Tapping outside a dish card is Keep: the caller's scrim decides.

signal primary_pressed
signal secondary_pressed
## The primary button is unavailable (LOCK-10) and was tapped: show `reason` as a short toast.
signal unavailable_pressed(reason: String)

enum Tone { REWARD, NEUTRAL, MILESTONE }

const WIDTH := 280.0
# RewardMoment main (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _PAD_X := 16.0
const _PAD_Y := 14.0
const _GAP := 10.0
const _RADIUS := 18.0
const _SHADOW_SIZE := 14.0
const _SHADOW_Y := 10.0
const _DISC := 52.0
const _DISC_ICON := 36.0
const _ITEM_GAP := 10.0
const _NAME_GAP := 2.0
const _TAG_GAP := 6.0
const _DOT := 10.0
const _DOT_RING := 1.5
const _REWARD_GAP := 8.0
const _STRIP_ICON := 18.0
const _STRIP_GAP := 8.0
const _STRIP_RADIUS := 10.0
const _STRIP_PAD := Vector4(10, 7, 12, 7)   # One-time strip padding: left, top, right, bottom
const _ACTION_GAP := 6.0
## Longest name before it is cut with …: the card's inner width minus the icon disc and its gap.
const NAME_MAX_W := WIDTH - _PAD_X * 2.0 - _DISC - _ITEM_GAP
const RARITY_COLORS := [UiTokens.COLOR_RARITY_COMMON, UiTokens.COLOR_RARITY_FINE, UiTokens.COLOR_RARITY_RARE, UiTokens.COLOR_RARITY_LEGENDARY]

var tone: Tone = Tone.REWARD: set = set_tone
var event := "": set = set_event
var icon: Texture2D: set = set_icon
var item_name := "": set = set_item_name
## 1–4 shows the rarity dot and word; 0 hides the tags row (fish and dishes have rarity, crops do not).
var rarity := 0: set = set_rarity
## Rarity word from content rarity_names (Common / Fine / Rare / Legendary). With rarity 0 it is a plain fact line
## under the name, no dot (the No dish card's `9 left today`: the name line ellipsizes, this one keeps the number).
var rarity_word := "": set = set_rarity_word
## 0 Plain (no badge), 1 Good, 2 Perfect.
var quality := 0: set = set_quality
## Float pills built by the caller (UiFloatText.pill(text, tone, icon)); [] hides the row. The card owns the
## pills it is given: pills dropped by a later assignment are freed, pills passed again are kept.
var rewards: Array = []: set = set_rewards
var strip := "": set = set_strip
var strip_icon: Texture2D: set = set_strip_icon
## Primary command; "" hides the whole actions block (catch cards).
var primary := "": set = set_primary
## Unavailable reason (LOCK-10): replaces the primary label, the button stays tappable.
var primary_reason := "": set = set_primary_reason
var secondary := "": set = set_secondary
var note := "": set = set_note

var _event: Label
var _disc: PanelContainer
var _icon: TextureRect
var _name: Label
var _tags: HBoxContainer
var _dot: Panel
var _rarity: Label
var _badge: UiQualityBadge
var _rewards: HBoxContainer
var _strip: PanelContainer
var _strip_icon: TextureRect
var _strip_text: Label
var _actions: VBoxContainer
var _primary: UiCommandButton
var _secondary: UiCommandButton
var _note: Label

func _init() -> void:
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP   # taps on the card never reach the scrim (outside = Keep)
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_CARD
	box.shadow_size = _SHADOW_SIZE
	box.shadow_offset = Vector2(0, _SHADOW_Y)
	add_theme_stylebox_override(&"panel", box.with_margins(_PAD_X, _PAD_Y, _PAD_X, _PAD_Y))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override(&"separation", int(_GAP))
	add_child(v)
	_event = UiKit.label("", UiTokens.STYLE_TITLE_XB20)
	_event.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_event)
	v.add_child(_build_item())
	_rewards = HBoxContainer.new()
	_rewards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rewards.alignment = BoxContainer.ALIGNMENT_CENTER
	_rewards.add_theme_constant_override(&"separation", int(_REWARD_GAP))
	v.add_child(_rewards)
	v.add_child(_build_strip())
	v.add_child(_build_actions())
	minimum_size_changed.connect(_shrink_wrap)
	_refresh()

## Placed freely (not in a container), the card follows its minimum size back down: wrapped labels report a tall
## minimum before their first layout, and a Control never shrinks on its own.
func _shrink_wrap() -> void:
	if not (get_parent() is Container): reset_size.call_deferred()

func _build_item() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", int(_ITEM_GAP))
	_disc = PanelContainer.new()
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.custom_minimum_size = Vector2(_DISC, _DISC)
	_icon = UiKit.icon(null, _DISC_ICON)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_disc.add_child(_icon)
	row.add_child(_disc)
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override(&"separation", int(_NAME_GAP))
	_name = UiKit.label("", UiTokens.STYLE_ROW_TITLE_XB15)
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(_name)
	_tags = HBoxContainer.new()
	_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tags.add_theme_constant_override(&"separation", int(_TAG_GAP))
	_dot = Panel.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.custom_minimum_size = Vector2(_DOT, _DOT)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tags.add_child(_dot)
	_rarity = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	_tags.add_child(_rarity)
	_badge = UiQualityBadge.new(0)
	_tags.add_child(_badge)
	names.add_child(_tags)
	row.add_child(names)
	return row

func _build_strip() -> Control:
	_strip = PanelContainer.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, _STRIP_RADIUS, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_DEFAULT)
		.with_margins(_STRIP_PAD.x, _STRIP_PAD.y, _STRIP_PAD.z, _STRIP_PAD.w))
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override(&"separation", int(_STRIP_GAP))
	_strip_icon = UiKit.icon(null, _STRIP_ICON)
	_strip_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_strip_icon)
	_strip_text = UiKit.label("", UiTokens.STYLE_CAPTION_XB12, UiTokens.COLOR_PRIMARY)
	_strip_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(_strip_text)
	_strip.add_child(h)
	return _strip

func _build_actions() -> Control:
	_actions = VBoxContainer.new()
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actions.add_theme_constant_override(&"separation", int(_ACTION_GAP))
	_primary = UiCommandButton.new("", UiCommandButton.Kind.PRIMARY)
	_primary.activated.connect(func(): primary_pressed.emit())
	_primary.unavailable_pressed.connect(func(r: String): unavailable_pressed.emit(r))
	_actions.add_child(_primary)
	_secondary = UiCommandButton.new("", UiCommandButton.Kind.SECONDARY)
	_secondary.activated.connect(func(): secondary_pressed.emit())
	_actions.add_child(_secondary)
	_note = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_actions.add_child(_note)
	return _actions

func set_tone(v: Tone) -> void: tone = v; _refresh()
func set_event(v: String) -> void: event = v; _refresh()
func set_icon(v: Texture2D) -> void: icon = v; _refresh()
func set_item_name(v: String) -> void: item_name = v; _refresh()
func set_rarity(v: int) -> void: rarity = v; _refresh()
func set_rarity_word(v: String) -> void: rarity_word = v; _refresh()
func set_quality(v: int) -> void: quality = v; _refresh()
func set_strip(v: String) -> void: strip = v; _refresh()
func set_strip_icon(v: Texture2D) -> void: strip_icon = v; _refresh()
func set_primary(v: String) -> void: primary = v; _refresh()
func set_primary_reason(v: String) -> void: primary_reason = v; _refresh()
func set_secondary(v: String) -> void: secondary = v; _refresh()
func set_note(v: String) -> void: note = v; _refresh()

func set_rewards(v: Array) -> void:
	rewards = v
	if _rewards == null: return
	var keep := v.slice(0, 2)
	for c in _rewards.get_children():
		_rewards.remove_child(c)
		if not keep.has(c): c.queue_free()
	for c in keep: _rewards.add_child(c)
	_rewards.visible = not keep.is_empty()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED: _fit_name()

## A clipped label has no natural width, so give the name its text width up to NAME_MAX_W (then …): short names
## stay centred with their icon, long ones never push the card past 280.
func _fit_name() -> void:
	if _name == null: return
	var font := _name.get_theme_font(&"font")
	var w := font.get_string_size(item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, _name.get_theme_font_size(&"font_size")).x if font else 0.0
	_name.custom_minimum_size.x = minf(ceilf(w), NAME_MAX_W)

## Fills the card in one call: keys are the field names above.
func show_fields(fields: Dictionary) -> void:
	for k in fields: set(k, fields[k])

func _refresh() -> void:
	if _note == null: return
	_event.text = event
	_event.visible = event != ""
	_event.add_theme_color_override(&"font_color", [UiTokens.COLOR_PRIMARY, UiTokens.COLOR_SECONDARY, UiTokens.COLOR_TEXT][tone])
	var disc_bg: Color = [UiTokens.COLOR_PRIMARY_TINT, UiTokens.COLOR_DISABLED, UiTokens.COLOR_QUALITY_GOLD][tone]
	_disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(disc_bg, _DISC * 0.5))
	_icon.texture = icon
	_name.text = item_name
	_fit_name()
	_tags.visible = rarity > 0 or quality > 0 or rarity_word != ""
	_dot.visible = rarity > 0
	if rarity > 0:
		_dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(RARITY_COLORS[clampi(rarity - 1, 0, 3)], _DOT * 0.5, UiTokens.COLOR_SURFACE_RAISED, _DOT_RING))
	_rarity.text = rarity_word
	_rarity.visible = rarity_word != ""
	_badge.quality = quality
	_strip.visible = strip != ""
	_strip_text.text = strip
	_strip_icon.texture = strip_icon
	_strip_icon.visible = strip_icon != null
	_actions.visible = primary != "" or secondary != "" or note != ""
	_primary.label = primary
	_primary.reason = primary_reason
	_primary.visible = primary != ""
	_secondary.label = secondary
	_secondary.visible = secondary != ""
	_note.text = note
	_note.visible = note != ""
	_rewards.visible = not _rewards.get_children().is_empty()
