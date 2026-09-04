extends Node3D
## 私有农场实例（PRD §3.2 第二层）灰盒：蓝图地表 + 锚点原语 + 自己的 Avatar + 45° 跟随相机。
## 由 AppRouter.push_instance(AppRouter.FARM, {...}) 压在地图之上；退出即 pop。

const WORLD_SCALE := 1.0 # 逻辑米 → 世界米；G1 调观感时只改这里，时长不变量不受影响
const CAM_DIST := 16.0
## 相机跟随点比玩家再往南（+z，靠相机一侧）偏这么多米：HUD 占掉屏幕下方约 40%，玩家若在正
## 中，南侧那一畦永远压在工具栏底下点不到（2026-09-04 真机）。偏移后玩家落在上三分之一。
const CAM_AHEAD := 3.0
## 田畦盒子高度；作物层从它的顶面往上长。
const BED_H := 0.15
const CAM_PITCH_DEG := 45.0
const TAP_MAX_PX := 16.0
## 工具 → 服务端命令。空工具名表示「移动模式」，点地就是走过去。
const TOOL_COMMAND := {
	"clear": "clear_cells", "till": "till_cells", "sow": "sow_cells",
	"care": "apply_care", "harvest": "harvest_cells",
}

var bp: FarmBlueprint
var grid: BlueprintGrid
var mover: PlayerMover
var _args := {}
var crop_field: CropField
var runner: ActionRunner
## 这三样可以为 null：没有服务端时农场退化成 G0 的灰盒，照旧能进能出能走动。
var session: FarmSession
var predictor: CellPredictor
## 当前工具与播种作物；空工具 = 移动模式。
var tool := ""
var sow_crop := "R"
## 行级工具：一次手势覆盖整畦 3 格，但仍逐格播放（PRD §6.3 L408）。
var row_tool := false
var _rig: AvatarRig
var _anim := ""
var _tap_start := Vector2.ZERO
var director: DirectorPanel
## 访客模式：只读、挥手、印章。零写入——不挂 session/predictor，工具不出现，命令不发。
var visitor := false
var snapshot: Dictionary = {}
var _emote_lock_s := 0.0
var _stamp_index := 0
const STAMPS := ["Nice!", "Lovely", "Wow"]
const STAMP_LIFETIME_S := 1.2
## -1 表示没在按。曾经初值是 0.0，进农场 3 秒后导演面板自己弹出来（2026-09-04 录屏）。
var _title_hold := -1.0
var _drag_points := PackedVector2Array()
var _dragging := false

@onready var cam: Camera3D = $Camera3D
@onready var ground: MeshInstance3D = $Ground
@onready var props: Node3D = $Props
@onready var crops_root: Node3D = $Crops
@onready var player: Node3D = $Player
@onready var title: Label = %Title
@onready var exit_btn: Button = %ExitButton
@onready var joystick: TouchStick = $HUD/SafeArea/Root/Joystick
@onready var hud: FarmHud = %Hud

func setup(args: Dictionary) -> void:
	_args = args

func _ready() -> void:
	# 压栈进入的新实例不会经过 AppRouter 的 suspend/resume 协议（那条协议只管
	# "已经在栈里、被别人盖住/揭开"的场景）；自己的相机要不要成为当前相机，
	# 得在第一次入树时自己抢——不抢的话会保留住下层地图冻结的位姿（2026-09-04 终审 C1）。
	cam.make_current()
	visitor = bool(_args.get("visitor", false))
	snapshot = _args.get("snapshot", {})
	bp = _args.get("blueprint")
	# 服务端农场的蓝图优先于本地选的：2026-09-04 真机上本地选了 sh_b、服务端农场是 sh_c，
	# 客户端按 sh_b 进场，发出去的每一格都 CELL_NOT_CULTIVABLE，草还画在别的坐标上。
	if not visitor:
		var s0: FarmSession = _args.get("session", Net.session if Net else null)
		if s0 and s0.has_farm() and not s0.layout_patch_id.is_empty():
			var server_bp := FarmBlueprint.load_file(FarmBlueprint.asset_path(s0.layout_patch_id, s0.blueprint_revision))
			if server_bp != null:
				bp = server_bp
				FarmChoice.save(s0.layout_patch_id, s0.blueprint_revision)
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
	# 作物挂 Crops（Props 的同级）：prop_count() 只数锚点原语与畦面，作物不进去。
	crop_field = CropField.new(bp, WORLD_SCALE)
	crop_field.ground_y = BED_H * WORLD_SCALE
	crops_root.add_child(crop_field)
	mover = PlayerMover.new(bp, grid, WORLD_SCALE)
	runner = ActionRunner.new()
	runner.cell_started.connect(_on_cell_started)
	runner.cell_done.connect(_on_cell_done)
	_spawn_player()
	_attach_session()
	title.text = bp.display_name
	if visitor:
		_enter_visitor_mode()
	exit_btn.pressed.connect(_leave)
	hud.tool_selected.connect(func(t):
		tool = t
		hud.set_hint("" if t.is_empty() else "Tap or drag over plots"))
	hud.crop_selected.connect(func(c): sow_crop = c)
	hud.row_tool_toggled.connect(func(on): row_tool = on)
	if not visitor:
		_build_director()
		# 第一眼就告诉玩家怎么开始；选了工具后提示会换成下一步。
		hud.set_hint("Pick a tool, then tap a plot")
	_refresh_hud()
	joystick.changed.connect(mover.set_joystick)
	player.position = mover.position
	_update_camera()

func _leave() -> void:
	_record_visit()
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
			_box(bp.cell_to_world(c, s), Vector3(0.9, BED_H, 0.9) * s, BlueprintGroundMesh.COLOR_BED)
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
	if runner:
		runner.step(dt)
	if _emote_lock_s > 0.0:
		_emote_lock_s -= dt
	if hud and runner:
		hud.set_action(runner.current_action(), runner.progress(), runner.pending_count())
	_tick_title_hold(dt)
	# 劳作中锁住动画：否则 _process 每帧无条件用 walk/idle 覆盖，动作动画永远播不出来。
	if not _action_locked():
		if mover.is_moving():
			player.look_at(player.position + mover.facing, Vector3.UP)
			_play("walk")
		else:
			_play("idle")
	elif mover.is_moving():
		player.look_at(player.position + mover.facing, Vector3.UP)
	_update_camera()

func _update_camera() -> void:
	var phi := deg_to_rad(CAM_PITCH_DEG)
	var target := player.position + Vector3(0.0, 0.0, CAM_AHEAD)
	cam.position = target + Vector3(0.0, CAM_DIST * sin(phi), CAM_DIST * cos(phi))
	cam.look_at(target + Vector3(0, 0.8, 0), Vector3.UP)

func _unhandled_input(e: InputEvent) -> void:
	# 缺蓝图退场帧：_ready() 里 call_deferred("_leave") 要到本帧末才生效，
	# 这期间仍可能收到输入事件，此时 mover/bp 还是 null，必须先跳过。
	if mover == null:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			_tap_start = e.position
			_drag_points = PackedVector2Array([e.position])
			_dragging = false
		elif _dragging:
			_drag_points.append(e.position)
			_finish_brush()
		elif e.position.distance_to(_tap_start) <= TAP_MAX_PX:
			if tool.is_empty():
				var hit = Plane(Vector3.UP, 0.0).intersects_ray(
					cam.project_ray_origin(e.position), cam.project_ray_normal(e.position))
				if hit != null:
					_on_ground_tapped(hit as Vector3)
			else:
				# 选了工具时点按 = 对单格执行动作；没选工具才是移动。
				_enqueue_cells(LabourBrush.trace(
					PackedVector2Array([e.position]), _projector()))
	elif e is InputEventScreenDrag and not tool.is_empty():
		# 摇杆矩形内的 drag 已被 TouchStick._gui_input 吃掉（accept_event），不会打架。
		_dragging = true
		_drag_points.append(e.position)

func _on_ground_tapped(world: Vector3) -> void:
	# 同上：退场帧内测试/输入可能直接调用本函数，mover 为 null 时安全跳过。
	if mover == null:
		return
	mover.set_target_cell(bp.world_to_cell(world, WORLD_SCALE))

func is_back_navigation_locked() -> bool:
	return false

## 把（预测叠加后的）格子状态推给作物渲染。now_ms 必须是**服务端时间**
## （FarmSession.server_now()）——本地时钟不可信，作物不该因为改系统时间提前熟。
func render_cells(cells: Dictionary, now_ms: int) -> void:
	if crop_field:
		crop_field.sync(cells, now_ms)

func _projector() -> Callable:
	return LabourBrush.ground_projector(cam, bp, WORLD_SCALE)

func _action_locked() -> bool:
	return (runner != null and runner.is_busy()) or _emote_lock_s > 0.0

func _finish_brush() -> void:
	var cells := LabourBrush.trace(_drag_points, _projector())
	_drag_points = PackedVector2Array()
	_dragging = false
	_enqueue_cells(cells)

## 命中格 → 过滤 →（行级工具）扩畦 → 入队。返回入队格数，测试用。
func _enqueue_cells(cells: Array) -> int:
	if visitor or tool.is_empty() or cells.is_empty():
		return 0
	var unlocked := 4 if predictor and predictor.beds_unlocked == 4 else 3
	if row_tool:
		cells = LabourBrush.expand_rows(cells, bp)
	cells = LabourBrush.filter_actionable(cells, bp, unlocked)
	return runner.enqueue(cells, tool)

## 每格开工：先本地预测（立刻有视觉反馈），再播动画。
func _on_cell_started(cell: Vector2i, action: String) -> void:
	var id := "%d,%d" % [cell.x, cell.y]
	if predictor:
		var r := predictor.predict(TOOL_COMMAND.get(action, ""), _payload_for(action, [id]),
			session.server_now() if session else 0)
		if r.ok:
			_render()
		else:
			# 本地就判定不合法：说原因、放弃这格、不发命令。原来会照常干 2 秒再被服务端拒，
			# 玩家看到的是白忙一场。
			if hud:
				hud.show_toast(FarmHud.reject_text(r.error))
			runner.abort_current()
			return
	var clip := AnimPlaceholders.clip_for(action)
	_play(clip)
	# 占位动作只回退到 idle 的话玩家看到的是站着发呆 2 秒——至少俯身、至少面向那格。
	if AnimPlaceholders.is_placeholder(action) and _rig:
		AnimPlaceholders.play_fallback(_rig, ActionRunner.ACTION_S)
	var target := bp.cell_to_world(cell, WORLD_SCALE)
	if target.distance_to(player.position) > 0.05:
		player.look_at(Vector3(target.x, player.position.y, target.z), Vector3.UP)
	if hud:
		hud.set_hint("")

## 每格收工：把命令发给服务端，回包对账；被拒就丢掉预测并把原因报出去。
func _on_cell_done(cell: Vector2i, action: String) -> void:
	var id := "%d,%d" % [cell.x, cell.y]
	if session == null:
		return
	var accepted: bool = await session.send(TOOL_COMMAND.get(action, ""), _payload_for(action, [id]))
	if predictor:
		if accepted:
			predictor.commit(session.state.get("cells", {}), session.version)
		else:
			predictor.rollback()
		_render()

func _payload_for(action: String, ids: Array) -> Dictionary:
	var p := {"cell_ids": ids}
	match action:
		"sow":
			p["crop"] = sow_crop
			p["lot"] = "bound"
			p["field_condition"] = _field_condition()
		"care":
			p["kind"] = AnimPlaceholders.CARE_ACTION.get(_field_condition(), "water")
	return p

func _field_condition() -> String:
	if session == null:
		return "sunny"
	return str((session.state.get("clock", {}) as Dictionary).get("field_condition", "sunny"))

func _render() -> void:
	if predictor:
		render_cells(predictor.view(), session.server_now() if session else 0)
	_refresh_hud()

## 把权威状态（叠上预测）刷到 HUD。倒计时与成熟判定都走服务端时间。
func _refresh_hud() -> void:
	if hud == null:
		return
	var now := session.server_now() if session else 0
	var cells: Dictionary = predictor.view() if predictor else {}
	hud.set_coins(int(session.state.get("wallet", 0)) if session else 0)
	hud.set_condition(_field_condition())
	var chapter := int((session.state.get("clock", {}) as Dictionary).get("chapter_index", 0)) if session else 0
	hud.set_unlocked_crops(CropUnlocks.unlocked(FarmHud.CROPS, chapter))
	hud.set_next_ripe(cells, now)
	hud.set_offline(session.offline if session else false)

## 导演面板入口：长按标题三秒，或命令行 --qa 直接打开。不额外占屏幕——
## QA 面板不该在正式玩家的界面上留按钮。
func _build_director() -> void:
	director = DirectorPanel.new()
	director.name = "Director"
	hud.add_child(director)
	director.command_requested.connect(_on_director_command)
	title.gui_input.connect(_on_title_input)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	if OS.get_cmdline_user_args().has("--qa"):
		director.visible = true

func _on_title_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventMouseButton:
		_title_hold = 0.0 if e.is_pressed() else -1.0

func _tick_title_hold(dt: float) -> void:
	if _title_hold < 0.0 or director == null:
		return
	_title_hold += dt
	if _title_hold >= DirectorPanel.HOLD_S:
		_title_hold = -1.0
		director.toggle()

## 导演命令直发服务端；客户端不本地加速时间。
func _on_director_command(type: String, payload: Dictionary) -> void:
	if session == null:
		director.report(false, "OFFLINE")
		return
	var body := payload
	if type == "qa_set_weather":
		# 面板选的是「今天改成什么」，命令要的是天气日索引 → 田况。
		var idx := int((session.state.get("clock", {}) as Dictionary).get("weather_day_index", 0))
		body = {"overrides": {str(idx): payload.get("day", "sunny")}}
	var accepted: bool = await session.send(type, body)
	director.report(accepted, session.last_error_code, session.player_id)
	if accepted:
		predictor.commit(session.state.get("cells", {}), session.version) if predictor else null
		_render()

## 接上服务端会话。允许通过 setup 参数注入（测试用），否则取全局 Net。
## 没有会话或会话里没有农场 → 退化成 G0 灰盒，照旧能进能出能走动。
func _attach_session() -> void:
	if _args.get("visitor", false):
		return
	var s: FarmSession = _args.get("session", Net.session if Net else null)
	if s == null or not s.has_farm():
		return
	session = s
	predictor = CellPredictor.from_blueprint(bp, session.state.get("cells", {}))
	predictor.beds_unlocked = int(session.state.get("beds_unlocked", 3))
	session.state_changed.connect(_on_server_state)
	session.offline_changed.connect(func(off): if hud: hud.set_offline(off))
	# 服务端拒绝必须说出来：静默回滚在玩家眼里就是「点了没反应」（2026-09-04 录屏）。
	session.rejected.connect(func(code, _detail): if hud: hud.show_toast(FarmHud.reject_text(code)))
	_render()

## 服务端每次回包都整体覆盖预测器；漂移一律以服务端为准（方案 §3 D4）。
func _on_server_state(state: Dictionary, version: int) -> void:
	if predictor:
		predictor.commit(state.get("cells", {}), version)
		predictor.beds_unlocked = int(state.get("beds_unlocked", 3))
	_render()


## —— 访客模式（PRD §3.3 / §8.4）——————————————————————————————————————————

func _enter_visitor_mode() -> void:
	title.text = "Visiting · %s" % SeededOutfit.short_name(str(snapshot.get("avatar_ref", "seed:unknown")))
	hud.set_visitor_mode(true)
	hud.set_condition(str(snapshot.get("weather_snapshot", "sunny")))
	hud.wave_pressed.connect(_wave)
	hud.stamp_pressed.connect(_stamp)
	if crop_field:
		crop_field.sync_snapshot(snapshot.get("cells", []))

## 挥手：本机动画，不发送给主人、不持久化、不产生任何资源。
func _wave() -> void:
	_emote_lock_s = 1.2
	_play(AnimPlaceholders.clip_for("wave"))
	if AnimPlaceholders.is_placeholder("wave") and _rig:
		AnimPlaceholders.play_wave_fallback(_rig, 1.2)

## 印章：头顶冒一个预设词，浮起淡出后消失；同样只在访客本机。
func _stamp() -> void:
	var label := Label3D.new()
	label.name = "Stamp"
	label.text = STAMPS[_stamp_index % STAMPS.size()]
	_stamp_index += 1
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.01
	label.modulate = DesignTokens.ACCENT_DEEP
	label.position = Vector3(0, 1.9, 0)
	var old := player.get_node_or_null("Stamp")
	if old:
		player.remove_child(old)
		old.queue_free()
	player.add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", 2.6, STAMP_LIFETIME_S)
	tw.parallel().tween_property(label, "modulate:a", 0.0, STAMP_LIFETIME_S)
	tw.finished.connect(func(): if is_instance_valid(label): label.queue_free())

## 离开访客农场时把「完成过一次访问」这条教学事实报给服务端（PRD §8.4 L655：零奖励）。
## D4 之前服务端回 CHAPTER_LOCKED，静默即可；不等回包，别拖住返回。
func _record_visit() -> void:
	if not visitor or Net == null or not Net.logged_in() or not Net.session.has_farm():
		return
	Net.session.send("record_visit_return", {"visited_farm_id": str(snapshot.get("farm_id", ""))})
