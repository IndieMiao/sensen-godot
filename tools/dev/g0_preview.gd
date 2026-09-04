extends Node
## G0 UI 预览宿主，作为 tools/dev/ui_preview.tscn 的目标场景使用（它负责注入手机安全区）。
##
## mode = select：SafeArea → Root → SelectPanel，喂 regions.json 第一个城市的真实候选
##   （512×512 的 preview.png）。2026-09-04 真机截图里「卡片撑破面板、盖住 Create Farm」
##   只有喂真图才复现——单测用的 PlaceholderTexture2D(64×64) 恰好等于预览高度，测不出。
## mode = farm：farm.tscn + sh_a 蓝图，直接挂树、不经 AppRouter 压栈。
##
##   G0_SHOT=/tmp/g0/select.png G0_FRAMES=20 godot --path . --resolution 360x800 \
##         tools/dev/ui_preview.tscn -- res://tools/dev/g0_select_preview.tscn flat
##   G0_SHOT=/tmp/g0/farm.png G0_FRAMES=120 godot --path . --resolution 360x800 \
##         tools/dev/ui_preview.tscn -- res://tools/dev/g0_farm_preview.tscn notch
## 360×800 窗口在 stretch=canvas_items/expand 下就是 360×800 逻辑视口，与 vivo V2509A 一致；
## G0_SHOT 指定截图路径（截完自动退出），G0_FRAMES 是截图前等待的帧数（农场要等
## Avatar 异步装配落地，≥120）。

@export_enum("select", "farm") var mode := "select"

const FARM_BLUEPRINT := "res://assets/blueprints/sh_a/r2/farm_blueprint.json"

func _ready() -> void:
	if mode == "farm":
		_farm()
	else:
		_select()
	var shot := OS.get_environment("G0_SHOT")
	if not shot.is_empty():
		_capture(shot, int(OS.get_environment("G0_FRAMES")) if OS.has_environment("G0_FRAMES") else 120)

## 自己截根视口的纹理再退出，不走 --write-movie：桌面窗口高度会被屏幕钳住，movie 帧
## 只截到视口中段（2026-09-04 实测 720×1600 请求下只拿到 720×1280 的中段裁切）。
## 用 --resolution 360x800 把窗口开在屏幕装得下的尺寸，视口逻辑尺寸即 360×800。
func _capture(path: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("g0_preview: window=%s visible=%s shot=%s -> %s" % [
		DisplayServer.window_get_size(), get_viewport().get_visible_rect().size, img.get_size(), path])
	get_tree().quit()

func _select() -> void:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	# 一层地图色的底，方便看清面板边缘（真机上这里是 Mapbox 底图）。
	var bg := ColorRect.new()
	bg.color = Color(0.93, 0.91, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var safe := SafeAreaMargin.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(safe)
	var root := Control.new()
	root.name = "Root"
	safe.add_child(root)
	var panel := SelectPanel.new()
	root.add_child(panel)
	var regions := FarmRegions.load_default()
	var items: Array = []
	for c in regions.regions[0].candidates:
		var id := str(c.layout_patch_id)
		var path := "res://assets/blueprints/%s/r%d/preview.png" % [id, int(c.get("revision", 1))]
		items.append({"id": id, "name": str(c.name),
			"preview": load(path) if ResourceLoader.exists(path) else null})
	panel.set_candidates(items)
	panel.focus(items[0].id)

func _farm() -> void:
	var farm := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	farm.setup({"blueprint": FarmBlueprint.load_file(FARM_BLUEPRINT)})
	add_child(farm)
