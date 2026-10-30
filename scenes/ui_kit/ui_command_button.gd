class_name UiCommandButton
extends Button
## Command button (SGODOT-212): CommandButton 483:216 (48 high) and Compact/Command 633:41273 (34 drawn in a
## 44 hit area). Connect `activated`, not `pressed`:
## - Unavailable (LOCK-10): set `reason`, e.g. "Need 6 more Timber". The button shows the reason in the
##   neutral CmdBlocked look and stays tappable; a tap emits `unavailable_pressed(reason)` so the caller can
##   show a short toast. Never a bare verb, never a separate explanation line.
## - In flight (WP7-B F-08): SUBMITTING ignores repeat taps with no visual change; PENDING (no reply after
##   MOTION_PENDING_DELAY_MS) also dims the button, keeping its label. track() follows a CommandLifecycle key.
## - Truly inert controls (e.g. offline) use Button.disabled with the reason as the label.
## - Offline (§10.7.1 SYS-OFFLINE): a button that sends a server command (`sends`) reads `Offline` in the CmdBlocked
##   look and does nothing while `UiCommandButton.offline` is up; its drawer stays open, nothing else changes. One
##   already unavailable keeps its reason.
##   Buttons that only open or browse (Free to do now, Gift, Trade, Pin) leave `sends` off and keep working.

signal activated
signal unavailable_pressed(reason: String)

enum Kind { PRIMARY, SECONDARY, DESTRUCTIVE, DANGER_SECONDARY }

const _VARIATIONS := {
	Kind.PRIMARY: [UiTokens.BUTTON_CMD_PRIMARY, UiTokens.BUTTON_CMD_PRIMARY_COMPACT],
	Kind.SECONDARY: [UiTokens.BUTTON_CMD_SECONDARY, UiTokens.BUTTON_CMD_SECONDARY_COMPACT],
	Kind.DESTRUCTIVE: [UiTokens.BUTTON_CMD_DESTRUCTIVE, UiTokens.BUTTON_CMD_DESTRUCTIVE_COMPACT],
	Kind.DANGER_SECONDARY: [UiTokens.BUTTON_CMD_DANGER_SECONDARY, UiTokens.BUTTON_CMD_DANGER_SECONDARY_COMPACT],
}

var kind: Kind = Kind.PRIMARY: set = set_kind
var compact := false: set = set_compact
## The command verb, e.g. "Craft" or "Buy · 4 coins" (English, from the caller: LOCK-23).
var label := "": set = set_label
## Non-empty = unavailable; this text replaces the label on the button (LOCK-10).
var reason := "": set = set_reason
## The reason is shown right next to the key (the placement bar's caption over a three-key row, too narrow for
## `Outside your yard`; 不知火舞 on 241 fcbd30a7): unavailable keeps the verb in the blocked look, a tap still says why.
var reason_beside := false: set = set_reason_beside
var phase: CommandLifecycle.State = CommandLifecycle.State.IDLE: set = set_phase
## Full-width rows with a long reason (ResidentDialogue Choices=Stacked): the label may use the side padding,
## as the main draws it (a 200 px reason in a 208 button on NPC-5).
var fit_text := false: set = set_fit_text
## The caller's width (a board row's 152, a shop row's 76): kept through every redraw — a label change, PENDING and
## back, Offline on and off — instead of being set on custom_minimum_size, which each redraw resets (亚瑟 on #84).
var min_width := 0.0: set = set_min_width
## The visible key drawn narrower than its touch area, this far in from each side (Compact/Shop action: a 68 × 34 key in
## its 76 × 44 touch area, q(151)); 0 draws the whole width. Kept through every state, as fit_text is.
var visual_inset_x := 0.0: set = set_visual_inset_x

## Kind=need-energy (SGODOT-266, Figma CommandButton): with a reason, an Energy shortfall on a priced action — the
## action with its gap (`Fly · Need 30 Energy`) in the warning tint and a warning label, not the grey; still tappable
## (unavailable_pressed: the caller opens the Energy card). Other gaps stay grey.
var need_energy := false: set = set_need_energy

## Sends a server command when activated: greys to `Offline` while offline, and the command it sends is tracked
## (P0Ui.track_pressed: SUBMITTING / PENDING, F-08).
var sends := false: set = set_sends

const OFFLINE_TEXT := "Offline"
const GROUP := &"ui_command_button"
## Every command button in the tree reads it; set it with set_offline() so the ones on screen redraw.
static var offline := false
## The sending button activated last and the frame it was pressed in: the command it sends in reply is its own.
static var _pressed: WeakRef = null
static var _pressed_frame := -1

var _lifecycle: CommandLifecycle
var _key := ""

func _init(text_: String = "", kind_: Kind = Kind.PRIMARY, compact_ := false) -> void:
	focus_mode = Control.FOCUS_NONE
	label = text_
	kind = kind_
	compact = compact_
	pressed.connect(_on_pressed)
	add_to_group(GROUP)
	_apply()

func set_kind(v: Kind) -> void: kind = v; _apply()
func set_compact(v: bool) -> void: compact = v; _apply()
func set_label(v: String) -> void: label = v; _apply()
func set_reason(v: String) -> void: reason = v; _apply()
func set_reason_beside(v: bool) -> void: reason_beside = v; _apply()
func set_phase(v: CommandLifecycle.State) -> void: phase = v; _apply()
func set_fit_text(v: bool) -> void: fit_text = v; _fit()
func set_sends(v: bool) -> void: sends = v; _apply()
func set_min_width(v: float) -> void: min_width = v; _apply()
func set_visual_inset_x(v: float) -> void: visual_inset_x = v; _fit()
func set_need_energy(v: bool) -> void:
	need_energy = v
	_apply()
	_fit()

## Offline on or off for every command button on screen (and the ones built while it lasts).
static func set_offline(tree: SceneTree, v: bool) -> void:
	offline = v
	if tree: tree.call_group(GROUP, &"_apply")

## The sending button pressed in this frame, if any (once: a second call returns null).
static func take_pressed() -> UiCommandButton:
	if _pressed == null or _pressed_frame != Engine.get_process_frames(): return null
	var b := _pressed.get_ref() as UiCommandButton
	_pressed = null
	return b

## An unavailable button keeps its reason offline: it is grey and inert already.
func is_offline() -> bool: return sends and offline and not is_unavailable()

const _FIT_PAD := 4.0
const _STYLES: Array[StringName] = [&"normal", &"hover", &"pressed", &"disabled", &"focus", &"hover_pressed"]
var _fitting := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and not _fitting: _fit()

## Narrow side padding and the visible key's side inset on top of whatever variation is current (re-run when the
## variation changes).
const _INKS: Array[StringName] = [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]

func _fit() -> void:
	_fitting = true
	for st in _STYLES: remove_theme_stylebox_override(st)
	for c in _INKS: remove_theme_color_override(c)
	var amber := need_energy and is_unavailable() and not is_offline()
	if fit_text or visual_inset_x > 0.0 or amber:
		for st in _STYLES:
			var sb := get_theme_stylebox(st)
			if sb == null: continue
			var t := sb.duplicate() as StyleBox
			if fit_text:
				t.content_margin_left = minf(t.content_margin_left, _FIT_PAD)
				t.content_margin_right = minf(t.content_margin_right, _FIT_PAD)
			if visual_inset_x > 0.0 and t is UiStyleBox:
				var u := t as UiStyleBox
				u.inset = Vector4(visual_inset_x, u.inset.y, visual_inset_x, u.inset.w)
			if amber and t is UiStyleBox:   # Kind=need-energy over whatever fit and inset the button has (周瑜 on #569)
				(t as UiStyleBox).bg_color = UiTokens.COLOR_WARNING_TINT
				(t as UiStyleBox).border_width = 0.0
			elif amber and t is StyleBoxFlat:
				(t as StyleBoxFlat).bg_color = UiTokens.COLOR_WARNING_TINT
				(t as StyleBoxFlat).set_border_width_all(0)
			add_theme_stylebox_override(st, t)
	if amber:
		for c in _INKS: add_theme_color_override(c, UiTokens.COLOR_WARNING)
	_fitting = false

func is_unavailable() -> bool: return reason != ""
func is_busy() -> bool: return phase != CommandLifecycle.State.IDLE

## Follow one command key of a CommandLifecycle (P0Session.command_started / command_settled).
func track(lifecycle: CommandLifecycle, key: String) -> void:
	if _lifecycle != null and _lifecycle.changed.is_connected(_on_lifecycle): _lifecycle.changed.disconnect(_on_lifecycle)
	_lifecycle = lifecycle
	_key = key
	lifecycle.changed.connect(_on_lifecycle)
	phase = lifecycle.state(key)

func _on_lifecycle(key: String, s: CommandLifecycle.State) -> void:
	if key == _key: phase = s

func _on_pressed() -> void:
	if is_busy() or is_offline(): return
	if is_unavailable():
		unavailable_pressed.emit(reason)
		return
	if sends:
		_pressed = weakref(self)
		_pressed_frame = Engine.get_process_frames()
	activated.emit()

func _apply() -> void:
	var i := 1 if compact else 0
	if sends: disabled = is_offline()   # only ours: a caller may disable a plain one itself
	if is_offline() or is_unavailable():
		var amber := need_energy and not is_offline()   # its box from the primary's, tinted in _fit
		theme_type_variation = _VARIATIONS[kind][i] if amber else UiTokens.BUTTON_CMD_BLOCKED_COMPACT if compact else UiTokens.BUTTON_CMD_BLOCKED
		text = OFFLINE_TEXT if is_offline() else (label if reason_beside else reason)
	else:
		theme_type_variation = _VARIATIONS[kind][i]
		text = label
	if compact:
		custom_minimum_size = Vector2(min_width, 0.0)
		UiKit.ensure_hit_area(self)
	else:
		custom_minimum_size = Vector2(maxf(UiTokens.SIZE_TOUCH, min_width), UiTokens.SIZE_COMMAND)
	modulate.a = UiTokens.OPACITY_PENDING if phase == CommandLifecycle.State.PENDING else 1.0
	if fit_text or visual_inset_x > 0.0: _fit()
