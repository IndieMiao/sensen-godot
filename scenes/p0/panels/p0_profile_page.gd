class_name P0ProfilePage
extends Control
## Own profile, P0 subset (SGODOT-225; PROFILE-1-P0, LOCK-22). One profile design: the same structure and kit
## parts as PROFILE-1, with the blocks P0 has no data for left out (title, ID, bio, relations, Edit, Medals /
## Guestbook / Second Home, the Crops and Cities collections). Full screen on the cream surface:
##   top bar     back + Profile + gear (Settings: Legal › Licenses and Version, q(129); 197 8d0d8212)
##   look        the saved outfit (BagCharacterPreview; a sideways drag turns it) + `Edit look ›` (the dressing room)
##   identity    name and, beside it, the title worn with its › (q(180) ④, LOCK-22 addition: _NameRow; opens Titles),
##               `City · Climate · Since Oct 2` (view.profile, SGODOT-228; a missing field hides its line)
##   skills      three UiSkillCards; tapping one opens the skill details
##   farm        UiFarmCard: farm name, Level N, the farm's status line, › to HOME-1
##   Collections Fish-dex and Cookbook pages as M count NEED-TILEs
##   voice       `Voice Profile ›`: a NavigationRow on a farm-card surface, 16 under Collections (SGODOT-349)
## Emits back_pressed, edit_look_pressed, skill_pressed(skill), settings_pressed, title_pressed, voice_pressed.

signal back_pressed
signal edit_look_pressed
signal skill_pressed(skill: String)
signal settings_pressed
## `Edit ›` on the name's line (SGODOT-491; spec v1.1 §3, PROFILE-1-EDIT 643:197324): only with accounts (view.account).
signal edit_name_pressed
## A Collections tile was tapped: "fish" (the Fish-dex, FISH-6), "pages" (the Cookbook) or "cities" (the Passport).
signal collection_pressed(key: String)
## The farm card was tapped: HOME-1 (§10.6.2, int11).
signal farm_pressed
## The title beside the name was tapped: the Titles drawer (q(180) ⑤).
signal title_pressed
## `Voice Profile ›` was tapped: the voice-match H5 (SGODOT-349; the host opens it, no transition of its own).
signal voice_pressed

const P0Titles := preload("res://modules/p0/p0_titles.gd")
const SKILLS := ["farming", "fishing", "cooking"]
const _SKILL_ICONS := {"farming": "hoe", "fishing": "rod", "cooking": "pot"}
# PROFILE-1-P0 layout (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _TOP := 38.0              # top bar y
const _LOOK := Vector2(360, 210)  # outfit area under the top bar (y 84)
const _LOOK_GAP := 2.0          # top bar → outfit area
const _FIGURE := Vector2(120, 196)
const _CONTENT_GAP := 8.0       # Profile content column
const _SKILL_GAP := 8.0
## The blocks under the name, as above. A world with no data for one leaves it out, as P0 leaves out PROFILE-1's: the
## dynamic farm (C-128) has none of them, so its profile is the top bar, the look and the name.
const BLOCKS := ["skills", "farm", "collections", "voice"]

var view := {}
var blocks: Array = BLOCKS
var safe_top := 0.0
var top_bar: UiProfileTopBar
var preview: BagCharacterPreview
## A sideways drag over the outfit area turns the figure (int10c 256 ⑦), as in the dressing room.
var spin: _Spin

var _body: VBoxContainer
var _refreshed_ms := 0
var _shown := {}   # the profile_data last drawn: rebuild only when it changes
## Back from the dressing room with Done (KEEP-P0-2): `Look saved` under the home line.
var look_saved := false
## A title just picked in Titles, {id, seq}, shown until the server's answer lands (P0Titles.worn); {} for none.
var title_pending := {}
var name_row: _NameRow

func _init(view_: Dictionary = {}, safe_top_ := 0.0, look_saved_ := false, title_pending_ := {}, blocks_: Array = BLOCKS) -> void:
	view = view_
	blocks = blocks_
	safe_top = safe_top_
	look_saved = look_saved_
	title_pending = title_pending_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UiTokens.COLOR_SURFACE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := TouchScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override(&"margin_left", int(UiTokens.SIZE_QUICK_BAR_X))
	pad.add_theme_constant_override(&"margin_right", int(UiTokens.SIZE_QUICK_BAR_X))
	pad.add_theme_constant_override(&"margin_top", int(_TOP + safe_top))
	pad.add_theme_constant_override(&"margin_bottom", int(UiTokens.SPACE_SECTION))
	scroll.add_child(pad)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 0)
	pad.add_child(_body)
	top_bar = UiProfileTopBar.new(UiProfileTopBar.Kind.SELF, "Profile")
	# The gear is back with the P0 Settings page (q(129): Legal › Licenses; not a reopening of LOCK-22, 197 8d0d8212).
	# Own profile only: another player's top bar has ··· there (UiProfileTopBar.Kind.OTHER).
	top_bar.back_pressed.connect(func(): back_pressed.emit())
	top_bar.settings_pressed.connect(func(): settings_pressed.emit())
	_body.add_child(top_bar)
	_gap(_LOOK_GAP)
	_body.add_child(_look())
	refresh(view_)

## The P0 UI hands every frame's view here; the facts are checked at most once a second (the farm countdown) and
## rebuilt only when they changed, so a tap is never cut in two by a rebuild (亚瑟 on #37).
func update(view_: Dictionary) -> void:
	view = view_
	if Time.get_ticks_msec() - _refreshed_ms < 1000: return
	_refreshed_ms = Time.get_ticks_msec()
	if profile_data(view_, title_pending) != _shown: refresh(view_)

## Rebuild the facts below the outfit from a new view (the outfit and top bar stay).
func refresh(view_: Dictionary) -> void:
	view = view_
	_refreshed_ms = Time.get_ticks_msec()
	while _body.get_child_count() > 3:
		var c := _body.get_child(3)
		_body.remove_child(c)
		c.queue_free()
	var d := profile_data(view, title_pending)
	_shown = d
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", int(_CONTENT_GAP))
	_body.add_child(col)
	var id := VBoxContainer.new()
	id.add_theme_constant_override(&"separation", int(_CONTENT_GAP))
	name_row = _NameRow.new(str(d.name), str(d.title), bool(d.edit))
	name_row.pressed.connect(func(): title_pressed.emit())
	name_row.edit_pressed.connect(func(): edit_name_pressed.emit())
	id.add_child(name_row)
	if str(d.home_line) != "": id.add_child(UiKit.label(str(d.home_line), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
	if look_saved: id.add_child(UiKit.label("Look saved", UiTokens.STYLE_C10_B, UiTokens.COLOR_PRIMARY_INK))   # KEEP-P0-2
	col.add_child(id)
	if "skills" in blocks:
		var skills := HBoxContainer.new()
		skills.add_theme_constant_override(&"separation", int(_SKILL_GAP))
		for s in d.skills:
			var card := UiSkillCard.new(Localization.ctx(str(s.name), "skill"), int(s.level), float(s.progress), P0Logic.icon(str(s.icon)))
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var key: String = s.key
			card.pressed.connect(func(): skill_pressed.emit(key))
			skills.add_child(card)
		col.add_child(skills)
	if "farm" in blocks:
		var farm := UiFarmCard.new(str(d.farm.name), str(d.farm.level_line), str(d.farm.status), load("res://assets/p0/art/homestead-thumb.jpg"))
		farm.chevron = true   # it opens HOME-1: no card that looks tappable and does nothing (int11, 不知火舞 on 225)
		farm.pressed.connect(func(): farm_pressed.emit())
		col.add_child(farm)
	if "collections" in blocks:
		col.add_child(UiKit.label("Collections", UiTokens.STYLE_C11_XB))
		var tiles := []
		for c in d.collections:
			var tile := UiNeedTile.new(str(c.name), int(c.have), int(c.need), UiNeedTile.Size.M, P0Logic.icon(str(c.icon)), true)
			var key := str(c.get("key", ""))
			if bool(c.get("badge", false)): tile.add_corner(P0FishDex.badge_icon(), _CORNER_BADGE, _CORNER_AT)   # the whole Fish-dex (283 PROFILE-1-DEX)
			tile.pressed.connect(func(): collection_pressed.emit(key))
			tiles.append(tile)
		col.add_child(UiNeedTile.group(tiles))
	if "voice" in blocks and voice_profile_shown(OS.get_name()): col.add_child(_voice_row())

## q(281) ③ (SGODOT-390): no Voice Profile on an iPhone (the card is not there at all); Android keeps it (the user) — but
## for the store build (SGODOT-483, Google Play: an AI reading of a recording sent abroad), which has none either.
## Now none in any build (the user 11-12, the store's second batch #7 via 奕星: the Android test build too): off till
## the user says otherwise; the row and its page stay in the code, and tests turn it on to keep them working.
static var voice_profile_enabled := false
static func voice_profile_shown(os_name: String, store := P0Build.store()) -> bool:
	return voice_profile_enabled and os_name != "iOS" and not store

## `Voice Profile ›` under Collections (SGODOT-349, 不知火舞 2ca37b44): the NavigationRow main (9:99743, 49 high,
## label and ›, no icon) on a full-width card that looks like the farm card (radius 12, the raised surface, no stroke);
## the whole row is the button. 16 under Collections: the column's gap and _VOICE_GAP more.
func _voice_row() -> Control:
	var wrap := MarginContainer.new()
	wrap.name = "VoiceProfile"
	wrap.add_theme_constant_override(&"margin_top", int(_VOICE_GAP))
	var card := PanelContainer.new()
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _VOICE_RADIUS)
	box.content_margin_left = _VOICE_PAD   # the NavigationRow main has no side padding of its own
	box.content_margin_right = _VOICE_PAD
	card.add_theme_stylebox_override(&"panel", box)
	wrap.add_child(card)
	var row := UiNavButton.new("Voice Profile")
	row.name = "VoiceProfileRow"
	row.pressed.connect(func(): voice_pressed.emit())
	card.add_child(row)
	return wrap

const _VOICE_GAP := 8.0      # + _CONTENT_GAP = 16 under Collections
const _VOICE_RADIUS := 12.0  # UiFarmCard's
const _VOICE_PAD := 16.0     # the row's text and › in from the card's sides, as SettingRow's (不知火舞 on 349)

## The Fish-dex badge on the Fish tile (283 PROFILE-1-DEX, Figma 9c93e46e): 22 at (51, −2) of the NeedTile M frame, its
## ring 15 in — (36, −2) from the ring, so a wider label line does not move it.
const _CORNER_BADGE := 22.0
const _CORNER_AT := Vector2(36, -2)

## Everything the page shows, from the server view (pure; tested). pending: a title just picked (P0Titles.worn).
static func profile_data(view: Dictionary, pending := {}) -> Dictionary:
	var p: Dictionary = view.get("profile", {})
	var home := []
	for k in ["city", "climate"]:
		if str(p.get(k, "")) != "": home.append(str(p[k]))
	if p.get("since_ms", null) != null: home.append("Since %s" % since_text(float(p.since_ms)))   # one line a translation orders (「10 月 27 日加入」)
	var sk: Dictionary = view.get("skills", {})
	var skills := SKILLS.map(func(k: String) -> Dictionary:
		var s: Dictionary = sk.get(k, {})
		return {key = k, name = k.capitalize(), level = int(s.get("level", 1)), progress = skill_progress(s), icon = _SKILL_ICONS[k]})
	var farm: Dictionary = p.get("farm", {})
	var name := str(view.get("account", {}).get("name", p.get("name", "")))   # accounts: the chosen name (contract §1)
	var dex: Array = view.get("fishing", {}).get("dex", [])
	var caught := dex.filter(func(f): return int(f.get("caught", 0)) > 0).size()
	var book := P0KitchenLogic.cookbook_progress(view)   # discovered pages / the pages shown (q(100))
	return {
		name = name if name != "" else "You",
		edit = view.has("account"),   # SGODOT-491: `Edit ›` once there are accounts
		title = P0Titles.worn_name(view, pending),   # "" with none: no title, no › (q(180) ④)
		home_line = " · ".join(home),
		skills = skills,
		farm = {name = str(farm.get("name", "Your Home")),
			level_line = "Level %d" % int(farm.level) if farm.has("level") else "",
			status = _farm_status(view)},
		collections = [
			{key = "fish", name = "Fish", have = caught, need = dex.size(), icon = "fish_crucian",
				badge = P0FishDex.badge_for(caught) != ""},   # its badge once all are caught (283 PROFILE-1-DEX)
			{key = "pages", name = "Pages", have = book.x, need = book.y, icon = "recipe_card"},   # as the Cookbook tab (q(100))
			# Cities (PROFILE-1, q(100)): cities reached, toward the Explorer medal next (§11.9.2: 3 / 10 / 30 / 100); opens PASS-1
			{key = "cities", name = "Cities", have = cities_have(view), need = cities_need(view), icon = "passport"},
		],
	}

## Cities reached by travel (the home city not counted) and the next Explorer medal's count (3 / 10 / 30 / 100).
const EXPLORER := [3, 10, 30, 100]
static func cities_have(view: Dictionary) -> int: return (view.get("travel", {}).get("visits", {}) as Dictionary).size()
static func cities_need(view: Dictionary) -> int:
	for n in EXPLORER: if cities_have(view) < n: return n
	return EXPLORER[-1]

## Progress within the current level, 0..1 (1 at the top level).
static func skill_progress(s: Dictionary) -> float:
	if s.is_empty() or s.get("next", null) == null: return 1.0
	return clampf(float(int(s.get("xp", 0)) - int(s.get("floor", 0))) / maxf(1.0, float(int(s.next) - int(s.get("floor", 0)))), 0.0, 1.0)

## `Oct 2` (`Oct 2, 2025` when not this year); under 中文 `10 月 2 日` (`2025 年 10 月 2 日`). Both days in the device's
## time zone, as the plaque's (P0Logic.plaque_lines; SGODOT-414, 不知火舞: an account made before 08:00 in UTC+8 read
## the day before, and the year was told wrong for those hours at New Year). `bias_min`: minutes east of UTC.
static func since_text(ms: float, now_ms := -1.0, bias_min := 999999) -> String:
	var bias := bias_min if bias_min != 999999 else int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(int(ms / 1000.0) + bias * 60)
	var now := Time.get_datetime_dict_from_unix_time(int((now_ms if now_ms >= 0.0 else Time.get_unix_time_from_system() * 1000.0) / 1000.0) + bias * 60)
	var text := P0Logic.month_day(int(d.month), int(d.day))
	if int(d.year) == int(now.year): return text
	# the language on screen, not the pick for the next start (#649 第二批 ③)
	return "%d 年 %s" % [int(d.year), text] if TranslationServer.get_locale() == "zh_CN" else "%s, %d" % [text, int(d.year)]

## The earliest crop on the plots: `Radishes ready in 3h 32m` (as Today says it; int12), or the first thing to do there.
static func _farm_status(view: Dictionary) -> String:
	var best := INF
	var crop := ""
	var ready := ""
	for p in view.get("plots", []):
		var st := str(p.get("state", ""))
		if st == "ready" and ready == "": ready = str(p.get("crop", ""))
		elif st == "growing" and float(p.get("ready_in", INF)) < best:
			best = float(p.get("ready_in", INF))
			crop = str(p.get("crop", ""))
	if ready != "": return "%s ready to harvest" % P0Logic.plural(P0Logic.item_name(view, ready))
	if crop != "": return "%s ready in %s" % [P0Logic.plural(P0Logic.item_name(view, crop)), P0Logic.span(best)]
	return ""

## The name and, beside it, the title worn and its › (q(180) ④; PROFILE-1-TITLE 2595:133638, -LONG 2639:134878,
## -CUT 2639:135042): the name C14XB; 8 on, the title C10B secondary; 4 on, the › C13XB secondary; each centred on
## the name's line. The title and the › tap as one, 44 high — above and below the line, which keeps the name's height,
## so nothing under it moves. On a line too short the title gives way first (P0Titles.fit). No title: the name alone.
## With accounts (SGODOT-491, PROFILE-1-EDIT 643:197324): `Edit ›` at the line's right end, info Bold 12, its right edge
## 16 from the screen's, tapping 44 high and at least 44 wide (edit_pressed); the title's room less its width and 12.
class _NameRow extends Control:
	signal pressed
	signal edit_pressed
	const GAP := 8.0
	const CHEVRON_GAP := 4.0
	const CHEVRON := "›"
	const EDIT := "Edit ›"
	const EDIT_GAP := 12.0
	const EDIT_RIGHT := 4.0   # the page's 12 in, plus 4: 16 from the screen's edge
	var name_label: Label
	var title_label: Label
	var chevron: Label
	var hit: Button
	var edit_label: Label
	var edit_hit: Button
	var _name := ""
	var _title := ""

	func _init(name_: String, title_: String, edit := false) -> void:
		_name = name_
		_title = title_
		if edit:
			edit_label = UiKit.label(EDIT, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_INFO)
			edit_label.name = "Edit"
			edit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(edit_label)
			edit_hit = Button.new()
			edit_hit.name = "EditHit"
			edit_hit.flat = true
			edit_hit.focus_mode = Control.FOCUS_NONE
			for st in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
				edit_hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			edit_hit.pressed.connect(func(): edit_pressed.emit())
			add_child(edit_hit)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label = UiKit.label(name_, UiTokens.STYLE_C14_XB)
		name_label.name = "Name"
		name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # a chosen name is never translated (SGODOT-491)
		add_child(name_label)
		title_label = UiKit.label(title_, UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
		title_label.name = "Title"
		chevron = UiKit.label(CHEVRON, UiTokens.STYLE_C13_XB, UiTokens.COLOR_SECONDARY)
		chevron.name = "Chevron"
		hit = Button.new()
		hit.name = "TitleHit"
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		for st in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
			hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		hit.pressed.connect(func(): pressed.emit())
		for c in [title_label, chevron, hit]:
			c.visible = title_ != ""
			add_child(c)
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		return Vector2(0, name_label.get_minimum_size().y if name_label != null else 0.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE: _layout()

	static func _measure(l: Label) -> Callable:
		var font := l.get_theme_font(&"font")
		var fs := l.get_theme_font_size(&"font_size")
		return func(t: String) -> float: return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

	func _layout() -> void:
		if not is_inside_tree() or size.x <= 0.0: return
		var chevron_w: float = _measure(chevron).call(CHEVRON)
		var room := size.x
		if edit_label != null:
			edit_label.size = edit_label.get_minimum_size()
			edit_label.position = Vector2(size.x - EDIT_RIGHT - edit_label.size.x, (size.y - edit_label.size.y) * 0.5)
			var hit_w := maxf(UiTokens.SIZE_TOUCH, edit_label.size.x + EDIT_RIGHT)
			edit_hit.size = Vector2(hit_w, UiTokens.SIZE_TOUCH)
			edit_hit.position = Vector2(size.x - hit_w, (size.y - UiTokens.SIZE_TOUCH) * 0.5)
			room = edit_label.position.x - EDIT_GAP
		var f := P0Titles.fit(_name, _title, room, GAP, CHEVRON_GAP + chevron_w, _measure(name_label), _measure(title_label))
		name_label.text = str(f.name)
		title_label.text = str(f.title)
		var h := size.y
		for l in [name_label, title_label, chevron]: (l as Label).size = (l as Label).get_minimum_size()
		name_label.position = Vector2(0, (h - name_label.size.y) * 0.5)
		title_label.position = Vector2(name_label.size.x + GAP, (h - title_label.size.y) * 0.5)
		chevron.position = Vector2(title_label.position.x + title_label.size.x + CHEVRON_GAP, (h - chevron.size.y) * 0.5)
		var right := chevron.position.x + chevron.size.x
		var w := maxf(UiTokens.SIZE_TOUCH, right - title_label.position.x)
		hit.position = Vector2(title_label.position.x, (h - UiTokens.SIZE_TOUCH) * 0.5)
		hit.size = Vector2(w, UiTokens.SIZE_TOUCH)

func _look() -> Control:
	var area := Control.new()
	area.custom_minimum_size = Vector2(0, _LOOK.y)
	preview = BagCharacterPreview.new()
	preview.custom_minimum_size = _FIGURE
	preview.set_anchors_preset(Control.PRESET_CENTER)
	preview.offset_left = -_FIGURE.x * 0.5
	preview.offset_right = _FIGURE.x * 0.5
	preview.offset_top = -_FIGURE.y * 0.5
	preview.offset_bottom = _FIGURE.y * 0.5
	area.add_child(preview)
	spin = _Spin.new()
	spin.preview = preview
	spin.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.add_child(spin)   # under `Edit look`, which stays a button
	var edit := UiNavButton.new("Edit look", true)
	edit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	edit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	edit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	edit.pressed.connect(func(): edit_look_pressed.emit())
	area.add_child(edit)
	area.ready.connect(func(): preview.set_active(true))
	return area

func _gap(h: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = h
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(g)

## Drag sideways over the outfit to turn the figure, 0.01 rad a pixel as in the dressing room (int10c 256 ⑦). A press
## is left to the page; once the drag goes past the tap slop and more sideways than up or down, it turns the figure
## and keeps the motion, so an upward drag still scrolls the page. Mouse events only: touch arrives as the emulated
## left button (P0Ui.is_tap), so handling both would turn twice.
class _Spin extends Control:
	const RAD_PER_PX := 0.01
	var preview: BagCharacterPreview
	var _travel := Vector2.ZERO
	var _turning := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func turning() -> bool: return _turning

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_travel = Vector2.ZERO
			_turning = false
		elif e is InputEventMouseMotion:
			# Held or not by the motion's own button mask: a release lost on the way can't leave a hover turning it
			# (亚瑟 on #136).
			if (e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
				_turning = false
				return
			var rel := (e as InputEventMouseMotion).relative
			_travel += rel
			if not _turning and absf(_travel.x) > GestureArbiter.TAP_SLOP and absf(_travel.x) > absf(_travel.y):
				_turning = true
			if _turning:
				if preview != null: preview.turn_by(-rel.x * RAD_PER_PX)
				accept_event()
