extends Node3D
## 私有农场实例（PRD §3.2 第二层）。
##
## 交互模型 v2（2026-09-04 晚真机反馈后重做）：**没有工具**。点一块田，它自己做该做的下一步
## （草→清理，空地→翻土，翻土→播种，已播→照料，熟了→收获）；人物先走到地头再干活，头顶
## 浮字说明在干什么；底部一个大按钮永远写着现在最该做的事；左上是今天的目标清单。
## 客户端不算钱、不算 XP、不算 ready_at——只预测格子状态跃迁给即时反馈，其余以服务端回包为准。

const WORLD_SCALE := 1.0 # 逻辑米 → 世界米；G1 调观感时只改这里，时长不变量不受影响
const CAM_DIST := 16.0
## 相机跟随点比玩家再往南（+z）偏这么多米：HUD 占掉屏幕下方约 40%，玩家若在正中，南侧那一畦
## 永远压在按钮下面点不到。偏移后玩家落在上三分之一。
const CAM_AHEAD := 3.0
## AvatarRig 的活动度控制默认 16 m 休眠动画。农场相机到玩家的距离约 18 m——不把阈值抬高，
## 走路和俯身动画就全没了（2026-09-04 晚真机：「动画完全丢失」）。
const RIG_SLEEP_DIST := 60.0
const RIG_REDUCED_DIST := 40.0
const CAM_PITCH_DEG := 45.0
const TAP_MAX_PX := 16.0
## 田畦盒子高度；作物层从它的顶面往上长。
const BED_H := 0.15
const STAMPS := ["Nice!", "Lovely", "Wow"]
const STAMP_LIFETIME_S := 1.2
const STALL_BUDGET := 100

var bp: FarmBlueprint
var grid: BlueprintGrid
var mover: PlayerMover
var crop_field: CropField
var runner: ActionRunner
## 这两样可以为 null：没有服务端时农场退化成灰盒，照旧能进能出能走动。
var session: FarmSession
var predictor: CellPredictor
var director: DirectorPanel
var stall: StallSheet
## 访客模式：只读、挥手、印章。零写入。
var visitor := false
var snapshot: Dictionary = {}
var _args := {}
var _rig: AvatarRig
var _anim := ""
var _tap_start := Vector2.ZERO
var _drag_points := PackedVector2Array()
var _dragging := false
var _emote_lock_s := 0.0
var _stamp_index := 0
## -1 表示没在按。曾经初值是 0.0，进农场 3 秒后导演面板自己弹出来（2026-09-04 录屏）。
var _title_hold := -1.0
## 当前这格的浮字（Label3D），干完就撤。
var _work_label: Label3D
var _last_bulk: Dictionary = {}
## 还没回包的命令数。>0 时队列不往下走：下一格的本地校验要看的是权威状态，不是一条
## 可能被服务端拒掉的预测（自动玩家：sow 被拒后紧跟的 care 照样发了出去）。
var _in_flight := 0
var _cta_was_busy := false

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
	# 压栈进入的新实例不会经过 AppRouter 的 suspend/resume 协议；自己的相机要自己抢
	# （2026-09-04 终审 C1）。
	cam.make_current()
	visitor = bool(_args.get("visitor", false))
	snapshot = _args.get("snapshot", {})
	bp = _args.get("blueprint")
	# 服务端农场的蓝图优先于本地选的：本地选了 sh_b、服务端农场是 sh_c 时，客户端按 sh_b 进场，
	# 发出去的每一格都 CELL_NOT_CULTIVABLE，草还画在别的坐标上（2026-09-04 真机）。
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
	runner.queue_empty.connect(func(): _refresh_hud())
	_spawn_player()
	_attach_session()
	title.text = bp.display_name
	exit_btn.pressed.connect(_leave)
	joystick.changed.connect(mover.set_joystick)
	hud.cta_pressed.connect(_on_cta)
	hud.seed_selected.connect(func(_c): _refresh_hud())
	hud.stall_pressed.connect(_open_stall)
	player.position = mover.position
	_update_camera()
	if visitor:
		_enter_visitor_mode()
	else:
		_build_director()
		_build_stall()
		hud.set_hint("Tap a plot to work it")
	_refresh_hud()

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
	# rig 模型的脸朝 +Z，Godot 的 look_at 让 -Z 朝目标——不转半圈就永远背朝前走
	# （2026-09-04 晚真机：「走路背朝前」）。
	_rig.rotation.y = PI
	for c in _rig.get_children():
		if c is RigActivity:
			c.sleep_distance = RIG_SLEEP_DIST
			c.reduced_distance = RIG_REDUCED_DIST
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
	if runner and _in_flight == 0:
		# 先走到地头：到了才开工。
		if runner.paused and not mover.is_moving():
			runner.paused = false
			_begin_work(runner.current_cell(), runner.current_action())
		runner.step(dt)
	if _emote_lock_s > 0.0:
		_emote_lock_s -= dt
	# 劳作中锁住动画：否则 _process 每帧无条件用 walk/idle 覆盖，动作动画永远播不出来。
	if not _action_locked():
		if mover.is_moving():
			player.look_at(player.position + mover.facing, Vector3.UP)
			_play("walk")
		else:
			_play("idle")
	elif mover.is_moving():
		player.look_at(player.position + mover.facing, Vector3.UP)
	if hud and runner and not visitor:
		var doing := ""
		if runner.is_busy() and not runner.paused:
			doing = NextStep.doing_label(runner.current_action(), hud.selected_crop, _field_condition())
		elif runner.is_busy():
			doing = "Walking…"
		hud.set_action(doing, runner.progress(), runner.pending_count())
		var busy_now := runner.is_busy() or _in_flight > 0
		if busy_now != _cta_was_busy:
			_cta_was_busy = busy_now
			hud.set_cta_busy(runner.pending_count() if busy_now else 0)
			if not busy_now:
				_refresh_hud()
		elif busy_now:
			hud.set_cta_busy(runner.pending_count())
	_tick_title_hold(dt)
	_update_camera()

func _update_camera() -> void:
	var phi := deg_to_rad(CAM_PITCH_DEG)
	var target := player.position + Vector3(0.0, 0.0, CAM_AHEAD)
	cam.position = target + Vector3(0.0, CAM_DIST * sin(phi), CAM_DIST * cos(phi))
	cam.look_at(target + Vector3(0, 0.8, 0), Vector3.UP)

## 点田 = 对那格做下一步；点地面 = 走过去；拖过多格 = 每格做各自的下一步。
func _unhandled_input(e: InputEvent) -> void:
	# 缺蓝图退场帧：mover/bp 还是 null，必须先跳过。
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
			var hit = _projector().call(e.position)
			if hit != null:
				_tap_cell(hit as Vector2i)
	elif e is InputEventScreenDrag:
		# 摇杆矩形内的 drag 已被 TouchStick._gui_input 吃掉（accept_event），不会打架。
		if e.position.distance_to(_tap_start) > TAP_MAX_PX:
			_dragging = true
		_drag_points.append(e.position)

func _tap_cell(cell: Vector2i) -> void:
	if _is_plot(cell):
		if visitor:
			return
		if _queue_plots([cell]) == 0:
			_explain_plot(cell)
	else:
		_on_ground_tapped(bp.cell_to_world(cell, WORLD_SCALE))

func _on_ground_tapped(world: Vector3) -> void:
	# 退场帧内测试/输入可能直接调用本函数，mover 为 null 时安全跳过。
	if mover == null:
		return
	mover.set_target_cell(bp.world_to_cell(world, WORLD_SCALE))

func is_back_navigation_locked() -> bool:
	return false

func _projector() -> Callable:
	return LabourBrush.ground_projector(cam, bp, WORLD_SCALE)

func _is_plot(cell: Vector2i) -> bool:
	return bp.mask_has("cultivable", cell)

func _action_locked() -> bool:
	return (runner != null and runner.is_busy() and not runner.paused) or _emote_lock_s > 0.0

func _finish_brush() -> void:
	var cells := LabourBrush.trace(_drag_points, _projector())
	_drag_points = PackedVector2Array()
	_dragging = false
	if visitor:
		return
	_queue_plots(cells)

## 每格按自己的状态入队下一步。返回入队格数。
func _queue_plots(cells: Array) -> int:
	if visitor or cells.is_empty():
		return 0
	var unlocked := 4 if predictor and predictor.beds_unlocked == 4 else 3
	var plots := LabourBrush.filter_actionable(cells, bp, unlocked)
	var view := _cells_view()
	var now := _now()
	var added := 0
	for c in plots:
		var id := _id(c)
		if not view.has(id):
			continue
		var step := NextStep.step_for(view[id], now)
		if step.is_empty():
			continue
		if step == "sow" and NextStep.seeds_of(_state().get("inventory", {}), hud.selected_crop) == 0:
			hud.show_toast("No %s seeds left — buy some at the stall" % CropInfo.name_of(hud.selected_crop))
			continue
		runner.enqueue([c], step)
		added += 1
	if added > 0:
		hud.set_hint("")
	return added

## 点了一块现在没事可做的田：说清楚为什么。
func _explain_plot(cell: Vector2i) -> void:
	var id := _id(cell)
	var view := _cells_view()
	if not view.has(id):
		hud.show_toast(FarmHud.reject_text("CELL_LOCKED") if bp.reserved_bed().get("cells", []).has(cell) else FarmHud.reject_text("CELL_NOT_CULTIVABLE"))
		return
	var slot: Dictionary = view[id]
	if str(slot.get("state", "")) == "growing":
		var ra = slot.get("ready_at")
		var left := (int(ra) - _now()) if ra != null else -1
		_float_label(cell, "Growing · %s" % FarmHud.format_countdown(maxi(left, 0)), 1.5)

## 大按钮：对整片田做最该做的那件事。
func _on_cta() -> void:
	var bulk := _last_bulk
	if bulk.is_empty() or not bool(bulk.get("enabled", true)):
		return
	match str(bulk.action):
		"stall":
			_open_stall()
		"":
			pass
		_:
			if str(bulk.action) == "sow" and not str(bulk.get("crop", "")).is_empty():
				hud.selected_crop = str(bulk.crop)
			var cells: Array = []
			for id in bulk.cells:
				cells.append(_parse(str(id)))
			for c in cells:
				runner.enqueue([c], str(bulk.action))
			hud.set_hint("")

## 每格开工前：先本地校验，不合法就说原因、放弃这格；合法就先走到地头。
func _on_cell_started(cell: Vector2i, action: String) -> void:
	var id := _id(cell)
	if predictor:
		var r := predictor.check(NextStep.COMMAND.get(action, ""), _payload_for(action, [id]), _now())
		if not r.ok:
			hud.show_toast(FarmHud.reject_text(r.error))
			runner.abort_current()
			return
	var stand := _stand_cell_for(cell)
	if stand != Vector2i(-1, -1) and stand != mover.cell() and mover.set_target_cell(stand):
		runner.paused = true
		return
	_begin_work(cell, action)

## 走到了：面向那格、俯身、头顶浮字，2 秒计时开始。
func _begin_work(cell, action: String) -> void:
	if cell == null:
		return
	var target := bp.cell_to_world(cell, WORLD_SCALE)
	if target.distance_to(player.position) > 0.05:
		player.look_at(Vector3(target.x, player.position.y, target.z), Vector3.UP)
	var clip := AnimPlaceholders.clip_for(action)
	_play(clip)
	if AnimPlaceholders.is_placeholder(action) and _rig:
		AnimPlaceholders.play_fallback(_rig, ActionRunner.ACTION_S)
	_float_label(cell, NextStep.doing_label(action, hud.selected_crop, _field_condition()), ActionRunner.ACTION_S + 0.2)

## 田不可走，站到它旁边最近的可走格。找不到就原地干。
func _stand_cell_for(cell: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_len := INF
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = cell + d
		if not bp.is_walkable(n):
			continue
		var p := grid.path(mover.cell(), n)
		if p.is_empty():
			continue
		if p.size() < best_len:
			best_len = p.size()
			best = n
	return best

## 每格收工：先本地预测让格子立刻变样，再发命令，回包对账；被拒就回滚并说原因。
func _on_cell_done(cell: Vector2i, action: String) -> void:
	var id := _id(cell)
	var type := str(NextStep.COMMAND.get(action, ""))
	var payload := _payload_for(action, [id])
	if predictor:
		var r := predictor.predict(type, payload, _now())
		if r.ok:
			_render()
	if session == null:
		_refresh_hud()
		return
	var before := _state().duplicate(true)
	_in_flight += 1
	var accepted: bool = await session.send(type, payload)
	_in_flight -= 1
	if predictor:
		if accepted:
			predictor.commit(session.state.get("cells", {}), session.version)
		else:
			predictor.rollback()
	if accepted:
		_celebrate(action, before, cell)
	_render()

## 正反馈：收获了什么、第一次做到什么。
func _celebrate(action: String, before: Dictionary, cell: Vector2i) -> void:
	if action != "harvest":
		return
	var pb: Dictionary = before.get("inventory", {}).get("produce", {})
	var pa: Dictionary = _state().get("inventory", {}).get("produce", {})
	for c in pa:
		var gained := int(pa[c]) - int(pb.get(c, 0))
		if gained > 0:
			_float_label(cell, "+%d %s" % [gained, CropInfo.name_of(c)], 1.6)
	var xb := int(before.get("xp", {}).get("total", 0))
	var xa := int(_state().get("xp", {}).get("total", 0))
	if xa > xb:
		hud.show_toast("+%d XP" % (xa - xb))

func _payload_for(action: String, ids: Array) -> Dictionary:
	var p := {"cell_ids": ids}
	match action:
		"sow":
			p["crop"] = hud.selected_crop
			p["lot"] = NextStep.seed_lot(_state().get("inventory", {}), hud.selected_crop)
			p["field_condition"] = _field_condition()
		"care":
			p["kind"] = AnimPlaceholders.CARE_ACTION.get(_field_condition(), "water")
	return p

func _field_condition() -> String:
	if session == null:
		return "sunny"
	return str((session.state.get("clock", {}) as Dictionary).get("field_condition", "sunny"))

func _state() -> Dictionary:
	return session.state if session else {}

func _now() -> int:
	return session.server_now() if session else int(Time.get_unix_time_from_system() * 1000.0)

func _cells_view() -> Dictionary:
	return predictor.view() if predictor else {}

## 只含现在能动的格（预留畦扩地前不算）：大按钮别把锁着的格数进去。
func _actionable_view() -> Dictionary:
	var out := {}
	var v := _cells_view()
	for id in v:
		if predictor == null or predictor.is_unlocked(id):
			out[id] = v[id]
	return out

func _id(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

func _parse(id: String) -> Vector2i:
	var parts := id.split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-1, -1)

## 把（预测叠加后的）格子状态推给作物渲染。now_ms 必须是**服务端时间**。
func render_cells(cells: Dictionary, now_ms: int) -> void:
	if crop_field:
		crop_field.sync(cells, now_ms)

func _render() -> void:
	if predictor:
		render_cells(predictor.view(), _now())
	_refresh_hud()

## 把权威状态（叠上预测）刷到 HUD：金币、田况、倒计时、目标、大按钮、种子行。
func _refresh_hud() -> void:
	if hud == null or visitor:
		return
	var st := _state()
	var cells := _cells_view()
	var now := _now()
	hud.set_coins(int(st.get("wallet", 0)))
	hud.set_condition(_field_condition())
	hud.set_next_ripe(cells, now)
	hud.set_offline(session.offline if session else false)
	var chapter := int((st.get("clock", {}) as Dictionary).get("chapter_index", 0))
	var unlocked := CropUnlocks.unlocked(CropInfo.ORDER, chapter)
	var has_tilled := false
	for id in cells:
		if str((cells[id] as Dictionary).get("state", "")) == "tilled":
			has_tilled = true
			break
	hud.set_seeds(st.get("inventory", {}), unlocked, has_tilled)
	if session == null:
		_last_bulk = {"action": "", "cells": [], "label": "Offline — farm not connected", "enabled": false}
	else:
		_last_bulk = NextStep.bulk(_actionable_view(), now, st, hud.selected_crop, unlocked)
	hud.set_cta(_last_bulk)
	hud.set_goals(DayGoals.evaluate(st, cells), chapter)
	if stall and stall.visible:
		# 延后到帧末：refresh 会重建按钮，而这里可能正处在某个按钮的 pressed 回调里。
		stall.call_deferred("refresh", st, unlocked, STALL_BUDGET)

## 头顶/田头浮字：干活时说在干什么，收获时说得了什么。
func _float_label(cell: Vector2i, text: String, seconds: float) -> void:
	if _work_label and is_instance_valid(_work_label):
		# 不在任何信号回调里，直接 free：queue_free 要等帧末，测试里会积成一串孤儿。
		crops_root.remove_child(_work_label)
		_work_label.free()
	var label := Label3D.new()
	label.name = "WorkLabel"
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.01
	label.outline_size = 8
	label.modulate = Color.WHITE
	label.outline_modulate = DesignTokens.INK
	label.position = bp.cell_to_world(cell, WORLD_SCALE) + Vector3(0, 1.1, 0)
	crops_root.add_child(label)
	_work_label = label
	# 计时器做标签的子节点：标签被提前 free 时计时器一起走，不会留下捕获着死对象的 lambda
	#（自动玩家日志里刷屏的「Lambda capture at index 0 was freed」）。
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = seconds
	t.autostart = true
	t.timeout.connect(label.queue_free)
	label.add_child(t)

# —— 会话 ————————————————————————————————————————————————————————————————

## 接上服务端会话。允许通过 setup 参数注入（测试用），否则取全局 Net。
func _attach_session() -> void:
	if visitor:
		return
	var s: FarmSession = _args.get("session", Net.session if Net else null)
	if s == null or not s.has_farm():
		return
	session = s
	predictor = CellPredictor.from_blueprint(bp, session.state.get("cells", {}))
	predictor.beds_unlocked = int(session.state.get("beds_unlocked", 3))
	session.state_changed.connect(_on_server_state)
	session.offline_changed.connect(func(off): if hud: hud.set_offline(off))
	# 服务端拒绝必须说出来：静默回滚在玩家眼里就是「点了没反应」。
	session.rejected.connect(func(code, _detail): if hud: hud.show_toast(FarmHud.reject_text(code)))
	_render()

## 服务端每次回包都整体覆盖预测器；漂移一律以服务端为准（方案 §3 D4）。
func _on_server_state(state: Dictionary, version: int) -> void:
	if predictor:
		predictor.commit(state.get("cells", {}), version)
		predictor.beds_unlocked = int(state.get("beds_unlocked", 3))
	_render()

# —— 摊位 ————————————————————————————————————————————————————————————————

func _build_stall() -> void:
	stall = StallSheet.new()
	hud.add_child(stall)
	stall.sell_requested.connect(_on_sell)
	stall.buy_requested.connect(_on_buy)

func _open_stall() -> void:
	if stall == null:
		return
	var chapter := int((_state().get("clock", {}) as Dictionary).get("chapter_index", 0))
	stall.refresh(_state(), CropUnlocks.unlocked(CropInfo.ORDER, chapter), STALL_BUDGET)
	stall.open()

func _on_sell(items: Array) -> void:
	if session == null:
		return
	var before := int(_state().get("wallet", 0))
	var ok: bool = await session.send("sell_at_stall", {"items": items})
	if ok:
		var gained := int(_state().get("wallet", 0)) - before
		hud.show_toast("+%d coins" % gained)
	_render()

func _on_buy(crop: String, qty: int) -> void:
	if session == null:
		return
	var ok: bool = await session.send("buy_seeds", {"crop": crop, "qty": qty})
	if ok:
		hud.show_toast("Bought %d %s seeds" % [qty, CropInfo.name_of(crop)])
		hud.selected_crop = crop
	_render()

# —— 导演模式 ——————————————————————————————————————————————————————————————

## 入口：长按标题三秒。不额外占屏幕——QA 面板不该在正式玩家的界面上留按钮。
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
		var idx := int((session.state.get("clock", {}) as Dictionary).get("weather_day_index", 0))
		body = {"overrides": {str(idx): payload.get("day", "sunny")}}
	var accepted: bool = await session.send(type, body)
	director.report(accepted, session.last_error_code, session.player_id)
	if accepted:
		if predictor:
			predictor.commit(session.state.get("cells", {}), session.version)
		_render()

# —— 访客模式（PRD §3.3 / §8.4）——————————————————————————————————————————

func _enter_visitor_mode() -> void:
	title.text = "Visiting · %s" % SeededOutfit.short_name(str(snapshot.get("avatar_ref", "seed:unknown")))
	hud.set_visitor_mode(true)
	hud.set_condition(str(snapshot.get("weather_snapshot", "sunny")))
	hud.wave_pressed.connect(_wave)
	hud.stamp_pressed.connect(_stamp)
	if crop_field:
		crop_field.sync_snapshot(snapshot.get("cells", []))

func _wave() -> void:
	_emote_lock_s = 1.2
	_play(AnimPlaceholders.clip_for("wave"))
	if AnimPlaceholders.is_placeholder("wave") and _rig:
		AnimPlaceholders.play_wave_fallback(_rig, 1.2)

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
		old.free()
	player.add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", 2.6, STAMP_LIFETIME_S)
	tw.parallel().tween_property(label, "modulate:a", 0.0, STAMP_LIFETIME_S)
	tw.finished.connect(func(): if is_instance_valid(label): label.queue_free())

## 离开访客农场时把「完成过一次访问」报给服务端（零奖励）。D4 之前 CHAPTER_LOCKED 静默。
func _record_visit() -> void:
	if not visitor or Net == null or not Net.logged_in() or not Net.session.has_farm():
		return
	Net.session.send("record_visit_return", {"visited_farm_id": str(snapshot.get("farm_id", ""))})
