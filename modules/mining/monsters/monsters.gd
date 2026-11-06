extends RefCounted
## The P0 mine's monsters by the kind the server names (view … mobs[].kind; 355 b1, contract-efg §10): each kind's json,
## look (a MonsterView) and fight (a MonsterBrain). F adds its kinds here — Cave Bat, Rock Beetle, Shroomling, the slime
## kings — each with its own brain and view under modules/mining/monsters/, and touches nothing else. A kind not listed
## yet is drawn and fought as a Slime, so a server naming monsters the client does not know never breaks a floor.

const SlimeView := preload("res://modules/mining/monsters/slime_view.gd")
const SlimeBrain := preload("res://modules/mining/monsters/slime_brain.gd")
const PLACEHOLDER_DIR := "res://modules/mining/monsters/placeholder/"
const MODEL_DIR := "res://assets/monsters/"

## kind → its json (a model's or a placeholder's, by this id), view and brain scripts; elite: drawn as one.
const KINDS := {
	"mob_slime": {"json": "mob_slime", "view": SlimeView, "brain": SlimeBrain},
	"mob_elite_slime": {"json": "mob_elite_slime", "view": SlimeView, "brain": SlimeBrain, "elite": true},
	"mob_cave_bat": {"json": "mob_cave_bat", "view": preload("res://modules/mining/monsters/bat_view.gd"), "brain": preload("res://modules/mining/monsters/bat_brain.gd")},
	"mob_elite_cave_bat": {"json": "mob_cave_bat", "view": preload("res://modules/mining/monsters/bat_view.gd"), "brain": preload("res://modules/mining/monsters/bat_brain.gd"), "elite": true},
	"mob_rock_beetle": {"json": "mob_rock_beetle", "view": preload("res://modules/mining/monsters/beetle_view.gd"), "brain": preload("res://modules/mining/monsters/beetle_brain.gd")},
	"mob_elite_rock_beetle": {"json": "mob_rock_beetle", "view": preload("res://modules/mining/monsters/beetle_view.gd"), "brain": preload("res://modules/mining/monsters/beetle_brain.gd"), "elite": true},
	"mob_shroomling": {"json": "mob_shroomling", "view": preload("res://modules/mining/monsters/shroom_view.gd"), "brain": preload("res://modules/mining/monsters/shroom_brain.gd")},
	"mob_elite_shroomling": {"json": "mob_shroomling", "view": preload("res://modules/mining/monsters/shroom_view.gd"), "brain": preload("res://modules/mining/monsters/shroom_brain.gd"), "elite": true},
	"boss_slime_king": {"json": "boss_slime_king", "view": preload("res://modules/mining/monsters/slime_king_view.gd"), "brain": preload("res://modules/mining/monsters/slime_king_brain.gd"), "guard": true},
	"boss_slime_king_iron": {"json": "boss_slime_king", "view": preload("res://modules/mining/monsters/slime_king_view.gd"), "brain": preload("res://modules/mining/monsters/slime_king_brain.gd"), "guard": true},
	"boss_slime_king_quartz": {"json": "boss_slime_king", "view": preload("res://modules/mining/monsters/slime_king_view.gd"), "brain": preload("res://modules/mining/monsters/slime_king_brain.gd"), "guard": true},
}
const UNKNOWN := {"json": "mob_slime", "view": SlimeView, "brain": SlimeBrain}

static var _meta: Dictionary = {}

static func entry(kind: String) -> Dictionary:
	return KINDS.get(kind, UNKNOWN)

static func known(kind: String) -> bool:
	return KINDS.has(kind)

static func is_elite(kind: String) -> bool:
	return bool(entry(kind).get("elite", false))

## A kind's json: the placeholder's — the movement a brain reads and a look's own numbers, which only it has — with the
## model's beside its glb (assets/monsters/<id>/<id>.json) over it when there is one: the art's radius, hit_point,
## durations, hit_at and spore_at (上官婉儿's contract v1, contract-efg §10). It had taken the model's alone, the bat's
## speed and aggro gone with it (周瑜 on the bat blockout, 11-02). Read once.
static func meta(kind: String) -> Dictionary:
	var id := str(entry(kind).json)
	if not _meta.has(id): _meta[id] = layered([PLACEHOLDER_DIR + id + ".json", MODEL_DIR + id + "/" + id + ".json"])
	return _meta[id]

## The jsons at `paths` that are there, each over the ones before: a later key wins, and a later dictionary (durations)
## is laid over the earlier one key by key — an action only the placeholder times keeps its time.
static func layered(paths: Array) -> Dictionary:
	var out := {}
	for path in paths:
		if not FileAccess.file_exists(path): continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary: continue
		for key in parsed:
			if out.get(key) is Dictionary and parsed[key] is Dictionary: (out[key] as Dictionary).merge(parsed[key], true)
			else: out[key] = parsed[key]
	return out

## The fight's numbers for one monster, from its json, under the old mine's names the fight has always used (a copy:
## each monster may change its own). HP is the server's (the view's max), set by the fight.
static func spec(kind: String) -> Dictionary:
	var m := meta(kind)
	var d: Dictionary = m.get("durations", {})
	var mv: Dictionary = m.get("move", {})
	return {"kind": kind, "radius": float(m.get("radius", 0.4)), "move_speed": float(mv.get("speed", 1.65)),
		"aggro_range": float(mv.get("aggro", 5.0)), "attack_range": float(mv.get("reach", 1.55)),
		"windup_seconds": float(d.get("windup", 0.65)), "dash_speed": float(mv.get("dash_speed", 4.2)),
		"dash_seconds": float(d.get("attack", 0.28)), "recovery_seconds": float(d.get("recover", 1.1)),
		"stun_resistant": bool(m.get("stun_resistant", false)), "knockback_resistance": float(m.get("knockback_resistance", 0.0))}

## A new look for one monster (its node in the fight), built from the fight's spec.
static func view(kind: String, spec: Dictionary) -> Node3D:
	var e := entry(kind)
	var node = (e.view as GDScript).new()
	node.kind = kind
	node.meta = meta(kind)
	node.build(spec, bool(e.get("elite", false)))
	return node

## A new brain for one monster.
static func brain(kind: String) -> RefCounted:
	return (entry(kind).brain as GDScript).new()
