extends SceneTree
## 检查主题字体（Nunito + Noto Sans SC 回退）是否覆盖 zh_CN.po 里全部译文字符。
## 用法：godot --headless --path . --script tools/i18n/check_glyphs.gd   （缺字退出码 2）
func _init() -> void:
	var font := GameUi.theme().default_font
	var po := FileAccess.get_file_as_string("res://locale/zh_CN.po")
	var missing := {}
	var total := 0
	for line in po.split("\n"):
		if not line.begins_with("msgstr \""):
			continue
		var text := line.trim_prefix("msgstr \"").trim_suffix("\"")
		for ch in text:
			total += 1
			if not font.has_char(ch.unicode_at(0)):
				missing[ch] = true
	print("glyph check: %d chars in zh_CN.po, %d missing: %s" % [total, missing.size(), " ".join(missing.keys())])
	quit(2 if missing.size() > 0 else 0)
