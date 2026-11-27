class_name UiActionClay
## The clay action key's configuration (C-185 D-489 §3.7, owner Q-285; C-186): which colour group and small icon each
## verb takes. Colour only tells actions apart, never whether the action can be done (state does that: grey clay,
## the dark short-of-Energy pill). Kept here, not in the scenes, so a verb or a colour changes in one place.

enum Group { EARTH, SOW, WATER, HARVEST, REST, OFF }

## Verb → group. A verb not listed is EARTH (the farm's default work colour); refusals draw OFF from the key's state.
const GROUPS := {
	"Till": Group.EARTH, "Clear": Group.EARTH, "Retry": Group.EARTH,
	"Sow": Group.SOW,
	"Water": Group.WATER, "Fill": Group.WATER,
	"Harvest": Group.HARVEST, "Gather": Group.HARVEST, "Feed": Group.HARVEST,
	"Rest": Group.REST,
	"Growing": Group.OFF, "Regrowing": Group.OFF,
}

## Verb → its single-colour 26 icon (Lucide, the set already in assets/ui/icons/lucide).
const ICONS := {
	"Till": preload("res://assets/ui/icons/lucide/shovel.svg"),
	"Clear": preload("res://assets/ui/icons/lucide/brush.svg"),
	"Retry": preload("res://assets/ui/icons/lucide/rotate-ccw.svg"),
	"Sow": preload("res://assets/ui/icons/lucide/sprout.svg"),
	"Water": preload("res://assets/ui/icons/lucide/droplet.svg"),
	"Fill": preload("res://assets/ui/icons/lucide/droplet.svg"),
	"Harvest": preload("res://assets/ui/icons/lucide/carrot.svg"),
	"Gather": preload("res://assets/ui/icons/lucide/leaf.svg"),
	"Feed": preload("res://assets/ui/icons/lucide/wheat.svg"),
	"Rest": preload("res://assets/ui/icons/lucide/moon.svg"),
	"Growing": preload("res://assets/ui/icons/lucide/clock-3.svg"),
	"Regrowing": preload("res://assets/ui/icons/lucide/clock-3.svg"),
}
const BOLT := preload("res://assets/ui/icons/lucide/zap.svg")

## [base, shade, light, ink] per group (`action/clay/<group>/*`).
static func palette(group: Group) -> Array[Color]:
	match group:
		Group.SOW: return [UiTokens.COLOR_ACTION_CLAY_SOW_BASE, UiTokens.COLOR_ACTION_CLAY_SOW_SHADE,
			UiTokens.COLOR_ACTION_CLAY_SOW_LIGHT, UiTokens.COLOR_ACTION_CLAY_SOW_INK]
		Group.WATER: return [UiTokens.COLOR_ACTION_CLAY_WATER_BASE, UiTokens.COLOR_ACTION_CLAY_WATER_SHADE,
			UiTokens.COLOR_ACTION_CLAY_WATER_LIGHT, UiTokens.COLOR_ACTION_CLAY_WATER_INK]
		Group.HARVEST: return [UiTokens.COLOR_ACTION_CLAY_HARVEST_BASE, UiTokens.COLOR_ACTION_CLAY_HARVEST_SHADE,
			UiTokens.COLOR_ACTION_CLAY_HARVEST_LIGHT, UiTokens.COLOR_ACTION_CLAY_HARVEST_INK]
		Group.REST: return [UiTokens.COLOR_ACTION_CLAY_REST_BASE, UiTokens.COLOR_ACTION_CLAY_REST_SHADE,
			UiTokens.COLOR_ACTION_CLAY_REST_LIGHT, UiTokens.COLOR_ACTION_CLAY_REST_INK]
		Group.OFF: return [UiTokens.COLOR_ACTION_CLAY_OFF_BASE, UiTokens.COLOR_ACTION_CLAY_OFF_SHADE,
			UiTokens.COLOR_ACTION_CLAY_OFF_LIGHT, UiTokens.COLOR_ACTION_CLAY_OFF_INK]
	return [UiTokens.COLOR_ACTION_CLAY_EARTH_BASE, UiTokens.COLOR_ACTION_CLAY_EARTH_SHADE,
		UiTokens.COLOR_ACTION_CLAY_EARTH_LIGHT, UiTokens.COLOR_ACTION_CLAY_EARTH_INK]

## The group a verb draws in (`Harvest ×5` reads as Harvest).
static func group_of(verb: String) -> Group:
	return GROUPS.get(verb.get_slice(" ×", 0), Group.EARTH)

## The verb's icon (a refusal keeps the action's own icon), or null.
static func icon_of(verb: String) -> Texture2D:
	return ICONS.get(verb.get_slice(" ×", 0), null)

## The icon's colour: Sow's sprout green (the reference's own), else the verb's cream.
static func glyph_color(group: Group) -> Color:
	if group == Group.SOW: return UiTokens.COLOR_ACTION_CLAY_SOW_GLYPH
	if group == Group.OFF: return UiTokens.COLOR_ACTION_CLAY_OFF_INK
	return UiTokens.COLOR_ACTION_CLAY_VERB

## The clay outline, `n` points round a w × h box: a superellipse with a slight wobble, the top-left a little fuller
## (the reference's hand-pressed lump). Drawn by UiSceneAction; shared so holding / pending strokes follow it.
static func outline(w: float, h: float, n := 72) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := Vector2(w, h) * 0.5
	var e := 2.0 / 3.6   # superellipse exponent 2/n with n = 3.6: a rounded square, not a circle
	for i in n:
		var t := TAU * float(i) / float(n)
		var ct := cos(t)
		var st := sin(t)
		var x := signf(ct) * pow(absf(ct), e)
		var y := signf(st) * pow(absf(st), e)
		var wobble := 1.0 + 0.018 * sin(3.0 * t + 0.6) + 0.012 * sin(5.0 * t + 1.7)
		# Fuller at the top-left (x < 0, y < 0), a touch narrower at the bottom-right.
		var lump := 1.0 + 0.03 * maxf(0.0, -(ct + st) * 0.7071)
		pts.append(c + Vector2(x * c.x, y * c.y) * wobble * lump * 0.97)
	return pts
