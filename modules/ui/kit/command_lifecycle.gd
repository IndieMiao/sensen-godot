class_name CommandLifecycle
extends Node
## Button-side command state (SGODOT-211, WP7-B F-08 §1). A keyed command is SUBMITTING the moment it is
## sent (the button locks and ignores repeats), turns PENDING when no result arrives within
## MOTION_PENDING_DELAY_MS (show the loading look), and returns to IDLE when it settles. Fast replies
## never flash the loading look. Connect a P0Session with watch(), or drive start()/settle() directly.

signal changed(key: String, state: State)

enum State { IDLE, SUBMITTING, PENDING }

var _started := {}   # key -> ms
var _state := {}     # key -> State

func watch(session: Node) -> void:
	session.command_started.connect(func(key: String): start(key))
	session.command_settled.connect(func(key: String, _ok: bool, _code: String): settle(key))

func state(key: String) -> State: return _state.get(key, State.IDLE)

func start(key: String, now_ms := Time.get_ticks_msec()) -> void:
	_started[key] = now_ms
	_assign(key, State.SUBMITTING)

func settle(key: String) -> void:
	_started.erase(key)
	_assign(key, State.IDLE)

func tick(now_ms: int) -> void:
	for key in _started.keys():
		if _state.get(key) == State.SUBMITTING and now_ms - int(_started[key]) >= UiTokens.MOTION_PENDING_DELAY_MS:
			_assign(key, State.PENDING)

func _process(_dt: float) -> void: tick(Time.get_ticks_msec())

func _assign(key: String, s: State) -> void:
	if _state.get(key, State.IDLE) == s: return
	if s == State.IDLE: _state.erase(key)
	else: _state[key] = s
	changed.emit(key, s)
