extends Node3D

@onready var anchor: Node3D = $RigAnchor
@onready var parts_panel = $UI/Panel/VBox
var rig: AvatarRig
var _dragging := false

func _ready() -> void:
	rig = Avatar.create_rig()
	anchor.add_child(rig)
	rig.config_applied.connect(func(_c): var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer; if ap: ap.play("idle"))
	rig.apply_config(Avatar.load_outfit())
	$UI/Panel/VBox/Buttons/SaveButton.pressed.connect(_on_save)
	$UI/Panel/VBox/Buttons/ResetButton.pressed.connect(_on_reset)
	$UI/Panel/VBox/Buttons/SceneButton.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/stress_test/stress_test.tscn"))
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
