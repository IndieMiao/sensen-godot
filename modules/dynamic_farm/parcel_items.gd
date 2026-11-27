extends RefCounted
## Names and icons of the parcel farm's items (C-59). The main farm's names are reused read-only (P0 content); only
## the parcel's own blueprints, which the main farm does not have, are named here. Icons are the UI v3 item art (C-86,
## Q-155; C-105) where it has the item; the blueprints keep the existing recipe-card icon, anything else P0's icon.
## C-151: the well's blueprint is named as the cottage's; the pail (水桶, SEN-C-151) shows P0's Water icon.
## C-181: the barn's blueprint as the others; milk is drawn here like the egg until item art comes.
## C-182: the sheep pen's blueprint likewise; wool is drawn here too (a fleece) until item art comes.
const NAMES := {"blueprint_cottage": "Cottage Blueprint", "blueprint_coop": "Coop Blueprint", "blueprint_well": "Well Blueprint",
	"blueprint_barn": "Barn Blueprint", "blueprint_sheep_pen": "Sheep Pen Blueprint", "pail": "Pail", "egg": "Egg", "milk": "Milk",
	"wool": "Wool"}
const ICONS := {"blueprint_cottage": "recipe_card", "blueprint_coop": "recipe_card", "blueprint_well": "recipe_card",
	"blueprint_barn": "recipe_card", "blueprint_sheep_pen": "recipe_card", "pail": "water"}
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
	if id == "milk": return milk_icon()
	if id == "wool": return wool_icon()
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

static var _milk: ImageTexture

## The Milk's icon (C-181): no item art has milk yet, so a bottle is drawn here (a white body with a soft shade, a
## narrower neck, a blue cap and a thin outline) until item art comes.
static func milk_icon() -> Texture2D:
	if _milk != null: return _milk
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.99, 0.99, 0.96)
	var shade := Color(0.82, 0.85, 0.88)
	var cap := Color(0.31, 0.53, 0.78)
	var edge := Color(0.45, 0.5, 0.58)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n
			var v := (y + 0.5) / n
			# Half width at this height: cap 0.10–0.20, neck 0.20–0.34, shoulder to 0.44, body to 0.90 (rounded bottom).
			var half := 0.0
			if v >= 0.1 and v < 0.2: half = 0.12
			elif v >= 0.2 and v < 0.34: half = 0.1
			elif v >= 0.34 and v < 0.44: half = lerpf(0.1, 0.22, (v - 0.34) / 0.1)
			elif v >= 0.44 and v < 0.84: half = 0.22
			elif v >= 0.84 and v < 0.9: half = 0.22 * sqrt(maxf(0.0, 1.0 - pow((v - 0.84) / 0.06, 2.0)))
			var off := absf(u - 0.5)
			if off > half: continue
			var c := cap if v < 0.2 else body.lerp(shade, clampf((u - 0.5) / maxf(half, 0.01) * 0.6 + 0.2, 0.0, 1.0))
			if v >= 0.2 and u < 0.42 and u > 0.36 and v > 0.46 and v < 0.78: c = c.lerp(Color.WHITE, 0.8)
			var rim := half - off
			if rim < 0.02: c = c.lerp(edge, 1.0 - rim / 0.02)
			c.a = clampf(rim * n * 0.6, 0.0, 1.0)
			img.set_pixel(x, y, c)
	_milk = ImageTexture.create_from_image(img)
	return _milk

static var _wool: ImageTexture

## The Wool's icon (C-182): no item art has wool yet, so a fleece is drawn here (seven overlapping cream puffs, each
## lit from the upper left, with a thin warm outline) until item art comes.
static func wool_icon() -> Texture2D:
	if _wool != null: return _wool
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.98, 0.95, 0.88)
	var shade := Color(0.84, 0.77, 0.66)
	var edge := Color(0.6, 0.5, 0.38)
	# Puffs [centre u, centre v, radius] in the unit square: a low wide row of four, three above.
	var puffs := [[0.27, 0.6, 0.17], [0.45, 0.64, 0.18], [0.63, 0.63, 0.18], [0.78, 0.58, 0.15],
		[0.36, 0.43, 0.17], [0.56, 0.41, 0.18], [0.72, 0.44, 0.14]]
	for y in n:
		for x in n:
			var u := (x + 0.5) / n
			var v := (y + 0.5) / n
			# The nearest puff's edge decides the outline; the topmost covering puff (last drawn) its shade.
			var inside := -1.0
			var c := Color(0, 0, 0, 0)
			for p: Array in puffs:
				var d := Vector2(u - float(p[0]), v - float(p[1])).length() / float(p[2])
				if d > 1.0: continue
				inside = maxf(inside, 1.0 - d)
				var light := clampf((u - float(p[0]) + v - float(p[1])) / float(p[2]) * 0.45 + 0.35, 0.0, 1.0)
				c = body.lerp(shade, light)
				if d > 0.86: c = c.lerp(shade, (d - 0.86) / 0.14 * 0.6)
			if inside < 0.0: continue
			var rim := inside * 0.16
			if rim < 0.02: c = c.lerp(edge, 1.0 - rim / 0.02)
			c.a = clampf(rim * n * 0.6, 0.0, 1.0)
			img.set_pixel(x, y, c)
	_wool = ImageTexture.create_from_image(img)
	return _wool

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
