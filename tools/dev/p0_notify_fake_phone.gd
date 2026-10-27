extends RefCounted
## Review shots only (P0_SHOT steps notify:<state>, SGODOT-350): GodotNotify's stand-in on a desktop, which has none.
## never — Android 13+, never asked; allowed — the system allows; refused — said no in the system dialog; old — Android 12.

signal permission(granted: bool)
var s := {"sdk": 34, "needs_grant": true, "allowed": false, "asked": false, "app": "P0 Demo"}

func _init(state := "never") -> void:
	match state:
		"allowed": s.allowed = true
		"refused": s.asked = true
		"old": s = {"sdk": 31, "needs_grant": false, "allowed": true, "asked": false, "app": "P0 Demo"}

func state() -> String: return JSON.stringify(s)
func request_permission() -> void:
	s.asked = true
	s.allowed = true
	permission.emit(true)
func open_settings() -> void: pass
func schedule(_at: float, _t: String, _b: String, _ch: String) -> void: pass
func cancel_all() -> void: pass
