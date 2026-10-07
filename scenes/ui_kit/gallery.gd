extends Control
## P0 UI kit gallery (SGODOT-211 / 212): every registered section from UiKitGallerySections, 360 wide.
## Desktop PNG shots: UI_KIT_SHOT=/abs/dir godot --path . scenes/ui_kit/gallery.tscn
## (tools/ui/shoot_gallery.sh wraps this and can compare against tests/ui_kit/snapshots/png).

signal built

var sections := {}   # id -> section Control (title + body)
var scroll: TouchScrollContainer
var _list: VBoxContainer

func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTokens.COLOR_SURFACE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	scroll = TouchScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, int(UiTokens.SPACE_PAGE))
	scroll.add_child(margin)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", int(UiTokens.SPACE_SECTION))
	margin.add_child(_list)
	for sec in UiKitGallerySections.all():
		var box := VBoxContainer.new()
		box.name = String(sec.id)
		box.add_theme_constant_override(&"separation", int(UiTokens.SPACE_WITHIN))
		box.add_child(UiKit.label(sec.title, UiTokens.STYLE_ROW_TITLE_XB15))
		var src := UiKit.label(sec.figma, UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
		src.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(src)
		var body: Control = sec.build.call()
		body.name = "Body"
		box.add_child(body)
		_list.add_child(box)
		sections[sec.id] = box
	built.emit()
	if OS.get_environment("UI_KIT_SHOT") != "":
		_shoot.call_deferred(OS.get_environment("UI_KIT_SHOT"))

func _shoot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport()
	for id in sections:
		var box: Control = sections[id]
		scroll.scroll_vertical = int(box.position.y)
		for i in 3: await get_tree().process_frame
		var img := vp.get_texture().get_image()
		var scale := float(img.get_width()) / vp.get_visible_rect().size.x
		var rect := box.get_global_rect()
		var px := Rect2i(Vector2i(rect.position * scale), Vector2i(rect.size * scale)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img.get_region(px).save_png(dir.path_join("%s.png" % id))
	print("UI_KIT_SHOT saved %d sections to %s" % [sections.size(), dir])
	get_tree().quit()
