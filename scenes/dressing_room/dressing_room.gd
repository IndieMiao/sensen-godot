extends Node3D
## The dressing room in UI v3 (C-108; C-85 page ②, owner-approved in Q-124; LOCK-22 lifted in C-82#19). The room,
## its camera and the 3D figure are as they were; the UI around them follows ②:
##   top bar   12 from the sides, safe top + 8: a glass ‹ Back, the `Dressing` name tag, a glass Reset (↺) and Done,
##             the primary pill (≥ 88 wide, 44 high); busy, Done reads `• • •` at the same width (Loading / Trying /
##             Saving before, ②-B) and the bar's other buttons hold
##   sheet     parts_panel.gd: the band with the hanger and the slot tabs, the slot's name, the Ø72 cells
##   leaving   with changes not saved, ‹ or Android Back ask first (leave_confirm.gd, ②-C): Save runs Done's save
##             and leaves, Discard leaves, ✕ / the scrim stay; with none it leaves at once
##   failures  a toast under the top bar (UiBarToast, ②-D), 4 s, a tap takes it away: `Couldn't save. Try again.`
##             (red bar; Done shakes ±4 three times in 200, M-02) and `Couldn't load %s. Previous look kept.`
##             (amber bar), the second under the first; a new choice clears them
## Saving is unchanged: only Done writes (Avatar.save_outfit), the outfit save's format is untouched.

const PartsPanel = preload("res://scenes/dressing_room/parts_panel.gd")
const LeaveConfirm = preload("res://scenes/dressing_room/leave_confirm.gd")
const RESET_ICON := preload("res://assets/ui/icons/lucide/rotate-ccw.svg")

@onready var anchor: Node3D = $RigAnchor
@onready var cam: DressingCamera = $Camera3D
@onready var safe_area: SafeAreaMargin = $UI/SafeArea
@onready var top_bar: HBoxContainer = $UI/SafeArea/VBox/TopBar
@onready var room_background: TextureRect = $RoomBackground/Scenery

## A tap on the figure (no drag) switches the framing between the whole figure and the open slot's part. The most a
## press may travel and still be a tap, in viewport units; past it, it is a drag that turns the figure.
const TAP_SLOP := 12.0
const DONE_MIN_W := 88.0
const BUSY_TEXT := "• • •"
const TOAST_GAP := 10.0       # top bar → the first toast (②-D: its top at 84 on a 640 screen)
const TOAST_HOLD_S := 4.0
const SHAKE_PX := 4.0
## The sheet's height: 41 % of the screen (262 on 640, ②-A), at least 240 and at most 300, plus the gesture bar.
const SHEET_RATIO := 0.41
const SHEET_MIN := 240.0
const SHEET_MAX := 300.0

var rig: AvatarRig
var parts_panel: Control
var drawer: Control
var back_button: Button
var restore_button: Button
var done_button: Button
var title_tag: UiTagPill
var toast_layer: Control
var leave_confirm: Control
var _dragging := false
var _drag_distance := 0.0
var _reframe_queued := false
var _reframe_animated := false
var _initial_ready := false
var _committing := false
var _safe_margins := Vector4(16.0, 16.0, 16.0, 16.0)
## The open slot's framing; after a tap back to the whole figure, the next tap returns to it.
var _slot_region: int = DressingCamera.Region.FULL


func _ready() -> void:
	$UI.add_child(_ui_root())
	_build_top_bar()
	drawer = PartsPanel.new()
	parts_panel = drawer
	drawer.theme = UiKit.theme()
	drawer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	$UI/Root.add_child(drawer)
	toast_layer = Control.new()
	toast_layer.name = "Toasts"
	toast_layer.theme = UiKit.theme()
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$UI/Root.add_child(toast_layer)
	# A new instance pushed by AppRouter does not go through its suspend/resume: it takes the current camera itself on
	# entering the tree, or the frozen map's camera would stay (2026-09-04 final review C1; farm.gd::_ready() too).
	cam.make_current()
	rig = Avatar.create_rig()
	anchor.add_child(rig)
	rig.config_applied.connect(_on_config_applied)
	rig.busy_changed.connect(_on_rig_busy_changed)

	# The thumbnail renderer lives under the scene and goes with it; the catalogue is the rig's.
	var thumbnailer := PartThumbnailer.new()
	thumbnailer.name = "PartThumbnailer"
	thumbnailer.catalog = Avatar.catalog
	add_child(thumbnailer)
	parts_panel.thumbnailer = thumbnailer

	parts_panel.setup(rig)
	parts_panel.selection_started.connect(_hide_feedback)
	parts_panel.selection_failed.connect(_show_feedback.bind(UiBarToast.Kind.WARNING))
	parts_panel.slot_changed.connect(_on_slot_changed)
	back_button.pressed.connect(_on_back)
	restore_button.pressed.connect(_on_restore)
	done_button.pressed.connect(_on_done)
	safe_area.margins_applied.connect(_on_safe_margins_applied)
	get_viewport().size_changed.connect(_reframe)

	rig.apply_config(Avatar.load_outfit())
	# SafeArea's first signal comes before this _ready(): refresh, so the camera keeps clear of the real safe area.
	safe_area.refresh()
	_place_drawer()
	_refresh_completion_state()
	parts_panel.play_enter()


## A full-screen root under the UI layer for the sheet and the toasts (themed with the v3 kit).
func _ui_root() -> Control:
	var root := Control.new()
	root.name = "Root"
	root.theme = UiKit.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return root


func _build_top_bar() -> void:
	top_bar.theme = UiKit.theme()
	back_button = UiGlassButton.new(null, UiGlassButton.Glyph.BACK)
	back_button.name = "BackButton"
	back_button.tooltip_text = L10n.text("Back")
	top_bar.add_child(back_button)
	title_tag = UiTagPill.new("Dressing")
	title_tag.name = "Title"
	title_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_bar.add_child(title_tag)
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	restore_button = UiGlassButton.new(RESET_ICON)
	restore_button.name = "RestoreButton"
	restore_button.tooltip_text = L10n.text("Reset")
	top_bar.add_child(restore_button)
	done_button = Button.new()
	done_button.name = "DoneButton"
	done_button.focus_mode = Control.FOCUS_NONE
	done_button.theme_type_variation = UiTokens.BUTTON_CMD_PRIMARY
	done_button.text = L10n.text("Done")
	done_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	done_button.custom_minimum_size = Vector2(DONE_MIN_W, UiTokens.SIZE_TOUCH_MIN)
	UiMotion.press_feedback(done_button)
	top_bar.add_child(done_button)


func _on_config_applied(_config: AvatarConfig) -> void:
	_initial_ready = true
	var animation_player := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation_player:
		animation_player.play("idle")
	parts_panel.refresh()
	_refresh_completion_state()
	_reframe()


## Changing clothes never reframes: the camera frames DressingCamera.reference_box(), a box that does not depend on
## the outfit, so a tall hairdo does not push it back. Layout changes (safe area, sheet, viewport) still reframe; a slot
## switch zooms on its part. Zooming out: entering (FULL), a tap on the figure, the same tab again.
func _on_slot_changed(slot: StringName) -> void:
	_slot_region = DressingCamera.region_for_slot(slot)
	cam.focus_region = _slot_region
	_reframe(true)


func _toggle_focus() -> void:
	var full: int = DressingCamera.Region.FULL
	cam.focus_region = full if cam.focus_region != full else _slot_region
	_reframe(true)


func _on_rig_busy_changed(_busy: bool) -> void:
	_refresh_completion_state()


## The bar sits 8 under the safe top and 12 from the sides (the glass ‹ draws its 36 disc 4 inside its 44 hit area).
func _on_safe_margins_applied(margins: Vector4) -> void:
	_safe_margins = margins
	var inset := (UiTokens.SIZE_TOUCH_MIN - UiTokens.SIZE_HUD_SIDE_BUTTON) * 0.5
	safe_area.add_theme_constant_override(&"margin_left", roundi(margins.x + UiTokens.SIZE_SCREEN_EDGE - inset))
	safe_area.add_theme_constant_override(&"margin_top", roundi(margins.y + UiTokens.SIZE_SCREEN_SAFE_INSET))
	safe_area.add_theme_constant_override(&"margin_right", roundi(margins.z + UiTokens.SIZE_SCREEN_EDGE))
	_place_drawer()
	_reframe()


## Unsaved changes: the outfit wanted now differs from the saved one (a part still loading counts).
func has_changes() -> bool:
	if rig == null: return false
	return not rig.desired_config().changed_slots(Avatar.load_outfit()).is_empty()


func _on_back() -> void:
	if _committing:
		return
	if is_instance_valid(leave_confirm):
		return
	if has_changes():
		_ask_before_leaving()
		return
	# The rig is a draft: leaving without save() drops it.
	AppRouter.pop_instance()


## Android Back: the confirm's ✕ while it is up, else ‹. The room handles it either way (AppRouter: locked).
func is_back_navigation_locked() -> bool:
	if _committing:
		return true
	if is_instance_valid(leave_confirm) and not leave_confirm.closing:
		_close_confirm()
		return true
	if has_changes():
		_ask_before_leaving()
		return true
	return false


func _ask_before_leaving() -> void:
	if is_instance_valid(leave_confirm) and not leave_confirm.closing: return
	leave_confirm = LeaveConfirm.new()
	leave_confirm.theme = UiKit.theme()
	$UI/Root.add_child(leave_confirm)
	leave_confirm.save.connect(func():
		_close_confirm()
		_on_done())
	leave_confirm.discard.connect(func():
		_close_confirm()
		AppRouter.pop_instance())
	leave_confirm.stay.connect(_close_confirm)
	leave_confirm.open()


func _close_confirm() -> void:
	if is_instance_valid(leave_confirm): leave_confirm.close()
	leave_confirm = null


func _on_restore() -> void:
	if _committing:
		return
	_hide_feedback()
	rig.apply_config(Avatar.slot_table.default_config())
	parts_panel.refresh()
	_refresh_completion_state()


func _on_done() -> void:
	if _committing or rig == null:
		return
	_committing = true
	_refresh_completion_state()
	# Guard the race in code as well: a test or a key may fire before the button is disabled; wait for the assembly.
	while rig.is_busy():
		await rig.busy_changed
		if not is_inside_tree() or not is_instance_valid(rig):
			return
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(rig):
		return
	var error := Avatar.save_outfit(rig.current_config())
	if error != OK:
		_committing = false
		push_warning("DressingRoom: save failed with error %d" % error)
		_show_feedback(L10n.text("Couldn't save. Try again."), UiBarToast.Kind.ERROR)
		_shake(done_button)
		_refresh_completion_state()
		return
	AppRouter.pop_instance()


func _refresh_completion_state() -> void:
	if rig == null:
		return
	var busy := rig.is_busy()
	done_button.disabled = _committing or busy
	back_button.disabled = _committing
	restore_button.disabled = _committing
	parts_panel.set_interaction_enabled(not _committing)
	# Busy (loading, trying a part on, saving): three dots at the same width (②-B).
	done_button.text = BUSY_TEXT if _committing or busy else L10n.text("Done")


## A toast under the top bar; one already up stays and the new one goes under it.
func _show_feedback(message: String, kind := UiBarToast.Kind.ERROR) -> UiBarToast:
	var top := _safe_margins.y + UiTokens.SIZE_SCREEN_SAFE_INSET + UiTokens.SIZE_TOUCH_MIN + TOAST_GAP
	for t in toast_layer.get_children():
		if t is UiBarToast and not t.has_meta(&"_leaving"):
			top = maxf(top, (t as UiBarToast).rest_y() + t.size.y + UiTokens.SPACE_S4)
	var toast := UiBarToast.new(message, kind)
	return toast.pop(toast_layer, top, TOAST_HOLD_S)


func feedback_toasts() -> Array:
	return toast_layer.get_children().filter(func(t): return t is UiBarToast and not t.has_meta(&"_leaving"))


func _hide_feedback() -> void:
	for t in feedback_toasts(): (t as UiBarToast).dismiss()


## M-02: ±4 along x three times over 200 (linear).
func _shake(c: Control) -> void:
	if UiMotion.reduced or not c.is_inside_tree(): return
	var rest := c.position.x
	var tw := UiMotion.tween(c, UiTokens.MOTION_EASING_LINEAR)
	var step := UiMotion.secs(UiTokens.MOTION_DURATION_BASE_MS) / 6.0
	for i in 3:
		tw.tween_property(c, "position:x", rest + SHAKE_PX, step)
		tw.tween_property(c, "position:x", rest - SHAKE_PX, step)
	tw.tween_property(c, "position:x", rest, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	# The press's start and the distance travelled tell a tap on the figure (framing) from a drag (turning): a release
	# within TAP_SLOP is a tap. Touch and mouse both: phones send ScreenTouch/ScreenDrag, desktop MouseButton/Motion.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_on_press_changed(event.pressed, event.position)
	elif event is InputEventScreenTouch:
		_on_press_changed(event.pressed, event.position)
	elif event is InputEventMouseMotion and _dragging:
		_track_drag(event.relative)
	elif event is InputEventScreenDrag:
		_track_drag(event.relative)


func _on_press_changed(pressed: bool, _at: Vector2) -> void:
	if pressed:
		_dragging = true
		_drag_distance = 0.0
		return
	var was_tap := _dragging and _drag_distance <= TAP_SLOP
	_dragging = false
	if was_tap:
		_toggle_focus()


## The path's length, not the straight distance: turning out and back again ends where it began, but it was a drag.
func _track_drag(relative: Vector2) -> void:
	anchor.rotate_y(-relative.x * 0.01)
	_drag_distance += relative.length()


func sheet_height() -> float:
	var vh := get_viewport().get_visible_rect().size.y
	return clampf(vh * SHEET_RATIO, SHEET_MIN, SHEET_MAX)


func _place_drawer() -> void:
	if drawer == null: return
	var h := sheet_height() + _safe_margins.w
	drawer.offset_top = -h
	drawer.offset_bottom = 0.0
	drawer.offset_left = 0.0
	drawer.offset_right = 0.0


func _reframe(animate := false) -> void:
	var compact := get_viewport().get_visible_rect().size.y < 720.0
	parts_panel.set_compact(compact)
	_place_drawer()
	# Requests in one frame are merged into the next; if any asks for a tween, it tweens (a slot switch and the safe
	# area's callback may land in the same frame, and a hard cut would eat the push-in).
	_reframe_animated = _reframe_animated or animate
	if _reframe_queued:
		return
	_reframe_queued = true
	await get_tree().process_frame
	_reframe_queued = false
	var animated := _reframe_animated
	_reframe_animated = false
	if not is_instance_valid(rig) or not is_instance_valid(cam):
		return
	# Canvas background stays fixed when category focus moves the 3D camera.
	room_background.size = get_viewport().get_visible_rect().size
	var header_bottom := _safe_margins.y + UiTokens.SIZE_SCREEN_SAFE_INSET + UiTokens.SIZE_TOUCH_MIN + 8.0
	cam.safe_margin_top = header_bottom
	cam.safe_margin_bottom = 0.0
	cam.drawer_height = sheet_height() + _safe_margins.w
	cam.reframe(rig, get_viewport().get_visible_rect().size, animated)
