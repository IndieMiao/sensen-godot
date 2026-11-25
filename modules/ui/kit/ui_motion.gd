class_name UiMotion
## UI v3 motion (docs/design/ui-v3-2026-11-24 §5, C-105): every Tween reads the v3 motion tokens
## (UiTokens.MOTION_DURATION_*_MS, MOTION_EASING_*). UI tweens run while the tree is paused (TWEEN_PAUSE_PROCESS), so a
## panel still closes; none holds input longer than 320 ms. Scaled controls must not sit directly in a Container (it
## resets their scale on layout); set the pivot here, from the control's size when the tween starts.
##   M-01 press()       buttons, slots, glass buttons: down ×0.94 in 80 (cubic out), up ×1 in 160 (back out)
##   M-04 panel_in()    scrim 0 → its alpha in 200 (linear); panel ×0.88 → 1 and alpha 0 → 1 in 260 (back out)
##   M-05 panel_out()   panel ×1 → 0.94 and alpha → 0 in 160 (cubic in), scrim → 0 in 200; input is let go at once
##   M-10 float_text()  pop ×0.6 → 1 in 120, rise 40 over 800 (cubic out), hold to 480 then fade in 320 (linear)
##   M-16 bar_shown()   quick bar hide: y +24 and fade in 200 (ease in); show: back in 260 (ease out)

## The design's 减少动效 switch (default off, §5): scale, move and loop motion become 120 ms fades.
static var reduced := false

const FLOAT_POP_FROM := 0.6
const FLOAT_HOLD_MS := 480.0
const BAR_HIDE_Y := 24.0
const PANEL_EXIT_SCALE := 0.94
const FLOAT_STACK_MAX := 4
const FLOAT_JITTER_X := 6.0

static func secs(ms: float) -> float: return ms / 1000.0

## A tween on `node` with one of the MOTION_EASING_* pairs, running while paused.
static func tween(node: Node, easing: Array) -> Tween:
	var tw := node.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_trans(easing[0]).set_ease(easing[1])
	return tw

## M-01: down = finger on (×0.94), up = released or moved off (back to ×1 with a small overshoot).
static func press(c: Control, down: bool) -> void:
	if c == null or not c.is_inside_tree(): return
	_kill(c, &"_ui_press")
	c.pivot_offset = c.size * 0.5
	if reduced:
		c.scale = Vector2.ONE
		return
	var tw := tween(c, UiTokens.MOTION_EASING_STANDARD if down else UiTokens.MOTION_EASING_POP)
	var target := Vector2.ONE * (UiTokens.MOTION_PRESS_SCALE if down else 1.0)
	tw.tween_property(c, "scale", target, secs(UiTokens.MOTION_DURATION_INSTANT_MS if down else UiTokens.MOTION_DURATION_QUICK_MS))
	c.set_meta(&"_ui_press", tw)

## Connects M-01 to a BaseButton's down / up.
static func press_feedback(b: BaseButton) -> void:
	b.button_down.connect(func(): press(b, true))
	b.button_up.connect(func(): press(b, false))

## M-04: `pivot` is a fraction of the panel's size (the bag: its centre; the NPC card: its bottom middle).
static func panel_in(panel: Control, scrim: CanvasItem = null, pivot := Vector2(0.5, 0.5)) -> Tween:
	if scrim != null:
		var to := scrim.modulate.a
		scrim.modulate.a = 0.0
		var st := tween(scrim, UiTokens.MOTION_EASING_LINEAR)
		st.tween_property(scrim, "modulate:a", to, secs(UiTokens.MOTION_DURATION_BASE_MS))
	_kill(panel, &"_ui_panel")
	panel.modulate.a = 0.0
	var tw: Tween
	if reduced:
		tw = tween(panel, UiTokens.MOTION_EASING_LINEAR)
		tw.tween_property(panel, "modulate:a", 1.0, secs(UiTokens.MOTION_DURATION_FAST_MS))
	else:
		panel.scale = Vector2.ONE * UiTokens.MOTION_PANEL_ENTER_SCALE
		tw = tween(panel, UiTokens.MOTION_EASING_POP)
		tw.tween_callback(func(): panel.pivot_offset = panel.size * pivot)
		tw.tween_property(panel, "scale", Vector2.ONE, secs(UiTokens.MOTION_DURATION_MODERATE_MS))
		tw.parallel().tween_property(panel, "modulate:a", 1.0, secs(UiTokens.MOTION_DURATION_MODERATE_MS))
	panel.set_meta(&"_ui_panel", tw)
	return tw

## M-05: `done` runs when the panel has faded (free it there). Input is the caller's to release at once.
static func panel_out(panel: Control, scrim: CanvasItem, done: Callable, pivot := Vector2(0.5, 0.5)) -> Tween:
	_kill(panel, &"_ui_panel")
	panel.pivot_offset = panel.size * pivot
	if scrim != null:
		var st := tween(scrim, UiTokens.MOTION_EASING_LINEAR)
		st.tween_property(scrim, "modulate:a", 0.0, secs(UiTokens.MOTION_DURATION_BASE_MS))
	var tw := tween(panel, UiTokens.MOTION_EASING_EXIT)
	var ms := UiTokens.MOTION_DURATION_FAST_MS if reduced else UiTokens.MOTION_DURATION_QUICK_MS
	if not reduced: tw.tween_property(panel, "scale", Vector2.ONE * PANEL_EXIT_SCALE, secs(ms))
	tw.parallel().tween_property(panel, "modulate:a", 0.0, secs(ms))
	if scrim != null and not reduced:
		tw.tween_interval(secs(UiTokens.MOTION_DURATION_BASE_MS - ms))
	tw.tween_callback(done)
	panel.set_meta(&"_ui_panel", tw)
	return tw

## M-10: plays a float from `at` (the bottom centre of where it shows, in its parent's space). `index` staggers
## lines 90 ms apart with ±6 px of x, each a line higher than the one before; frees the node when done.
static func float_text(c: Control, at: Vector2, index := 0) -> Tween:
	var jitter := 0.0 if index == 0 else FLOAT_JITTER_X * (1.0 if index % 2 == 1 else -1.0)
	c.position = at - Vector2(c.size.x * 0.5 - jitter, c.size.y + (c.size.y + UiTokens.SPACE_S1) * index)
	c.pivot_offset = Vector2(c.size.x * 0.5, c.size.y)
	c.modulate.a = 0.0
	var delay := secs(UiTokens.MOTION_STAGGER_MS_FLOAT * index)
	var total := secs(UiTokens.MOTION_DURATION_FLOAT_MS)
	var tw := tween(c, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_interval(delay)
	tw.tween_callback(func(): c.modulate.a = 1.0)
	if reduced:
		tw.tween_property(c, "modulate:a", 0.0, total).set_trans(Tween.TRANS_LINEAR)
	else:
		c.scale = Vector2.ONE * FLOAT_POP_FROM
		tw.tween_property(c, "scale", Vector2.ONE, secs(UiTokens.MOTION_DURATION_FAST_MS)).set_trans(Tween.TRANS_BACK)
		tw.parallel().tween_property(c, "position:y", c.position.y - UiTokens.MOTION_FLOAT_TEXT_RISE, total)
		tw.parallel().tween_property(c, "modulate:a", 0.0, total - secs(FLOAT_HOLD_MS)) \
			.set_delay(secs(FLOAT_HOLD_MS)).set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(c.queue_free)
	return tw

## M-16: the quick bar slides 24 down and fades out (200, ease in), or comes back (260, ease out). `shown` false
## leaves it invisible at the end so it takes no touches.
static func bar_shown(c: Control, shown: bool, rest_y: float) -> Tween:
	_kill(c, &"_ui_bar")
	if shown: c.visible = true
	var tw := tween(c, UiTokens.MOTION_EASING_STANDARD if shown else UiTokens.MOTION_EASING_EXIT)
	var ms := UiTokens.MOTION_DURATION_MODERATE_MS if shown else UiTokens.MOTION_DURATION_BASE_MS
	if not reduced: tw.tween_property(c, "position:y", rest_y + (0.0 if shown else BAR_HIDE_Y), secs(ms))
	tw.parallel().tween_property(c, "modulate:a", 1.0 if shown else 0.0, secs(ms))
	if not shown: tw.tween_callback(func(): c.visible = false)
	c.set_meta(&"_ui_bar", tw)
	return tw

static func _kill(c: Object, key: StringName) -> void:
	if c.has_meta(key):
		var old = c.get_meta(key)
		if old is Tween and (old as Tween).is_valid(): (old as Tween).kill()
		c.remove_meta(key)
