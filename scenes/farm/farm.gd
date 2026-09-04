extends Node3D
## 私有农场实例（PRD §3.2 第二层）灰盒：蓝图地表 + 锚点原语 + 自己的 Avatar + 45° 跟随相机。
## 由 AppRouter.push_instance(AppRouter.FARM, {...}) 压在地图之上；退出即 pop。

const WORLD_SCALE := 1.0 # 逻辑米 → 世界米；G1 调观感时只改这里，时长不变量不受影响
const CAM_DIST := 16.0
const CAM_PITCH_DEG := 45.0
const TAP_MAX_PX := 16.0

var bp: FarmBlueprint
var grid: BlueprintGrid
var mover: PlayerMover
var _args := {}
var _rig: AvatarRig
var _anim := ""
var _tap_start := Vector2.ZERO

@onready var cam: Camera3D = $Camera3D
@onready var ground: MeshInstance3D = $Ground
@onready var props: Node3D = $Props
@onready var player: Node3D = $Player
@onready var title: Label = %Title
@onready var exit_btn: Button = %ExitButton
@onready var joystick: TouchStick = $HUD/SafeArea/Root/Joystick

func setup(args: Dictionary) -> void:
	_args = args

func _ready() -> void:
	# 压栈进入的新实例不会经过 AppRouter 的 suspend/resume 协议（那条协议只管
	# "已经在栈里、被别人盖住/揭开"的场景）；自己的相机要不要成为当前相机，
	# 得在第一次入树时自己抢——不抢的话会保留住下层地图冻结的位姿（2026-09-04 终审 C1）。
	cam.make_current()
	bp = _args.get("blueprint")
	if bp == null:
		bp = FarmBlueprint.load_file(FarmBlueprint.asset_path(
			str(_args.get("layout_patch_id", "")), int(_args.get("revision", 1))))
	if bp == null:
		push_error("Farm: 缺少蓝图，退出实例")
		call_deferred("_leave")
		return
	grid = BlueprintGrid.new(bp)
	ground.mesh = BlueprintGroundMesh.build(bp, WORLD_SCALE)
	ground.material_override = BlueprintGroundMesh.material()
	_build_props()
	mover = PlayerMover.new(bp, grid, WORLD_SCALE)
	_spawn_player()
	title.text = bp.display_name
	exit_btn.pressed.connect(_leave)
	joystick.changed.connect(mover.set_joystick)
	player.position = mover.position
	_update_camera()

func _leave() -> void:
	AppRouter.pop_instance()

func prop_count() -> int:
	return props.get_child_count()

func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	props.add_child(mi)

func _build_props() -> void:
	var s := WORLD_SCALE
	_box(bp.cell_to_world(bp.anchor("house"), s), Vector3(2.4, 2.2, 2.4) * s, Color(0.35, 0.45, 0.75))
	_box(bp.cell_to_world(bp.anchor("storage"), s), Vector3(0.9, 0.9, 0.9) * s, Color(0.5, 0.5, 0.5))
	_box(bp.cell_to_world(bp.anchor("well"), s), Vector3(0.8, 1.0, 0.8) * s, Color(0.3, 0.6, 0.85))
	_box(bp.cell_to_world(bp.anchor("exit"), s), Vector3(0.3, 2.0, 0.3) * s, Color(0.85, 0.3, 0.3))
	for bed in bp.beds():
		for c in bed.cells:
			_box(bp.cell_to_world(c, s), Vector3(0.9, 0.15, 0.9) * s, BlueprintGroundMesh.COLOR_BED)
	for c in bp.reserved_bed().get("cells", []):
		_box(bp.cell_to_world(c, s), Vector3(0.9, 0.08, 0.9) * s, Color(0.78, 0.66, 0.55))

func _spawn_player() -> void:
	_rig = Avatar.create_rig()
	_rig.assembler = AvatarAssemblerMerged.new()
	player.add_child(_rig)
	_rig.config_applied.connect(func(_c): _play("idle"))
	_rig.apply_config(Avatar.load_outfit())

func _play(anim: String) -> void:
	if _anim == anim or _rig == null:
		return
	var ap := _rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(anim):
		ap.play(anim)
		_anim = anim

func _process(dt: float) -> void:
	if mover == null:
		return
	mover.step(dt)
	player.position = mover.position
	if mover.is_moving():
		player.look_at(player.position + mover.facing, Vector3.UP)
		_play("walk")
	else:
		_play("idle")
	_update_camera()

func _update_camera() -> void:
	var phi := deg_to_rad(CAM_PITCH_DEG)
	cam.position = player.position + Vector3(0.0, CAM_DIST * sin(phi), CAM_DIST * cos(phi))
	cam.look_at(player.position + Vector3(0, 0.8, 0), Vector3.UP)

func _unhandled_input(e: InputEvent) -> void:
	# 缺蓝图退场帧：_ready() 里 call_deferred("_leave") 要到本帧末才生效，
	# 这期间仍可能收到输入事件，此时 mover/bp 还是 null，必须先跳过。
	if mover == null:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			_tap_start = e.position
		elif e.position.distance_to(_tap_start) <= TAP_MAX_PX:
			var hit = Plane(Vector3.UP, 0.0).intersects_ray(
				cam.project_ray_origin(e.position), cam.project_ray_normal(e.position))
			if hit != null:
				_on_ground_tapped(hit as Vector3)

func _on_ground_tapped(world: Vector3) -> void:
	# 同上：退场帧内测试/输入可能直接调用本函数，mover 为 null 时安全跳过。
	if mover == null:
		return
	mover.set_target_cell(bp.world_to_cell(world, WORLD_SCALE))

func is_back_navigation_locked() -> bool:
	return false
