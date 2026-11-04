extends "res://scenes/p0/p0_pond.gd"
## Isolated review only; these overrides are never shipped into p0_pond.gd.
func _go_online(_session: P0Session) -> void:pass
func _arrival_hint() -> void:pass
func _make_trap_float() -> Node3D:
	var marker=load("res://assets/props/fish_trap_marker/fish_trap_marker.glb").instantiate()
	marker.name="FishTrap"
	return marker
