extends GdUnitTestSuite
## Layout snapshots of the UI kit gallery (SGODOT-211 / 212). Each registered section is laid out at the
## 360 px base width and its Control tree (type, variation, rounded rect, text) compared with
## tests/ui_kit/snapshots/<id>.json. Missing snapshots are recorded on first run; refresh deliberately with
## UPDATE_UI_SNAPSHOTS=1 tools/run_tests.sh res://tests/ui_kit and review the diff.
## Pixel shots are separate: tools/ui/shoot_gallery.sh (needs a desktop renderer).

const SNAP_DIR := "res://tests/ui_kit/snapshots"
## Glyphs Nunito has no face for (★ ✓) are drawn by a font of the OS, measured differently on macOS and on the
## Ubuntu check runner (quality_badge, reward_moment, gear_row failed there only, C-22). The snapshots are laid out
## with the project's own fonts alone: a missing glyph is the engine's box, the same everywhere.
const OWN_FONTS := ["res://assets/ui/fonts/Nunito.ttf", "res://assets/ui/fonts/NotoSansSC-Regular.otf"]

## Sections are snapshotted online: a P0 world an earlier suite opened keeps P0Runtime's singleton alive, and with no
## server it goes offline, which leaves the static UiCommandButton.offline set and every sending button reading
## `Offline` (inbox_row, gear_row, board_card, shop_row, blueprint_card failed only after tests/p0).
func test_every_section_matches_its_layout_snapshot() -> void:
	var was_offline := UiCommandButton.offline
	UiCommandButton.offline = false
	var fonts: Array[FontFile] = []
	for path in OWN_FONTS:
		var f := load(path) as FontFile
		if f.allow_system_fallback:
			f.allow_system_fallback = false
			fonts.append(f)
	var host := Control.new()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	var gallery: Control = load("res://scenes/ui_kit/gallery.tscn").instantiate()
	host.add_child(gallery)
	gallery.size = host.size
	for i in 3: await get_tree().process_frame
	var update := OS.get_environment("UPDATE_UI_SNAPSHOTS") == "1"
	var mismatched := []
	for id in gallery.sections:
		var dump := JSON.stringify(_dump(gallery.sections[id], gallery.sections[id]), "  ", false)
		var path := SNAP_DIR.path_join("%s.json" % id)
		if update or not FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(dump + "\n")
			f.close()
			continue
		if FileAccess.get_file_as_string(path).strip_edges() != dump.strip_edges(): mismatched.append(id)
	UiCommandButton.offline = was_offline
	for f in fonts: f.allow_system_fallback = true
	assert_array(mismatched).override_failure_message("layout changed: %s (rerun with UPDATE_UI_SNAPSHOTS=1 if intended)" % [mismatched]).is_empty()

func _dump(node: Control, origin: Control) -> Dictionary:
	var r := node.get_global_rect()
	var o := origin.get_global_rect().position
	var d := {
		"type": _type(node),
		"rect": [roundi(r.position.x - o.x), roundi(r.position.y - o.y), roundi(r.size.x), roundi(r.size.y)],
	}
	if node.theme_type_variation != &"": d["variation"] = String(node.theme_type_variation)
	if node is Label: d["text"] = (node as Label).text
	if node is Button:
		d["text"] = (node as Button).text
		if (node as Button).disabled: d["disabled"] = true
		if (node as Button).button_pressed: d["pressed"] = true
	var kids := []
	for c in node.get_children():
		if c is Control and (c as Control).visible: kids.append(_dump(c, origin))
	if not kids.is_empty(): d["children"] = kids
	return d

func _type(node: Node) -> String:
	var s: Script = node.get_script()
	if s != null and s.get_global_name() != &"": return String(s.get_global_name())
	return node.get_class()
