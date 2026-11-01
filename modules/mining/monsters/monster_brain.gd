extends RefCounted
## How a monster fights (355 b1, contract-efg §10): one brain per monster, run by the P0 mine fight each frame on its
## dictionary (phase, timer, mover, spec …). The client moves monsters and judges touches; the server settles hits, HP
## and loot (mine_attack). A brain reads its numbers from enemy.spec, which Monsters.spec builds from the monster's json.

## A chasing monster finds its path to the player again this often, and at most one monster a frame does it (perf Q6,
## SGODOT-260): fights at floor 4 jerked about 4 times a second when they all landed in one frame.
const REPATH_S := 0.25

## One frame: move enemy.mover, set enemy.phase / timer, and when a hit lands on the player raise it through
## fight.touch(enemy). `may_path`: no other monster has found its path this frame. Returns whether this one did.
func step(_enemy: Dictionary, _fight, _player: PlayerMover, _dt: float, _may_path: bool) -> bool:
	return false

## Whether a swing can hit it now (a Shroomling hiding cannot: it is left out of mine_attack's targets).
func can_be_hit(_enemy: Dictionary) -> bool:
	return true

## Whether it is stunned now (a Rock Beetle after its charge): a hit on it is sent in mine_attack's `stunned`.
func stunned(_enemy: Dictionary) -> bool:
	return false

## A swing struck it (at the press, before the server answers): the old mine's short stun unless it resists.
func on_hit(enemy: Dictionary, stun_s: float) -> void:
	if bool(enemy.spec.get("stun_resistant", false)): return
	enemy.phase = "stunned"
	enemy.timer = stun_s
	(enemy.mover as PlayerMover).stop()
