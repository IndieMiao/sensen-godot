extends Node3D

@onready var anchor: Node3D = $RigAnchor
@onready var parts_panel = $UI/SafeArea/VBox/Drawer/VBox
@onready var cam: DressingCamera = $Camera3D
@onready var safe_area: SafeAreaMargin = $UI/SafeArea
@onready var top_bar: Control = $UI/SafeArea/VBox/TopBar
@onready var drawer: PanelContainer = $UI/SafeArea/VBox/Drawer
@onready var back_button: Button = $UI/SafeArea/VBox/TopBar/BackButton
@onready var restore_button: Button = $UI/SafeArea/VBox/TopBar/RestoreButton
@onready var done_button: Button = $UI/SafeArea/VBox/TopBar/DoneButton
@onready var feedback_panel: PanelContainer = $UI/SafeArea/VBox/Drawer/VBox/FeedbackPanel
@onready var feedback_label: Label = $UI/SafeArea/VBox/Drawer/VBox/FeedbackPanel/FeedbackLabel

## 点角色（不拖动）在"全身"与"当前分类部位"之间切换取景。
## 判定为点击的最大位移，单位与视口一致；超过就当作转身拖拽。
const TAP_SLOP := 12.0

var rig: AvatarRig
var _dragging := false
var _drag_distance := 0.0
var _reframe_queued := false
var _reframe_animated := false
var _initial_ready := false
var _committing := false
var _safe_margins := Vector4(16.0, 16.0, 16.0, 16.0)
## 当前分类对应的推近档位；点角色缩回全身后，再点一次回到这一档。
var _slot_region: int = DressingCamera.Region.FULL


func _ready() -> void:
	# 压栈进入的新实例不会经过 AppRouter 的 suspend/resume 协议；自己的相机要不要
	# 成为当前相机得在第一次入树时自己抢，否则会保留住地图冻结的位姿
	# （2026-09-04 终审 C1；同样的一行也补进了 farm.gd::_ready()）。
	cam.make_current()
	rig = Avatar.create_rig()
	anchor.add_child(rig)
	rig.config_applied.connect(_on_config_applied)
	rig.busy_changed.connect(_on_rig_busy_changed)

	# 缩略图渲染器挂在场景下，随场景一起销毁；catalog 与 rig 用的是同一份。
	var thumbnailer := PartThumbnailer.new()
	thumbnailer.name = "PartThumbnailer"
	thumbnailer.catalog = Avatar.catalog
	add_child(thumbnailer)
	parts_panel.thumbnailer = thumbnailer

	parts_panel.setup(rig)
	parts_panel.selection_started.connect(_hide_feedback)
	parts_panel.selection_failed.connect(_show_feedback)
	parts_panel.slot_changed.connect(_on_slot_changed)
	back_button.pressed.connect(_on_back)
	restore_button.pressed.connect(_on_restore)
	done_button.pressed.connect(_on_done)
	safe_area.margins_applied.connect(_on_safe_margins_applied)
	get_viewport().size_changed.connect(_reframe)

	rig.apply_config(Avatar.load_outfit())
	# SafeArea 的首次信号早于父节点 _ready()；主动刷新，保证相机避开真实安全区。
	safe_area.refresh()
	_refresh_completion_state()


func _on_config_applied(_config: AvatarConfig) -> void:
	_initial_ready = true
	var animation_player := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation_player:
		animation_player.play("idle")
	parts_panel.refresh()
	_refresh_completion_state()
	_reframe()


## 换装不再触发重新取景：相机对着 DressingCamera.reference_box() 这个与装扮无关的
## 固定盒子取景，换高发型也不会推远相机。以前这里连着 slot_applied 调 _reframe()，
## 正是"换个发型角色就忽大忽小"的来源。布局变化（安全区/抽屉/视口）仍会重新取景。
## 切分类推近到对应部位。zoom out 的三个入口：进场（默认 FULL）、点角色、
## 再点一次当前分区。没做"停顿若干秒自动缩回"——用户逐个试发型时会来回抽动。
func _on_slot_changed(slot: StringName) -> void:
	_slot_region = DressingCamera.region_for_slot(slot)
	cam.focus_region = _slot_region
	_reframe(true)


func _toggle_focus() -> void:
	var full: int = DressingCamera.Region.FULL
	cam.focus_region = full if cam.focus_region != full else _slot_region
	_reframe(true)


func _on_rig_busy_changed(_busy: bool) -> void:
	_refresh_completion_state()


func _on_safe_margins_applied(margins: Vector4) -> void:
	_safe_margins = margins
	_reframe()


func _on_back() -> void:
	if _committing:
		return
	# 当前 rig 是编辑草稿；不调用 save 即可丢弃改动。
	AppRouter.pop_instance()


func is_back_navigation_locked() -> bool:
	return _committing


func _on_restore() -> void:
	if _committing:
		return
	_hide_feedback()
	rig.apply_config(Avatar.slot_table.default_config())
	parts_panel.refresh()
	_refresh_completion_state()


func _on_done() -> void:
	if _committing or rig == null:
		return
	_committing = true
	_refresh_completion_state()
	# 代码层也守住竞态：即使测试或键盘在按钮禁用前触发，仍等装配真正收敛。
	while rig.is_busy():
		await rig.busy_changed
		if not is_inside_tree() or not is_instance_valid(rig):
			return
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(rig):
		return
	var error := Avatar.save_outfit(rig.current_config())
	if error != OK:
		_committing = false
		push_warning("DressingRoom: save failed with error %d" % error)
		_show_feedback("Couldn't save. Try again.")
		_refresh_completion_state()
		return
	AppRouter.pop_instance()


func _refresh_completion_state() -> void:
	if rig == null:
		return
	var busy := rig.is_busy()
	done_button.disabled = _committing or busy
	back_button.disabled = _committing
	restore_button.disabled = _committing
	parts_panel.set_interaction_enabled(not _committing)
	if _committing:
		done_button.text = "Saving..."
	elif busy:
		done_button.text = "Preparing..." if not _initial_ready else "Trying on..."
	else:
		done_button.text = "Done"


func _show_feedback(message: String) -> void:
	feedback_label.text = message
	feedback_panel.visible = true
	_reframe()


func _hide_feedback() -> void:
	feedback_panel.visible = false
	_reframe()


func _unhandled_input(event: InputEvent) -> void:
	# 按下起点 + 累计位移用来区分"点角色切取景"和"拖拽转身"：
	# 松手时位移仍在 TAP_SLOP 内才算点击。触摸与鼠标两条路都要覆盖，
	# 真机走 ScreenTouch/ScreenDrag，桌面调试走 MouseButton/MouseMotion。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_on_press_changed(event.pressed, event.position)
	elif event is InputEventScreenTouch:
		_on_press_changed(event.pressed, event.position)
	elif event is InputEventMouseMotion and _dragging:
		_track_drag(event.relative)
	elif event is InputEventScreenDrag:
		_track_drag(event.relative)


func _on_press_changed(pressed: bool, _at: Vector2) -> void:
	if pressed:
		_dragging = true
		_drag_distance = 0.0
		return
	var was_tap := _dragging and _drag_distance <= TAP_SLOP
	_dragging = false
	if was_tap:
		_toggle_focus()


## 累计**路径长度**而不是首尾直线距离：转出去再转回来虽然首尾重合，
## 但那显然是一次拖拽，不该当成点击。
func _track_drag(relative: Vector2) -> void:
	anchor.rotate_y(-relative.x * 0.01)
	_drag_distance += relative.length()


func _reframe(animate := false) -> void:
	# 同一帧内的多次请求合并到下一帧执行；只要其中一次要求补间就补间
	# （切分类与安全区回调可能同帧到达，硬落位会把推拉动画吃掉）。
	_reframe_animated = _reframe_animated or animate
	if _reframe_queued:
		return
	_reframe_queued = true
	await get_tree().process_frame
	_reframe_queued = false
	var animated := _reframe_animated
	_reframe_animated = false
	if not is_instance_valid(rig) or not is_instance_valid(cam):
		return
	var header_height := maxf(top_bar.size.y, top_bar.get_combined_minimum_size().y)
	cam.safe_margin_top = _safe_margins.y + header_height + 8.0
	cam.safe_margin_bottom = _safe_margins.w
	cam.drawer_height = drawer.size.y if drawer.size.y > 0.0 else drawer.custom_minimum_size.y
	cam.reframe(rig, get_viewport().get_visible_rect().size, animated)
