extends Node3D
## 私有农场实例（PRD §3.2 第二层）。
##
## 默认行走：点空地、耕地或作物只移动。明确选择劳作后，点按做下一步，长按拖动刷格。
## 客户端仅预测格子变化；物品、奖励与成熟时间仍由服务端确认。

const WORLD_SCALE := 1.0 # 逻辑米 → 世界米；G1 调观感时只改这里，时长不变量不受影响
const FarmProps = preload("res://modules/farm/farm_props.gd")
const FarmCamera = preload("res://modules/farm/farm_camera.gd")
const FarmScenery = preload("res://modules/farm/farm_scenery.gd")
const FarmArt = preload("res://modules/farm/farm_art.gd")
const MineArt = preload("res://modules/mining/mine_art.gd")
const AvatarFocus = preload("res://modules/ui/avatar_focus_button.gd")
const CAM_DIST := 11.0
## AvatarRig 的活动度控制默认 16 m 休眠动画。农场相机到玩家的距离约 18 m——不把阈值抬高，
## 走路和俯身动画就全没了（2026-09-04 晚真机：「动画完全丢失」）。
const RIG_SLEEP_DIST := 60.0
const RIG_REDUCED_DIST := 40.0
const CAM_PITCH_DEG := 43.0
const CAM_YAW_DEG := 14.5
## 地面是平的（田畦盒子随自由格子种田退役）；作物直接从 y=0 往上长。
const BED_H := 0.0
const STAMPS := ["Nice!", "Lovely", "Wow"]
const STAMP_LIFETIME_S := 1.2
const STALL_BUDGET := 100

## 矿洞位置来自布局的 mine 锚点，不写死世界坐标：原来的 (6.65, 0, -5.8) 是按旧 13m 场地
## 量出来的，换到 32m 场地后矿洞会杵在田中间——真机上它就落在玩家刚开垦的地旁边。
## 做成静态函数而不是成员，是因为矿井场景的测试按 `Farm.mine_approach()` 直接取值，
## 不实例化农场；FarmPlot.blueprint_for() 本身带静态缓存，重复调用不重读文件。
static func mine_position(plot: FarmBlueprint = null) -> Vector3:
	if plot == null: plot = FarmPlot.blueprint_for()
	return plot.cell_to_world(plot.anchor("mine"))

## 站位取锚点正南两格：锚点那格是 mine_mouth 的岩石、不可通行，南边两格是土。
## tests/mining/test_mine_scene.gd 会断言这一格可通行且从出生点走得到。
static func mine_approach(plot: FarmBlueprint = null) -> Vector3:
	if plot == null: plot = FarmPlot.blueprint_for()
	return plot.cell_to_world(plot.anchor("mine") + Vector2i(0, -2))

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
var life_sheet: PanelContainer
var _saved_farm_environment: Environment
var _stall_uncertain := false
var _connection_recovery_busy := false
var _pending_state_refresh := false
## 访客模式：只读、挥手、印章。零写入。
var visitor := false
var work_mode := false
var snapshot: Dictionary = {}
## 地理蓝图：只留给标题、选城与地图叠加；农场地面属性来自 FarmPlot。
var geo_blueprint: FarmBlueprint
var farm_activities: FarmActivities
var activity_sheet: PanelContainer
var _activity_pending := ""
var _activity_busy := false
var _activity_args: Dictionary = {}
var _relocate_button: Button
var _terrain_stale := false
var _terrain_refresh_busy := false
var _terrain_loading: CanvasLayer
var plot_surface: PlotSurface
## 长按刷子沿途命中的格；松手才真正提交。
## 当前被木本作物挡住的格；与新状态比对后只翻转差集。
var _woody_blocked: Dictionary = {}
var _brush_cells: Array = []
var _brush_points := PackedVector2Array()
var online: OnlineSpace
var _args := {}
var _rig: AvatarRig
var _anim := ""
var camera_pan := preload("res://modules/farm/scene_pan.gd").new()
var _emote_lock_s := 0.0
var _stamp_index := 0
## -1 表示没在按。曾经初值是 0.0，进农场 3 秒后导演面板自己弹出来（2026-09-04 录屏）。
var _title_hold := -1.0
## 当前这格的浮字（Label3D），干完就撤。
var _work_label: Label3D
var _last_bulk: Dictionary = {}
var _explicit_crop := ""
## 还没回包的命令数。>0 时队列不往下走：下一格的本地校验要看的是权威状态，不是一条
## 可能被服务端拒掉的预测（自动玩家：sow 被拒后紧跟的 care 照样发了出去）。
var _in_flight := 0
var _cta_was_busy := false
var hints: PlotHints
var _queued_move = null
## 走不动兜底用：上次记下的位置与静止累计时长。见 _watch_walk_stall。
var _walk_stall_pos := Vector3.ZERO
var _walk_stall_s := 0.0
var _field_center := Vector3.ZERO
var _camera_center := Vector3.ZERO
var _camera_initialized := false
var _camera_recenter: Tween
var _focus_button: Button
var scenery: Node3D
var farm_style := "cottage"
var _house_outline := PackedVector3Array()
var mine_entrance: Node3D
var _mine_pending := false
var fishing_panel: FishingPanel
var fishing_view: FishingPresentation
var fishing_site: Dictionary = {}
var _fishing_pending := false
var _fishing_plan: Dictionary = {}
## 每秒重画一次：成熟是时间派生的，没有回包也没有输入会通知它——不定时刷，倒计时不走、
## 作物不变高、大按钮永远停在「Crops are growing」（自动玩家第四轮等了 260 秒）。
var _tick := 0.0
const TICK_S := 1.0
var _chapter_seen_index := -1
var _chapter_seen_complete := false
var _chapter_refresh_busy := false
var _next_chapter_refresh_ticks := 0

@onready var cam: Camera3D = $Camera3D
@onready var ground: MeshInstance3D = $Ground
@onready var props: Node3D = $Props
@onready var crops_root: Node3D = $Crops
@onready var player: Node3D = $Player
@onready var title: Button = %Title
@onready var exit_btn: Button = %ExitButton
@onready var hud: FarmHud = %Hud

func setup(args: Dictionary) -> void:
	_args = args

func _ready() -> void:
	# Each stacked farm owns its environment. Multiple BG_CANVAS layers at -1 can cover the new 3D view.
	get_viewport().transparent_bg = false
	var own_environment := ($WorldEnvironment.environment as Environment).duplicate() as Environment
	own_environment.background_mode = Environment.BG_COLOR
	$WorldEnvironment.environment = own_environment
	$FarmBackground.hide()
	# 压栈进入的新实例不会经过 AppRouter 的 suspend/resume 协议；自己的相机要自己抢
	# （2026-09-04 终审 C1）。
	cam.make_current()
	$HUD/SafeArea.theme = GameUi.theme()
	exit_btn.text = ""
	exit_btn.icon = GameUi.icon("arrow-left")
	exit_btn.tooltip_text = L10n.text("Return")
	exit_btn.custom_minimum_size = Vector2(44, 44)
	title.theme_type_variation = &"ChoiceButton"
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.icon = GameUi.icon("sprout")
	title.clip_text = true
	title.add_theme_constant_override("icon_max_width", 22)
	title.custom_minimum_size = Vector2(88, 44)
	hud.attach_status_to($HUD/SafeArea/Root/TopBar)
	title.add_theme_color_override("font_color", GameUi.INK)
	visitor = bool(_args.get("visitor", false))
	snapshot = _args.get("snapshot", {})
	var terrain: Dictionary = snapshot.get("farm_terrain", {}) if visitor else {}
	bp = _args.get("blueprint")
	# 服务端农场的蓝图优先于本地选的：本地选了 sh_b、服务端农场是 sh_c 时，客户端按 sh_b 进场，
	# 发出去的每一格都 CELL_NOT_CULTIVABLE，草还画在别的坐标上（2026-09-04 真机）。
	if not visitor:
		var s0: FarmSession = _args.get("session", Net.session if Net else null)
		if s0 and s0.has_farm() and not s0.layout_patch_id.is_empty():
			terrain = s0.farm_terrain
			var server_bp := FarmBlueprint.load_choice(s0.farm_choice())
			if server_bp != null:
				bp = server_bp
				# FarmSession owns saving generated choices; do not drop its persisted terrain.
				if terrain.is_empty(): FarmChoice.save(s0.layout_patch_id, s0.blueprint_revision, s0.location)
	if visitor and not terrain.is_empty():
		bp = FarmBlueprint.load_choice(snapshot)
	if bp == null:
		bp = FarmBlueprint.load_file(FarmBlueprint.asset_path(
			str(_args.get("layout_patch_id", "")), int(_args.get("revision", 1))))
	if bp == null:
		push_error("Farm: 缺少蓝图，退出实例")
		call_deferred("_leave")
		return
	if visitor and snapshot.get("location") is Dictionary:
		bp = bp.with_location(snapshot.location)
	geo_blueprint = bp
	bp = FarmPlot.register_terrain(terrain) if not terrain.is_empty() else FarmPlot.blueprint_for()
	if bp == null:
		push_error("Farm: invalid persisted terrain")
		call_deferred("_leave")
		return
	fishing_site = FishingModel.site_for_plot("farm_pond", bp)
	grid = BlueprintGrid.new(bp)
	_frame_field()
	var lawn := PlaneMesh.new()
	lawn.size = Vector2.ONE * 96.0 * WORLD_SCALE
	ground.mesh = lawn
	ground.position = Vector3(bp.play_area_m * 0.5, -0.008, -bp.play_area_m * 0.5)
	var grass := ShaderMaterial.new()
	grass.shader = preload("res://modules/farm/shaders/meadow.gdshader")
	grass.set_shader_parameter("meadow_texture", preload("res://assets/farm/art/meadow.png"))
	grass.set_shader_parameter("woodland_start", -bp.cell_to_world(bp.anchor("house")).z + 3.75)
	ground.material_override = grass
	farm_style = FarmArt.style_for(geo_blueprint.region_id, geo_blueprint.layout_patch_id,
		str(_args.get("farm_style", terrain.get("farm_style", ""))))
	_build_props()
	_build_mine_entrance()
	scenery = FarmScenery.new()
	add_child(scenery)
	scenery.build(bp, farm_style)
	add_child(FishingWater.build("farm_pond", fishing_site))
	# 作物挂 Crops（Props 的同级）：prop_count() 只数锚点原语与畦面，作物不进去。
	# 地面状态层：取代逐格动作图标，用一张 64×64 纹理喂给 shader，1 个 draw call。
	plot_surface = PlotSurface.new(bp, WORLD_SCALE)
	add_child(plot_surface)
	crop_field = CropField.new(bp, WORLD_SCALE)
	crop_field.ground_y = BED_H * WORLD_SCALE
	crops_root.add_child(crop_field)
	mover = PlayerMover.new(bp, grid, WORLD_SCALE)
	runner = ActionRunner.new()
	runner.duration_for = func(cell: Vector2i, action: String):
		if action != "harvest": return ActionRunner.ACTION_S
		var crop := str(_state().get("cells", {}).get(_id(cell), {}).get("crop", ""))
		return CharacterModel.gather_seconds(_state(), "wood" if CropInfo.is_woody(crop) else "crop", ActionRunner.ACTION_S)
	runner.cell_started.connect(_on_cell_started)
	runner.cell_done.connect(_on_cell_done)
	runner.queue_empty.connect(func(): _refresh_hud())
	hints = PlotHints.new()
	hints.name = "PlotHints"
	hints.cam = cam
	hints.bp = bp
	$HUD/SafeArea/Root.add_child(hints)
	$HUD/SafeArea/Root.move_child(hints, 0)
	_spawn_player()
	_build_focus_button()
	camera_pan.free_pan = true
	camera_pan.tapped.connect(_tap_scene)
	# 长按起刷：按住一块地 0.28 秒后拖动，沿轨迹连续开垦/播种/浇水/收割。
	# 单指拖动仍然是相机平移，双指仍然是缩放——肌肉记忆不变。
	camera_pan.hold_enabled = false
	camera_pan.hold_began.connect(_brush_begin)
	camera_pan.hold_moved.connect(_brush_move)
	camera_pan.hold_ended.connect(_brush_end)
	camera_pan.hold_canceled.connect(_discard_brush)
	_attach_session()
	fishing_panel = FishingPanel.new()
	add_child(fishing_panel)
	fishing_panel.opened.connect(_begin_fishing_view)
	fishing_panel.closed.connect(_end_fishing_view)
	var fish_button := GameUi.button("fish", L10n.text("Go fishing"), L10n.text("Go fishing"))
	fish_button.name = "GoFishing"
	fish_button.pressed.connect(func():
		hud.close_modal()
		_go_fishing())
	hud.add_farm_action(fish_button)
	_relocate_button = GameUi.button("map-pin", L10n.text("Relocate farm"), L10n.text("Choose a new farm location · one chance"))
	_relocate_button.name = "RelocateFarm"
	_relocate_button.add_theme_font_size_override("font_size", 12)
	_relocate_button.pressed.connect(func():
		hud.close_modal()
		_begin_relocation())
	hud.add_farm_action(_relocate_button)
	title.text = L10n.text("My Farm")
	title.tooltip_text = title.text
	hud.set_farm_title(title.text)
	title.pressed.connect(hud.open_farm_actions)
	exit_btn.pressed.connect(_leave)
	hud.work_mode_changed.connect(_set_work_mode)
	hud.cta_pressed.connect(_on_cta)
	hud.cancel_pressed.connect(_cancel_work)
	hud.seed_selected.connect(_on_seed_selected)
	hud.reconnect_pressed.connect(_recover_connection)
	hud.stall_pressed.connect(_open_stall)
	hud.life_pressed.connect(_open_life)
	player.position = mover.position
	_update_camera()
	if visitor:
		_enter_visitor_mode()
	else:
		_build_director()
		_build_stall()
		farm_activities = FarmActivities.new()
		farm_activities.setup(bp)
		add_child(farm_activities)
		farm_activities.sync(_state())
		hud.set_hint(L10n.text("Tap a plot to work it"))
	_refresh_hud()
	if not visitor: focus_destination.call_deferred(_args)
	var live_session: FarmSession = Net.session if visitor else session
	if live_session and live_session.logged_in():
		var online_args := {"farm_id": str(snapshot.get("farm_id", "")) if visitor else session.farm_id}
		online_args.merge(_args.get("online_join", {}), true)
		online_args.terrain_checksum = bp.checksum
		online = OnlineSpace.attach(self, live_session, "farm", online_args,
			func(): return mover, func(): return _anim)
		online.farm_relocated.connect(_on_farm_relocated)

func _begin_relocation() -> void:
	if visitor or session == null or not session.relocation_available(): return
	if not party_travel_ready() or session.offline or session.has_unconfirmed_command():
		hud.show_toast(L10n.text("Finish your current work first"), true)
		return
	AppRouter.begin_farm_relocation(session, self)

func _on_farm_relocated() -> void:
	_terrain_stale = true
	if online: online.stop()
	if mover: mover.stop()
	if runner: runner.cancel_pending()
	_set_work_mode(false)
	_reload_relocated_farm.call_deferred()

func _own_terrain_changed() -> bool:
	if visitor or session == null or geo_blueprint == null: return false
	return not session.layout_patch_id.is_empty() and session.layout_patch_id != geo_blueprint.layout_patch_id

func _reload_relocated_farm() -> void:
	if _terrain_refresh_busy or process_mode == Node.PROCESS_MODE_DISABLED or AppRouter.top_instance() != self: return
	_terrain_refresh_busy = true
	if _terrain_loading == null:
		_terrain_loading = preload("res://modules/ui/loading_overlay.gd").new()
		add_child(_terrain_loading)
		_terrain_loading.close_button.pressed.connect(_leave)
	hud.show_toast(L10n.text("This farm has moved. Reloading its new ground…"))
	var args: Dictionary = {"session": session}
	var ok := false
	if visitor:
		var response := await Net.snapshot(str(snapshot.get("farm_id", "")))
		if not is_inside_tree(): return
		ok = bool(response.get("ok", false))
		if ok:
			var updated: Dictionary = response.snapshot
			var blueprint := FarmBlueprint.load_choice(updated)
			ok = blueprint != null
			args = {"visitor": true, "snapshot": updated, "blueprint": blueprint}
	else:
		ok = await session.refresh()
		if not is_inside_tree(): return
		if ok:
			FarmChoice.save_choice(session.farm_choice())
			var root_map := get_tree().current_scene
			if root_map and root_map.has_method("refresh_owned_farm_after_relocation"):
				root_map.call("refresh_owned_farm_after_relocation", session.farm_choice())
	if ok:
		hud.close_modal()
		# Keep the stale-scene guard until replacement has actually completed. A DTO
		# adoption emits state_changed and may have queued another reload callback.
		await AppRouter.replace_farm_instance(self, args)
		if not is_inside_tree(): return
	hud.show_toast(L10n.text("Could not connect. Reconnect and try again."), true)
	_terrain_loading.failed()
	_terrain_refresh_busy = false

func _leave() -> void:
	if _activity_busy or (activity_sheet and activity_sheet.is_busy()): return
	_record_visit()
	AppRouter.pop_instance()

## Called by historical street goals and router redirects; reuse this private instance.
func focus_destination(args: Dictionary) -> void:
	if visitor or session == null or farm_activities == null or not party_travel_ready(): return
	if session.offline or session.has_unconfirmed_command():
		hud.show_toast(SessionPanel.error_text("PENDING_ACTION"), true)
		return
	var target := str(args.get("target", ""))
	var seed_crop := str(args.get("seed_crop", ""))
	var plant_crop := str(args.get("plant_crop", ""))
	if CropInfo.ORDER.has(plant_crop):
		hud.selected_crop = plant_crop
		_on_seed_selected(plant_crop)
	if target == "stall" or CropInfo.ORDER.has(seed_crop):
		_open_stall(seed_crop)
		return
	if target == "mine":
		_go_mine()
		return
	if target in ["", "farm"] and str(args.get("walk_place", args.get("place", ""))) in ["", "farm"] and not args.has("resident"): return
	farm_activities.sync(_state())
	if not farm_activities.targets.has(target):
		var place := str(args.get("walk_place", args.get("place", "")))
		if args.has("resident"):
			target = "resident:" + str(StreetCommons.RESIDENTS.find_key(str(args.resident)))
		elif not place.is_empty():
			for id in farm_activities.targets:
				var entry: Dictionary = farm_activities.targets[id]
				if entry.kind == "resource" and entry.place == place:
					target = id
					break
	if not farm_activities.targets.has(target):
		# Indoor work areas remain available from farm signposts.
		var place := str(args.get("place", ""))
		if place in ["nursery", "bistro", "courtyard"]:
			AppRouter.open_instance(AppRouter.PLACE, {"session": session, "place_id": place, "target": target})
		return
	hud.close_modal()
	_set_work_mode(false)
	var destination: Vector3 = farm_activities.targets[target].approach
	_on_ground_tapped(destination)
	_activity_args = args.duplicate(true)
	if mover.position.distance_to(destination) < 0.5:
		_arrive_activity(target)
	elif mover.is_moving():
		_activity_pending = target

func _arrive_activity(id: String) -> void:
	if visitor or session == null or not farm_activities.targets.has(id): return
	var target: Dictionary = farm_activities.targets[id]
	mover.stop()
	_clear_brush()
	match str(target.kind):
		"place":
			AppRouter.open_instance(AppRouter.PLACE, {"session": session, "place_id": str(target.place)})
		"resource":
			_collect_activity(target.bundle)
		"resident":
			var panel := JourneyActivityPanel.new()
			panel.place_id = "street" # Historical command identity, no public room.
			panel.target = "resident:" + str(target.resident)
			panel.prefer_timber_only = str(_activity_args.get("request_timber_slot", _activity_args.get("change_request", ""))) == id.trim_prefix("resident:")
			panel.goal_requested.connect(_activity_goal)
			panel.destination_requested.connect(func(place): _activity_goal({"place": place, "target": place}))
			panel.target_requested.connect(func(target_id): _activity_goal({"place": str(target.place), "target": target_id}))
			panel.requests_requested.connect(func():
				hud.close_modal()
				_open_life()
				if life_sheet and life_sheet.active is BagPanel: life_sheet.active.select_page("requests"))
			_show_activity_panel(panel)
			panel.command("talk_to_resident", {"resident_id": str(target.resident)}, "")
		"gathering":
			var panel := JourneyGatheringPanel.new()
			panel.theme_id = str(target.theme)
			panel.goal_requested.connect(_activity_goal)
			_show_activity_panel(panel)

func _collect_activity(bundle: Dictionary) -> void:
	if _activity_busy or session.has_unconfirmed_command(): return
	_activity_busy = true
	var round_id := int(session.state.journey.exploration.round)
	var materials: Dictionary = bundle.materials
	_play("labour_till" if materials.has("stone") else "labour_clear")
	await get_tree().create_timer(CharacterModel.gather_seconds(session.state, CharacterModel.resource_kind(materials))).timeout
	if not is_inside_tree(): return
	var accepted := await session.send("collect_resource", {"node_id": bundle.node, "round": round_id, "choice": bundle.choice})
	if not is_inside_tree(): return
	_activity_busy = false
	_play("idle")
	hud.show_toast("+" + JourneyProgress.material_label(materials) if accepted else SessionPanel.error_text(session.last_error_code), not accepted)
	farm_activities.sync(_state())
	_refresh_hud()

func _show_activity_panel(panel: SessionPanel) -> void:
	if activity_sheet == null:
		activity_sheet = preload("res://scenes/farm/farm_activity_sheet.gd").new()
		hud.add_child(activity_sheet)
		activity_sheet.closed.connect(hud.close_modal)
	panel.setup(session)
	activity_sheet.show_panel(panel)
	hud.show_modal(activity_sheet)

func _activity_goal(goal: Dictionary) -> void:
	if activity_sheet and activity_sheet.is_busy(): return
	hud.close_modal()
	if goal.get("place") == "farm":
		var destination := goal.duplicate(true)
		if goal.get("action") == "stall":
			destination.target = "stall"
			destination.seed_crop = str(goal.get("crop", ""))
		elif goal.get("action") == "sow" and goal.has("crop"):
			destination.plant_crop = str(goal.crop)
		focus_destination(destination)
		return
	if goal.get("surface") == "street" or goal.get("place") == "street" or goal.has("resident"):
		focus_destination(goal)
	else:
		AppRouter.open_instance(AppRouter.PLACE, {"session": session, "place_id": str(goal.get("place", "nursery")), "target": str(goal.get("target", ""))})

func prop_count() -> int:
	return props.get_child_count()

func _build_props() -> void:
	var s := WORLD_SCALE
	for kind in ["house", "storage", "well"]:
		props.add_child(FarmProps.build(kind, bp.cell_to_world(bp.anchor(kind), s), s, farm_style))
	var house := props.get_node("House") as MeshInstance3D
	# Compute the hull once. A box includes empty space above the eaves and shrinks touch targets.
	for point in house.mesh.create_convex_shape(true, true).points:
		_house_outline.append(house.transform * point)
	_house_outline.append(house.position + Vector3(-0.53, house.mesh.get_aabb().end.y + 0.45, -0.37))
	if farm_style == "windmill":
		_house_outline.append(house.position + Vector3(0, 3.55, 1.28))

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
	Avatar.follow_saved_outfit(_rig)

func _build_mine_entrance() -> void:
	mine_entrance = MineArt.entrance()
	mine_entrance.position = mine_position(bp)
	mine_entrance.scale = Vector3.ONE * 0.7
	add_child(mine_entrance)

func _begin_fishing_view(_site: String) -> void:
	_stop_camera_recenter()
	_end_fishing_view()
	fishing_view = FishingPresentation.new()
	add_child(fishing_view)
	fishing_view.configure(fishing_panel, player, _rig, cam,
		[$HUD/SafeArea/Root, online.hud if online else null])

func _end_fishing_view() -> void:
	if is_instance_valid(fishing_view): fishing_view.finish()
	fishing_view = null

func _go_fishing(clicked := Vector3.INF) -> void:
	if _terrain_stale: return
	if _activity_busy: return
	_activity_pending = ""
	var own_session: FarmSession = online.session if online else session
	if _in_flight > 0 or own_session == null or _connection_recovery_busy: return
	if not CharacterModel.has_fishing_rod(own_session.state):
		hud.show_toast(L10n.text("Equip a fishing rod on the character page first."), true)
		return
	if own_session.offline or own_session.has_unconfirmed_command():
		hud.show_toast(L10n.text("Check previous action"), true)
		return
	hud.close_modal()
	_cancel_work()
	runner.abort_current()
	runner.paused = false
	_mine_pending = false
	_set_work_mode(false)
	_fishing_plan = FishingModel.plan("farm_pond", mover.position, clicked, grid, fishing_site)
	if _fishing_plan.is_empty():
		hud.show_toast(L10n.text("Can't reach that spot"), true)
		return
	var target: Vector3 = _fishing_plan.origin
	_fishing_pending = mover.set_target_position(target)
	if hints: hints.destination(target, _fishing_pending, mover.remaining_path())
	if not _fishing_pending: hud.show_toast(L10n.text("Can't reach that spot"), true)

func _go_mine() -> void:
	if _terrain_stale: return
	if _activity_busy: return
	if fishing_panel and fishing_panel.visible: return
	_fishing_pending = false
	var connected: FarmSession = online.session if visitor and online else session
	if connected == null or (visitor and not Net.online_available): return
	if connected.offline or connected.has_unconfirmed_command():
		hud.show_toast(L10n.text("Check the connection to continue mining"), true)
		return
	if (runner and runner.is_busy()) or _in_flight > 0:
		hud.show_toast(L10n.text("Finish your current work first"), true)
		return
	hud.close_modal()
	_on_ground_tapped(mine_approach(bp))
	_mine_pending = mover.is_moving()
	if not _mine_pending and mover.position.distance_to(mine_approach(bp)) < 0.4:
		AppRouter.open_instance(AppRouter.mine_scene(), {"session": connected})

func _pick_mine(point: Vector2) -> bool:
	if (visitor and (online == null or not Net.online_available)) or _world_modal_open(): return false
	return _mine_pick_rect().has_point(point)

func _mine_pick_rect() -> Rect2:
	if not is_instance_valid(mine_entrance) or not mine_entrance.is_visible_in_tree(): return Rect2()
	var model := mine_entrance.get_node_or_null("MineArch") as MeshInstance3D
	if model == null or not model.is_visible_in_tree(): return Rect2()
	var bounds := model.get_aabb()
	var rect := Rect2()
	for corner in 8:
		var world := model.global_transform * bounds.get_endpoint(corner)
		if cam.is_position_behind(world): return Rect2()
		var point := cam.unproject_position(world)
		rect = Rect2(point, Vector2.ZERO) if corner == 0 else rect.expand(point)
	if not rect.has_area(): return rect
	# Match the visible arch and rails, with the same minimum touch area as mine models.
	var touch_size := Vector2(maxf(44, rect.size.x + 12), maxf(44, rect.size.y + 12))
	return Rect2(rect.get_center() - touch_size * 0.5, touch_size).intersection(_camera_play_area())

func _play(anim: String) -> void:
	if _rig == null: return
	_rig.play_motion(anim)
	_anim = anim

func _process(dt: float) -> void:
	if _focus_button and (_terrain_stale or _world_modal_open() or (fishing_panel and fishing_panel.visible)):
		_focus_button.hide()
	if _terrain_stale:
		if mover: mover.stop()
		return
	if mover == null:
		return
	if online and online.travel_busy:
		# 这一支只想跳过劳作与 HUD 的处理，**不能**把人冻在半路：mover.step 是全场唯一
		# 推进移动的地方，跳过它 is_moving() 就永远为真，runner.paused 也就永远清不掉，
		# 队列会一直停在「正在前往…」（真机 2026-09-17 两次复现，掉线重连时触发）。
		mover.step(dt)
		player.position = mover.position
		if runner and _in_flight == 0: runner.step(dt)
		_update_camera(dt)
		return
	if fishing_panel and fishing_panel.visible:
		mover.stop()
		player.position = mover.position
		return
	if _activity_busy: return
	if _world_modal_open(): _clear_brush()
	if session: mover.speed = CharacterModel.current(session.state, "move_speed")
	elif online and online.session: mover.speed = CharacterModel.current(online.session.state, "move_speed")

	camera_pan.step(dt, cam)
	mover.step(dt)
	player.position = mover.position
	if not _activity_pending.is_empty() and not mover.is_moving():
		var arrived := _activity_pending
		_activity_pending = ""
		if farm_activities and farm_activities.targets.has(arrived) and player.position.distance_to(farm_activities.targets[arrived].approach) < 0.5:
			_arrive_activity(arrived)
	_watch_walk_stall(dt)
	if _fishing_pending and not mover.is_moving():
		_fishing_pending = false
		if not _fishing_plan.is_empty() and player.position.distance_to(_fishing_plan.origin) < 0.3:
			_clear_brush()
			_play("idle")
			fishing_panel.open(online.session if online else session, "farm_pond", _fishing_plan.target, fishing_site)
			return
	if _mine_pending and not mover.is_moving() and not runner.is_busy() and _in_flight == 0:
		_mine_pending = false
		AppRouter.open_instance(AppRouter.mine_scene(), {"session": online.session if visitor and online else session})
		return
	if runner and _in_flight == 0:
		# 先走到地头：到了才开工。
		if runner.paused and not mover.is_moving():
			runner.paused = false
			_begin_work(runner.current_cell(), runner.current_action())
		runner.step(dt)
	if _emote_lock_s > 0.0:
		_emote_lock_s -= dt
	# 劳作中锁住动画，避免被移动或待机动画覆盖。
	if not _action_locked():
		if mover.is_moving():
			player.look_at(player.position + mover.facing, Vector3.UP)
			_play("run")
		else:
			_play("idle")
	elif mover.is_moving():
		player.look_at(player.position + mover.facing, Vector3.UP)
	if hud and runner and not visitor:
		var doing := ""
		if runner.is_busy() and not runner.paused:
			doing = NextStep.doing_label(runner.current_action(), hud.selected_crop)
		elif runner.is_busy():
			# 暂停中有两种：真在赶路，和在等上一条命令的回包。两种都写「正在前往」，
			# 网络一卡就看起来像人走不动了——真机验收时正是被这条误导的。
			# 字面量要和词表的键逐字一致（三个点，不是省略号字符），否则翻译查不到。
			doing = L10n.text("Walking...") if mover.is_moving() else L10n.text("Syncing...")
		hud.set_action(doing, runner.progress(), runner.pending_count())
		var busy_now := runner.is_busy() or _in_flight > 0
		if busy_now != _cta_was_busy:
			_cta_was_busy = busy_now
			hud.set_cta_busy(runner.pending_count() if busy_now else 0)
			if not busy_now:
				_refresh_hud()
		elif busy_now:
			hud.set_cta_busy(runner.pending_count())
	if _queued_move != null and not runner.is_busy() and _in_flight == 0:
		var move: Vector3 = _queued_move
		_queued_move = null
		_on_ground_tapped(move)
	_tick_title_hold(dt)
	_tick += dt
	if _tick >= TICK_S and not visitor and predictor:
		_tick = 0.0
		_render()
	_update_camera(dt)
	if hints:
		hints.active = runner.current_cell()
		hints.progress = runner.progress()
		hints.world_rect = _camera_play_area()
		hints.visible = not _world_modal_open()
		hints.update_motion(mover.is_moving(), mover.remaining_path(), dt)

## 走不动的兜底。`runner.paused` 只在「走到了」时清除，而「走到了」完全依赖 mover 推进——
## 任何让 mover 停下来的原因（提前返回、场景被挂起、路径被外部清空）都会把队列永久钉在
## 「正在前往…」上，玩家除了点取消没有别的出路。位置连续不动超过阈值就主动停表：
## is_moving() 转 false，下一帧照常在当前位置开工，而不是无限期等下去。
func _watch_walk_stall(dt: float) -> void:
	if runner == null or not runner.is_busy() or not runner.paused or _in_flight > 0:
		_walk_stall_s = 0.0
		return
	if mover.position.distance_to(_walk_stall_pos) > 0.01:
		_walk_stall_pos = mover.position
		_walk_stall_s = 0.0
		return
	_walk_stall_s += dt
	if _walk_stall_s >= WALK_STALL_S:
		_walk_stall_s = 0.0
		mover.stop()

func _build_focus_button() -> void:
	_focus_button = AvatarFocus.new()
	$HUD/SafeArea/Root.add_child(_focus_button)
	_focus_button.pressed.connect(recenter_on_player)

func _update_camera(_delta := 0.0) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	var view_width := VIEW_M * 1.2 if viewport_size.y < 700 and viewport_size.x < 600 else VIEW_M
	cam.size = maxf(view_width, 7.2 * aspect) * WORLD_SCALE / camera_pan.zoom
	if not _camera_initialized:
		_camera_center = player.position + Vector3.UP * 0.7
		_camera_initialized = true
	# Released pan and zoom-anchor adjustments become the persistent view position.
	if not camera_pan.active():
		_camera_center += camera_pan.offset
		camera_pan.offset = Vector3.ZERO
		camera_pan._raw_offset = Vector3.ZERO
	_place_camera(_camera_center)
	cam.position += camera_pan.offset
	FarmCamera.fit_ground_depth(cam)
	_update_focus_indicator()

func _update_focus_indicator() -> void:
	if _focus_button == null or player == null or cam == null: return
	var viewport_rect := get_viewport().get_visible_rect()
	var point := player.position + Vector3.UP * 0.7
	var behind := cam.is_position_behind(point)
	var projected := cam.unproject_position(point)
	if behind or not projected.is_finite():
		# Perspective projection flips points behind the lens. Camera-local axes
		# retain their true direction and also handle the orthographic edge case.
		var local := cam.to_local(point)
		var direction := Vector2(local.x, -local.y)
		if direction.is_zero_approx(): direction = Vector2.DOWN
		projected = viewport_rect.get_center() + direction.normalized() * viewport_rect.size.length()
	_focus_button.update_indicator(projected, viewport_rect, _camera_play_area(), behind,
		_terrain_stale or _world_modal_open() or (fishing_panel != null and fishing_panel.visible))

func _place_camera(center: Vector3) -> void:
	var phi := deg_to_rad(CAM_PITCH_DEG)
	var yaw := deg_to_rad(CAM_YAW_DEG)
	cam.position = center + Vector3(sin(yaw) * CAM_DIST * cos(phi), CAM_DIST * sin(phi), cos(yaw) * CAM_DIST * cos(phi))
	cam.look_at(center, Vector3.UP)

func _stop_camera_recenter() -> void:
	if _camera_recenter:
		_camera_recenter.kill()
		_camera_recenter = null

func recenter_on_player() -> void:
	if player == null or _terrain_stale or _world_modal_open() or (fishing_panel and fishing_panel.visible): return
	_stop_camera_recenter()
	_clear_brush()
	_camera_center += camera_pan.offset
	camera_pan.offset = Vector3.ZERO
	camera_pan._raw_offset = Vector3.ZERO
	var start := _camera_center
	_camera_recenter = create_tween()
	_camera_recenter.tween_method(func(weight: float):
		_camera_center = start.lerp(player.position + Vector3.UP * 0.7, weight)
		_update_camera(), 0.0, 1.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _camera_play_area() -> Rect2:
	if hud == null or hud.size.x < 48 or hud.size.y < 200: return Rect2()
	var top := hud.top_content_bottom() + 4
	var bottom := hud.get_global_rect().end.y - 4
	if visitor and hud._visitor_bar.visible: bottom = minf(bottom, hud._visitor_bar.global_position.y - 4)
	elif hud._bottom.visible: bottom = minf(bottom, hud._bottom.global_position.y - 4)
	return Rect2(hud.global_position.x + 4, top, hud.size.x - 8, maxf(0, bottom - top))

func _world_modal_open() -> bool:
	return (hud != null and hud.modal_open()) or GameUi.modal_is_open(self)

## 约 6m 横向近景，对应参考图中可辨认的人物、房屋与身边几块田。
const VIEW_M := 6.0
## 赶路卡住时终止本格，避免队列永久等待。
const WALK_STALL_S := 2.5

func _frame_field() -> void:
	_field_center = bp.cell_to_world(bp.anchor("spawn"), WORLD_SCALE)

## Taps work plots or move the player; drags pan the scene, including visitor farms.
func _input(e: InputEvent) -> void:
	if _world_modal_open():
		_clear_brush()
		return
	if _terrain_stale: return
	if _activity_busy: return
	if fishing_panel and fishing_panel.visible: return
	if online and (online.travel_busy or is_instance_valid(online.panel)): return
	if mover == null: return
	if camera_pan.handle(e, cam):
		_stop_camera_recenter()
		_update_camera(get_process_delta_time())
		get_viewport().set_input_as_handled()

func _unhandled_input(e: InputEvent) -> void:
	if _terrain_stale: return
	if _activity_busy: return
	if fishing_panel and fishing_panel.visible: return
	if online and (online.travel_busy or is_instance_valid(online.panel)): return
	if mover == null or _world_modal_open(): return
	if camera_pan.handle(e, cam, true):
		_stop_camera_recenter()
		_update_camera(get_process_delta_time())
		get_viewport().set_input_as_handled()

func _brush_begin(point: Vector2) -> void:
	if not work_mode or visitor or _world_modal_open(): return
	_brush_points = PackedVector2Array([point])
	_brush_cells = LabourBrush.filter_actionable(LabourBrush.trace(_brush_points, _projector()), bp)
	_render()

func _brush_move(point: Vector2) -> void:
	if not work_mode or visitor or _brush_points.is_empty(): return
	_brush_points.append(point)
	_brush_cells = LabourBrush.filter_actionable(LabourBrush.trace(_brush_points, _projector()), bp)
	_render()

func _brush_end(point: Vector2) -> void:
	if not work_mode or visitor or _brush_points.is_empty(): return
	_brush_points.append(point)
	var cells := LabourBrush.filter_actionable(LabourBrush.trace(_brush_points, _projector()), bp)
	_brush_points = PackedVector2Array()
	_brush_cells = []
	if cells.is_empty():
		_render()
		return
	_queue_plots(cells)

func _tap_scene(point: Vector2) -> void:
	if _activity_busy or _world_modal_open(): return
	if fishing_panel and fishing_panel.visible: return
	var fishing_hit = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(point), cam.project_ray_normal(point))
	if fishing_hit is Vector3 and FishingModel.contains("farm_pond", fishing_hit, 0.0, fishing_site):
		_go_fishing(fishing_hit)
		return
	if _pick_mine(point):
		_go_mine()
		return
	if farm_activities and not work_mode:
		var activity := farm_activities.pick(cam, point, _camera_play_area())
		if not activity.is_empty():
			focus_destination({"target": activity})
			return
	var hit = _projector().call(point)
	if hit != null:
		if _is_plot(hit as Vector2i):
			_tap_cell(hit as Vector2i)
		else:
			var world = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(point), cam.project_ray_normal(point))
			if world is Vector3: _on_ground_tapped(world)

func _clear_brush() -> void:
	camera_pan.cancel()
	_discard_brush()

func _discard_brush() -> void:
	_brush_points = PackedVector2Array()
	_brush_cells.clear()
	if plot_surface: plot_surface.highlight(runner.queued_cells() if runner else [], [], runner.current_cell() if runner else null)

func _set_work_mode(enabled: bool) -> void:
	work_mode = enabled and not visitor
	_clear_brush()
	camera_pan.hold_enabled = work_mode
	if not work_mode and runner: _cancel_work()
	hud.set_work_mode(work_mode)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _clear_brush()

func _tap_cell(cell: Vector2i) -> void:
	if _is_plot(cell) and work_mode and not visitor:
		if _queue_plots([cell]) == 0:
			_explain_plot(cell)
	else:
		_on_ground_tapped(bp.cell_to_world(cell, WORLD_SCALE))

func _on_ground_tapped(world: Vector3) -> void:
	if _activity_busy: return
	_activity_pending = ""
	if fishing_panel and fishing_panel.visible: return
	_fishing_pending = false
	_mine_pending = false
	# 退场帧内测试/输入可能直接调用本函数，mover 为 null 时安全跳过。
	if mover == null:
		return
	if runner and runner.is_busy():
		runner.cancel_pending()
		if runner.paused:
			runner.abort_current()
			runner.paused = false
		else:
			_queued_move = world
			var path := mover.grid.point_path(mover.position, world, WORLD_SCALE)
			if hints: hints.destination(world, not path.is_empty(), path)
			return
	var reachable := mover.set_target_position(world)
	if hints: hints.destination(world, reachable, mover.remaining_path())
	if not reachable: hud.show_toast(L10n.text("Can't reach that spot"), true)

func _cancel_work() -> void:
	runner.cancel_pending()
	if runner.paused:
		runner.abort_current()
		runner.paused = false
		mover.stop()
	_queued_move = null

func party_travel_ready() -> bool:
	return not _terrain_stale and not _activity_busy and not (activity_sheet and activity_sheet.is_busy()) and not (fishing_panel and fishing_panel.visible) and _in_flight == 0 and not runner.is_busy() and not _stall_uncertain and not _connection_recovery_busy

func is_back_navigation_locked() -> bool:
	if _activity_busy or (activity_sheet and activity_sheet.visible and activity_sheet.is_busy()): return true
	if fishing_panel and fishing_panel.visible:
		fishing_panel.close()
		return true
	if online and online.consume_back(): return true
	if life_sheet and life_sheet.visible and life_sheet.is_busy(): return true
	if life_sheet and life_sheet.visible and life_sheet.consume_back(): return true
	if hud and hud.modal_open():
		hud.close_modal()
		return true
	return false

func _open_life() -> void:
	if visitor or session == null: return
	if life_sheet == null:
		life_sheet = load("res://scenes/farm/life_sheet.gd").new()
		life_sheet.setup(session)
		hud.add_child(life_sheet)
		life_sheet.closed.connect(hud.close_modal)
		life_sheet.gift_requested.connect(_visit_resident)
		life_sheet.goal_requested.connect(_bag_goal)
	else:
		life_sheet.select_section(life_sheet.section)
	hud.show_modal(life_sheet)

func show_mine_rescue() -> void:
	if visitor or session == null: return
	mover.stop()
	_open_life()
	if life_sheet.active is BagPanel: life_sheet.active.select_page("character")
	hud.show_toast(L10n.text("Rescued to the farm. Your items are safe."))

func _bag_goal(goal: Dictionary) -> void:
	if runner.is_busy() or _in_flight > 0:
		hud.show_toast(L10n.text("Finish your current work first"), true)
		return
	if goal.get("place") == "farm":
		hud.close_modal()
		if goal.get("action") == "stall":
			_open_stall(str(goal.get("crop", "")))
		elif goal.has("crop") and goal.get("action") == "sow":
			hud.selected_crop = str(goal.crop)
			_on_seed_selected(str(goal.crop))
		elif goal.has("plant_crop"):
			hud.selected_crop = str(goal.plant_crop)
			_on_seed_selected(str(goal.plant_crop))
		elif goal.get("target") == "stall": _open_stall()
		elif goal.get("target") == "mine": _go_mine()
		return
	BagNavigation.follow(life_sheet.active, goal)

func _visit_resident(resident: String) -> void:
	if runner.is_busy() or _in_flight > 0:
		hud.show_toast(L10n.text("Finish your current work first"), true)
		return
	var destination := {"nursery_keeper": "nursery", "bistro_owner": "bistro", "restorer": "courtyard"}
	hud.close_modal()
	AppRouter.open_instance(AppRouter.PLACE, {"place_id": destination.get(resident, "nursery"), "session": session, "resident_id": resident})

func suspend() -> void:
	_stop_camera_recenter()
	_end_fishing_view()
	_fishing_pending = false
	if fishing_panel: fishing_panel.interrupt()
	if online: online.suspend()
	_clear_brush()
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	for child in get_children():
		if child is CanvasLayer: child.visible = false
	cam.current = false
	_saved_farm_environment = $WorldEnvironment.environment
	$WorldEnvironment.environment = null

func resume() -> void:
	if _own_terrain_changed(): _terrain_stale = true
	if online and not _terrain_stale: online.resume()
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	for child in get_children():
		if child is CanvasLayer and child != fishing_panel: child.visible = true
	$FarmBackground.hide()
	get_viewport().transparent_bg = false
	$WorldEnvironment.environment = _saved_farm_environment
	cam.make_current()
	if _terrain_stale:
		_reload_relocated_farm.call_deferred()
		return
	if _pending_state_refresh and session:
		_pending_state_refresh = false
		_on_server_state(session.state, session.version)
	else:
		_refresh_hud()

## 屏幕点 → 格坐标。地面是平的（没有田畦盒子了），所以一次射线加一次除法就够，
## 不必再遍历田畦列表、也不需要方盒容差——那套容差是为 1.3m 畦间距调的。
func _projector() -> Callable:
	return func(point: Vector2):
		var hit = Plane(Vector3.UP, 0.0).intersects_ray(
			cam.project_ray_origin(point), cam.project_ray_normal(point))
		if hit == null: return null
		var cell := bp.world_to_cell(hit as Vector3, WORLD_SCALE)
		return cell if bp.in_bounds(cell) else null

func _is_plot(cell: Vector2i) -> bool:
	return bp.mask_has("cultivable", cell)

func _plot_unlocked(cell_id: String) -> bool:
	return predictor.is_unlocked(cell_id) if predictor else true

func _action_locked() -> bool:
	return (runner != null and runner.is_busy() and not runner.paused) or _emote_lock_s > 0.0

## 每格按自己的状态入队下一步。返回入队格数。
func _queue_plots(cells: Array) -> int:
	if _terrain_stale: return 0
	_mine_pending = false
	if visitor or cells.is_empty() or session == null or session.offline:
		return 0
	var plots: Array = LabourBrush.filter_actionable(cells, bp)
	var view := _cells_view()
	var now := _now()
	if BagModel.tool_scope(_state()) > 1:
		plots = _expand_tool_plots(plots, view, now)
	var sowing := _sowing_options(true)
	var added := 0
	for c in plots:
		var id := _id(c)
		# 荒地不在 view 里（稀疏存储）——那正是「可以开垦」，不能当成没这格。
		if not _plot_unlocked(id) or runner.contains(c):
			continue
		var step := NextStep.step_for(view.get(id, {}), now)
		if step.is_empty():
			continue
		if step == "sow":
			var reason := _sow_block_reason(sowing)
			if not reason.is_empty():
				hud.show_toast(reason, true)
				continue
			if NextStep.seeds_of(_state().get("inventory", {}), hud.selected_crop) == 0:
				hud.show_toast(L10n.format_text("No %s seeds left — buy some at the stall", CropInfo.name_of(hud.selected_crop)), true)
				continue
		var count := runner.enqueue([c], step)
		added += count
		if step == "sow": sowing.room -= count
	if added > 0:
		hud.set_hint("")
	return added

func _expand_tool_plots(plots: Array, view: Dictionary, now: int) -> Array:
	var out := plots.duplicate()
	for cell in plots:
		var action := NextStep.step_for(view.get(_id(cell), {}), now)
		if not ["till", "water", "harvest"].has(action): continue
		for neighbour in LabourBrush.thicken([cell], bp):
			if not out.has(neighbour) and NextStep.step_for(view.get(_id(neighbour), {}), now) == action:
				out.append(neighbour)
	return out

func _sowing_options(include_pending := false) -> Dictionary:
	var st := _state()
	var chapter := int((st.get("clock", {}) as Dictionary).get("chapter_index", 0))
	var view := _cells_view()
	var options := NextStep.sowing_options(view, st, CropUnlocks.unlocked(CropInfo.ORDER, chapter, st))
	if include_pending and runner:
		for id in view:
			if str(view[id].get("state", "")) == "tilled" and runner.contains(_parse(str(id))):
				options.room -= 1
	return options

func _sow_block_reason(options: Dictionary) -> String:
	if not options.crops.has(hud.selected_crop):
		return L10n.text("First harvest starts with radishes")
	if int(options.room) <= 0:
		return L10n.text("Harvest the first batch before sowing more")
	return ""

## 点了一块现在没事可做的田：说清楚为什么。
func _explain_plot(cell: Vector2i) -> void:
	var id := _id(cell)
	var view := _cells_view()
	if not view.has(id):
		hud.show_toast(FarmHud.reject_text("CELL_LOCKED") if bp.reserved_bed().get("cells", []).has(cell) else FarmHud.reject_text("CELL_NOT_CULTIVABLE"), true)
		return
	var slot: Dictionary = view[id]
	if str(slot.get("state", "")) == "growing":
		var ra = slot.get("ready_at")
		var left := (int(ra) - _now()) if ra != null else -1
		_float_label(cell, L10n.format_text("Growing · %s", FarmHud.format_countdown(maxi(left, 0))), 1.5)

func _on_seed_selected(crop: String) -> void:
	_explicit_crop = crop
	_refresh_hud()

## 大按钮：对整片田做最该做的那件事。
func _on_cta() -> void:
	if _terrain_stale: return
	if _activity_busy: return
	if runner.is_busy() or _in_flight > 0 or session == null or session.offline: return
	var bulk := _last_bulk
	if bulk.is_empty() or not bool(bulk.get("enabled", true)):
		return
	match str(bulk.action):
		"stall":
			_open_stall(str(bulk.get("crop", "")))
		"explore":
			if bulk.get("surface") == "street":
				focus_destination(bulk)
			else: AppRouter.open_instance(AppRouter.PLACE, {"place_id": str(bulk.get("place", "nursery")), "session": session, "target": str(bulk.get("target", ""))})
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
	if action == "sow":
		var reason := _sow_block_reason(_sowing_options())
		if not reason.is_empty():
			hud.show_toast(reason, true)
			runner.abort_current()
			return
	if predictor:
		var r: Dictionary = predictor.check(NextStep.COMMAND.get(action, ""), _payload_for(action, [id]), _now())
		if not r.ok:
			hud.show_toast(FarmHud.reject_text(r.error), true)
			runner.abort_current()
			return
	var stand := _stand_cell_for(cell)
	if stand != Vector2i(-1, -1) and stand != mover.cell() and mover.set_target_cell(stand):
		runner.paused = true
		if hints: hints.destination(bp.cell_to_world(stand), true, mover.remaining_path())
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
		AnimPlaceholders.play_fallback(_rig, runner.action_seconds)

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
		if action == "sow": _explicit_crop = ""
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
			_float_label(cell, L10n.format_text("+%d %s", [gained, CropInfo.name_of(c)]), 1.6)
	var xb := int(before.get("xp", {}).get("total", 0))
	var xa := int(_state().get("xp", {}).get("total", 0))
	if xa > xb:
		hud.show_toast(L10n.format_text("+%d XP", (xa - xb)))

func _payload_for(action: String, ids: Array) -> Dictionary:
	var p := {"cell_ids": ids}
	match action:
		"sow":
			p["crop"] = hud.selected_crop
			p["lot"] = NextStep.seed_lot(_state().get("inventory", {}), hud.selected_crop)
			p["field_condition"] = _field_condition()
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
	var view := predictor.view() if predictor else {}
	for id in view.keys():
		if not _plot_unlocked(str(id)): view.erase(id)
	return view

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
	if scenery: scenery.sync_ground(cells)
	if crop_field:
		crop_field.sync(cells, now_ms)
	_sync_woody_blocking(cells)
	if plot_surface:
		plot_surface.sync(cells, now_ms)
		plot_surface.highlight(runner.queued_cells() if runner else [], _brush_cells,
			runner.current_cell() if runner else null)

## 木本作物（果树）占住格子并阻挡通行；一年生作物可以直接踩过去。
## 只对变化的格调增量 API，不为此重建整张寻路图。
func _sync_woody_blocking(cells: Dictionary) -> void:
	if grid == null: return
	var blocked := {}
	for id in cells:
		if CropInfo.blocks_movement(cells[id]): blocked[str(id)] = true
	for id in blocked:
		if not _woody_blocked.has(id): grid.set_solid(_parse(str(id)), true)
	for id in _woody_blocked:
		if not blocked.has(id): grid.set_solid(_parse(str(id)), false)
	_woody_blocked = blocked

func _render() -> void:
	if predictor:
		render_cells(predictor.view(), _now())
	if farm_activities: farm_activities.sync(_state())
	_refresh_hud()

## 把权威状态（叠上预测）刷到 HUD：金币、田况、倒计时、目标、大按钮、种子行。
func _refresh_hud() -> void:
	if _relocate_button:
		_relocate_button.visible = not visitor and session != null and session.relocation_available()
		_relocate_button.disabled = _terrain_stale or _terrain_refresh_busy or (session != null and (session.offline or session.has_unconfirmed_command()))
	if hud == null or visitor:
		return
	var st := _state()
	var cells := _cells_view()
	var now := _now()
	hud.set_bag_alert(not BagModel.snapshot(st).get("overflow", []).is_empty())
	hud.set_coins(int(st.get("wallet", 0)))
	hud.set_condition(_field_condition())
	hud.set_next_ripe(cells, now)
	hud.set_offline(session.offline if session else false)
	hud.set_connection_recovery(_terrain_stale or (session != null and (session.offline or (_in_flight == 0 and session.has_unconfirmed_command()))), _connection_recovery_busy or _terrain_refresh_busy)
	var chapter := int((st.get("clock", {}) as Dictionary).get("chapter_index", 0))
	var unlocked := CropUnlocks.unlocked(CropInfo.ORDER, chapter, st)
	var has_tilled := false
	for id in cells:
		if str((cells[id] as Dictionary).get("state", "")) == "tilled":
			has_tilled = true
			break
	var sowing := NextStep.sowing_options(cells, st, unlocked)
	if hud.selected_crop != _explicit_crop or not sowing.crops.has(_explicit_crop) \
			or NextStep.seeds_of(st.get("inventory", {}), _explicit_crop) == 0:
		_explicit_crop = ""
	if session == null:
		_last_bulk = {"action": "", "cells": [], "label": L10n.text("Offline — farm not connected"), "enabled": false}
	else:
		_last_bulk = NextStep.bulk(_actionable_view(), now, st, hud.selected_crop, unlocked, not _explicit_crop.is_empty())
	var working := (runner != null and runner.is_busy()) or _in_flight > 0
	if not _cta_was_busy and not working:
		hud.set_cta(_last_bulk)
		# World taps and the action dock use the same visible seed selection.
		if _last_bulk.get("action") == "sow": hud.selected_crop = str(_last_bulk.crop)
	hud.set_seeds(st.get("inventory", {}), sowing.crops, has_tilled and int(sowing.room) > 0, working)
	var progress := DayGoals.progress(st.merged({"cells": _actionable_view()}, true), session.derived if session else {}, now)
	hud.set_goals(DayGoals.evaluate(st, cells), chapter, progress)
	if not JourneyProgress.active(st) and _chapter_seen_index == chapter and not _chapter_seen_complete and progress.complete:
		hud.show_toast(L10n.format_text("Chapter %d complete", (chapter + 1)))
	elif not JourneyProgress.active(st) and _chapter_seen_index >= 0 and chapter > _chapter_seen_index:
		hud.show_toast(L10n.format_text("Chapter %d · %s", [chapter + 1, progress.title]))
	_chapter_seen_index = chapter
	_chapter_seen_complete = bool(progress.complete)
	if progress.complete and int(progress.next_open_in_ms) == 0:
		call_deferred("_refresh_next_chapter")
	if director: director.sync_state(st)
	if stall and stall.visible:
		# 延后到帧末：refresh 会重建按钮，而这里可能正处在某个按钮的 pressed 回调里。
		stall.call_deferred("refresh", st, unlocked, STALL_BUDGET)

func _refresh_next_chapter() -> void:
	if session == null or session.offline or _chapter_refresh_busy or Time.get_ticks_msec() < _next_chapter_refresh_ticks:
		return
	_chapter_refresh_busy = true
	_next_chapter_refresh_ticks = Time.get_ticks_msec() + 5000
	await session.refresh()
	_chapter_refresh_busy = false

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
	label.font_size = 28
	label.pixel_size = 0.006
	label.outline_size = 4
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
	session.state_changed.connect(_on_server_state)
	session.offline_changed.connect(func(off): if hud: hud.set_offline(off))
	# 服务端拒绝必须说出来：静默回滚在玩家眼里就是「点了没反应」。
	session.rejected.connect(func(code, _detail):
		if code == "FARM_RELOCATED": _on_farm_relocated()
		if hud: hud.show_toast(FarmHud.reject_text(code), true))
	_render()

## 服务端每次回包都整体覆盖预测器；漂移一律以服务端为准（方案 §3 D4）。
func _on_server_state(state: Dictionary, version: int) -> void:
	if _own_terrain_changed():
		_terrain_stale = true
		if process_mode != Node.PROCESS_MODE_DISABLED: _on_farm_relocated()
		return
	if process_mode == Node.PROCESS_MODE_DISABLED:
		_pending_state_refresh = true
		return
	if predictor:
		predictor.commit(state.get("cells", {}), version)
	_render()


# —— 摊位 ————————————————————————————————————————————————————————————————

func _build_stall() -> void:
	stall = StallSheet.new()
	hud.add_child(stall)
	stall.sell_requested.connect(_on_sell)
	stall.fish_sell_requested.connect(_on_sell_fish)
	stall.buy_requested.connect(_on_buy)
	stall.retry_requested.connect(_retry_stall)
	stall.closed.connect(hud.close_modal)

func _open_stall(crop := "") -> void:
	if stall == null:
		return
	_stall_uncertain = session != null and session.has_meta("pending_stall_command")
	stall.set_uncertain(_stall_uncertain)
	var chapter := int((_state().get("clock", {}) as Dictionary).get("chapter_index", 0))
	stall.refresh(_state(), CropUnlocks.unlocked(CropInfo.ORDER, chapter, _state()), STALL_BUDGET)
	hud.show_modal(stall)
	if not crop.is_empty(): stall.focus_seed(crop)

func _on_sell(items: Array) -> void:
	if _terrain_stale: return
	if session == null or (stall and stall.is_busy()):
		return
	if stall: stall.set_busy(true)
	var before := int(_state().get("wallet", 0))
	var ok: bool = await session.send("sell_at_stall", {"items": items})
	_stall_uncertain = not ok and session.last_error_code in ["TRANSPORT", "OFFLINE"]
	if _stall_uncertain: session.set_meta("pending_stall_command", true)
	if stall: stall.set_uncertain(_stall_uncertain)
	if stall: stall.set_busy(false)
	if ok:
		var gained := int(_state().get("wallet", 0)) - before
		hud.show_toast(L10n.format_text("+%d coins", gained))
	_render()

func _on_sell_fish(stack_id: String, quantity: int) -> void:
	if _terrain_stale: return
	if session == null or stall.is_busy(): return
	stall.set_busy(true)
	var before := int(session.state.wallet)
	var accepted := await session.send("sell_fish", {"sequence": int(session.state.bag.sequence), "stack_id": stack_id, "quantity": quantity})
	_stall_uncertain = session.has_unconfirmed_command()
	if _stall_uncertain: session.set_meta("pending_stall_command", true)
	stall.set_uncertain(_stall_uncertain)
	stall.set_busy(false)
	hud.show_toast(L10n.format_text("+%d coins", int(session.state.wallet) - before) if accepted else SessionPanel.error_text(session.last_error_code), not accepted)
	_render()

func _on_buy(crop: String, qty: int) -> void:
	if _terrain_stale: return
	if session == null or (stall and stall.is_busy()):
		return
	if stall: stall.set_busy(true)
	var ok: bool = await session.send("buy_seeds", {"crop": crop, "qty": qty})
	_stall_uncertain = not ok and session.last_error_code in ["TRANSPORT", "OFFLINE"]
	if _stall_uncertain: session.set_meta("pending_stall_command", true)
	if stall: stall.set_uncertain(_stall_uncertain)
	if stall: stall.set_busy(false)
	if ok:
		hud.show_toast(L10n.format_text("Bought %d %s seeds", [qty, CropInfo.name_of(crop)]))
		hud.selected_crop = crop
		_explicit_crop = crop
	_render()

# —— 导演模式 ——————————————————————————————————————————————————————————————

func _retry_stall() -> void:
	if session == null or stall == null or stall.is_busy(): return
	stall.set_busy(true)
	var ok := await session.refresh()
	stall.set_busy(false)
	if ok:
		_stall_uncertain = false
		if session.has_meta("pending_stall_command"): session.remove_meta("pending_stall_command")
		stall.set_uncertain(false)
		hud.show_toast(L10n.text("Trade checked. Your basket is up to date."))
	else:
		hud.show_toast(L10n.text("Could not connect. Try again."), true)
	_render()

func _recover_connection() -> void:
	if _terrain_stale:
		_reload_relocated_farm()
		return
	if session == null or _connection_recovery_busy or _in_flight > 0: return
	_connection_recovery_busy = true
	_refresh_hud()
	var ok := await session.refresh()
	_connection_recovery_busy = false
	hud.show_toast(L10n.text("Farm synced") if ok else L10n.text("Could not connect. Try again."), not ok)
	_render()

## 入口：长按标题三秒。不额外占屏幕——QA 面板不该在正式玩家的界面上留按钮。
func _build_director() -> void:
	director = DirectorPanel.new()
	director.name = "Director"
	hud.add_child(director)
	director.command_requested.connect(_on_director_command)
	director.closed.connect(hud.close_modal)
	title.gui_input.connect(_on_title_input)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	if OS.get_cmdline_user_args().has("--qa"):
		hud.show_modal(director)

func _on_title_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventMouseButton:
		_title_hold = 0.0 if e.is_pressed() else -1.0

func _tick_title_hold(dt: float) -> void:
	if _title_hold < 0.0 or director == null:
		return
	_title_hold += dt
	if _title_hold >= DirectorPanel.HOLD_S:
		_title_hold = -1.0
		if director.visible: hud.close_modal()
		else: hud.show_modal(director)

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
	if accepted and type in ["qa_set_clock", "qa_skip_days", "qa_set_weather"]:
		accepted = await session.refresh()
	director.report(accepted, session.last_error_code, session.player_id)
	if accepted:
		if predictor:
			predictor.commit(session.state.get("cells", {}), session.version)
		_render()

# —— 访客模式（PRD §3.3 / §8.4）——————————————————————————————————————————

func _enter_visitor_mode() -> void:
	title.text = L10n.format_text("Visiting · %s", SeededOutfit.short_name(str(snapshot.get("avatar_ref", "seed:unknown"))))
	title.tooltip_text = title.text
	hud.set_farm_title(title.text)
	hud.set_visitor_mode(true)
	hud.set_condition(str(snapshot.get("weather_snapshot", "sunny")))
	hud.wave_pressed.connect(_wave)
	hud.stamp_pressed.connect(_stamp)
	# 访客看到的就是主人实际开垦过的那些格——没有解锁概念要过滤了。
	var local_cells: Array = snapshot.get("cells", [])
	_frame_field()
	if crop_field:
		crop_field.sync_snapshot(local_cells)
	var ground_cells := {}
	for entry in local_cells:
		var slot: Dictionary = entry.duplicate(true)
		# Snapshot ripeness is frozen. Derive surface color without writing timestamps or saves.
		slot["ready_at"] = 0 if bool(entry.get("ripe", false)) else null
		ground_cells[str(entry.get("cell_id", ""))] = slot
	plot_surface.sync(ground_cells, 0)
	scenery.sync_ground(ground_cells)
	_sync_woody_blocking(ground_cells)

func _wave() -> void:
	_emote_lock_s = 1.2
	_play(AnimPlaceholders.clip_for("wave"))
	if AnimPlaceholders.is_placeholder("wave") and _rig:
		AnimPlaceholders.play_wave_fallback(_rig, 1.2)

func _stamp() -> void:
	var label := Label3D.new()
	label.name = "Stamp"
	label.text = L10n.text(STAMPS[_stamp_index % STAMPS.size()])
	_stamp_index += 1
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.pixel_size = 0.006
	label.outline_size = 3
	label.modulate = GameUi.GREEN
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
