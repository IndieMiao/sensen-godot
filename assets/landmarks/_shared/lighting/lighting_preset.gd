@tool
extends Resource
## Environment and one sun. Applying a preset never changes host shadow settings.

@export var environment: Environment
@export var sun_color: Color = Color(1.0, 0.965, 0.88)
@export_range(0.0, 4.0, 0.01) var sun_energy: float = 0.98
@export var sun_rotation_degrees: Vector3 = Vector3(-56.0, -34.0, 0.0)


func apply_to(world_environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if environment == null or world_environment == null or sun == null:
		push_error("Lighting preset requires an Environment, WorldEnvironment and DirectionalLight3D.")
		return
	# Isolate host edits from the reusable .tres and from other instances.
	world_environment.environment = environment.duplicate(true)
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.rotation_degrees = sun_rotation_degrees
