extends RefCounted
## The homestead's starting template (SGODOT-342, 338·L2): by the home city's climate band only, never by the farm's
## point on the map (user 10-26). content.farm_templates (assets/p0/content/farm_templates.json) gives each band its
## dressing; a band missing from it, or a climate the table does not know, wears the temperate one. Preloaded, no
## class_name (a new global class needs an editor import).

const BANDS := ["temperate", "subtropical", "tropical", "cool"]
const FALLBACK := {"style": "cottage"}

## The home city's band, "temperate"…: the view's profile.climate (the server's home facts: `Tropical` for a
## Singapore home), else the content's (the written city's, before the first view).
static func band(view = null) -> String:
	var z := ""
	if view is Dictionary: z = str((view as Dictionary).get("profile", {}).get("climate", ""))
	if z == "": z = str(P0Logic.content().get("profile", {}).get("climate", ""))
	z = z.to_lower()
	return z if z in BANDS else "temperate"

## The band's template: {style}, every key there even when the table leaves one out.
static func of(view = null) -> Dictionary:
	var table: Dictionary = P0Logic.content().get("farm_templates", {})
	var row = table.get(band(view), table.get("temperate", {}))
	return FALLBACK.merged(row, true) if row is Dictionary else FALLBACK.duplicate()

## The house, storage and well style (FarmArt.STYLES) the scenery and the looks go with.
static func style(view = null) -> String:
	return str(of(view).get("style", FALLBACK.style))
