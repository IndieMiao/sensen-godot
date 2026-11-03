extends Node

signal language_changed

const SETTINGS_PATH := "user://language.cfg"
const SUPPORTED := ["zh_CN", "en"]

## P0 (0.2.21, 中文版): its own table and its own choice, English by default (the user, 11-02); see use_p0().
const P0_SETTINGS_PATH := "user://p0_language.cfg"
const P0_TABLE := "res://assets/localization/p0_zh_CN.json"
const P0_SUPPORTED := ["en", "zh_CN"]

var _journey: Translation
var p0_translation: P0Translation

func _init() -> void:
	var translation := Translation.new()
	translation.locale = "zh_CN"
	var messages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/localization/zh_CN.json"))
	for source in messages:
		translation.add_message(source, messages[source])
	TranslationServer.add_translation(translation)
	_journey = translation
	var locale := load_preference()
	# Godot consumes --language before autoloads; use an explicit QA override.
	var override := OS.get_environment("SENSEN_LANGUAGE")
	if override in SUPPORTED: locale = override
	TranslationServer.set_locale(locale)

func load_preference(path := SETTINGS_PATH) -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK: return "zh_CN"
	var saved := str(config.get_value("interface", "language", "zh_CN"))
	return saved if saved in SUPPORTED else "zh_CN"

func select_language(locale: String, path := SETTINGS_PATH) -> Error:
	if locale not in SUPPORTED: return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("interface", "language", locale)
	var error := config.save(path)
	if error != OK: return error
	TranslationServer.set_locale(locale)
	language_changed.emit()
	return OK

## P0's language (0.2.21): Journey's table goes (the same English can mean another thing there), P0's table comes in and
## the locale is the player's choice, English until they pick 中文 (the user, 11-02). Labels and buttons translate as
## they draw (P0Ui's root translates since 0.2.21), through P0Translation; SENSEN_LANGUAGE still overrides for QA.
## English (the default) changes nothing else: Journey's table is inert under "en", and the fonts keep their metrics.
func use_p0(path := P0_SETTINGS_PATH) -> void:
	var locale := p0_language(path)
	var override := OS.get_environment("SENSEN_LANGUAGE")
	if override in P0_SUPPORTED: locale = override
	if locale == "zh_CN":
		if _journey != null:
			TranslationServer.remove_translation(_journey)
			_journey = null
		if p0_translation == null:
			p0_translation = P0Translation.new()
			p0_translation.load_table(P0_TABLE)
			TranslationServer.add_translation(p0_translation)
		set_cjk_fonts(true)
	TranslationServer.set_locale(locale)

## One English word, two Chinese ones (李白's notes §三 #8 / #9, 不知火舞 385 B): the skill `Cooking` 烹饪 vs the stove's
## `Cooking` 烹饪中, the family `Water` 水 vs the button's `Water` 浇水. Under P0's 中文 the table's `"<src>@<context>"`
## (`Cooking@skill`, `Water@family`) when it has one, else `src` as it is — English always `src`. The label keeps
## translating: the Chinese has no letters (P0Translation passes it), and a word with no such key reads its plain one.
## A format too: `ctx("%d", "trip") % 6` is `6` in English, 「第 6 档」 by `%d@trip` (the city card's `6 · Continental`).
func ctx(src: String, context: String) -> String:
	if p0_translation == null or TranslationServer.get_locale() != "zh_CN": return src
	return str(p0_translation.exact("%s@%s" % [src, context], src))

## UiKit's three weights (nunito_w400 / 700 / 800) draw Chinese through Noto Sans SC, 700 and 800 emboldened (Journey's
## GameUi.theme did 0.45; 不知火舞 sets the values from shots). Only under 中文: a fallback adds its ascent and descent to
## every line's height, which would move the English layouts measured to the frames.
const CJK_FONT := "res://assets/ui/fonts/NotoSansSC-Regular.otf"
const CJK_EMBOLDEN := {400: 0.0, 700: 0.45, 800: 0.6}
## The three weights as set here, held for as long as this autoload lives: nothing else may hold them yet when P0 starts
## (the theme loads later), and a font no one holds leaves the resource cache — the next load() made a new one without
## the fallback, and Chinese was drawn by the system's fallback font: thin at every weight, 远 and 鉴 boxes (B 档 shots,
## SGODOT-385, 11-03).
var _cjk_held: Array[FontVariation] = []
func set_cjk_fonts(on: bool) -> void:
	_cjk_held.clear()
	for weight in CJK_EMBOLDEN:
		var font := load("res://assets/ui/fonts/nunito_w%d.tres" % weight) as FontVariation
		if font == null: continue
		if not on:
			font.fallbacks = []
			continue
		_cjk_held.append(font)
		var cjk := FontVariation.new()
		cjk.base_font = load(CJK_FONT)
		cjk.variation_embolden = float(CJK_EMBOLDEN[weight])
		font.fallbacks = [cjk]

func _exit_tree() -> void:
	# P0's table is a script's Translation: let it go before the engine unloads its script (a crash at quit otherwise)
	if p0_translation != null:
		TranslationServer.remove_translation(p0_translation)
		p0_translation = null

## The language the player picked in P0's Settings; English when none (or one this build does not know).
func p0_language(path := P0_SETTINGS_PATH) -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK: return "en"
	var saved := str(config.get_value("interface", "language", "en"))
	return saved if saved in P0_SUPPORTED else "en"

## Saved for the next start (the user's pick: a restart applies it, P0's Settings says so); the locale is not changed
## now, as text already drawn in code would stay in the other language.
func select_p0_language(locale: String, path := P0_SETTINGS_PATH) -> Error:
	if locale not in P0_SUPPORTED: return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("interface", "language", locale)
	return config.save(path)

## P0's zh_CN table (assets/localization/p0_zh_CN.json: English source → Chinese). A line not in it is tried as a
## template — a source with format specs (%d, %s, %+d, %.1f; %% a percent sign: `Need %d more %s` → `还差 %d 个%s`;
## `{1}` / `{2}` in the Chinese to reorder) — with each %s it caught translated again (an item's name, a weekday) and a
## plural ending (`dish%s` → s / es) dropped; then line by line, then by its ` · ` parts; a link's ` ›` (`Edit look ›`) and
## a list whose every item it knows (`Carrot, Herb` → `胡萝卜、香草`), spaces around a line (`Muscle Memory `) and a
## count after it (`Home Cook 0/8`) are read around. Nothing found: "" (the English stays). Answers are cached: labels ask again on every redraw. P0_I18N_MISSES=<file> (QA): every line drawn that found
## nothing is written there once, for the translators.
class P0Translation extends Translation:
	var _exact := {}
	var _templates: Array = []   # [RegEx, Chinese, literal length, %s count, has ` · `] — the longest literal tried first
	var _cache := {}
	const CACHE_MAX := 4096
	const PLURAL_ENDINGS := ["s", "es"]   # `%d dish%s`: English's plural, nothing in Chinese (李白's notes, q(275))
	const LINK := " ›"   # a row or key that opens something: the arrow stays, the words before it are translated
	const LIST_LAST := {" and ": "和", " or ": "或"}   # a list's last item: `Carrot and Herb` 胡萝卜和香草
	var _misses := {}
	var _miss_file: FileAccess
	static var SPEC := _spec_re()
	static var COUNT := _count_re()

	static func _spec_re() -> RegEx:
		var re := RegEx.new()
		re.compile("%[+-]?[0-9]*(\\.[0-9]+)?[dsf]")
		return re

	static func _count_re() -> RegEx:
		var re := RegEx.new()
		re.compile(" [0-9][0-9,]*/[0-9][0-9,]*$")
		return re

	func load_table(path: String) -> void:
		locale = "zh_CN"
		if not FileAccess.file_exists(path): return
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary: return
		set_table(data)

	func set_table(data: Dictionary) -> void:
		_exact.clear()
		_templates.clear()
		_cache.clear()
		for source in data:
			var en := str(source)
			var zh = data[source]
			if en.begins_with("_") or not zh is String or str(zh).is_empty(): continue
			if SPEC.search(en) != null and not en.contains("@"):   # a context key (`%d@trip`) is Localization.ctx's, whole
				var re := RegEx.new()
				if re.compile(_pattern(en)) == OK:
					_templates.append([re, str(zh), en.replace("%d", "").replace("%s", "").length(), en.count("%s"), en.contains(" · ")])
			else:
				_exact[en] = str(zh)
		# as long: the one with fewer %s first — `%d XP` takes `+20 XP` (「+20 经验」), `%s XP` the skill's `Farming XP`
		# (「种植经验」), #649 第二批 ②
		_templates.sort_custom(func(a, b): return int(a[2]) > int(b[2]) or (int(a[2]) == int(b[2]) and int(a[3]) < int(b[3])))

	static func _pattern(en: String) -> String:
		var out := "^"
		var i := 0
		while i < en.length():
			if en[i] == "%" and i + 1 < en.length() and en[i + 1] == "%":
				out += "%"
				i += 2
				continue
			if en[i] == "%":
				var m := SPEC.search(en, i)
				if m != null and m.get_start() == i:
					var kind := m.get_string().right(1)
					out += "(.*?)" if kind == "s" else ("([+-]?[0-9][0-9,]*\\.?[0-9]*)" if kind == "f" else "([+-]?[0-9][0-9,]*)")
					i = m.get_end()
					continue
			var c := en[i]
			out += ("\\" + c) if c in ".^$*+?()[]{}|\\/" else c
			i += 1
		return out + "$"

	func _get_message(src_message: StringName, _context: StringName) -> StringName:
		var s := String(src_message)
		if s.is_empty() or not _letters(s): return &""   # numbers and signs alone: nothing to translate
		if _exact.has(s): return _exact[s]
		if _cache.has(s): return _cache[s]
		var out := translate_line(s)
		if _cache.size() >= CACHE_MAX: _cache.clear()
		_cache[s] = out
		if out == "": _miss(s)
		return out

	## QA only (P0_I18N_MISSES): a line no part of which is in the table, once per run.
	func _miss(s: String) -> void:
		if _misses.has(s): return
		_misses[s] = true
		if _miss_file == null:
			var path := OS.get_environment("P0_I18N_MISSES")
			if path == "": return
			_miss_file = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
			if _miss_file == null: return
			_miss_file.seek_end()
		_miss_file.store_line(s.c_escape())
		_miss_file.flush()

	## The table's own line for `s`, nothing pieced together (Localization.ctx's `<src>@<context>` keys).
	func exact(s: String, otherwise := "") -> String: return str(_exact.get(s, otherwise))

	## The Chinese for one line, or "" when no part of it is known.
	func translate_line(s: String) -> String:
		if _exact.has(s): return _exact[s]
		var t := _template(s)
		if t != "": return t
		if s.ends_with(" · ") and s.length() > 3:   # a line's first half drawn on its own (the HUD's `San Francisco · `)
			var head := translate_line(s.left(s.length() - 3))
			return head + " · " if head != "" else ""
		var bare := s.strip_edges()
		if bare != s and bare != "":   # a label padded with spaces (`Muscle Memory `): the spaces stay where they were
			var z := translate_line(bare)
			if z == "": return ""
			var at := s.find(bare)
			return s.left(at) + z + s.substr(at + bare.length())
		if s.contains("\n"):
			var lines := s.split("\n")
			var parts: Array = []
			var any := false
			for line in lines:
				var z := translate_line(line)
				any = any or z != ""
				parts.append(z if z != "" else line)
			return "\n".join(parts) if any else ""
		if s.contains(" · "):
			var segs := s.split(" · ")
			var parts: Array = []
			var any := false
			for seg in segs:
				var z := translate_line(seg)
				any = any or z != ""
				parts.append(z if z != "" else seg)
			return " · ".join(parts) if any else ""
		if s.begins_with("· ") and s.length() > 2:   # a caption's second half drawn on its own (`· Mission Market Square`)
			var rest := translate_line(s.substr(2))
			return "· " + rest if rest != "" else ""
		if s.ends_with(LINK) and s.length() > LINK.length():
			var head := translate_line(s.left(s.length() - LINK.length()))
			return head + LINK if head != "" else ""
		var count := COUNT.search(s)
		# A title with its count after it (`Home Cook 0/8`): the count stays. Only `n/m` — a bare number may be part of
		# the name (`Floor 10`).
		if count != null and count.get_start() > 0:
			var head := translate_line(s.left(count.get_start()))
			return head + count.get_string() if head != "" else ""
		# a list: only when every item is known, joined the Chinese way — `Carrot, Herb` 胡萝卜、香草; with its last item
		# after ` and ` / ` or ` (`Carrot and Herb`, `A, B and C`, `Grilled or Soup`) 和 / 或 before it (#649 第二批 ⑩).
		# A template has had the whole line first (`Try %s or %s`); a sentence with an unknown word stays English.
		for conj in LIST_LAST:
			var at := s.rfind(conj)
			if at <= 0: continue
			var items := _list_items(s.left(at).split(", ") + PackedStringArray([s.substr(at + conj.length())]))
			if items.is_empty(): return ""
			return "、".join(items.slice(0, -1)) + str(LIST_LAST[conj]) + str(items[-1])
		if s.contains(", "):
			return "、".join(_list_items(s.split(", ")))
		return ""

	## Each item's Chinese, or [] when one is not known.
	func _list_items(parts: PackedStringArray) -> Array:
		var items: Array = []
		for item in parts:
			var z := translate_line(item)
			if z == "": return []
			items.append(z)
		return items

	func _template(s: String) -> String:
		for entry in _templates:
			var m: RegExMatch = (entry[0] as RegEx).search(s)
			if m == null: continue
			# a template with no ` · ` of its own is one part: `%s XP` does not take `Common · First cook +10 XP` whole,
			# the line's parts go one by one (`First cook +%d XP` the second) — #649 第二批 ⑦
			if not bool(entry[4]) and s.contains(" · "): continue
			var values: Array = []
			for g in range(1, m.get_group_count() + 1):
				var v := m.get_string(g)
				if v in PLURAL_ENDINGS:
					values.append("")
					continue
				var z := "" if v.is_empty() or v.replace(",", "").replace("+", "").replace("-", "").is_valid_float() else translate_line(v)
				values.append(z if z != "" else v)
			return _fill(str(entry[1]), values)
		return ""

	## The Chinese template filled: `{1}`…`{n}` by position when it has them (any may be left out — a plural's ending),
	## else its format specs in order; `%%` is a percent sign either way.
	static func _fill(zh: String, values: Array) -> String:
		if zh.contains("{1}") or zh.contains("{2}"):
			var out := zh
			for i in values.size(): out = out.replace("{%d}" % (i + 1), str(values[i]))
			return out.replace("%%", "%")
		var out := ""
		var k := 0
		var i := 0
		while i < zh.length():
			if zh[i] == "%" and i + 1 < zh.length() and zh[i + 1] == "%":
				out += "%"
				i += 2
				continue
			if zh[i] == "%" and k < values.size():
				var m := SPEC.search(zh, i)
				if m != null and m.get_start() == i:
					out += str(values[k])
					k += 1
					i = m.get_end()
					continue
			out += zh[i]
			i += 1
		return out

	static func _letters(s: String) -> bool:
		for c in s:
			if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z"): return true
		return false
