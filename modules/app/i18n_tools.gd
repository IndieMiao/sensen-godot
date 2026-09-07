class_name I18nTools
extends RefCounted
## i18n 抽取与校验的纯函数（tools/i18n/extract_pot.gd 与守卫测试共用）。
## 抽三类：`tr("…")` 字面量；`page_title = "…"`；带 `## i18n` 尾注的行上所有双引号字串
## （用于 AppRoutes.TAB_TITLES、FirebaseAuth.describe() 这类不经 tr() 直接返回 key 的地方）。

const PATTERN_TR := 'tr\\("((?:[^"\\\\]|\\\\.)+)"\\)'
const PATTERN_TITLE := 'page_title\\s*=\\s*"((?:[^"\\\\]|\\\\.)+)"'
const PATTERN_QUOTED := '"((?:[^"\\\\]|\\\\.)+)"'
const I18N_MARK := "## i18n"

## 返回 [{msgid, ref}]，ref 形如 path:line。
static func extract_from_source(text: String, path: String) -> Array:
	var out: Array = []
	var re_tr := RegEx.create_from_string(PATTERN_TR)
	var re_title := RegEx.create_from_string(PATTERN_TITLE)
	var re_quoted := RegEx.create_from_string(PATTERN_QUOTED)
	var lines := text.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		if line.strip_edges().begins_with("#"):
			continue # 注释里的示例不是 key
		var ref := "%s:%d" % [path, i + 1]
		for m in re_tr.search_all(line):
			out.append({"msgid": _unescape(m.get_string(1)), "ref": ref})
		for m in re_title.search_all(line):
			out.append({"msgid": _unescape(m.get_string(1)), "ref": ref})
		if line.contains(I18N_MARK):
			var code_part := line.substr(0, line.find(I18N_MARK))
			for m in re_quoted.search_all(code_part):
				out.append({"msgid": _unescape(m.get_string(1)), "ref": ref})
	return out

## 抽取工具自己的正则常量不算 key。
const SELF_FILE := "i18n_tools.gd"

static func extract_from_files(paths: Array) -> Array:
	var out: Array = []
	for p in paths:
		if not FileAccess.file_exists(p) or str(p).ends_with(SELF_FILE):
			continue
		out.append_array(extract_from_source(FileAccess.get_file_as_string(p), p))
	return out

## 递归列出目录下的 .gd 文件。
static func list_gd_files(root: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while not name.is_empty():
		var full := root.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				out.append_array(list_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

## 去重并按 msgid 排序；同一 msgid 的 ref 合并。
static func unique_entries(entries: Array) -> Array:
	var by_id := {}
	for e in entries:
		var id: String = e.msgid
		if not by_id.has(id):
			by_id[id] = {"msgid": id, "refs": []}
		if not (by_id[id].refs as Array).has(e.ref):
			by_id[id].refs.append(e.ref)
	var ids := by_id.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		out.append(by_id[id])
	return out

## 源语言 .po：与 pot 同一份 key，msgstr 留空（Godot 空 msgstr 回退到 msgid）。
static func en_po_text(entries: Array) -> String:
	var s := "# en-US 源语言模板，由 tools/i18n/extract_pot.gd 生成，勿手改；msgstr 留空即回退 msgid。\n"
	s += "msgid \"\"\nmsgstr \"\"\n\"Language: en\\n\"\n\"Content-Type: text/plain; charset=UTF-8\\n\"\n\n"
	for e in unique_entries(entries):
		s += "msgid \"%s\"\nmsgstr \"\"\n\n" % _escape(e.msgid)
	return s

static func pot_text(entries: Array) -> String:
	var s := "# 由 tools/i18n/extract_pot.gd 生成，勿手改；翻译写在 locale/<lang>.po。\n"
	s += "msgid \"\"\nmsgstr \"\"\n\"Content-Type: text/plain; charset=UTF-8\\n\"\n\n"
	for e in unique_entries(entries):
		for r in e.refs:
			s += "#: %s\n" % r
		s += "msgid \"%s\"\nmsgstr \"\"\n\n" % _escape(e.msgid)
	return s

## 解析 .po 文本，返回 {msgid: msgstr}（不含头部空 msgid）。支持多行续接。
static func parse_po(text: String) -> Dictionary:
	var out := {}
	var cur_id := ""
	var cur_str := ""
	var mode := ""
	var have_id := false
	var lines := text.split("\n")
	lines.append("")
	for raw in lines:
		var line: String = raw.strip_edges()
		if line.begins_with("#"):
			continue
		if line.begins_with("msgid "):
			if have_id and not cur_id.is_empty():
				out[cur_id] = cur_str
			cur_id = _unescape(_strip_quotes(line.trim_prefix("msgid ")))
			cur_str = ""
			mode = "id"
			have_id = true
		elif line.begins_with("msgstr "):
			cur_str = _unescape(_strip_quotes(line.trim_prefix("msgstr ")))
			mode = "str"
		elif line.begins_with("\""):
			var piece := _unescape(_strip_quotes(line))
			if mode == "id":
				cur_id += piece
			elif mode == "str":
				cur_str += piece
		elif line.is_empty():
			if have_id and not cur_id.is_empty():
				out[cur_id] = cur_str
			cur_id = ""
			cur_str = ""
			mode = ""
			have_id = false
	return out

## msgid 里出现的格式占位符（%s / %d / %%）序列，用来校验翻译没丢参数。
static func placeholders(s: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("%[sdf%]")
	for m in re.search_all(s):
		out.append(m.get_string(0))
	return out

## 返回 {missing: [msgid], placeholder_mismatch: [msgid]}。
static func check_po(entries: Array, po: Dictionary, require_translation: bool) -> Dictionary:
	var missing: Array = []
	var mismatch: Array = []
	for e in unique_entries(entries):
		var id: String = e.msgid
		if not po.has(id):
			missing.append(id)
			continue
		var tr_str: String = po[id]
		if require_translation and tr_str.is_empty():
			missing.append(id)
			continue
		if not tr_str.is_empty() and placeholders(tr_str) != placeholders(id):
			mismatch.append(id)
	return {"missing": missing, "placeholder_mismatch": mismatch}

static func _strip_quotes(s: String) -> String:
	var t := s.strip_edges()
	if t.begins_with("\"") and t.ends_with("\"") and t.length() >= 2:
		return t.substr(1, t.length() - 2)
	return t

static func _escape(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

static func _unescape(s: String) -> String:
	return s.replace("\\n", "\n").replace("\\\"", "\"").replace("\\\\", "\\")
