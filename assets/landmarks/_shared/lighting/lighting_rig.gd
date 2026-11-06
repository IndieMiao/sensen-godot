@tool
extends Node3D
## Assign a different .tres to change the entire lighting setup once.
## No _process, tween, additional light or per-frame resource allocation.

@export var preset: LandmarkLightingPreset = preload("res://assets/landmarks/_shared/lighting/warm_noon.tres"):
	set(value):
		preset = value
		if is_node_ready():
			apply_preset()


func _ready() -> void:
	apply_preset()


func apply_preset() -> void:
	if preset != null:
		preset.apply_to($Environment, $Sun)
