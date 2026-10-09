class_name P0ProfilePage
extends Control
## Own profile, P0 subset (SGODOT-225; PROFILE-1-P0, LOCK-22). One profile design: the same structure and kit
## parts as PROFILE-1, with the blocks P0 has no data for left out (title, ID, bio, relations, Edit, Medals /
## Guestbook / Second Home, the Crops and Cities collections). Full screen on the cream surface:
##   top bar     back + Profile (+ gear for Settings: hidden until P0 has a Settings page)
##   look        the saved outfit (BagCharacterPreview; a sideways drag turns it) + `Edit look ›` (the dressing room)
##   identity    name, `City · Climate · Since Oct 2` (view.profile, SGODOT-228; a missing field hides its line)
##   skills      three UiSkillCards; tapping one opens the skill details
##   farm        UiFarmCard: farm name, Level N, the farm's status line, › to HOME-1
##   Collections Fish-dex and Cookbook pages as M count NEED-TILEs
## Emits back_pressed, edit_look_pressed, skill_pressed(skill), settings_pressed.

signal back_pressed
signal edit_look_pressed
signal skill_pressed(skill: String)
signal settings_pressed
## A Collections tile was tapped: "fish" (the Fish-dex, FISH-6) or "pages" (the Cookbook).
signal collection_pressed(key: String)
## The farm card was tapped: HOME-1 (§10.6.2, int11).
signal farm_pressed

const SKILLS := ["farming", "fishing", "cooking"]
const _SKILL_ICONS := {"farming": "hoe", "fishing": "rod", "cooking": "pot"}
const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
# PROFILE-1-P0 layout (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _TOP := 38.0              # top bar y
const _LOOK := Vector2(360, 210)  # outfit area under the top bar (y 84)
const _LOOK_GAP := 2.0          # top bar → outfit area
const _FIGURE := Vector2(120, 196)
const _CONTENT_GAP := 8.0       # Profile content column
const _SKILL_GAP := 8.0

var view := {}
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

func _init(view_: Dictionary = {}, safe_top_ := 0.0, look_saved_ := false) -> void:
	view = view_
	safe_top = safe_top_
	look_saved = look_saved_
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
	# TODO(LOCK-22): P0 has no Settings page (cut from the demo, 2026-10-08); show the gear again when first-run /
	# Settings come back.
	top_bar.show_settings = false
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
	if profile_data(view_) != _shown: refresh(view_)

## Rebuild the facts below the outfit from a new view (the outfit and top bar stay).
func refresh(view_: Dictionary) -> void:
	view = view_
	_refreshed_ms = Time.get_ticks_msec()
	while _body.get_child_count() > 3:
		var c := _body.get_child(3)
		_body.remove_child(c)
		c.queue_free()
	var d := profile_data(view)
	_shown = d
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", int(_CONTENT_GAP))
	_body.add_child(col)
	var id := VBoxContainer.new()
	id.add_theme_constant_override(&"separation", int(_CONTENT_GAP))
	id.add_child(UiKit.label(str(d.name), UiTokens.STYLE_C14_XB))
	if str(d.home_line) != "": id.add_child(UiKit.label(str(d.home_line), UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
	if look_saved: id.add_child(UiKit.label("Look saved", UiTokens.STYLE_C10_B, UiTokens.COLOR_PRIMARY))   # KEEP-P0-2
	col.add_child(id)
	var skills := HBoxContainer.new()
	skills.add_theme_constant_override(&"separation", int(_SKILL_GAP))
	for s in d.skills:
		var card := UiSkillCard.new(str(s.name), int(s.level), float(s.progress), P0Logic.icon(str(s.icon)))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = s.key
		card.pressed.connect(func(): skill_pressed.emit(key))
		skills.add_child(card)
	col.add_child(skills)
	var farm := UiFarmCard.new(str(d.farm.name), str(d.farm.level_line), str(d.farm.status), load("res://assets/p0/art/homestead-thumb.jpg"))
	farm.chevron = true   # it opens HOME-1: no card that looks tappable and does nothing (int11, 不知火舞 on 225)
	farm.pressed.connect(func(): farm_pressed.emit())
	col.add_child(farm)
	col.add_child(UiKit.label("Collections", UiTokens.STYLE_C11_XB))
	var tiles := []
	for c in d.collections:
		var tile := UiNeedTile.new(str(c.name), int(c.have), int(c.need), UiNeedTile.Size.M, P0Logic.icon(str(c.icon)), true)
		var key := str(c.get("key", ""))
		tile.pressed.connect(func(): collection_pressed.emit(key))
		tiles.append(tile)
	col.add_child(UiNeedTile.group(tiles))

## Everything the page shows, from the server view (pure; tested).
static func profile_data(view: Dictionary) -> Dictionary:
	var p: Dictionary = view.get("profile", {})
	var home := []
	for k in ["city", "climate"]:
		if str(p.get(k, "")) != "": home.append(str(p[k]))
	if p.get("since_ms", null) != null: home.append("Since " + since_text(float(p.since_ms)))
	var sk: Dictionary = view.get("skills", {})
	var skills := SKILLS.map(func(k: String) -> Dictionary:
		var s: Dictionary = sk.get(k, {})
		return {key = k, name = k.capitalize(), level = int(s.get("level", 1)), progress = skill_progress(s), icon = _SKILL_ICONS[k]})
	var farm: Dictionary = p.get("farm", {})
	var name := str(p.get("name", ""))
	var dex: Array = view.get("fishing", {}).get("dex", [])
	var pages: Array = view.get("cooking", {}).get("cookbook", [])
	return {
		name = name if name != "" else "You",
		home_line = " · ".join(home),
		skills = skills,
		farm = {name = str(farm.get("name", "Your Homestead")),
			level_line = "Level %d" % int(farm.level) if farm.has("level") else "",
			status = _farm_status(view)},
		collections = [
			{key = "fish", name = "Fish", have = dex.filter(func(f): return int(f.get("caught", 0)) > 0).size(), need = dex.size(), icon = "fish_crucian"},
			{key = "pages", name = "Pages", have = pages.filter(func(r): return r.get("name", null) != null).size(), need = pages.size(), icon = "recipe_card"},
		],
	}

## Progress within the current level, 0..1 (1 at the top level).
static func skill_progress(s: Dictionary) -> float:
	if s.is_empty() or s.get("next", null) == null: return 1.0
	return clampf(float(int(s.get("xp", 0)) - int(s.get("floor", 0))) / maxf(1.0, float(int(s.next) - int(s.get("floor", 0)))), 0.0, 1.0)

## `Oct 2` (`Oct 2, 2025` when not this year).
static func since_text(ms: float, now_ms := -1.0) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(ms / 1000.0))
	var now := Time.get_datetime_dict_from_unix_time(int((now_ms if now_ms >= 0.0 else Time.get_unix_time_from_system() * 1000.0) / 1000.0))
	var text := "%s %d" % [_MONTHS[int(d.month) - 1], int(d.day)]
	return text if int(d.year) == int(now.year) else "%s, %d" % [text, int(d.year)]

## The earliest crop on the plots: `Radishes ready 3h 32m`, or the first thing to do there.
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
	if crop != "": return "%s ready %s" % [P0Logic.plural(P0Logic.item_name(view, crop)), P0Logic.duration(best)]
	return ""

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
