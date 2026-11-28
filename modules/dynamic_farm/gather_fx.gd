extends RefCounted
## C-236: how gathering looks and sounds, read from SEN-C-234's approved parameters (D-558, owner SEN-Q-345), copied as
## assets/farm/data/gather_presentation.json. The client only: the server never reads it. Chop a tree (axe, sideways),
## break a rock (pick, overhead), pick a wild herb (crouch and pull up); in the yard (Q4) the same for its tree, bush,
## stone and weed (`Pull`). How many hits an outer object takes is the numbers table's (dynamic_farm.json economy.gather,
## SEN-Q-342); a yard obstacle's is `core_obstacles` here. Only the last hit settles (SEN-Q-345 Q3).
## The models' gathering scenes and the held plants are SEN-C-235's (assets/dynamic_farm/gathering, its README's binding).
const PATH := "res://assets/farm/data/gather_presentation.json"
const ART := "res://assets/dynamic_farm/gathering/"
## Model -> its gathering scene in ART (C-235: four trees, three rocks, the herbs, bushes and weeds).
const SCENES := {"wild_pz_tree_20": "Linden", "wild_pz_tree_20_g": "OrchardElm", "wild_pz_pine_01": "Spruce",
	"wild_pz_pine_03": "Fir", "wild_pz_rock_08": "Ledge", "wild_pz_rock_13": "Cobble", "wild_pz_softrock_10": "Flint",
	"wild_pz_flower_20": "flower_20", "wild_pz_flower_23": "flower_23", "wild_pz_bush_05": "bush_05",
	"wild_pz_bush_07": "bush_07", "wild_pz_grass_24": "grass_24", "wild_pz_foot_leafy": "foot_leafy"}
## Model -> the plant GatherGrip holds once it is pulled up (C-235: kept in the hand until the reply).
const HELD := {"wild_pz_flower_20": "Flower20", "wild_pz_flower_23": "Flower23", "wild_pz_grass_24": "Grass24",
	"wild_pz_foot_leafy": "Leafy"}
## An outer kind (economy.gather) -> its presentation kind.
const OUTER := {"tree": "tree", "rock": "rock", "flower": "flower"}
## The tool each kind shows in the hand (GatherGrip's Hand/Grip child; "" = bare hand).
const GRIP := {"axe": "Axe", "pickaxe": "Pickaxe", "hand": ""}
## The key's badge per tool (LOCK-02: the top-left badge shows the tool in use; Lucide, assets/ui/icons/lucide).
const TOOL_ICONS := {"axe": preload("res://assets/ui/icons/lucide/axe.svg"),
	"pickaxe": preload("res://assets/ui/icons/lucide/pickaxe.svg"), "hand": preload("res://assets/ui/icons/lucide/hand.svg")}
## C-235's clips (gather_actions.tres, added to the rig as the `gather` library) and where each one strikes (s).
const LIBRARY := &"gather"
const CLIPS := {"labour_chop": 0.30, "labour_break": 0.36, "labour_pluck": 0.60}

static var _config := {}

static func config() -> Dictionary:
	if _config.is_empty():
		var raw = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_config = raw if raw is Dictionary else {}
	return _config

## The presentation of `kind` (tree, rock, flower, bush, weed): its own entry over the one it is `like`.
static func kind(name: String) -> Dictionary:
	var kinds: Dictionary = config().get("kinds", {})
	var own: Dictionary = kinds.get(name, {})
	if own.is_empty(): return {}
	var base: Dictionary = kinds.get(str(own.get("like", "")), {})
	var out := base.duplicate(true)
	for key: String in own:
		if own[key] is Dictionary and out.get(key) is Dictionary: out[key].merge(own[key], true)
		else: out[key] = own[key]
	return out

static func common() -> Dictionary:
	return config().get("common", {})

## A new hit memory with the approved `common.damage_memory_ms`.
static func damage() -> Damage:
	return Damage.new(int(common().get("damage_memory_ms", 30000)))

## The key's verb for `kind`: Chop / Break / Pick / Pull (SEN-Q-345 Q1, LOCK-02).
static func verb(kind_name: String) -> String:
	return str(kind(kind_name).get("verb", "Gather"))

static func tool_of(kind_name: String) -> String:
	return str(kind(kind_name).get("tool", "hand"))

static func tool_icon(kind_name: String) -> Texture2D:
	return TOOL_ICONS.get(tool_of(kind_name))

## The rig clip one hit plays (`gather/labour_chop`), when C-235's clip exists; else "".
static func clip(kind_name: String) -> String:
	var name := str(kind(kind_name).get("clip", ""))
	return "%s/%s" % [LIBRARY, name] if CLIPS.has(name) else ""

## Seconds from the start of one hit to its contact, and its whole length (the approved cycle: 220 + 80 of 560 ms...).
static func contact_s(kind_name: String) -> float:
	return float(CLIPS.get(str(kind(kind_name).get("clip", "")), 0.3))

static func cycle_s(kind_name: String) -> float:
	var total := 0.0
	for part in kind(kind_name).get("cycle", {}).values(): total += float(part)
	return total / 1000.0 if total > 0.0 else 0.6

## The presentation kind and hits of a yard obstacle's role (tree, bush, stone, weed), {} when it has none.
static func core(role: String) -> Dictionary:
	var entry = config().get("core_obstacles", {}).get(role)
	if not entry is Dictionary or kind(str(entry.get("kind", ""))).is_empty(): return {}
	return {"kind": str(entry.kind), "hits": maxi(1, int(entry.get("hits", 1)))}

## The damage stage after `done` of `hits` (0 none, 1 light, 2 deep): `done / hits >= threshold` per the approved
## `damage_stage_compare` (a 3-chop tree: 0.33 -> none, 0.67 -> light; a 5-chop tree: 2 light, 4 deep).
static func stage(kind_name: String, done: int, hits: int) -> int:
	var at := 0
	if hits <= 0: return 0
	for threshold in kind(kind_name).get("damage_stages", []):
		if float(done) / float(hits) >= float(threshold) - 0.0001: at += 1
	return mini(at, 2)

static func scene_of(model: String) -> PackedScene:
	return load(ART + str(SCENES[model]) + ".tscn") if SCENES.has(model) else null

## Milliseconds a kind's setting says (`fall.tilt_ms`), or `default`.
static func ms(kind_name: String, group: String, key: String, default := 0.0) -> float:
	return float(kind(kind_name).get(group, {}).get(key, default))

## One sound's stream (SEN-C-236's synthesised set, tools/audio/gather_sfx.py), null when it is missing.
static func sound(name: String) -> AudioStream:
	var path := "%s/%s.wav" % [str(config().get("sfx", {}).get("dir", "res://assets/audio/gather")), name]
	return load(path) if ResourceLoader.exists(path) else null

## Hits already landed on one object, kept on this device only for `common.damage_memory_ms` (30 s) after the last one
## (walk away and come back to go on; longer and the scar closes). Leaving the scene drops them all. Nothing here is
## saved or sent: the server only ever sees the last hit's `gather` / `clear_obstacle`.
class Damage:
	extends RefCounted
	var memory_ms := 30000
	var _hits := {}

	func _init(ms_ := 30000) -> void:
		memory_ms = ms_

	func done(key: String, now_ms: int) -> int:
		var at: Dictionary = _hits.get(key, {})
		if at.is_empty(): return 0
		if now_ms - int(at.at) > memory_ms:
			_hits.erase(key)
			return 0
		return int(at.done)

	func hit(key: String, now_ms: int) -> int:
		var count := done(key, now_ms) + 1
		_hits[key] = {"done": count, "at": now_ms}
		return count

	func forget(key: String) -> void:
		_hits.erase(key)

	func clear() -> void:
		_hits.clear()

	## Keys whose hits ran out by `now_ms` (their scar closes).
	func expire(now_ms: int) -> Array:
		var gone := []
		for key: String in _hits.keys():
			if now_ms - int(_hits[key].at) > memory_ms:
				_hits.erase(key)
				gone.append(key)
		return gone
