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
var phase: CommandLifecycle.State = CommandLifecycle.State.IDLE: set = set_phase

var _lifecycle: CommandLifecycle
var _key := ""

func _init(text_: String = "", kind_: Kind = Kind.PRIMARY, compact_ := false) -> void:
	focus_mode = Control.FOCUS_NONE
	label = text_
	kind = kind_
	compact = compact_
	pressed.connect(_on_pressed)
	_apply()

func set_kind(v: Kind) -> void: kind = v; _apply()
func set_compact(v: bool) -> void: compact = v; _apply()
func set_label(v: String) -> void: label = v; _apply()
func set_reason(v: String) -> void: reason = v; _apply()
func set_phase(v: CommandLifecycle.State) -> void: phase = v; _apply()

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
	if is_busy(): return
	if is_unavailable(): unavailable_pressed.emit(reason)
	else: activated.emit()

func _apply() -> void:
	var i := 1 if compact else 0
	if is_unavailable():
		theme_type_variation = UiTokens.BUTTON_CMD_BLOCKED_COMPACT if compact else UiTokens.BUTTON_CMD_BLOCKED
		text = reason
	else:
		theme_type_variation = _VARIATIONS[kind][i]
		text = label
	if compact:
		custom_minimum_size = Vector2.ZERO
		UiKit.ensure_hit_area(self)
	else:
		custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH, UiTokens.SIZE_COMMAND)
	modulate.a = UiTokens.OPACITY_PENDING if phase == CommandLifecycle.State.PENDING else 1.0
