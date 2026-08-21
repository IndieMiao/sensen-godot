class_name RigActivity
extends Node
## 角色活动度三档控制：按屏幕可见性+相机距离节流动画/粒子。
## 挂在 AvatarRig 下；rig 上所有 AnimationPlayer/GPUParticles3D 的播放权归本节点。

enum Level { ACTIVE, REDUCED, SLEEP }

@export var reduced_distance := 8.0
@export var sleep_distance := 16.0
@export var check_interval := 0.25

signal level_changed(level: int)

var current_level: int = Level.ACTIVE
var _accum := 0.0
var _notifier: VisibleOnScreenNotifier3D

func _ready() -> void:
	var rig := get_parent() as Node3D
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))
	rig.add_child.call_deferred(_notifier)

func _process(delta: float) -> void:
	_accum += delta
	if _accum < check_interval:
		return
	_accum = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rig := get_parent() as Node3D
	var dist := cam.global_position.distance_to(rig.global_position)
	var visible_on_screen := _notifier.is_on_screen() if _notifier and _notifier.is_inside_tree() else true
	var lv := level_for(dist, visible_on_screen)
	if lv != current_level:
		apply_level(lv)

func level_for(distance: float, on_screen: bool) -> int:
	if not on_screen or distance > sleep_distance:
		return Level.SLEEP
	if distance > reduced_distance:
		return Level.REDUCED
	return Level.ACTIVE

func apply_level(level: int) -> void:
	current_level = level
	var rig := get_parent()
	var main_player := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if main_player:
		main_player.playback_active = (level != Level.SLEEP)
	_apply_recursive(rig, level)
	level_changed.emit(level)

func _apply_recursive(node: Node, level: int) -> void:
	for c in node.get_children():
		if c == self:
			continue
		if c is AnimationPlayer and c.get_parent() != get_parent():
			# socket 部件内的 T1 动画：仅 ACTIVE 时播放
			(c as AnimationPlayer).playback_active = (level == Level.ACTIVE)
			if level == Level.ACTIVE and not (c as AnimationPlayer).is_playing():
				var list := (c as AnimationPlayer).get_animation_list()
				if list.size() > 0:
					(c as AnimationPlayer).play(list[0])
		elif c is GPUParticles3D:
			(c as GPUParticles3D).emitting = (level == Level.ACTIVE)
		_apply_recursive(c, level)
