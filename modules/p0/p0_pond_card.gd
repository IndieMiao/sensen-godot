extends RefCounted
## The map's pond card and pin tag (SGODOT-227 follow-up; Figma TUT-3-04 482:193, Li Bai q(48)), from the content's
## fishing.places / sites and the player's skills: no server state of its own.
##   title, subtitle (Beginner for the beginner pond, else its template), the beginner line, Distance from where
##   the player is (the place chip's place), Recommended by template (Outleveled once every fish there pays 0 XP),
##   and the pin tag "Beginner pond · 0.8 km" / "Pond · 1.6 km".

const RECOMMENDED := {"Pond": "Lv1–3", "River": "Lv4–5", "Coast": "Lv6+"}   # q(48); Coast from P1 (§6.3.1, SGODOT-283)
const BEGINNER_LINE := "A nearby pond for your first catch."

## {} for a pond the content does not know (another city's pond).
static func info(view: Dictionary, pond_id: String, km: float) -> Dictionary:
	var fishing: Dictionary = P0Logic.content().get("fishing", {})
	var place := place_of(pond_id)
	if place.is_empty(): return {}
	var site: Dictionary = fishing.get("sites", {}).get(str(place.get("site", "pond")), {})
	var template := str(site.get("template", "Pond"))
	var beginner := bool(place.get("beginner", false))
	var distance := P0PlaceSheet.distance_text(km)
	return {
		"title": str(place.get("name", "")),
		"subtitle": "Beginner" if beginner else template,
		"line": BEGINNER_LINE if beginner else "",
		"facts": [["Distance", distance], ["Recommended", "Outleveled" if outleveled(view, pond_id) else str(RECOMMENDED.get(template, ""))]],
		"tag": "%s · %s" % ["Beginner pond" if beginner else template, distance],
	}

## Every fish of the site pays 0 XP at the player's Fishing level (the server's xpPercent: a gap past the
## xp_multiplier table is "outleveled").
static func outleveled(view: Dictionary, pond_id: String) -> bool:
	var content := P0Logic.content()
	var level := int(view.get("skills", {}).get("fishing", {}).get("level", 1))
	var gaps: Array = content.get("xp_multiplier", []).map(func(row): return int(row[0]))
	var widest := int(gaps.max()) if not gaps.is_empty() else 4
	var fish: Array = P0Logic.pond_fish(view, pond_id)
	if fish.is_empty(): return false
	for id in fish:
		for f in content.get("fish", []):
			if str(f.get("id", "")) == str(id) and level - int(f.get("level", 1)) <= widest: return false
	return true

## Details ›: the fish of this pond's template that P0 can catch (q(48) c), easiest first. caught = the player has
## landed one (view.fishing.dex); the card shows those with their icon and name, the rest as a silhouette with
## their name and the Fishing level they need (Old Kai's Golden Koi shows up in the Pond list this way). That is
## for global fish, which all P0 fish are; regional fish (P1) show only a silhouette and "?" until caught (q(48)).
static func fish_rows(view: Dictionary, pond_id: String) -> Array:
	var content := P0Logic.content()
	var place := place_of(pond_id)
	if place.is_empty(): return []
	var caught := {}
	for d in view.get("fishing", {}).get("dex", []): caught[str(d.get("id", ""))] = int(d.get("caught", 0)) > 0
	var defs := {}
	for f in content.get("fish", []): defs[str(f.get("id", ""))] = f
	var rows: Array = []
	for id in P0Logic.pond_fish(view, pond_id):
		var f: Dictionary = defs.get(str(id), {})
		var regional := bool(f.get("regional", false))
		var got := bool(caught.get(str(id), false))
		# A regional fish not yet caught keeps its name back (q(48), 不知火舞 69310899): `?` over `Fishing Lv3 · Regional`
		rows.append({"id": str(id), "name": str(f.get("name", id)) if got or not regional else "?", "level": int(f.get("level", 1)),
			"rarity": int(f.get("rarity", 1)), "caught": got, "regional": regional})
	rows.sort_custom(func(a, b): return [a.level, a.rarity, a.id] < [b.level, b.rarity, b.id])
	return rows

## A Details row's second line for a fish not yet caught: `Fishing Lv3`, a regional one `Fishing Lv3 · Regional`.
static func locked_line(row: Dictionary) -> String:
	return "Fishing Lv%d" % int(row.get("level", 1)) + (" · Regional" if bool(row.get("regional", false)) else "")

## A pond's content place ({name, site, beginner}): the hand-written table, else a generated pond of a city already read
## (P0CityPlaces, SGODOT-280: `gn-1850147~pond0`, its site and name from the server's generator).
static func place_of(pond_id: String) -> Dictionary:
	var own: Dictionary = P0Logic.content().get("fishing", {}).get("places", {}).get(pond_id, {})
	if not own.is_empty(): return own
	var gen: Dictionary = load("res://modules/p0/p0_city_places.gd").pond(pond_id)
	return {} if gen.is_empty() else {"name": gen.name, "site": gen.site, "beginner": gen.beginner, "city": gen.cluster}
