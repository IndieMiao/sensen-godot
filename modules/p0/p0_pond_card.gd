extends RefCounted
## The map's pond card and pin tag (SGODOT-227 follow-up; Figma TUT-3-04 482:193, Li Bai q(48)), from the content's
## fishing.places / sites and the player's skills: no server state of its own.
##   title, subtitle (Beginner for the beginner pond, else its template), the beginner line, Distance from where
##   the player is (the place chip's place), Recommended by template (Outleveled once every fish there pays 0 XP),
##   and the pin tag "Beginner pond · 0.8 km" / "Pond · 1.6 km".
##   P1 (SGODOT-283; 不知火舞 e61cda10 ②, Figma POND-CARD-WX-V2 2255:143053): the template's thumbnail left of the title,
##   the condition line now (`Dusk · Windy`, from view.fishing.places[id]), Biting more (now, hidden when none),
##   Forecast (Fishing Lv3+) and Your trap (q(109) ⑦), in that order after Recommended.

const Board := preload("res://modules/p0/p0_bite_board.gd")
const Trap := preload("res://modules/p0/p0_trap.gd")
const RECOMMENDED := {"Pond": "Lv1–3", "River": "Lv4–5", "Coast": "Lv6+"}   # q(48); Coast from P1 (§6.3.1, SGODOT-283)
const BEGINNER_LINE := "A nearby pond for your first catch."

## {} for a pond the content does not know (another city's pond).
static func info(view: Dictionary, pond_id: String, km: float) -> Dictionary:
	var place := place_of(pond_id)
	if place.is_empty(): return {}
	var template := template_of(pond_id)
	var beginner := bool(place.get("beginner", false))
	var distance := P0PlaceSheet.distance_text(km)
	var facts: Array = [["Distance", distance], ["Recommended", "Outleveled" if outleveled(view, pond_id) else str(RECOMMENDED.get(template, ""))]]
	var now: Dictionary = view.get("fishing", {}).get("places", {}).get(pond_id, {})
	var level := int(view.get("skills", {}).get("fishing", {}).get("level", 1))
	var caught: Dictionary = view.get("fishing", {}).get("caught", {})
	if level >= Board.BITING_NOW_LEVEL:   # one line: Biting now replaces Biting more from Lv8 (不知火舞 on 283)
		var now_fish := Board.biting_now(now, level, caught)
		if now_fish != "": facts.append(["Biting now", now_fish])
	else:
		var more := Board.biting_more(now, level, caught)
		if more != "": facts.append(["Biting more", more])
	var days := Board.forecast(now, level)
	if not days.is_empty(): facts.append(["Forecast", days])   # [[day, weather icon]] × 3: the sheet draws the icons
	var trap := Trap.pond_fact(view, pond_id)
	if not trap.is_empty(): facts.append(trap)
	return {
		"title": str(place.get("name", "")),
		"subtitle": "Beginner" if beginner else template,
		"thumb": str(place.get("site", "pond")),
		"conditions": Board.conditions(now),
		"line": BEGINNER_LINE if beginner else "",
		"facts": facts,
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
	var now: Dictionary = view.get("fishing", {}).get("places", {}).get(pond_id, {})
	var rows: Array = []
	for id in P0Logic.pond_fish(view, pond_id):
		var f: Dictionary = defs.get(str(id), {})
		var regional := bool(f.get("regional", false))
		var got := bool(caught.get(str(id), false))
		# A regional fish not yet caught keeps its name back (q(48), 不知火舞 69310899): `?` over `Fishing Lv3 · Regional`
		# line: the second line (283 e61cda10 ②, 1e21c014 ④) — caught, its condition tags (`Night ×2 · Rain ×1.5`, none for an
		# all-day fish); not yet, `Fishing Lv9 · Night only · Rain ×2`; a regional one only `Fishing Lv8 · Regional`.
		# dim: outside its time window now — its icon and name at 45 %, the line kept (a fish to come back for).
		rows.append({"id": str(id), "name": str(f.get("name", id)) if got or not regional else "?", "level": int(f.get("level", 1)),
			"rarity": int(f.get("rarity", 1)), "caught": got, "regional": regional,
			"line": Board.details_line(f, got), "dim": not now.is_empty() and Board.dim_now(f, now)})
	rows.sort_custom(func(a, b): return [a.level, a.rarity, a.id] < [b.level, b.rarity, b.id])
	return rows

## A Details row's level line for a fish not yet caught: `Fishing Lv3`, a regional one `Fishing Lv3 · Regional` (the
## row's own `line` adds the condition tags since 283).
static func locked_line(row: Dictionary) -> String:
	return "Fishing Lv%d" % int(row.get("level", 1)) + (" · Regional" if bool(row.get("regional", false)) else "")

## A pond's content place ({name, site, beginner}): the hand-written table, else a generated pond of a city already read
## (P0CityPlaces, SGODOT-280: `gn-1850147~pond0`, its site and name from the server's generator).
static func place_of(pond_id: String) -> Dictionary:
	var own: Dictionary = P0Logic.content().get("fishing", {}).get("places", {}).get(pond_id, {})
	if not own.is_empty(): return own
	var gen: Dictionary = load("res://modules/p0/p0_city_places.gd").pond(pond_id)
	return {} if gen.is_empty() else {"name": gen.name, "site": gen.site, "beginner": gen.beginner, "city": gen.cluster}

## A pond's fishing template, content.fishing.sites[its site].template (Pond when none): the card's subtitle, its
## Recommended and the map pin's icon go by it alike.
static func template_of(pond_id: String) -> String:
	var site := str(place_of(pond_id).get("site", "pond"))
	return str(P0Logic.content().get("fishing", {}).get("sites", {}).get(site, {}).get("template", "Pond"))

## The map pin's icon by the pond's fishing template (SGODOT-406, 安其拉's B set; 不知火舞 9b2d28ae, and by the template
## as the card says it, on #740): still water, a stream, a cove. Any other: the still water.
const PIN_ICONS := {"Pond": "pond", "River": "pond_river", "Coast": "pond_coast"}
static func pin_icon(pond_id: String) -> String:
	return str(PIN_ICONS.get(template_of(pond_id), "pond"))

## Where the Details sheet may reach up to: below the HUD's two rows and the place chip (SGODOT-283).
const FISH_SHEET_TOP := 150.0

## Details ›: the pond's fish list (q(48) c; 283 e61cda10 ②) as `ui`'s modal "pond_fish": each fish's icon (a silhouette
## until caught) and name, its second line `line` (fish_rows), icon and name at 45 % outside its window now. × and
## Android Back call `back` (the pond card again). The map's and the Bite Board's pond cards both open it. Returns the
## holder.
static func open_fish(ui: P0Ui, pond_id: String, info: Dictionary, back: Callable) -> Control:
	var holder := Control.new()
	holder.theme = UiKit.theme()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sheet := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_SHEET, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	panel.add_theme_stylebox_override(&"panel", sheet.with_margins(16, 18, 16, 20 + ui.safe_bottom()))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 12)
	panel.add_child(col)
	col.add_child(UiObjectHeader.new({"title": str(info.get("title", "")), "state": "%s fish" % ("Pond" if str(info.get("subtitle", "")) == "Beginner" else str(info.get("subtitle", "")))}))
	# From P1 a pond lists up to ten fish (its regional and night ones, SGODOT-283): the rows scroll under the header and
	# the sheet stops below the HUD, instead of growing past it.
	var scroll := TouchScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = "FishList"
	col.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 12)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for f in fish_rows(ui.view, pond_id):
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		row.name = str(f.id)
		# outside its time window now (283 e61cda10 ②): the icon and the name at 45 %, the tags line at full strength
		var fade := 0.45 if bool(f.get("dim", false)) else 1.0
		var icon := UiKit.icon(P0Logic.icon(str(f.id)), 32)
		icon.name = "Icon"
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.modulate = Color(0.13, 0.15, 0.14, fade) if not f.caught else Color(1, 1, 1, fade)   # not caught: silhouette
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.add_theme_constant_override(&"separation", 2)
		var name_ := UiKit.label(str(f.name), UiTokens.STYLE_C14_XB)
		name_.name = "Name"
		name_.modulate.a = fade
		text.add_child(name_)
		if str(f.get("line", "")) != "":
			var tags := UiKit.label(str(f.line), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
			tags.name = "Line"
			text.add_child(tags)
		row.add_child(text)
		rows.add_child(row)
	# the list's height: all of it when it fits, else what is left between the HUD and the bottom (row 44 + gap 12)
	var room := maxf(160.0, ui.root.size.y - ui.safe_top() - FISH_SHEET_TOP - 18 - 20 - ui.safe_bottom() - 12 - 56)
	scroll.custom_minimum_size.y = minf(room, rows.get_combined_minimum_size().y)
	holder.add_child(panel)
	var close := UiCloseButton.new()
	close.pressed.connect(back)
	holder.add_child(close)
	panel.resized.connect(func():
		close.position = Vector2(panel.size.x - 16 - UiTokens.SIZE_CLOSE, panel.position.y - 6 - UiTokens.SIZE_CLOSE))
	ui._open_modal(holder, 0.0, false)
	ui.modal_kind = "pond_fish"
	ui._modal_back = back   # set after _open_modal, which clears it
	return holder
