class_name AvatarPartDef
extends Resource

@export var id: String = ""
@export var slot: StringName = &""
@export var attach: String = "mesh"  # "mesh" | "socket"
@export var tier: int = 0
@export var mesh: Mesh               # attach == "mesh"
@export var skin: Skin               # attach == "mesh"（可为 null：无骨骼的测试网格）
@export var scene: PackedScene       # attach == "socket"
@export var offset_pos: Vector3 = Vector3.ZERO
@export var offset_rot_deg: Vector3 = Vector3.ZERO
@export var offset_scale: Vector3 = Vector3.ONE
