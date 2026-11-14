extends RefCounted
## Players' names on screen (SGODOT-491; 不知火舞's account spec v1.1 §4; 后裔's roster `name`, 11-14): the one way a
## member is named — the name they chose (roster.members[] / peer.member / blocks `name`), else the default `Traveller
## 8c3f` from their handle's first four (`旅人 8c3f` under 中文: only the frame translates) — and how a name gives way
## when it does not fit, always at its end with `…`, measured as drawn (16 W, 16 汉字; q(311)'s way).
## A name is never translated: Labels showing one turn auto-translate off; sentences with one go through
## Localization.with_names.

const DEFAULT := "Traveller %s"
## The widest default name (`Traveller wwww`): a name tag never grows past it, so a chosen name crowds no more than
## the defaults did (q(311) ⑤ took their width as it was).
const WIDEST_DEFAULT := "Traveller wwww"
const ELLIPSIS := "…"

## The member's name: `name` when they chose one, else the default from `player` (their handle).
static func of(member: Dictionary) -> String:
	var chosen := str(member.get("name", "")).strip_edges()
	if chosen != "": return chosen
	var handle := str(member.get("player", member.get("handle", "")))
	return Localization.with_names(DEFAULT, [handle.substr(0, 4)])

## `text` as it fits `width` in `font` at `size`: whole, or cut at a letter's edge (a grapheme: an accent or a 汉字 stays
## whole) with `…` after it.
static func fit(text: String, font: Font, size: int, width: float) -> String:
	if font == null or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width: return text
	var breaks := TextServerManager.get_primary_interface().string_get_character_breaks(text)
	var best := ""
	for end in breaks:
		var head := text.substr(0, end).strip_edges(false, true) + ELLIPSIS
		if font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width: break
		best = head
	return best if best != "" else ELLIPSIS

## The name tag's room: the widest default name as drawn (in the language on screen: `旅人 wwww` under 中文), measured
## once per font, size and language.
static var _tag_widths := {}
static func tag_width(font: Font, size: int) -> float:
	if font == null: return INF
	var key := "%d|%d|%s" % [font.get_instance_id(), size, TranslationServer.get_locale()]
	if not _tag_widths.has(key):
		_tag_widths[key] = font.get_string_size(Localization.with_names(DEFAULT, ["wwww"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return float(_tag_widths[key])

## A one-line title with a name in it (`Block <name>?`, `Report <name>`): only the name gives way, the rest stays whole
## (as P0Titles.fit leaves the title: the frame's own words first). `template` takes the name as its one %s.
static func title(template: String, name: String, font: Font, size: int, width: float) -> String:
	var whole := Localization.with_names(template, [name])
	if font == null or font.get_string_size(whole, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width: return whole
	var frame := font.get_string_size(Localization.with_names(template, [""]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return Localization.with_names(template, [fit(name, font, size, maxf(0.0, width - frame))])
