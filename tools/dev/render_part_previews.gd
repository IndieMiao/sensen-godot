## 把部件逐个渲成 PNG，用于"不装机也能看清每个部件长什么样"的目视挑选。
##
## 复用 PartThumbnailer（换装页用的同一个离屏渲染器），所以这里看到的颜色/打光
## 与换装页里的缩略图一致；不一致就说明渲染器本身有问题，而不是选件问题。
##
## 必须带窗口跑——headless 的 dummy 渲染驱动下 SubViewport 拿不到图像，
## 存出来会是全透明。用法（RENDER_SIZE 由 PartThumbnailer 决定）：
##   godot --path . --script res://tools/dev/render_part_previews.gd -- <输出目录> [id1 id2 ...]
## 不给 id 列表则渲 manifest 里的全部部件（denylist 不生效——目的就是看被剔除的那些）。
extends SceneTree

const MANIFEST := "res://assets/avatar/parts_manifest.json"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("用法: ... -- <输出目录> [part_id ...]")
		quit(2)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var catalog := PartCatalog.load_from_file(MANIFEST)
	if catalog == null:
		printerr("manifest 加载失败: %s" % MANIFEST)
		quit(2)
		return

	var ids: Array = args.slice(1) if args.size() > 1 else catalog.all_ids()
	ids.sort()

	var thumber := PartThumbnailer.new()
	thumber.catalog = catalog
	root.add_child(thumber)
	# _initialize() 期间 root 还没走完进树流程，add_child 不会立刻触发 _ready——
	# 少了这一帧，PartThumbnailer 的 _viewport/_stage 全是 null。
	await process_frame

	var ok := 0
	var failed: PackedStringArray = []
	for id in ids:
		var tex: Texture2D = await thumber.thumbnail(String(id))
		if tex == null:
			failed.append(String(id))
			continue
		var img := tex.get_image()
		if img == null or img.is_empty():
			failed.append(String(id))
			continue
		var path := "%s/%s.png" % [out_dir, id]
		if img.save_png(path) != OK:
			failed.append(String(id))
			continue
		ok += 1
		print("渲出 %s" % path)

	if failed.size() > 0:
		printerr("失败 %d 个: %s" % [failed.size(), ", ".join(failed)])
	print("完成: %d/%d" % [ok, ids.size()])
	quit(1 if failed.size() > 0 else 0)
