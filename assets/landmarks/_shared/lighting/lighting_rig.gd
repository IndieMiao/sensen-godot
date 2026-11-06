@tool
extends Node3D
## Assign a different .tres to change the entire lighting setup once.
## No _process, tween, additional light or per-frame resource allocation.

const LightingPreset = preload("res://assets/landmarks/_shared/lighting/lighting_preset.gd")

@export var preset: Resource = preload("res://assets/landmarks/_shared/lighting/warm_noon.tres"):
	set(value):
		if value != null and value.get_script() != LightingPreset:
			push_warning("Lighting rig requires a resource using lighting_preset.gd; keeping the current preset.")
			return
		preset = value
		if is_node_ready():
			apply_preset()


func _ready() -> void:
	apply_preset()


func apply_preset() -> void:
	var lighting_preset := preset as LightingPreset
	if lighting_preset != null:
		lighting_preset.apply_to($Environment, $Sun)
