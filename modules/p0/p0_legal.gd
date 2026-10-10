class_name P0Legal
extends RefCounted
## Settings › Legal (q(129); SETTINGS-1-2 1252:88686, SET-LICENSES 1254:88796 — 不知火舞 280 4c8d286a): the credits as
## data (assets/p0/legal/licenses.json: groups of rows {id, title, license, credit?, text}), each row's full text, and
## the Version row's words. Map data rows are added by hand there: no dependency list carries them (q(129) ④).

const DATA := "res://assets/p0/legal/licenses.json"
const ENGINE := "engine"   # a row's text: Godot's own license and its third-party notices, from the engine itself

static var _data := {}

## The page's groups in order: [{title, rows: [{id, title, license, credit?, text}]}].
static func groups() -> Array:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
		_data = parsed if parsed is Dictionary else {"groups": []}
	return _data.get("groups", [])

## One row by id, {} when there is none.
static func row(id: String) -> Dictionary:
	for g in groups():
		for r in g.get("rows", []):
			if str(r.get("id", "")) == id: return r
	return {}

## A row's full text as shipped (the publisher's own file, unchanged); "" when it is missing.
static func full_text(r: Dictionary) -> String:
	var src := str(r.get("text", ""))
	if src == ENGINE: return engine_text()
	return FileAccess.get_file_as_string(src) if src != "" and FileAccess.file_exists(src) else ""

## Godot's MIT license, then the components it is built from with their copyright and license, then those licenses'
## texts — the engine's own lists (Engine.get_copyright_info / get_license_info, 李白 on #292).
static func engine_text() -> String:
	var out := Engine.get_license_text().strip_edges() + "\n\nThird-party components"
	for c in Engine.get_copyright_info():
		for part in c.get("parts", []):
			var who := ", ".join(Array(part.get("copyright", [])).map(func(x): return "© " + str(x)))
			out += "\n\n%s: %s (%s)" % [str(c.get("name", "")), who, str(part.get("license", ""))]
	var texts: Dictionary = Engine.get_license_info()
	out += "\n\nLicenses"
	for name in texts:
		out += "\n\n%s\n\n%s" % [str(name), str(texts[name]).strip_edges()]
	return out

## The text as paragraphs for a narrow page: blank lines part them; the hard-wrapped lines inside one join with a space
## (the files are wrapped at about 72 columns), or with none after a word broken at its hyphen (`CC-` / `licensed`); a
## Markdown heading's #s and the ===== rules go (a heading is a paragraph of its own, even with no blank line after it),
## an HTML entity reads as its character. Nothing else of the text changes.
static func paragraphs(text: String) -> Array:
	var out: Array = []
	for block in text.replace("\r\n", "\n").split("\n\n"):
		var joined := ""
		for line in block.split("\n"):
			var t := line.strip_edges()
			if t == "" or t.replace("=", "") == "" or t.replace("-", "") == "": continue
			var heading := t.begins_with("#")
			while t.begins_with("#"): t = t.substr(1)
			t = _entities(t.strip_edges())
			if heading:
				if joined != "": out.append(joined)
				out.append(t)
				joined = ""
			elif joined == "": joined = t
			elif _broken_at_hyphen(joined): joined += t
			else: joined += " " + t
		if joined != "": out.append(joined)
	return out

## The few HTML entities a Markdown licence file writes (Mapbox's `Copyright &copy; 2021 - 2026`) as their characters.
static func _entities(line: String) -> String:
	return line.replace("&copy;", "©").replace("&quot;", "\"").replace("&#39;", "'").replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")

## A line that ends in a word's own hyphen (`CC-`, not ` -` or the `--` dash).
static func _broken_at_hyphen(line: String) -> bool:
	if not line.ends_with("-") or line.ends_with("--") or line.length() < 2: return false
	var c := line.unicode_at(line.length() - 2)
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

## The Version row (SETTINGS-1-2): `0.2.1 (2026101001)` — the demo build's version name and code (baked by
## tools/p0/build_demo_apk.sh into its server file); `dev` in any other build.
static func version_line(config: Dictionary) -> String:
	var code := int(config.get("version", 0))
	var name := str(config.get("name", ""))
	if code <= 0: return "dev"
	return "%s (%d)" % [name, code] if name != "" else str(code)
