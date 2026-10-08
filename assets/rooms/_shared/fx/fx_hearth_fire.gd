@tool
extends Node3D
## Configure before add_child. Defaults also fit Basic Room's <=20 particle budget.
const Style = preload("res://assets/rooms/_shared/fx/particle_style.gd")
@export var emission_box := Vector3(.32, .015, .065)
@export_range(1, 24, 1) var flame_count: int = 16
@export_range(0, 6, 1) var spark_count: int = 4
@export_range(.1, 2.0) var flame_height: float = .68
@export_range(.5, .9) var flame_lifetime: float = .72
@export_range(0.0, 8.0) var light_energy: float = 3.1
@export_range(0.0, 4.0) var glow_boost: float = 1.0
@export_range(0.0, .10) var flicker_strength: float = .08
@export var light_path: NodePath
@export var light_range: float = 4.25
@export var light_color := Color("ff8b36")
var light: OmniLight3D
var _phase := 0.0
var _base_light_energy := 0.0

func _ready() -> void:
 var h := maxf(flame_height, .1)
 var box := emission_box.abs()
 var bounds := AABB(Vector3(-box.x-h*.3, -h*.60, -box.z-h*.3), Vector3(box.x*2+h*.6, h*1.72, box.z*2+h*.6))
 var flames := Style.particles("Flames", clampi(flame_count,1,24), flame_lifetime, bounds)
 var process := ParticleProcessMaterial.new()
 process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
 process.emission_box_extents = box
 process.direction = Vector3.UP
 process.spread = 0.0
 process.gravity = Vector3.ZERO
 process.initial_velocity_min = h*.18/flame_lifetime
 process.initial_velocity_max = h*.30/flame_lifetime
 process.scale_min = .90
 process.scale_max = 1.05
 process.scale_curve = Style.curve([Vector2(0,.75),Vector2(.18,1.0),Vector2(.65,.6),Vector2(1,.06)])
 process.color_ramp = Style.ramp(PackedColorArray([Color(1,1,1,0),Color(1,1,1,.94),Color(1,.72,.52,.88),Color(1,.45,.2,0)]),PackedFloat32Array([0,.08,.60,1]))
 process.anim_offset_min = 0.0
 process.anim_offset_max = 1.0
 process.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
 flames.process_material = process
 flames.draw_pass_1 = Style.sprite(preload("res://assets/rooms/_shared/fx/flame_strip.png"),Vector2(h*.40,h*.95),4,true)
 flames.position.y = h*.34 + box.y
 add_child(flames)
 if spark_count > 0:
  var sparks := Style.particles("Sparks",clampi(spark_count,0,6),.55,bounds)
  var motion := ParticleProcessMaterial.new()
  motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
  motion.emission_box_extents = Vector3(box.x*.70,0,box.z*.5)
  motion.direction = Vector3.UP
  motion.spread = 4.0
  motion.gravity = Vector3.ZERO
  motion.initial_velocity_min = h*.72
  motion.initial_velocity_max = h*1.05
  motion.scale_curve = Style.curve([Vector2(0,.35),Vector2(.12,1),Vector2(1,0)])
  motion.color_ramp = Style.ramp(PackedColorArray([Color(1,.75,.34,0),Color(1,.75,.34,1),Color(1,.22,.04,0)]),PackedFloat32Array([0,.14,1]))
  motion.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
  sparks.process_material = motion
  sparks.draw_pass_1 = Style.sprite(preload("res://assets/rooms/_shared/fx/spark.png"),Vector2(.022,.034),1,true)
  sparks.position.y = h*.12
  add_child(sparks)
 if not light_path.is_empty(): light = get_node_or_null(light_path) as OmniLight3D
 if light == null:
  light = OmniLight3D.new()
  light.name = "HearthGlow"
  light.position.y = h*.5
  light.light_color = light_color
  light.omni_range = light_range
  light.shadow_enabled = false
  add_child(light)
 light.light_energy = light_energy
 _base_light_energy = light_energy

func _process(delta: float) -> void:
 if not is_instance_valid(light): return
 _phase += delta
 # Smooth, deterministic low frequencies; convex sum stays within +/- strength.
 var wave := .55*sin(_phase*2.13)+.30*sin(_phase*3.71+.9)+.15*sin(_phase*5.03+2.0)
 light.light_energy = _base_light_energy*glow_boost*(1.0+clampf(flicker_strength,0,.1)*wave)
