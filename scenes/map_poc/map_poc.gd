extends Node3D
## G1 PoC：Mapbox 原生 MapView 垫底 + Godot 透明层渲染角色（方案 A 的 Android 合成验证）。
##
## 验证目标（docs/superpowers/plans/2026-08-29-3dmap-g1-poc.md）：
##   1) 地图在 Godot 渲染面之下可见（透明合成生效）
##   2) Godot 角色叠加在地图上正常渲染（材质/动画不受影响）
##   3) 手势经 Godot → JNI 桥驱动地图相机（pan/zoom/pitch）
## G2 的相机同步数学不在本场景范围，此处角色固定在屏幕中心。

const TOKEN_PATH := "res://mapbox_token.txt"
const START_LAT := 31.2304 # 上海人民广场附近
const START_LNG := 121.4737

@onready var status: Label = $HUD/Margin/VBox/Status
@onready var rigs: Node3D = $Rigs
@onready var cam: Camera3D = $Camera3D

var map: Object = null
var zoom := 16.0
var pitch := 45.0
var bearing := 0.0
var _touch_count := 0

func _ready() -> void:
	# 根视口透明：配合 project.godot 的 per_pixel_transparency/allowed 才能在
	# Android 上得到 TRANSLUCENT surface（G1 关键开关）。
	get_viewport().transparent_bg = true
	$Sun.rotation_degrees = Vector3(-55, 30, 0)
	_spawn_character()
	_update_godot_camera()
	_wire_buttons()

	if Engine.has_singleton("GodotMap"):
		map = Engine.get_singleton("GodotMap")
		map.connect("map_ready", _on_map_ready)
		var token := _load_token()
		if token.is_empty():
			status.text = "G1: 缺 res://mapbox_token.txt（构建机放置，勿提交）"
		else:
			map.createMap(token, START_LAT, START_LNG, zoom)
			status.text = "G1: createMap 已调用，等待 map_ready…"
	else:
		status.text = "G1: 无 GodotMap 插件（桌面运行仅能看透明视口与角色）"

func _process(_dt: float) -> void:
	if map != null and Engine.get_process_frames() % 30 == 0:
		var info: String = map.getCameraInfo()
		if not info.is_empty():
			status.text = "G1: %s" % info

func _on_map_ready() -> void:
	status.text = "G1: map_ready ✅ 样式加载完成"

func _load_token() -> String:
	if not FileAccess.file_exists(TOKEN_PATH):
		return ""
	var f := FileAccess.open(TOKEN_PATH, FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""

func _spawn_character() -> void:
	var rig := Avatar.create_rig()
	rig.assembler = AvatarAssemblerMerged.new()
	rigs.add_child(rig)
	rig.apply_config(Avatar.slot_table.default_config())
	rig.config_applied.connect(func(_c):
		var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap:
			ap.play("idle"))

func _update_godot_camera() -> void:
	# 与地图 pitch 联动的轨道相机：仰角 = 90° - pitch，注视角色胸口。
	# fov 对齐 Mapbox 默认竖向 FOV（G2 用 projectionMatrix 精确校准）。
	cam.fov = 36.87
	var elev := deg_to_rad(90.0 - pitch)
	var dist := 5.0
	var target := Vector3(0, 0.9, 0)
	cam.position = target + Vector3(0, sin(elev), cos(elev)) * dist
	cam.look_at(target, Vector3.UP)

func _wire_buttons() -> void:
	$HUD/Margin/VBox/Row1/ZoomIn.pressed.connect(func(): _set_zoom(zoom + 1.0))
	$HUD/Margin/VBox/Row1/ZoomOut.pressed.connect(func(): _set_zoom(zoom - 1.0))
	$HUD/Margin/VBox/Row1/PitchUp.pressed.connect(func(): _set_pitch(pitch + 15.0))
	$HUD/Margin/VBox/Row1/PitchDown.pressed.connect(func(): _set_pitch(pitch - 15.0))
	$HUD/Margin/VBox/Row2/Rotate.pressed.connect(func(): _set_bearing(bearing + 30.0))
	$HUD/Margin/VBox/Row2/ToDressing.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/dressing_room/dressing_room.tscn"))

func _set_zoom(v: float) -> void:
	zoom = clampf(v, 3.0, 20.0)
	if map:
		map.setZoom(zoom)

func _set_pitch(v: float) -> void:
	pitch = clampf(v, 0.0, 70.0)
	if map:
		map.setPitch(pitch)
	_update_godot_camera() # 倾角联动演示：Godot 相机跟随同一 pitch

func _set_bearing(v: float) -> void:
	bearing = fmod(v + 360.0, 360.0)
	if map:
		map.setBearing(bearing)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		_touch_count += 1 if e.pressed else -1
		_touch_count = maxi(_touch_count, 0)
	if map == null:
		return
	if e is InputEventScreenDrag and _touch_count <= 1:
		map.panBy(float(e.relative.x), float(e.relative.y))
	elif e is InputEventMagnifyGesture:
		# 双指捏合（需 project 开 enable_pan_and_scale_gestures）
		_set_zoom(zoom + log(e.factor) / log(2.0) * 2.0)
	elif e is InputEventPanGesture:
		# 双指拖拽 → 调 pitch（对齐 Mapbox 原生手势习惯）
		_set_pitch(pitch - e.delta.y * 0.2)
