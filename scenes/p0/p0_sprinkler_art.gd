extends Node3D
## SGODOT-244 v1.3: keep both GLB meshes and the authored head pivot; only a confirmed watering or tap animates it.

const FarmArt = preload("res://modules/farm/farm_art.gd")
const MODEL := "res://assets/farm/art/sprinkler.glb"
const SPIN_SECONDS := 2.5
const TURN_PER_SECOND := TAU / SPIN_SECONDS

var head: Node3D
var spray_origin: Node3D
var remaining := 0.0
var _drops: CPUParticles3D

func _init() -> void:
	name = "Sprinkler"
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(model)
	head = model.find_child("head", true, false) as Node3D
	spray_origin = model.find_child("spray_origin", true, false) as Node3D
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = FarmArt.material()
	set_process(false)

func _ready() -> void:
	set_process(remaining > 0.0)

func play() -> void:
	remaining = SPIN_SECONDS
	if _drops == null:
		_drops = CPUParticles3D.new()
		_drops.name = "WaterDrops"
		_drops.emitting = false
		_drops.amount = 12
		_drops.lifetime = 0.35
		_drops.local_coords = false
		_drops.direction = Vector3.UP
		_drops.spread = 80.0
		_drops.initial_velocity_min = 0.6
		_drops.initial_velocity_max = 1.0
		_drops.gravity = Vector3(0, -3.0, 0)
		_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_drops.emission_sphere_radius = 0.16
		var mesh := SphereMesh.new()
		mesh.radius = 0.018
		mesh.height = 0.045
		mesh.radial_segments = 6
		mesh.rings = 3
		_drops.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.55, 0.78, 0.95)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_drops.material_override = material
		_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_drops)
		_drops.position = to_local(spray_origin.global_position)
	_drops.emitting = true
	set_process(true)

func _process(dt: float) -> void:
	if remaining <= 0.0: return
	var step := minf(maxf(dt, 0.0), remaining)
	head.rotate_y(step * TURN_PER_SECOND)
	remaining = maxf(0.0, remaining - step)
	if remaining == 0.0:
		_drops.emitting = false
		set_process(false)
