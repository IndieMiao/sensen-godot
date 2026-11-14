class_name P0SysScreen
extends Control
## Whole-screen system states (WP6 E-03, §10.7.1; SGODOT-233). Each takes the whole screen and every touch; no HUD,
## no ✕. Laid out on the 360 × 800 frame of page 14:
##   LAUNCH      the launch splash (q(290); SGODOT-420, 不知火舞's boot-splash spec v1.1): the screen's height, centred
##               (splash_layout) — the engine's boot splash draws the same image the same way (Keep Height), so the hand
##               over from it is not seen; no wordmark over it (the art has one). Whole from its first frame; after 8 s the
##               spinner and `Taking longer than usual…` on a small card above the art's Gensen mark (SYS-LOADING-2)
##   FAIL        the same art under the modal scrim, SystemCard `Can't connect` · Retry (SYS-LOADING-FAIL, no wordmark)
##   MAINT       SYS-MAINT 1245:87657 — `Down for maintenance` · `We'll be back around 14:30.` · Check again
##   UPDATE      SYS-UPDATE 1245:87698 — `Update to keep playing` · `This version is out of date.` · Update
##   SCENE       SYS-LOADING-SCENE, the town map (不知火舞's spec v1 + 425 120c7163, frame L123v2; the user 11-06 00:40):
##               the illustrated town under a 15 % surface haze; on the centre line the destination's pin, the place
##               (`San Francisco · Reed Pond`) on a white pill and a 200 × 8 progress bar; after 8 s `Taking longer than
##               usual…` on its own pill under the bar. No spinner.
##   PLACE_FAIL  SYS-LOADING-SCENE-FAIL 1780:103778 (q(78)): getting to a place failed, over the same map under the modal
##               scrim; `Couldn't get there` · Retry (the same place again) · Go back (where the player came from; Back too)
##   SESSION     SYS-SESSION 645:197668 (the design's 9:119672; 不知火舞's account spec v1.1 §6.1) — 401 session_replaced:
##               `Signed in on another device` · `You've been signed out here.` · Sign in
##   DELETED     SYS-DELETED 720:201839 (spec v2 §6) — 401 account_deleted: `This account was deleted` · `Sign in to start
##               a new farm.` · Sign in
##   SUSPENDED   ACC-SUSPENDED 645:197762 / -PERM 645:197805 (spec v1.1 §6.4) — 403 suspended: `Account suspended` · `You
##               can play again on Nov 20.` (or `This account can't be used anymore.` with no end) · the support code line
##               (a tap copies it) · Contact us
##   The three account states stand on the cream as MAINT and UPDATE (the user 11-11 bot 733), the face-player icon in the
##   disc; no other way out (P0Ui.show_account_state).
## show_kind(kind, detail) draws one; `primary_pressed(kind)` is its card's button.

signal primary_pressed(kind: Kind)
## The card's secondary (PLACE_FAIL's Go back).
signal secondary_pressed(kind: Kind)
## The card's small line (SUSPENDED's support code).
signal note_pressed(kind: Kind)

enum Kind { LAUNCH, FAIL, MAINT, UPDATE, SCENE, PLACE_FAIL, SESSION, DELETED, SUSPENDED }
## The states on the account shell's cream (the art on the screen's foot, the wordmark, the card).
const CREAM := [Kind.MAINT, Kind.UPDATE, Kind.SESSION, Kind.DELETED, Kind.SUSPENDED]

## MAINT and UPDATE's ground: the account shell's brand cream (the user 11-11 bot 733, 「系统页也换」, as the sign-up's
## scheme 3 bot 728): #F6F4EA, the art the screen's width on its foot, the cream on up past it. The farm art it replaces
## is gone.
const BACKDROP := P0AccShell.BACKDROP
## The launch splash (SGODOT-420, 1214 × 1618): q(290)'s art (the user's v2, 747 × 1618) unchanged in the middle at
## x 233, its blurred copy baked into the sides (radius about 20 px, 6 % darker). Also project.godot's boot splash
## image (stretch Keep Height) and the iOS launch screen's (tools/ios): keep the three the same file.
const SPLASH := preload("res://assets/p0/ui/launch_splash.png")
const SPLASH_SKY := Color("61bbfa")   # the art's sky at its top: the sides past a 3:4 screen, as the boot splash's
## The splash in the art's 812 rows (the art read as 375 × 812, so its wordmark and marks keep their rows).
const SPLASH_SIZE := Vector2(1214.0 * 812.0 / 1618.0, 812.0)
## The Gen Sen wordmark's top (its spark too), in the 812 rows: measured on the v2 art (79 on v1; 周瑜 / 不知火舞 on
## #767) — measure again with a new art.
const SPLASH_MARK_TOP := 85.0
const SPLASH_LOGO_TOP := 752.0   # the small Gensen mark at the bottom: the slow card ends 16 above it
const SPLASH_CARD_GAP := 16.0
const SPLASH_CARD_PAD := Vector2(16, 12)
const SPLASH_CARD_ALPHA := 0.9
const SPLASH_CARD_RADIUS := 16
const SPLASH_FADE_OUT := 0.3     # into the first scene
const SPLASH_MIN_S := 0.8        # shown at least this long: a quick launch does not flash it
const CLOCK := preload("res://assets/p0/icons/clock.svg")
const FACE := preload("res://assets/p0/icons/face_player.svg")   # Gensen / Icon / i-face-player (9:956)
const WIFI_OFF := preload("res://assets/ui/kit_icons/wifi_off.svg")
const SLOW_TEXT := "Taking longer than usual…"
## The scene cover's town map (上官婉儿, Sensenjoy, 1080 × 2340, the centre left plain; 不知火舞 425), covering the screen.
## Loaded when a scene cover shows, not with the script (the launch screen is this script too): about 10 MB once decoded,
## held only while a cover is up.
const SCENE_MAP := "res://assets/ui/loading/loading_town_map.jpg"
const SCENE_HAZE := 0.15         # a surface haze over the map: the pin and the pills read on it
## On the 360 × 800 frame's centre line, kept on the screen's centre (y − 400 from it): the pin's disc ends at 360 (it
## drops 20 into place with a little bounce), the place pill's centre at 410, the bar 444–452, the slow pill's centre 472.
const SCENE_PIN_BOTTOM := 360.0
const SCENE_PIN_SIDE := 40.0
const SCENE_PIN_ICON := 24.0
const SCENE_PIN_DROP := 20.0
const SCENE_PIN_DROP_S := 0.25
const SCENE_PILL_MID := 410.0
const SCENE_PILL_H := 36.0
const SCENE_PILL_PAD := 16.0
const SCENE_PILL_MAX := 328.0
const SCENE_BAR_TOP := 444.0
const SCENE_BAR := Vector2(200, 8)
const SCENE_SLOW_MID := 472.0
const SCENE_SLOW_H := 24.0
const SCENE_SLOW_PAD := 12.0
## The pills and the pin's disc: solid surface, a 1 px border edge and a soft shadow (0, 2, 8, black 12 %; 425 120c7163).
const SCENE_SHADOW := Color(0, 0, 0, 0.12)

const _FRAME_H := 800.0
const _MARK_TOP_LAUNCH := 330.0  # the wordmark alone, a little above the middle
const _MARK_TOP := 84.0          # over a SystemCard
const _SPINNER_BELOW := 66.0     # spinner at y 396 under the launch wordmark at 330
const _CAPTION_BELOW := 104.0    # caption at y 434
const _SCENE_TEXT_SIZE := 18     # Destination ExtraBold 18, text colour, on its pill
const _BLUR_LOD := 3.5           # SYS-LOADING-SCENE's layer blur 10: the screen behind read from a low mip
const _BLUR_SHADER := "shader_type canvas_item;\nuniform float lod = 3.5;\nvoid fragment() { COLOR = textureLod(TEXTURE, UV, lod); }\n"

var kind: Kind = Kind.LAUNCH
var detail := {}
var slow := false
var card: UiSystemCard
var spinner: UiSpinner
## The scene cover's bar, 0–1 as drawn (P0LoadingLayer eases it toward the load's progress).
var progress := 0.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		if _bar_fill: _bar_fill.size.x = roundf(SCENE_BAR.x * progress)

var _bg: ColorRect
var _art: TextureRect
var _splash: TextureRect
var _slow_card: Panel
var _splash_since := -1   # msec the splash first showed, -1 before
var _shot: TextureRect
var _scrim: ColorRect
var _mark: UiWordmark
var _caption: Label
var _place: Label
var _return_main: UiDismissButton
var _map: TextureRect
var _haze: ColorRect
var _pin: Panel
var _pin_icon: TextureRect
var _place_pill: Panel
var _bar_track: Panel
var _bar_fill: Panel
var _slow_pill: Panel
var _pin_drop := 0.0   # the pin's drop still to fall (SCENE_PIN_DROP → 0 as it lands)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # a system state takes every touch
	theme = UiKit.theme()
	_bg = ColorRect.new()
	_bg.color = UiTokens.COLOR_SURFACE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_splash = TextureRect.new()
	_splash.name = "Splash"
	_splash.texture = SPLASH
	_splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_splash.stretch_mode = TextureRect.STRETCH_SCALE
	_splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_splash)
	_art = TextureRect.new()
	_art.texture = BACKDROP
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_map = TextureRect.new()
	_map.name = "SceneMap"
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_map)
	_haze = ColorRect.new()
	_haze.color = Color(UiTokens.COLOR_SURFACE, SCENE_HAZE)
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_haze)
	_shot = TextureRect.new()
	_shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_shot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var blur := Shader.new()
	blur.code = _BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = blur
	mat.set_shader_parameter(&"lod", _BLUR_LOD)
	_shot.material = mat
	_shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shot)
	_scrim = ColorRect.new()
	_scrim.color = UiTokens.COLOR_SCRIM_MODAL
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)
	_mark = UiWordmark.new()
	add_child(_mark)
	_slow_card = Panel.new()
	_slow_card.name = "SlowCard"
	_slow_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slow_card.add_theme_stylebox_override(&"panel", UiStyleBox.make(Color(UiTokens.COLOR_SURFACE, SPLASH_CARD_ALPHA), SPLASH_CARD_RADIUS))
	add_child(_slow_card)
	spinner = UiSpinner.new()
	add_child(spinner)
	_caption = UiKit.label(SLOW_TEXT, UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	_pin = _scene_panel("ScenePin", SCENE_PIN_SIDE * 0.5, UiTokens.COLOR_PRIMARY, 2.0)
	_pin_icon = TextureRect.new()
	_pin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin_icon.position = Vector2.ONE * (SCENE_PIN_SIDE - SCENE_PIN_ICON) * 0.5
	_pin_icon.size = Vector2.ONE * SCENE_PIN_ICON
	_pin.add_child(_pin_icon)
	_place_pill = _scene_panel("PlacePill", SCENE_PILL_H * 0.5)
	_bar_track = Panel.new()
	_bar_track.name = "SceneBar"
	_bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_track.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_BORDER, SCENE_BAR.y * 0.5))
	add_child(_bar_track)
	_bar_fill = Panel.new()
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_fill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY, SCENE_BAR.y * 0.5))
	_bar_fill.size = Vector2(0, SCENE_BAR.y)
	_bar_track.add_child(_bar_fill)
	_slow_pill = _scene_panel("SlowPill", SCENE_SLOW_H * 0.5)
	_place = UiKit.label("", UiTokens.STYLE_TITLE_XB20, UiTokens.COLOR_TEXT)
	_place.add_theme_font_size_override(&"font_size", _SCENE_TEXT_SIZE)
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_place)
	move_child(_caption, -1)   # over the slow pill
	card = UiSystemCard.new()
	card.primary_pressed.connect(func(): primary_pressed.emit(kind))
	card.secondary_pressed.connect(func(): secondary_pressed.emit(kind))
	card.note_pressed.connect(func(): note_pressed.emit(kind))
	card.minimum_size_changed.connect(_layout)   # a card outside a container never shrinks on its own
	add_child(card)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)

## A scene-cover pill or the pin's disc: solid surface, 1 px edge (border, or the pin's primary ring), soft shadow.
func _scene_panel(id: String, radius: float, edge := UiTokens.COLOR_BORDER, width := 1.0) -> Panel:
	var p := Panel.new()
	p.name = id
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, radius, edge, width)
	box.shadow_color = SCENE_SHADOW
	box.shadow_size = 8.0
	box.shadow_offset = Vector2(0, 2)
	p.add_theme_stylebox_override(&"panel", box)
	add_child(p)
	return p

## kind: the state; detail: {back_at (MAINT, "HH:MM" local or ""), place (SCENE), icon (SCENE: the destination pin's
## Texture2D), progress (SCENE, 0–1), card ({…} for PLACE_FAIL), until (SUSPENDED: `Nov 20` already in the player's
## words, "" for no end), code (SUSPENDED: the support code, "" hides its line)}.
func show_kind(k: Kind, d := {}) -> void:
	kind = k
	detail = d
	slow = false
	# The scene cover and its failure are on the town map (the user 11-06): the player is still in the game, so no
	# launch backdrop or wordmark (不知火舞 233 walkthrough).
	var scene := k in [Kind.SCENE, Kind.PLACE_FAIL]
	var splash := k in [Kind.LAUNCH, Kind.FAIL]   # q(290): the splash art in place of the farm backdrop and wordmark
	_bg.color = SPLASH_SKY if splash else (P0AccShell.GROUND if k in CREAM else UiTokens.COLOR_SURFACE)
	_splash.visible = splash
	# Whole from its first frame (420): it takes over from the boot splash's same image, a fade would flash the sky.
	if splash and _splash_since < 0: _splash_since = Time.get_ticks_msec()
	_art.visible = not scene and not splash
	_map.visible = scene
	if scene and _map.texture == null: _map.texture = load(SCENE_MAP)
	_haze.visible = scene
	_shot.visible = false   # the town map stands in for the screen behind (no read back from the GPU either)
	_scrim.visible = k in [Kind.PLACE_FAIL, Kind.FAIL]
	_mark.visible = not scene and not splash
	_slow_card.visible = false
	var on_map := k == Kind.SCENE
	for n in [_place, _place_pill, _pin, _bar_track]: (n as CanvasItem).visible = on_map
	_slow_pill.visible = false
	_place.text = str(d.get("place", ""))
	_pin_icon.texture = d.get("icon", null)
	progress = float(d.get("progress", 0.0))
	spinner.visible = false
	_caption.visible = false
	card.visible = k in [Kind.FAIL, Kind.PLACE_FAIL] or k in CREAM
	if card.visible: card.show_card(card_spec(k, d))
	_layout()

## 341: only a failed launch on a test account exposes a direct return; never shown over loading or normal play.
func set_return_main(action: Callable) -> void:
	if _return_main == null and action.is_valid():
		_return_main = P0SettingsPage.return_main_link(action)
		card.secondary.get_parent().add_child(_return_main)
	if _return_main != null: _return_main.visible = action.is_valid() and kind == Kind.FAIL
	_layout()

## The card each state draws (q(74) copy; the maintenance time is the player's local clock).
static func card_spec(k: Kind, d := {}) -> Dictionary:
	match k:
		Kind.FAIL:
			return {icon = WIFI_OFF, icon_tint = UiTokens.COLOR_TEXT, title = "Can't connect",
				body = "Check your connection and try again.", primary = "Retry"}
		Kind.MAINT:
			var at := str(d.get("back_at", ""))
			return {icon = CLOCK, title = "Down for maintenance",
				body = ("We'll be back around %s." % at) if at != "" else "We'll be back soon.", primary = "Check again"}
		Kind.UPDATE:
			return {icon = UiWordmark.SPROUT, title = "Update to keep playing", body = "This version is out of date.",
				primary = "Update" if str(d.get("url", "")) != "" else ""}
		Kind.PLACE_FAIL:   # SYS-LOADING-SCENE-FAIL 1780:103778, q(78): like Can't connect, plus the way back
			return {icon = WIFI_OFF, icon_tint = UiTokens.COLOR_TEXT, title = "Couldn't get there",
				body = "Check your connection and try again.", primary = "Retry", secondary = "Go back"}
		Kind.SESSION:   # the design's own lines (LOCK-28)
			return {icon = FACE, title = "Signed in on another device", body = "You've been signed out here.", primary = "Sign in"}
		Kind.DELETED:   # spec v2 §6: no new farm here any more, signing in leads to one
			return {icon = FACE, title = "This account was deleted", body = "Sign in to start a new farm.", primary = "Sign in"}
		Kind.SUSPENDED:
			var until := str(d.get("until", ""))
			var code := str(d.get("code", ""))
			return {icon = FACE, title = "Account suspended",
				body = ("You can play again on %s." % until) if until != "" else "This account can't be used anymore.",
				note = ("Support code %s" % code) if code != "" else "", primary = "Contact us"}
	return {}

## 8 s in: `Taking longer than usual…` (LOADING-2) — with the spinner on a small surface card over the launch's splash
## (q(290)); on the scene cover on its own pill under the bar, the bar going on (no spinner).
func taking_longer() -> void:
	if not kind in [Kind.LAUNCH, Kind.SCENE]: return
	slow = true
	spinner.visible = kind == Kind.LAUNCH
	_caption.visible = true
	_slow_card.visible = kind == Kind.LAUNCH
	_slow_pill.visible = kind == Kind.SCENE
	_caption.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY)
	_caption.theme_type_variation = UiTokens.STYLE_CAPTION_B12 if kind == Kind.SCENE else UiTokens.STYLE_C13_B
	_layout()

## The scene cover's pin lands: it drops SCENE_PIN_DROP into place with a little bounce, once, when the cover shows.
func drop_pin() -> void:
	if kind != Kind.SCENE or not is_inside_tree(): return
	_pin_drop = SCENE_PIN_DROP
	_layout()
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): _pin_drop = v; _layout(), SCENE_PIN_DROP, 0.0, SCENE_PIN_DROP_S)

## The boot splash's Keep Height (420, spec v1.1 §2): s = h ÷ 812, the splash's top and bottom on the screen's, centred —
## a narrow screen (20:9, 19.5:9, 21:9) cuts its blurred sides and a little of the art, a wide one (18:9, 16:9) shows
## them; the art's wordmark well under the status bar either way. Not rounded: the engine's isn't. {scale, origin (the
## splash's top-left on screen)}.
static func splash_layout(screen: Vector2) -> Dictionary:
	var s := screen.y / SPLASH_SIZE.y
	return {"scale": s, "origin": Vector2((screen.x - SPLASH_SIZE.x * s) * 0.5, 0.0)}

## Takes a launch splash down into the scene under it: at least SPLASH_MIN_S after it first showed, then a 300 ms fade;
## the layer it is on goes with it. It takes no more touches from now (the caller has already let go of it).
func leave(layer: Node) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in find_children("*", "Control", true, false): (c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_inside_tree():
		layer.queue_free()
		return
	var shown := (Time.get_ticks_msec() - _splash_since) / 1000.0 if _splash_since >= 0 else SPLASH_MIN_S
	var tw := create_tween()
	if shown < SPLASH_MIN_S: tw.tween_interval(SPLASH_MIN_S - shown)
	tw.tween_property(self, ^"modulate:a", 0.0, SPLASH_FADE_OUT)
	tw.tween_callback(layer.queue_free)

func _layout() -> void:
	var w := size.x
	var h := size.y if size.y > 0.0 else _FRAME_H
	var k := h / _FRAME_H   # the frame's heights on a taller or shorter screen
	var sl := splash_layout(Vector2(w, h))
	_splash.position = sl.origin
	_splash.size = SPLASH_SIZE * float(sl.scale)
	var art_h := roundf(w * BACKDROP.get_height() / BACKDROP.get_width())   # on the screen's foot, as the account shell's
	_art.position = Vector2(0, h - art_h)
	_art.size = Vector2(w, art_h)
	var mark_size := _mark.get_combined_minimum_size()
	var mark_top := roundf(_MARK_TOP_LAUNCH * k) if kind == Kind.LAUNCH else _MARK_TOP
	_mark.position = Vector2(roundf((w - mark_size.x) * 0.5), mark_top)
	_mark.size = mark_size
	spinner.position = Vector2(roundf((w - UiSpinner.SIDE) * 0.5), mark_top + _SPINNER_BELOW)
	spinner.size = Vector2(UiSpinner.SIDE, UiSpinner.SIDE)
	_caption.position = Vector2(0, mark_top + _CAPTION_BELOW)
	_caption.size = Vector2(w, 0)
	if kind == Kind.SCENE: _layout_scene(w, h)
	if kind == Kind.LAUNCH:   # q(290): spinner over caption on the slow card, its bottom 16 above the art's Gensen mark
		var cap := _caption.get_combined_minimum_size()
		var inner := Vector2(maxf(cap.x, UiSpinner.SIDE), UiSpinner.SIDE + 8.0 + cap.y)
		var box := inner + SPLASH_CARD_PAD * 2.0
		var bottom := float((sl.origin as Vector2).y) + SPLASH_LOGO_TOP * float(sl.scale) - SPLASH_CARD_GAP
		_slow_card.size = box.round()
		_slow_card.position = Vector2(roundf((w - box.x) * 0.5), roundf(bottom - box.y))
		spinner.position = Vector2(roundf((w - UiSpinner.SIDE) * 0.5), _slow_card.position.y + SPLASH_CARD_PAD.y)
		_caption.position = Vector2(0, spinner.position.y + UiSpinner.SIDE + 8.0)
	var card_size := card.get_combined_minimum_size()
	card.position = Vector2(roundf((w - card_size.x) * 0.5), roundf((h - card_size.y) * 0.5))
	card.size = card_size

## The scene cover on the frame's centre line, kept on the screen's centre (y − 400 from it): the pin, the place on its
## pill (wrapped at a ` · ` past SCENE_PILL_MAX), the bar, and the slow line on its pill.
func _layout_scene(w: float, h: float) -> void:
	var at := func(y: float) -> float: return roundf(h * 0.5 + y - _FRAME_H * 0.5)
	var cx := w * 0.5
	_pin.size = Vector2.ONE * SCENE_PIN_SIDE
	_pin.position = Vector2(roundf(cx - SCENE_PIN_SIDE * 0.5), at.call(SCENE_PIN_BOTTOM) - SCENE_PIN_SIDE - roundf(_pin_drop))
	var font := _place.get_theme_font(&"font")
	var inner := minf(SCENE_PILL_MAX, w - 32.0) - SCENE_PILL_PAD * 2.0
	_place.text = UiKit.break_at_dot(str(detail.get("place", "")), font, _SCENE_TEXT_SIZE, inner)
	var text := _place.get_combined_minimum_size()
	var pill := Vector2(minf(text.x, inner) + SCENE_PILL_PAD * 2.0, maxf(SCENE_PILL_H, text.y + 8.0)).round()
	_place_pill.size = pill
	_place_pill.position = Vector2(roundf(cx - pill.x * 0.5), at.call(SCENE_PILL_MID) - roundf(pill.y * 0.5))
	_place.position = _place_pill.position
	_place.size = pill
	_bar_track.size = SCENE_BAR
	_bar_track.position = Vector2(roundf(cx - SCENE_BAR.x * 0.5), at.call(SCENE_BAR_TOP) + maxf(0.0, pill.y - SCENE_PILL_H) * 0.5)
	_bar_fill.size = Vector2(roundf(SCENE_BAR.x * progress), SCENE_BAR.y)
	var cap := _caption.get_combined_minimum_size()
	var slow_box := Vector2(cap.x + SCENE_SLOW_PAD * 2.0, SCENE_SLOW_H).round()
	_slow_pill.size = slow_box
	_slow_pill.position = Vector2(roundf(cx - slow_box.x * 0.5), _bar_track.position.y + (SCENE_SLOW_MID - SCENE_BAR_TOP) - roundf(slow_box.y * 0.5))
	_caption.position = Vector2(0, _slow_pill.position.y + roundf((slow_box.y - cap.y) * 0.5))
	_caption.size = Vector2(w, 0)

## The screen as it is now, halved and with mipmaps: the scene cover reads it from a low mip (blurred). Null where
## nothing has been drawn (headless runs).
static func blurred_screen(vp: Viewport) -> Texture2D:
	var tex := vp.get_texture() if vp else null
	var img := tex.get_image() if tex else null
	if img == null or img.is_empty(): return null
	img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
