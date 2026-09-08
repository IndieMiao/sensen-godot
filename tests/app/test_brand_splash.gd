extends GdUnitTestSuite
## 三端开屏（Godot boot_splash / iOS storyboard / Android 12+ splash theme）取值同源于 Brand，
## 但引擎与导出器读的是 project.godot 和 export_presets.cfg 里的字面值。
## 这套用例守护三处不漂移：只改 Brand 忘了改配置、或只改配置忘了改 Brand，都会红。
## 素材本身由 tools/brand/render.sh 从 assets/brand/logo_mark.svg 生成。

const PRESETS := "res://export_presets.cfg"
const ANDROID := "preset.0.options"
const IOS := "preset.1.options"

func _presets() -> ConfigFile:
	var cfg := ConfigFile.new()
	assert_int(cfg.load(PRESETS)).override_failure_message("读不到 %s" % PRESETS).is_equal(OK)
	return cfg


## 读磁盘上的原始 PNG，而不是导入后的纹理：导出器消费的就是磁盘这一份。
## （Image.load_from_file 会刷 "this will not work on export" 警告，不要用。）
func _png(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	assert_int(bytes.size()).override_failure_message("读不到 %s" % path).is_greater(0)
	var img := Image.new()
	assert_int(img.load_png_from_buffer(bytes)).override_failure_message("%s 解码失败" % path).is_equal(OK)
	return img
func test_engine_boot_splash_matches_brand() -> void:
	assert_str(ProjectSettings.get_setting("application/boot_splash/image", "")).is_equal(Brand.SPLASH_IMAGE)
	assert_str(ProjectSettings.get_setting("application/config/icon", "")).is_equal(Brand.MARK_SVG)
	# 比 to_html 不比 Color 本体：project.godot 存的是六位小数，浮点相等不可靠。
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.BLACK)
	assert_str(bg.to_html(false)).is_equal(Brand.SPLASH_BG.to_html(false))
	# 开屏底色必须就是壳的纸色，否则开屏 → 登录页会闪一下别的颜色。
	assert_str(Brand.SPLASH_BG.to_html(false)).is_equal(DesignTokens.UI_PAPER.to_html(false))

func test_android_launcher_icons_point_at_brand_assets() -> void:
	# 这四个值也决定 Android 12+ 系统开屏：导出器据此生成 @mipmap/icon_background 与
	# @drawable/splash_icon，自动生成的 GodotAppSplashTheme 引用它们。
	# 所以定制不写进 android/build（那目录 gitignore，重装模板即丢）。
	var cfg := _presets()
	assert_str(cfg.get_value(ANDROID, "launcher_icons/main_192x192", "")).is_equal(Brand.ICON_LEGACY)
	assert_str(cfg.get_value(ANDROID, "launcher_icons/adaptive_foreground_432x432", "")).is_equal(Brand.ICON_ADAPTIVE_FG)
	assert_str(cfg.get_value(ANDROID, "launcher_icons/adaptive_background_432x432", "")).is_equal(Brand.ICON_ADAPTIVE_BG)
	assert_str(cfg.get_value(ANDROID, "launcher_icons/adaptive_monochrome_432x432", "")).is_equal(Brand.ICON_ADAPTIVE_MONO)

func test_ios_storyboard_matches_brand() -> void:
	# 4.7 没有 use_launch_screen_storyboard 开关，storyboard 常开，只需底色与两张图。
	var cfg := _presets()
	assert_bool(cfg.get_value(IOS, "storyboard/use_custom_bg_color", false)).is_true()
	var bg: Color = cfg.get_value(IOS, "storyboard/custom_bg_color", Color.BLACK)
	assert_str(bg.to_html(false)).is_equal(Brand.SPLASH_BG.to_html(false))
	assert_str(cfg.get_value(IOS, "storyboard/custom_image@2x", "")).is_equal(Brand.STORYBOARD_2X)
	assert_str(cfg.get_value(IOS, "storyboard/custom_image@3x", "")).is_equal(Brand.STORYBOARD_3X)

func test_display_name_matches_project_and_android_package() -> void:
	var cfg := _presets()
	assert_str(ProjectSettings.get_setting("application/config/name", "")).is_equal(Brand.DISPLAY_NAME)
	assert_str(cfg.get_value(ANDROID, "package/name", "")).is_equal(Brand.DISPLAY_NAME)

func test_generated_assets_exist_at_expected_sizes() -> void:
	var expected := Brand.expected_sizes()
	assert_int(expected.size()).is_equal(7)
	for path in expected:
		var edge: int = expected[path]
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("缺生成物 %s，跑 tools/brand/render.sh" % path).is_true()
		var img := _png(path)
		assert_int(img.get_width()).override_failure_message("%s 宽度不对" % path).is_equal(edge)
		assert_int(img.get_height()).override_failure_message("%s 高度不对" % path).is_equal(edge)

func test_splash_image_keeps_transparent_corners() -> void:
	# 引擎用 bg_color 铺底再居中画图；图带不透明底就会在开屏上出现一个方块。
	var splash := _png(Brand.SPLASH_IMAGE)
	assert_float(splash.get_pixel(2, 2).a).is_equal(0.0)
	assert_float(splash.get_pixel(Brand.SIZE_SPLASH - 3, Brand.SIZE_SPLASH - 3).a).is_equal(0.0)

func test_adaptive_layers_are_shaped_for_the_system_mask() -> void:
	# 内容越出中心 66% 安全区会被系统的圆形 / 方形遮罩裁掉。
	assert_bool(Brand.ADAPTIVE_CONTENT_RATIO <= 0.66) \
		.override_failure_message("自适应前景内容比例超出 66% 安全区").is_true()
	var fg := _png(Brand.ICON_ADAPTIVE_FG)
	assert_float(fg.get_pixel(2, 2).a).is_equal(0.0)
	assert_float(fg.get_pixel(Brand.SIZE_ADAPTIVE - 3, 2).a).is_equal(0.0)
	# 背景层被铺满整个图标与开屏底，必须是整块不透明纯色。
	var bg := _png(Brand.ICON_ADAPTIVE_BG)
	var corners: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(Brand.SIZE_ADAPTIVE - 1, 0),
		Vector2i(Brand.SIZE_ADAPTIVE / 2, Brand.SIZE_ADAPTIVE / 2),
		Vector2i(0, Brand.SIZE_ADAPTIVE - 1),
	]
	for p in corners:
		var c := bg.get_pixelv(p)
		assert_float(c.a).is_equal(1.0)
		assert_str(c.to_html(false)).is_equal(Brand.SPLASH_BG.to_html(false))

func test_monochrome_layer_is_a_white_silhouette() -> void:
	# themed icon 由系统上色，素材必须是白剪影 + 透明底。
	# 逐像素扫而不是取固定坐标：换标识后这条依然成立。
	var mono := _png(Brand.ICON_ADAPTIVE_MONO)
	var opaque := 0
	var non_white := 0
	for y in range(0, Brand.SIZE_ADAPTIVE, 4):
		for x in range(0, Brand.SIZE_ADAPTIVE, 4):
			var c := mono.get_pixel(x, y)
			if c.a < 0.99:
				continue
			opaque += 1
			if c.to_html(false) != "ffffff":
				non_white += 1
	assert_int(opaque).override_failure_message("monochrome 层几乎全透明，染色逻辑没生效").is_greater(200)
	assert_int(non_white).override_failure_message("monochrome 层有非白像素").is_equal(0)
	assert_float(mono.get_pixel(2, 2).a).is_equal(0.0)

func test_placeholder_flag_still_marks_brand_as_undecided() -> void:
	# 占位标识（E6 / R11），品牌决策 = SSLAUNCH B1。B1 落地、素材换掉之后：
	# 把 Brand.PLACEHOLDER 改 false，同时改本条断言，并按 assets/brand/README.md 走一遍清单。
	assert_bool(Brand.PLACEHOLDER) \
		.override_failure_message("品牌已定版？同步 docs/release-process.md 的提审前检查").is_true()
