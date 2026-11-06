@tool
extends Resource
## One sun plus optional companion backdrops. No per-frame work or shadow changes.

const FarMaterialSet = preload("res://assets/landmarks/_shared/lighting/far_material_set.gd")

@export var environment: Environment
@export var sea_material: ShaderMaterial
@export var far_materials: Resource
@export var sun_color: Color = Color(1.0, 0.965, 0.88)
@export_range(0.0, 4.0, 0.01) var sun_energy: float = 0.98
@export var sun_rotation_degrees: Vector3 = Vector3(-56.0, -34.0, 0.0)


func apply_to(world_environment: WorldEnvironment, sun: DirectionalLight3D,
		sea_targets: Array[GeometryInstance3D] = [], city_targets: Array[GeometryInstance3D] = [],
		hill_targets: Array[GeometryInstance3D] = [], bridge_targets: Array[GeometryInstance3D] = []) -> void:
	if environment == null or world_environment == null or sun == null:
		push_error("Lighting preset requires an Environment, WorldEnvironment and DirectionalLight3D.")
		return
	# Isolate host edits from the reusable .tres and from other instances.
	world_environment.environment = environment.duplicate(true)
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.rotation_degrees = sun_rotation_degrees
	apply_material(sea_material, sea_targets)
	var palette := far_materials as FarMaterialSet
	if palette != null:
		apply_material(palette.city, city_targets)
		apply_material(palette.hills, hill_targets)
		apply_material(palette.bridge, bridge_targets)


func apply_material(material: ShaderMaterial, targets: Array[GeometryInstance3D]) -> void:
	if material == null or targets.is_empty():
		return
	# Share one host-local copy within each role; preserve original shader/resources.
	var local_material := material.duplicate() as ShaderMaterial
	for target in targets:
		if is_instance_valid(target):
			target.material_override = local_material
