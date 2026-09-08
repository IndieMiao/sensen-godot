extends SceneTree
## 由 assets/brand/logo_mark.svg 生成三端开屏与启动图标 PNG。
##   godot --headless --path . --script tools/brand/render_brand_assets.gd
##
## 生成物提交进仓库：引擎读 boot_splash、导出器读 launcher_icons / storyboard，
## 都发生在构建期，不能指望 CI 现场跑一遍生成。
## 品牌素材（SSLAUNCH B1）到手后：换掉 SVG、按需改 Brand 里的颜色，重跑本脚本。

## 必须等于 logo_mark.svg 的 width / height 属性；换素材请保持 512。
const SVG_BASE := 512

func _initialize() -> void:
	var svg := FileAccess.get_file_as_string(Brand.MARK_SVG)
	if svg.is_empty():
		push_error("读不到标识源 %s" % Brand.MARK_SVG)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(Brand.GENERATED_DIR)

	var failed := 0
	var report: PackedStringArray = []

	# 引擎开屏：Godot 先用 bg_color 铺满再居中画图，所以图本身留透明底。
	failed += _save(_mark(svg, Brand.SIZE_SPLASH), Brand.SPLASH_IMAGE, report)

	# 旧版（非自适应）启动图标必须不透明，否则老机器上是黑底。
	var legacy := _mark(svg, int(round(Brand.SIZE_LEGACY * 0.76)))
	failed += _save(_over(Brand.SIZE_LEGACY, Brand.SPLASH_BG, legacy), Brand.ICON_LEGACY, report)

	# 自适应图标：内容缩到中心 60%，越过 66% 安全区会被系统裁掉。
	# 这张前景同时被 Android 12+ 系统开屏当 windowSplashScreenAnimatedIcon 的同源素材。
	var adaptive := _mark(svg, int(round(Brand.SIZE_ADAPTIVE * Brand.ADAPTIVE_CONTENT_RATIO)))
	failed += _save(_over(Brand.SIZE_ADAPTIVE, TRANSPARENT, adaptive), Brand.ICON_ADAPTIVE_FG, report)
	failed += _save(_flat(Brand.SIZE_ADAPTIVE, Brand.SPLASH_BG), Brand.ICON_ADAPTIVE_BG, report)
	failed += _save(_over(Brand.SIZE_ADAPTIVE, TRANSPARENT, _silhouette(adaptive)), Brand.ICON_ADAPTIVE_MONO, report)

	# iOS：Godot 生成的 LaunchScreen storyboard 在 custom_bg_color 上居中放这两张。
	failed += _save(_mark(svg, Brand.SIZE_STORYBOARD_2X), Brand.STORYBOARD_2X, report)
	failed += _save(_mark(svg, Brand.SIZE_STORYBOARD_3X), Brand.STORYBOARD_3X, report)

	for line in report:
		print(line)
	if failed > 0:
		push_error("%d 个生成物写入失败" % failed)
		quit(1)
		return
	print("完成：%d 个生成物（源 %s）" % [report.size(), Brand.MARK_SVG])
	quit(0)

const TRANSPARENT := Color(0, 0, 0, 0)

## 按目标边长栅格化标识；thorvg 取整可能差 1px，兜底 resize 保证尺寸可断言。
func _mark(svg: String, size: int) -> Image:
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(size) / float(SVG_BASE))
	if err != OK:
		push_error("SVG 栅格化失败（%d）" % err)
		return Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != size or img.get_height() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return img

func _flat(size: int, bg: Color) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	return img

## 底色画布上居中叠标识（alpha 混合，不是覆盖）。
func _over(size: int, bg: Color, mark: Image) -> Image:
	var canvas := _flat(size, bg)
	var offset := (canvas.get_size() - mark.get_size()) / 2
	canvas.blend_rect(mark, Rect2i(Vector2i.ZERO, mark.get_size()), offset)
	return canvas

## Android themed icon 要纯剪影：非透明像素一律置白，系统自己上色。
func _silhouette(src: Image) -> Image:
	var out := src.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var a := out.get_pixel(x, y).a
			if a > 0.0:
				out.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return out

func _save(img: Image, path: String, report: PackedStringArray) -> int:
	var err := img.save_png(path)
	if err != OK:
		push_error("写不出 %s（%d）" % [path, err])
		return 1
	report.append("  %-52s %dx%d" % [path, img.get_width(), img.get_height()])
	return 0
