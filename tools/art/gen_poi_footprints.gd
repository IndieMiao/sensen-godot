extends SceneTree
## 离线烘焙 POI/地标贴图的视觉足迹，供地图阴影贴住素材可视底座。
## 阈值化：只统计 alpha>0.5 的实体像素；行密度 >=3% 才算内容行。
## 用法: godot --headless -s tools/art/gen_poi_footprints.gd
## 输出粘贴进 modules/map/city_map_data.gd 的 ART_FOOTPRINTS。

func _init() -> void:
	var dir := DirAccess.open("res://assets/map/poi")
	var names := Array(dir.get_files())
	names.sort()
	print("const ART_FOOTPRINTS := {")
	for file in names:
		if not str(file).ends_with(".png"): continue
		var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/map/poi/" + str(file)))
		if image == null: continue
		var w := image.get_width()
		var h := image.get_height()
		var min_density := int(w / 2 * 0.03)
		var bottom_y := -1
		var y := h - 1
		while y >= 0 and bottom_y < 0:
			var count := 0
			for x in range(0, w, 2):
				if image.get_pixel(x, y).a > 0.5: count += 1
			if count >= min_density: bottom_y = y
			y -= 2
		if bottom_y < 0: continue
		var min_x := w
		var max_x := 0
		for by in range(maxi(0, bottom_y - int(h * 0.1)), bottom_y + 1, 2):
			for x in range(0, w, 2):
				if image.get_pixel(x, by).a > 0.5:
					min_x = mini(min_x, x)
					max_x = maxi(max_x, x)
		print('\t"%s": {"cx": %.3f, "bottom": %.3f, "width": %.3f},' % [str(file).trim_suffix(".png"),
			(min_x + max_x) * 0.5 / w - 0.5, float(bottom_y + 1) / h, float(max_x - min_x) / w])
	print("}")
	quit()
