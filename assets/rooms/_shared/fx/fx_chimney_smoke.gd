@tool
extends Node3D
const Style = preload("res://assets/rooms/_shared/fx/particle_style.gd")
@export_range(12,20,1) var smoke_count: int = 16
@export_range(3.0,4.0) var lifetime: float = 3.5
@export var drift := Vector3(.19,.44,-.015)
@export var emission_box := Vector3(.055,.01,.035)
@export_range(.1,.6) var start_size: float = .30
@export_range(.6,1.5) var end_size: float = 1.15

func _ready() -> void:
 var box := emission_box.abs()
 var travel := drift*lifetime*1.05
 var radius := end_size*.65
 var minimum := Vector3(minf(0,travel.x),minf(0,travel.y),minf(0,travel.z))-box-Vector3.ONE*radius
 var maximum := Vector3(maxf(0,travel.x),maxf(0,travel.y),maxf(0,travel.z))+box+Vector3.ONE*radius
 var smoke := Style.particles("Smoke",clampi(smoke_count,12,20),lifetime,AABB(minimum,maximum-minimum))
 smoke.seed = 236
 var process := ParticleProcessMaterial.new()
 process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
 process.emission_box_extents = box
 process.direction = drift.normalized() if drift.length() > .001 else Vector3.UP
 process.spread = 0.0
 process.gravity = Vector3.ZERO
 process.initial_velocity_min = drift.length()*.95
 process.initial_velocity_max = drift.length()*1.05
 process.scale_curve = Style.curve([Vector2(0,start_size),Vector2(.55,end_size*.70),Vector2(1,end_size)])
 process.angle_min = -9
 process.angle_max = 9
 process.anim_offset_min = 0.0
 process.anim_offset_max = 1.0
 process.color_ramp = Style.ramp(PackedColorArray([Color(.80,.82,.83,0),Color(.84,.86,.87,.8),Color(.97,.97,.96,.64),Color(1,1,1,0)]),PackedFloat32Array([0,.06,.65,1]))
 process.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
 smoke.process_material = process
 smoke.draw_pass_1 = Style.sprite(preload("res://assets/rooms/_shared/fx/smoke_strip.png"),Vector2.ONE,4,false)
 add_child(smoke)
