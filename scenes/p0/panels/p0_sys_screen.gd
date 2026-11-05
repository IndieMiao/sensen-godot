class_name P0SysScreen
extends Control
## Whole-screen system states (WP6 E-03, §10.7.1; SGODOT-233). Each takes the whole screen and every touch; no HUD,
## no ✕. Laid out on the 360 × 800 frame of page 14:
##   LAUNCH      the splash art (q(290), 不知火舞's spec v1, 302 c9986a33): its bottom on the screen's, cut only from the sky
##               at the top, or on a wider screen fitted under the status bar over its own blurred copy (splash_layout);
##               no wordmark over it (the art has one). It fades in from the sky colour; after 8 s the spinner and
##               `Taking longer than usual…` on a small card above the art's Gensen mark (SYS-LOADING-2)
##   FAIL        the same art under the modal scrim, SystemCard `Can't connect` · Retry (SYS-LOADING-FAIL, no wordmark)
##   MAINT       SYS-MAINT 1245:87657 — `Down for maintenance` · `We'll be back around 14:30.` · Check again
##   UPDATE      SYS-UPDATE 1245:87698 — `Update to keep playing` · `This version is out of date.` · Update
##   SCENE       SYS-LOADING-SCENE 1245:87648 — the screen behind, blurred, under the modal scrim; the spinner and
##               the destination (`San Francisco · Reed Pond`) in white; after 8 s `Taking longer than usual…`
##   PLACE_FAIL  SYS-LOADING-SCENE-FAIL 1780:103778 (q(78)): getting to a place failed, over the same blurred screen;
##               `Couldn't get there` · Retry (the same place again) · Go back (where the player came from; Back too)
## show_kind(kind, detail) draws one; `primary_pressed(kind)` is its card's button.

signal primary_pressed(kind: Kind)
## The card's secondary (PLACE_FAIL's Go back).
signal secondary_pressed(kind: Kind)

enum Kind { LAUNCH, FAIL, MAINT, UPDATE, SCENE, PLACE_FAIL }

const BACKDROP := preload("res://assets/p0/ui/sys_backdrop_farm.jpg")
## q(290): the splash art (the user's, 375 × 812 until the large one comes) and its pre-rendered blurred copy (radius
## about 20 px, 6 % darker, half size) for the sides a wide screen shows.
const SPLASH := preload("res://assets/p0/ui/splash.png")
const SPLASH_BLUR := preload("res://assets/p0/ui/splash_blur.png")
const SPLASH_SKY := Color("61bbfa")   # the art's sky at its top: the system splash and the engine's first frames too
const SPLASH_SIZE := Vector2(375, 812)
const SPLASH_MARK_TOP := 79.0    # the Gen Sen wordmark's top (its spark too), in the art's rows
const SPLASH_MARK_GAP := 8.0     # … kept this far under the status bar
const SPLASH_LOGO_TOP := 752.0   # the small Gensen mark at the bottom: the slow card ends 16 above it
const SPLASH_CARD_GAP := 16.0
const SPLASH_CARD_PAD := Vector2(16, 12)
const SPLASH_CARD_ALPHA := 0.9
const SPLASH_CARD_RADIUS := 16
const SPLASH_FADE_IN := 0.2      # from the sky colour, the first time it shows
const SPLASH_FADE_OUT := 0.3     # into the first scene
const SPLASH_MIN_S := 0.8        # shown at least this long, the fade-in in it: a quick launch does not flash it
const CLOCK := preload("res://assets/p0/icons/clock.svg")
const WIFI_OFF := preload("res://assets/ui/kit_icons/wifi_off.svg")
const SLOW_TEXT := "Taking longer than usual…"

const _FRAME_H := 800.0
const _ART_TOP := 330.0          # Scene art · farm (backdrop) at y 330, 360 × 800, cropped by the screen
const _MARK_TOP_LAUNCH := 330.0  # the wordmark alone, a little above the middle
const _MARK_TOP := 84.0          # over a SystemCard
const _SPINNER_BELOW := 66.0     # spinner at y 396 under the launch wordmark at 330
const _CAPTION_BELOW := 104.0    # caption at y 434
const _SCENE_SPINNER := 370.0
const _SCENE_TEXT := 410.0
const _SCENE_TEXT_SIZE := 18     # Destination ExtraBold 18 white, 0 2 6 shadow
const _SCENE_SHADOW_Y := 2
const _BLUR_LOD := 3.5           # SYS-LOADING-SCENE's layer blur 10: the screen behind read from a low mip
const _BLUR_SHADER := "shader_type canvas_item;\nuniform float lod = 3.5;\nvoid fragment() { COLOR = textureLod(TEXTURE, UV, lod); }\n"

var kind: Kind = Kind.LAUNCH
var detail := {}
var slow := false
var card: UiSystemCard
var spinner: UiSpinner

## The status bar's height (P0Ui.safe_top): the fitted splash keeps the wordmark under it.
var status_top := 0.0

var _bg: ColorRect
var _art: TextureRect
var _fade: TextureRect
var _splash: TextureRect
var _splash_blur: TextureRect
var _slow_card: Panel
var _splash_since := -1   # msec the splash first showed, -1 before
var _shot: TextureRect
var _scrim: ColorRect
var _mark: UiWordmark
var _caption: Label
var _place: Label
var _return_main: UiDismissButton

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # a system state takes every touch
	theme = UiKit.theme()
	_bg = ColorRect.new()
	_bg.color = UiTokens.COLOR_SURFACE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_splash_blur = TextureRect.new()
	_splash_blur.name = "SplashBlur"
	_splash_blur.texture = SPLASH_BLUR
	_splash_blur.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_splash_blur.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_splash_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_splash_blur)
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
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_fade = TextureRect.new()
	_fade.texture = _fade_texture()
	_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade.stretch_mode = TextureRect.STRETCH_SCALE
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
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
	_place = UiKit.label("", UiTokens.STYLE_TITLE_XB20, UiTokens.COLOR_SURFACE_RAISED)
	_place.add_theme_font_size_override(&"font_size", _SCENE_TEXT_SIZE)
	_place.add_theme_color_override(&"font_shadow_color", UiTokens.COLOR_SHADOW_CARD)
	_place.add_theme_constant_override(&"shadow_offset_y", _SCENE_SHADOW_Y)
	_place.add_theme_constant_override(&"shadow_offset_x", 0)
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_place)
	card = UiSystemCard.new()
	card.primary_pressed.connect(func(): primary_pressed.emit(kind))
	card.secondary_pressed.connect(func(): secondary_pressed.emit(kind))
	card.minimum_size_changed.connect(_layout)   # a card outside a container never shrinks on its own
	add_child(card)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)

## Surface at the top fading out toward the art at the bottom (Backdrop fade: 100 % to the middle, 35 % at 72 %, 0).
static func _fade_texture() -> GradientTexture2D:
	var g := Gradient.new()
	var s := UiTokens.COLOR_SURFACE
	g.offsets = PackedFloat32Array([0.0, 0.5, 0.72, 1.0])
	g.colors = PackedColorArray([s, s, Color(s, 0.35), Color(s, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 256
	return t

## kind: the state; detail: {back_at (MAINT, "HH:MM" local or ""), place (SCENE), shot (SCENE: the screen behind,
## a Texture2D), card ({…} for PLACE_FAIL)}.
func show_kind(k: Kind, d := {}) -> void:
	kind = k
	detail = d
	slow = false
	# The scene cover and its failure stay on the blurred screen being left: the player is still in the game, so no
	# launch backdrop or wordmark (不知火舞 233 walkthrough).
	var scene := k in [Kind.SCENE, Kind.PLACE_FAIL]
	var splash := k in [Kind.LAUNCH, Kind.FAIL]   # q(290): the splash art in place of the farm backdrop and wordmark
	_bg.color = SPLASH_SKY if splash else UiTokens.COLOR_SURFACE
	_splash.visible = splash
	if splash and _splash_since < 0:   # the first time: in from the sky colour
		_splash_since = Time.get_ticks_msec()
		for t in [_splash, _splash_blur]: (t as CanvasItem).modulate.a = 0.0
		if is_inside_tree():
			var tw := create_tween().set_parallel()
			for t in [_splash, _splash_blur]: tw.tween_property(t, ^"modulate:a", 1.0, SPLASH_FADE_IN)
		else:
			for t in [_splash, _splash_blur]: (t as CanvasItem).modulate.a = 1.0
	_art.visible = not scene and not splash
	_fade.visible = not scene and not splash
	_shot.visible = scene
	_scrim.visible = scene or k == Kind.FAIL
	_mark.visible = not scene and not splash
	_slow_card.visible = false
	_place.visible = k == Kind.SCENE
	_place.text = str(d.get("place", ""))
	_shot.texture = d.get("shot", null)
	spinner.visible = k == Kind.SCENE
	_caption.visible = false
	card.visible = k in [Kind.FAIL, Kind.MAINT, Kind.UPDATE, Kind.PLACE_FAIL]
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
	return {}

## 8 s in: the spinner and `Taking longer than usual…` (LOADING-2); white on the scene's scrim, on a small surface card
## over the launch's splash (q(290)).
func taking_longer() -> void:
	if not kind in [Kind.LAUNCH, Kind.SCENE]: return
	slow = true
	spinner.visible = true
	_caption.visible = true
	_slow_card.visible = kind == Kind.LAUNCH
	_caption.add_theme_color_override(&"font_color", UiTokens.COLOR_SURFACE_RAISED if kind == Kind.SCENE else UiTokens.COLOR_SECONDARY)
	_layout()

## q(290)'s one formula: the art's bottom on the screen's, centred. Covering (s = the larger of the two fits) while the
## wordmark's top still sits SPLASH_MARK_GAP under the status bar — only the sky and the sides are cut (20:9, 19.5:9,
## 21:9); else (a wider screen: 18:9, 16:9, an iPad) s = (h − status − gap) ÷ (812 − 79), the wordmark right there and
## the sides showing the blurred copy. {scale, origin (the art's top-left on screen), fit}.
static func splash_layout(screen: Vector2, status := 0.0) -> Dictionary:
	var s := maxf(screen.x / SPLASH_SIZE.x, screen.y / SPLASH_SIZE.y)
	var fit := screen.y - SPLASH_SIZE.y * s + SPLASH_MARK_TOP * s < status + SPLASH_MARK_GAP
	if fit: s = (screen.y - status - SPLASH_MARK_GAP) / (SPLASH_SIZE.y - SPLASH_MARK_TOP)
	return {"scale": s, "origin": Vector2((screen.x - SPLASH_SIZE.x * s) * 0.5, screen.y - SPLASH_SIZE.y * s), "fit": fit}

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
	var sl := splash_layout(Vector2(w, h), status_top)
	_splash.position = (sl.origin as Vector2).round()
	_splash.size = (SPLASH_SIZE * float(sl.scale)).round()
	_splash_blur.visible = _splash.visible and bool(sl.fit)
	_art.position = Vector2(0, roundf(_ART_TOP * k))
	_art.size = Vector2(w, h)
	var mark_size := _mark.get_combined_minimum_size()
	var mark_top := roundf(_MARK_TOP_LAUNCH * k) if kind == Kind.LAUNCH else _MARK_TOP
	_mark.position = Vector2(roundf((w - mark_size.x) * 0.5), mark_top)
	_mark.size = mark_size
	var spin_top := (mark_top + _SPINNER_BELOW) if kind == Kind.LAUNCH else roundf(_SCENE_SPINNER * k)
	spinner.position = Vector2(roundf((w - UiSpinner.SIDE) * 0.5), spin_top)
	spinner.size = Vector2(UiSpinner.SIDE, UiSpinner.SIDE)
	_place.position = Vector2(0, roundf(_SCENE_TEXT * k))
	_place.size = Vector2(w, 0)
	var caption_top := (mark_top + _CAPTION_BELOW) if kind == Kind.LAUNCH else _place.position.y + _place.get_combined_minimum_size().y + 4.0
	_caption.position = Vector2(0, caption_top)
	_caption.size = Vector2(w, 0)
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

## The screen as it is now, halved and with mipmaps: the scene cover reads it from a low mip (blurred). Null where
## nothing has been drawn (headless runs).
static func blurred_screen(vp: Viewport) -> Texture2D:
	var tex := vp.get_texture() if vp else null
	var img := tex.get_image() if tex else null
	if img == null or img.is_empty(): return null
	img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
