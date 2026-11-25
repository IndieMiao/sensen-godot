extends RefCounted
## Names and icons of the parcel farm's items (C-59). The main farm's names are reused read-only (P0 content); only
## the parcel's own blueprints, which the main farm does not have, are named here. Icons are the UI v3 item art (C-86,
## Q-155; C-105) where it has the item; the blueprints keep the existing recipe-card icon, anything else P0's icon.
const NAMES := {"blueprint_cottage": "Cottage Blueprint", "blueprint_coop": "Coop Blueprint", "egg": "Egg"}
const ICONS := {"blueprint_cottage": "recipe_card", "blueprint_coop": "recipe_card"}
## Parcel item → UiArt item art. The hoe is the v3 row tool; the wild herb (picked from the flowers) is the chamomile.
const ART := {"crop_carrot": "carrot", "seed_carrot": "seed_carrot", "wood": "wood", "stone": "stone",
	"wild_herb": "chamomile", "hoe_starter": "row_tool"}

static var _names := {}

## The item's display name, or "" for an id nothing names.
static func name_of(id: String) -> String:
	if NAMES.has(id): return NAMES[id]
	if _names.is_empty(): _names = _content_names()
	return str(_names.get(id, ""))

static func icon_of(id: String) -> Texture2D:
	if ART.has(id):
		var art := UiArt.item(str(ART[id]))
		if art != null: return art
	if id == "egg": return egg_icon()
	return P0Logic.icon(str(ICONS.get(id, id)))

static var _egg: ImageTexture

## The Egg's icon (C-154): neither the UI v3 item art nor P0 has an egg yet, so a cream egg is drawn here (an oval
## with a soft shade, a highlight and a thin warm outline) until item art comes.
static func egg_icon() -> Texture2D:
	if _egg != null: return _egg
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.98, 0.93, 0.82)
	var shade := Color(0.88, 0.76, 0.6)
	var edge := Color(0.62, 0.45, 0.3)
	for y in n:
		for x in n:
			# An egg: a wider bottom than top (y down), centred, 0.62 × 0.82 of the square.
			var u := (x + 0.5 - n * 0.5) / (n * 0.31)
			var v := (y + 0.5 - n * 0.54) / (n * 0.41)
			var widen := 1.0 + 0.16 * v
			var r := sqrt(u * u / (widen * widen) + v * v)
			if r > 1.0: continue
			var c := body.lerp(shade, clampf((u + v) * 0.35 + 0.15, 0.0, 1.0))
			var hl := Vector2(u + 0.35, v + 0.4).length()
			if hl < 0.28: c = c.lerp(Color.WHITE, 0.7 * (1.0 - hl / 0.28))
			if r > 0.92: c = c.lerp(edge, (r - 0.92) / 0.08)
			c.a = clampf((1.0 - r) * n * 0.2, 0.0, 1.0)
			img.set_pixel(x, y, c)
	_egg = ImageTexture.create_from_image(img)
	return _egg

static func _content_names() -> Dictionary:
	var content := P0Logic.content()
	var names := {}
	for crop: Dictionary in content.get("crops", []):
		names[str(crop.get("id", ""))] = str(crop.get("name", ""))
		names[str(crop.get("seed", ""))] = str(crop.get("seed_name", ""))
	names.merge(content.get("tools", {}).get("names", {}))
	for id: String in content.get("materials", {}):
		names[id] = str(content.materials[id].get("name", ""))
	names.erase("")
	return names
