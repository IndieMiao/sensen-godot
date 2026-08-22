extends Node3D

@onready var anchor: Node3D = $RigAnchor
@onready var parts_panel = $UI/SafeArea/VBox/Drawer/VBox
@onready var cam: DressingCamera = $Camera3D
@onready var safe_area: SafeAreaMargin = $UI/SafeArea
@onready var drawer: PanelContainer = $UI/SafeArea/VBox/Drawer
var rig: AvatarRig
var _dragging := false

func _ready() -> void:
	rig = Avatar.create_rig()
	anchor.add_child(rig)
	rig.config_applied.connect(func(_c): var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer; if ap: ap.play("idle"))
	rig.config_applied.connect(func(_c): _reframe())
	rig.apply_config(Avatar.load_outfit())
	$UI/SafeArea/VBox/Drawer/VBox/Buttons/SaveButton.pressed.connect(_on_save)
	$UI/SafeArea/VBox/Drawer/VBox/Buttons/ResetButton.pressed.connect(_on_reset)
	$UI/SafeArea/VBox/Drawer/VBox/Buttons/SceneButton.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/stress_test/stress_test.tscn"))
	safe_area.margins_applied.connect(func(m: Vector4):
		cam.safe_margin_top = m.y
		cam.safe_margin_bottom = m.w
		_reframe())
	# Godot 中子节点 _ready() 先于父节点执行，SafeArea 的首发 margins_applied
	# 在此之前就已发出（本仓库 6fd571a 踩过同类时序坑）。这里主动补一次 refresh，
	# 让相机拿到真实安全区，而不是停在默认的 16。
	safe_area.refresh()
	parts_panel.setup(rig)

func _on_save() -> void:
	var err := Avatar.save_outfit(rig.current_config())
	print("保存结果: %d" % err)

func _on_reset() -> void:
	rig.apply_config(Avatar.slot_table.default_config())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		anchor.rotate_y(-event.relative.x * 0.01)
	elif event is InputEventScreenDrag:
		anchor.rotate_y(-event.relative.x * 0.01)

func _reframe() -> void:
	# 等一帧让装配后的网格与骨骼姿态落定，否则包围盒可能仍是上一套部件的
	await get_tree().process_frame
	if not is_instance_valid(rig) or not is_instance_valid(cam):
		return
	var h := drawer.size.y if drawer.size.y > 0.0 else drawer.custom_minimum_size.y
	cam.drawer_height = h
	cam.reframe(rig, get_viewport().get_visible_rect().size)
