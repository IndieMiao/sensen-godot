extends Node3D
## A monster's look (355 b1, contract-efg §10): the placeholder drawn in code, a grey model or the final one take the
## same calls, so a model is swapped by its resource path alone (上官婉儿's monster file contract v1). `meta` is the
## monster's json — radius, hit_point, durations by action, hit_at, spore_at — a model's beside its glb
## (assets/monsters/<id>/<id>.json) or a placeholder's (modules/mining/monsters/placeholder/<id>.json), the same keys.
## A brain reads its timings from it (via the fight's spec, Monsters.spec), never numbers of its own.
## Actions: idle and move (loops), windup, attack, recover, hit, die (once), and a monster's own (fly_high and stunned
## loop; hide, spore once). A model plays its animation of that name; a placeholder draws it in update().

const LOOPS := ["idle", "move", "fly_high", "stunned"]

var kind := ""
var meta: Dictionary = {}
var action := "idle"
var action_time := 0.0   # seconds since `action` started

## Starts an action; a looping one already playing goes on.
func play(name: String) -> void:
	if name == action and name in LOOPS: return
	action = name
	action_time = 0.0

## An action's length from the json (0 when it gives none).
func duration(name: String) -> float:
	return float(meta.get("durations", {}).get(name, 0.0))

## Elites, guards and later climate variants change material parameters only, never the file.
func set_tint(_params: Dictionary) -> void:
	pass

## A guard's head ornament (assets/monsters/slime_king/*.glb, its origin the face it sits on) on top of the body.
func attach(ornament: PackedScene, top := 1.0) -> Node3D:
	var node := ornament.instantiate() as Node3D
	node.position.y = top
	add_child(node)
	return node

## Each frame after the brain, with the fight's dictionary for this monster: `was` its phase before the brain ran,
## `stepped` whether the brain ran at all (not while the fight holds still), `elapsed` the fight's clock.
func update(_enemy: Dictionary, _was: String, delta: float, _stepped: bool, _elapsed: float) -> void:
	action_time += delta
