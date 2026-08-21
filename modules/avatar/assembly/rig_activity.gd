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
var _applied_once := false
var _notifier: VisibleOnScreenNotifier3D

func _ready() -> void:
	var rig := get_parent() as Node3D
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))
	rig.add_child.call_deferred(_notifier)
	# 装配（换装/初次加载）可能在本节点 _ready 之后才把新部件挂上树，
	# 需要在装配变化后重新按当前档位应用一次，否则新挂件永远不会启动。
	if rig and rig.has_signal("slot_applied"):
		rig.slot_applied.connect(func(_s, _p): apply_level(current_level))
	if rig and rig.has_signal("config_applied"):
		rig.config_applied.connect(func(_c): apply_level(current_level))

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
	# 稳态 ACTIVE（默认档位从未变化）也必须至少应用一次，否则新装配的
	# T1 socket 动画/T2 粒子永远不会被启动播放。
	if lv != current_level or not _applied_once:
		apply_level(lv)

func level_for(distance: float, on_screen: bool) -> int:
	if not on_screen or distance > sleep_distance:
		return Level.SLEEP
	if distance > reduced_distance:
		return Level.REDUCED
	return Level.ACTIVE

func apply_level(level: int) -> void:
	_applied_once = true
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
