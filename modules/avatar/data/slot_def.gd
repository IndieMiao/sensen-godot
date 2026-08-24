class_name AvatarSlotDef
extends Resource

@export var slot_name: StringName = &""
@export var attach_bone: String = ""
@export var required: bool = false
@export var default_part: String = ""

## socket 帧的授权偏移（对应 Unity DT_AvatarBase.prefab 里 AvatarStructureConfig.sockets
## 那一层 *_socket 变换中「超出骨骼轴向归一化」的部分，例如 backpack_socket 的位移）。
## 骨骼轴向归一化本身不存在这里——它由 assembler 按目标骨架的 bone rest 实时推导，
## 因为 Unity 是左手系、Godot 是右手系，那边的四元数不能逐字照搬。
@export var socket_offset_pos: Vector3 = Vector3.ZERO
@export var socket_offset_rot_deg: Vector3 = Vector3.ZERO
