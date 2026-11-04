class_name P0Legal
extends RefCounted
## Settings › Legal (q(129); SETTINGS-1-2 1252:88686, SET-LICENSES 1254:88796 — 不知火舞 280 4c8d286a): the credits as
## data (assets/p0/legal/licenses.json: groups of rows {id, title, license, credit?, text}), each row's full text, and
## the Version row's words. Map data rows are added by hand there: no dependency list carries them (q(129) ④).

const DATA := "res://assets/p0/legal/licenses.json"
## Settings › Privacy › Voice chat (q(277), 李白 5b8090b1; 不知火舞's words): where voice goes and that nothing keeps it.
const VOICE_CHAT := "Your voice is relayed live by LiveKit, a US-based service. Only people in your layer hear it, and only while your mic is on. We don't record it, and we keep LiveKit's recording off."
const ENGINE := "engine"   # a row's text: Godot's own license and its third-party notices, from the engine itself

static var _data := {}

## q(281) ① (SGODOT-390): the Privacy Policy, by platform — Legal's first row opens it in the system browser. The row
## shows only once the pages are up: PRIVACY_LIVE was false until they were; both up 11-03 21:46 (奕星), so true.
const PRIVACY_LIVE := true
const PRIVACY_IOS := "https://gensen.app/privacy"
const PRIVACY_ANDROID := "https://gensen.app/privacy-android"
static func privacy_url(os_name: String, live := PRIVACY_LIVE) -> String:
	if not live: return ""
	return PRIVACY_IOS if os_name == "iOS" else PRIVACY_ANDROID

## q(281) ② (后裔's privacy-server-2026-11-03 ①): the support code a player sends with a request about their data —
## SHA-256 of `p0-support/v1/` + the player id (UTF-8), its first 50 bits as 10 Crockford Base32 characters (0–9 and
## the letters but I L O U), `XXXXX-XXXXX`. Worked out here, so it shows offline; the server has the same function to
## look a save up. Not a credential. "" without an id.
const SUPPORT_PREFIX := "p0-support/v1/"
const CROCKFORD := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
static func support_code(player_id: String) -> String:
	if player_id == "": return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((SUPPORT_PREFIX + player_id).to_utf8_buffer())
	var digest := ctx.finish()
	var bits := 0   # the first 56 bits; the top 50 are used
	for i in 7: bits = (bits << 8) | digest[i]
	bits = bits >> 6
	var out := ""
	for i in 10: out = CROCKFORD[(bits >> (5 * i)) & 31] + out
	return out.left(5) + "-" + out.right(5)

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
## a list item (`* `, `- `) starts its own; an HTML entity reads as its character. Nothing else of the text changes.
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
			elif t.begins_with("* ") or t.begins_with("- "):   # a list item starts its own (BSD's clauses; 刘邦 on #292)
				out.append(joined)
				joined = t
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
