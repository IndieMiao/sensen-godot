class_name UiArt
## UI v3 art (C-86 D-256, 70 pieces, owner approved as is in Q-155), under res://assets/ui/v3/:
##   items/  icon_item_<name>.png   128 px   bag 48 / quick bar 32 / float 24
##   hero/   hero_<panel>.png       256 px   panel hero 80
##   sys/    icon_sys_<name>.png     96 px   24 on a Ø36 glass circle
##   color/  icon_<kind>_<name>.png  96 px   tabs, dressing kinds, skills, the coin
## Provenance, prompts and the item id table: docs/design/ui-v3-assets-2026-11-25 (assets.json).

const DIR := "res://assets/ui/v3/%s/%s.png"
const COIN := preload("res://assets/ui/v3/color/icon_currency_coin.png")
const HERO_BAG := preload("res://assets/ui/v3/hero/hero_bag.png")
const SYS_BAG := preload("res://assets/ui/v3/sys/icon_sys_bag.png")

static func item(name: String) -> Texture2D: return _load("items", "icon_item_" + name)
static func hero(name: String) -> Texture2D: return _load("hero", "hero_" + name)
static func sys(name: String) -> Texture2D: return _load("sys", "icon_sys_" + name)
## A coloured icon by its full name (`tab_tasks`, `dress_hair`, `skill_cooking`, `currency_coin`).
static func color(name: String) -> Texture2D: return _load("color", "icon_" + name)

## The farm quick bar's Bag end (C-211, C-185 §3.1 D / §7: the reference's orange bag is the existing grey one
## coloured): SYS_BAG through `bar/bagShade` → `bar/bagLight`.
static func bag_end() -> Texture2D:
	return tinted(SYS_BAG, UiTokens.COLOR_BAR_BAG_SHADE, UiTokens.COLOR_BAR_BAG_LIGHT)

static var _tints := {}

## `tex` coloured by its own light: each pixel's luminance from TINT_DARK to TINT_LIGHT maps onto `shade` → `light`
## (its shading and alpha kept). Made once per texture and colours; the texture itself when its pixels cannot be read.
static func tinted(tex: Texture2D, shade: Color, light: Color) -> Texture2D:
	if tex == null: return null
	var key := "%s|%s|%s" % [tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id()), shade.to_html(), light.to_html()]
	if _tints.has(key): return _tints[key]
	var img := tex.get_image()
	if img == null or img.is_empty(): return tex
	img = img.duplicate()
	if img.is_compressed() and img.decompress() != OK: return tex
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var k := clampf(inverse_lerp(TINT_DARK, TINT_LIGHT, c.get_luminance()), 0.0, 1.0)
			var out := shade.lerp(light, k)
			out.a = c.a
			img.set_pixel(x, y, out)
	var made := ImageTexture.create_from_image(img)
	_tints[key] = made
	return made

## The grey icons' luminance span (SYS_BAG: its outline ~0.45, its lit face ~0.92).
const TINT_DARK := 0.45
const TINT_LIGHT := 0.92

static func _load(kind: String, file: String) -> Texture2D:
	var path := DIR % [kind, file]
	return load(path) if ResourceLoader.exists(path) else null
