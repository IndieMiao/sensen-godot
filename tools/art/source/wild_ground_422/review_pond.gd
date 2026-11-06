extends "res://scenes/p0/p0_pond.gd"
## Offline fixture: use the real scene/camera/avatar/UI without sending game commands.
func _go_online(_session: P0Session) -> void: pass
func _arrival_hint() -> void: pass
