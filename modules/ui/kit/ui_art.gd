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

static func _load(kind: String, file: String) -> Texture2D:
	var path := DIR % [kind, file]
	return load(path) if ResourceLoader.exists(path) else null
