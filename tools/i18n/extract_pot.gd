extends SceneTree
## 用法：
##   godot --headless --path . --script res://tools/i18n/extract_pot.gd            # 写 locale/messages.pot 与 locale/en.po
##   godot --headless --path . --script res://tools/i18n/extract_pot.gd -- --check # 只校验 en/zh_CN 是否覆盖全部 key，缺失退出码 2
## 抽取范围：社交主线代码（modules/app、modules/ui、scenes/app、modules/net/firebase_auth.gd、modules/net/ws_client.gd）。
## 翻译后 PO 交 SSLAUNCH E10 校对，导回时不要改 msgid。

## 用 preload 而不是全局类名：独立 --script 运行时全局类缓存可能还没建（要先 --import）。
const Tools := preload("res://modules/app/i18n_tools.gd")

const ROOTS := ["res://modules/app", "res://modules/ui", "res://scenes/app"]
const EXTRA_FILES := ["res://modules/net/firebase_auth.gd", "res://modules/net/ws_client.gd"]
const POT := "res://locale/messages.pot"
const PO_FILES := {"en": "res://locale/en.po", "zh_CN": "res://locale/zh_CN.po"}

func _init() -> void:
	var files: Array = []
	for r in ROOTS:
		files.append_array(Tools.list_gd_files(r))
	files.append_array(EXTRA_FILES)
	var entries := Tools.extract_from_files(files)
	var check_only := OS.get_cmdline_user_args().has("--check")
	var code := 0
	if check_only:
		for lang in PO_FILES:
			var po := Tools.parse_po(FileAccess.get_file_as_string(PO_FILES[lang]))
			var res := Tools.check_po(entries, po, lang != "en")
			for m in res.missing:
				printerr("[%s] missing: %s" % [lang, m])
			for m in res.placeholder_mismatch:
				printerr("[%s] placeholder mismatch: %s" % [lang, m])
			if not res.missing.is_empty() or not res.placeholder_mismatch.is_empty():
				code = 2
		print("i18n check: %d keys, %s" % [Tools.unique_entries(entries).size(), "OK" if code == 0 else "FAILED"])
	else:
		var f := FileAccess.open(POT, FileAccess.WRITE)
		f.store_string(Tools.pot_text(entries))
		f.close()
		var en := FileAccess.open(PO_FILES["en"], FileAccess.WRITE)
		en.store_string(Tools.en_po_text(entries))
		en.close()
		print("wrote %s and %s (%d keys from %d files)" % [POT, PO_FILES["en"], Tools.unique_entries(entries).size(), files.size()])
	quit(code)
