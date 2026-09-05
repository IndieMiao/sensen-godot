class_name WeekPhoto
extends Node3D

signal closed()
signal saved(path: String)

var canvas: CanvasLayer
var camera: Camera3D
var _status: Label
var _ready_count := 0
var _saving := false
var farm_state: Dictionary = {}

func _ready() -> void:
	name = "WeekPhoto"
	add_child(PlaceScenery.build("nursery", farm_state))
	if bool(farm_state.get("week_summary", {}).get("life_priority", false)):
		add_child(DecorationLayout.build(DecorationLayout.saved(farm_state)))
	for index in 4:
		var rig := Avatar.create_rig()
		rig.name = "Player" if index == 0 else ResidentCast.ORDER[index - 1]
		var personal := bool(farm_state.get("week_summary", {}).get("life_priority", false))
		var positions := [Vector3(-0.5, 0.06, 1.1), Vector3(-1.8, 0.06, 0.6), Vector3(0.8, 0.06, 0.75), Vector3(2.0, 0.06, 0.35)]
		rig.position = positions[index] if personal else Vector3((index - 1.5) * 1.25, 0.06, 0.6)
		rig.rotation.y = 0.3
		var config := Avatar.load_outfit() if index == 0 else ResidentCast.outfit(ResidentCast.ORDER[index - 1])
		rig.config_applied.connect(func(_config):
			_ready_count += 1
			var animation := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if animation and animation.has_animation("idle"): animation.play("idle"))
		rig.ready.connect(func(): rig.apply_config(config), CONNECT_ONE_SHOT)
		add_child(rig)
		if bool(farm_state.get("week_summary", {}).get("life_priority", false)):
			var label := Label3D.new()
			label.text = "You" if index == 0 else str(ResidentCast.definition(ResidentCast.ORDER[index - 1]).short_name)
			label.position = rig.position + Vector3(0, 2.3, 0)
			label.font_size = 30
			label.pixel_size = 0.008
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = GameUi.INK
			label.outline_modulate = Color.WHITE
			add_child(label)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 9
	camera.position = Vector3(3, 5, 12)
	add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.make_current()
	canvas = CanvasLayer.new()
	add_child(canvas)
	var safe := SafeAreaMargin.new()
	safe.theme = GameUi.theme()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(safe)
	var column := VBoxContainer.new()
	safe.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var close := GameUi.button("arrow-left", "", "Back to nursery")
	close.pressed.connect(func():
		if not _saving: closed.emit())
	header.add_child(close)
	header.add_child(GameUi.label("Our first week", 18))
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	_status = GameUi.label("", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var capture := GameUi.button("camera", "Save photo", "Save our group photo", true)
	capture.name = "SavePhoto"
	capture.pressed.connect(capture_photo)
	column.add_child(capture)

func capture_photo() -> void:
	if _saving: return
	if _ready_count < 4:
		_status.text = "Getting everyone ready..."
		return
	_saving = true
	canvas.hide()
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var side := mini(picture.get_width(), picture.get_height())
	picture = picture.get_region(Rect2i((picture.get_width() - side) / 2, (picture.get_height() - side) / 2, side, side))
	var directory := "user://photos"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var target := directory.path_join("first-week-%d.png" % int(Time.get_unix_time_from_system()))
	var result := picture.save_png(target)
	canvas.show()
	_saving = false
	_status.text = "Photo saved" if result == OK else "Could not save photo. Try again."
	if result == OK: saved.emit(ProjectSettings.globalize_path(target))

func consume_back() -> bool:
	if not _saving: closed.emit()
	return true
