@tool
extends Node3D
const Style = preload("res://assets/rooms/_shared/fx/particle_style.gd")
@export_range(8,10,1) var smoke_count: int = 8
@export_range(3.0,4.0) var lifetime: float = 4.0
@export var drift := Vector3(.28,.72,-.04)
@export var emission_box := Vector3(.055,.01,.035)
@export_range(.1,.6) var start_size: float = .30
@export_range(.6,2.0) var end_size: float = 1.9
@export_range(12.0,15.0) var spread_degrees: float = 15.0
@export var wind_acceleration := Vector3(.18,.04,0)

func _ready() -> void:
 var box := emission_box.abs()
 # Conservative bound includes cone spread, velocity randomness, wind and rotated quads.
 var travel := drift*lifetime*1.12
 var wind := wind_acceleration*lifetime*lifetime*.5
 var margin := emission_box.abs()+Vector3.ONE*(drift.length()*1.12*lifetime*sin(deg_to_rad(spread_degrees))+end_size*1.25*.71)
 var minimum := Vector3(minf(0,travel.x)+minf(0,wind.x),minf(0,travel.y)+minf(0,wind.y),minf(0,travel.z)+minf(0,wind.z))-margin
 var maximum := Vector3(maxf(0,travel.x)+maxf(0,wind.x),maxf(0,travel.y)+maxf(0,wind.y),maxf(0,travel.z)+maxf(0,wind.z))+margin
 var smoke := Style.particles("Smoke",clampi(smoke_count,8,10),lifetime,AABB(minimum,maximum-minimum))
 smoke.seed = 236
 var process := ParticleProcessMaterial.new()
 process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
 process.emission_box_extents = box
 process.direction = drift.normalized() if drift.length() > .001 else Vector3.UP
 process.spread = spread_degrees
 process.gravity = wind_acceleration
 process.initial_velocity_min = drift.length()*.88
 process.initial_velocity_max = drift.length()*1.12
 process.scale_curve = Style.curve([Vector2(0,start_size),Vector2(.55,end_size*.72),Vector2(1,end_size)])
 process.scale_min = .75
 process.scale_max = 1.25
 process.angle_min = -180
 process.angle_max = 180
 process.angular_velocity_min = -8
 process.angular_velocity_max = 8
 process.anim_offset_min = 0.0
 process.anim_offset_max = .999
 process.anim_speed_min = 0.0
 process.anim_speed_max = 0.0
 process.color_ramp = Style.ramp(PackedColorArray([Color(.80,.82,.83,0),Color(.90,.91,.92,.90),Color(.94,.95,.96,.90),Color(.98,.98,.98,.68),Color(1,1,1,0)]),PackedFloat32Array([0,.06,.40,.75,1]))
 process.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
 smoke.process_material = process
 smoke.draw_pass_1 = Style.sprite(preload("res://assets/rooms/_shared/fx/smoke_strip.png"),Vector2.ONE,4,false)
 add_child(smoke)
