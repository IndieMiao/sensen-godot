extends Node3D
## 压测场景：批量生成角色，direct/merged 策略可切换对比 HUD 读数。

@onready var rigs_root: Node3D = $Rigs
@onready var stats: Label = $HUD/SafeArea/VBox/Card/CardVBox/StatsLabel
@onready var slider: HSlider = $HUD/SafeArea/VBox/Card/CardVBox/CountSlider
@onready var strategy_btn: Button = $HUD/SafeArea/VBox/StrategyButton

var _merged := true
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 20260821  # 固定种子，压测可复现
	slider.value_changed.connect(func(v): _respawn(int(v)))
	strategy_btn.pressed.connect(_toggle_strategy)
	$HUD/SafeArea/VBox/SceneButton.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/dressing_room/dressing_room.tscn"))
	$HUD/SafeArea/VBox/MapButton.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/map_poc/map_poc.tscn"))
	_respawn(int(slider.value))

func _toggle_strategy() -> void:
	_merged = not _merged
	strategy_btn.text = "策略: %s" % ("merged" if _merged else "direct")
	_respawn(rigs_root.get_child_count())

func _respawn(count: int) -> void:
	for c in rigs_root.get_children():
		rigs_root.remove_child(c)
		c.queue_free()
	Avatar.cache.clear()
	var side := int(ceil(sqrt(float(count))))
	for i in count:
		var rig := Avatar.create_rig()
		rig.assembler = AvatarAssemblerMerged.new() if _merged else AvatarAssemblerDirect.new()
		var row := floori(float(i) / side)
		rig.position = Vector3((i % side) * 1.5 - side * 0.75, 0, row * 1.5)
		rigs_root.add_child(rig)
		rig.apply_config(_random_config())
		rig.config_applied.connect(func(_c):
			var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap:
				ap.play("walk" if _rng.randf() > 0.5 else "idle"))

func _random_config() -> AvatarConfig:
	var cfg := Avatar.slot_table.default_config()
	for slot_def in Avatar.slot_table.slots:
		var pool := Avatar.catalog.parts_for_slot(slot_def.slot_name)
		if pool.is_empty():
			continue
		if slot_def.required or _rng.randf() > 0.5:
			cfg.slots[slot_def.slot_name] = pool[_rng.randi_range(0, pool.size() - 1)].id
	return cfg

func _process(_delta: float) -> void:
	stats.text = "角色: %d  策略: %s\nFPS: %d  帧时: %.2fms\nDrawCalls: %d\n显存: %.1fMB" % [
		rigs_root.get_child_count(),
		"merged" if _merged else "direct",
		Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
	]
