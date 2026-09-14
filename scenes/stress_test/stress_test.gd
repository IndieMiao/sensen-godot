extends Node3D
## 内部性能监视：批量生成角色，对比 direct/merged 装配策略。

@onready var rigs_root: Node3D = $Rigs
@onready var title: Label = $HUD/SafeArea/VBox/Card/CardVBox/HeaderRow/Title
@onready var badge: Label = $HUD/SafeArea/VBox/Card/CardVBox/HeaderRow/Badge
@onready var stats: Label = $HUD/SafeArea/VBox/Card/CardVBox/StatsLabel
@onready var slider: HSlider = $HUD/SafeArea/VBox/Card/CardVBox/CountSlider
@onready var load_label: Label = $HUD/SafeArea/VBox/Card/CardVBox/LoadRow/LoadLabel
@onready var count_value: Label = $HUD/SafeArea/VBox/Card/CardVBox/LoadRow/CountValue
@onready var strategy_btn: Button = $HUD/SafeArea/VBox/Row/StrategyButton

var _merged := true
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 20260821  # 固定种子，压测可复现
	_apply_design_tokens()
	slider.value_changed.connect(_on_count_changed)
	strategy_btn.pressed.connect(_toggle_strategy)
	$HUD/SafeArea/VBox/Row/MapButton.pressed.connect(AppRouter.go_to_map)
	count_value.text = str(int(slider.value))
	_respawn(int(slider.value))


func _apply_design_tokens() -> void:
	title.add_theme_font_size_override(&"font_size", DesignTokens.FONT_TITLE)
	badge.add_theme_color_override(&"font_color", DesignTokens.INK_SUB)
	badge.add_theme_font_size_override(&"font_size", DesignTokens.FONT_MICRO)
	stats.add_theme_font_size_override(&"font_size", DesignTokens.FONT_LABEL)
	load_label.add_theme_font_size_override(&"font_size", DesignTokens.FONT_LABEL)
	count_value.add_theme_color_override(&"font_color", DesignTokens.ACCENT_DEEP)
	count_value.add_theme_font_size_override(&"font_size", DesignTokens.FONT_LABEL)


func _on_count_changed(value: float) -> void:
	count_value.text = str(int(value))
	_respawn(int(value))


func _toggle_strategy() -> void:
	_merged = not _merged
	strategy_btn.text = L10n.format_text("Assembly: %s", (L10n.text("Merged") if _merged else L10n.text("Direct")))
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
	stats.text = L10n.format_text("Characters %d  ·  %s Assembly\nFPS %d  ·  Frame %.2f ms\nDraw Calls %d  ·  VRAM %.1f MB", [
		rigs_root.get_child_count(),
		L10n.text("Merged") if _merged else L10n.text("Direct"),
		Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
	])
