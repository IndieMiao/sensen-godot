class_name UiHudAvatar
extends AvatarFocusButton
## UI v3 HUD avatar (C-H1, docs/design/ui-v3-2026-11-24 §4.1; C-108): a Ø52 disc — a 4 ring on `hud/ringTrack`,
## filled from 12 o'clock with the `hud/ringFrom → hud/ringTo` gradient by `progress` (0 = no fill), round a white
## Ø44 inner disc with the saved outfit's head rendered in 3D (AvatarFocusButton's cached portrait). Tapping it opens
## the profile (`pressed`); pressed plays M-01. Until the portrait renders, the inner disc shows the account glyph.

const SIZE := float(UiTokens.SIZE_HUD_AVATAR_V3)
const RING := 4.0
const _GLYPH := preload("res://assets/ui/icons/lucide/user-round.svg")
const _GLYPH_SIZE := 24.0

## The ring's fill, 0..1 (a level's progress); the dynamic farm has none, so its ring is the bare track.
var progress := 0.0: set = set_progress
## C-186 (C-185 §3.1 B, the owner's attachment-1820): a 52 cream clay rounded square (radius 16) round a light-green
## inner square instead of the ring, which had no data in the farm (F-02). Set before it enters the tree.
var clay := false

func _ready() -> void:
	name = "Avatar"
	custom_minimum_size = Vector2.ONE * SIZE
	size = custom_minimum_size
	focus_mode = Control.FOCUS_NONE
	flat = true
	tooltip_text = "Profile"
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_show_glyph()
	add_child(portrait)
	# AvatarFocusButton renders only on a visible branch: follow every ancestor's visibility, as it does.
	var ancestor: Node = self
	while ancestor:
		if ancestor.has_signal("visibility_changed"):
			ancestor.connect("visibility_changed", _sync_render_state)
			_visibility_sources.append(ancestor)
		ancestor = ancestor.get_parent()
	portrait_ready.connect(_fit_portrait)
	Avatar.outfit_saved.connect(set_outfit)
	set_outfit(Avatar.load_outfit())
	UiMotion.press_feedback(self)

func set_progress(v: float) -> void:
	progress = clampf(v, 0.0, 1.0)
	queue_redraw()

## Before the head has rendered: the account glyph, centred in the inner disc.
func _show_glyph() -> void:
	portrait.texture = _GLYPH
	portrait.modulate = UiTokens.COLOR_TEXT_MUTED
	var inset := (SIZE - _GLYPH_SIZE) * 0.5
	portrait.offset_left = inset
	portrait.offset_top = inset
	portrait.offset_right = -inset
	portrait.offset_bottom = -inset

## The rendered head fills the inner disc (it comes back already cut round).
func _fit_portrait() -> void:
	var inset := RING
	portrait.offset_left = inset
	portrait.offset_top = inset
	portrait.offset_right = -inset
	portrait.offset_bottom = -inset

func shows_head() -> bool:
	return portrait != null and portrait.texture != _GLYPH

func _draw() -> void:
	if clay:
		var rect := Rect2((size - Vector2.ONE * SIZE) * 0.5, Vector2.ONE * SIZE)
		draw_style_box(UiClay.face(UiTokens.SIZE_HUD_CLAY_AVATAR_RADIUS), rect)
		var inner := StyleBoxFlat.new()
		inner.bg_color = UiTokens.COLOR_HUD_CLAY_AVATAR_FILL
		inner.set_corner_radius_all(int(UiTokens.SIZE_HUD_CLAY_AVATAR_RADIUS - RING))
		inner.anti_aliasing = true
		draw_style_box(inner, rect.grow(-RING))
		return
	var c := size * 0.5
	var r := SIZE * 0.5
	# E1 under the disc, so the white avatar holds on a light scene.
	draw_circle(c + Vector2(0, UiTokens.ELEVATION_E1_OFFSET_Y), r, UiTokens.ELEVATION_E1_COLOR, true, -1.0, true)
	draw_circle(c, r, UiTokens.COLOR_HUD_RING_TRACK, true, -1.0, true)
	if progress > 0.0:
		var steps := maxi(2, int(48.0 * progress))
		var from := -PI * 0.5
		for i in steps:
			var a0 := from + TAU * progress * float(i) / float(steps)
			var a1 := from + TAU * progress * float(i + 1) / float(steps)
			var col := UiTokens.COLOR_HUD_RING_FROM.lerp(UiTokens.COLOR_HUD_RING_TO, float(i) / float(steps))
			draw_arc(c, r - RING * 0.5, a0, a1 + 0.01, 3, col, RING, true)
	draw_circle(c, r - RING, UiTokens.COLOR_SURFACE_RAISED, true, -1.0, true)
