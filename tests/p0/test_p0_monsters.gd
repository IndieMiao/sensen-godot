extends GdUnitTestSuite
## The P0 mine's monster interface (355 b1, contract-efg §10): each kind's json, look and brain through Monsters; the
## slime moved onto it unchanged (its numbers are the old mine table's), a kind the client does not know yet fought as a
## slime, and the swing leaving out what cannot be hit and reporting what it struck stunned (mine_attack's `stunned`).

const Monsters := preload("res://modules/mining/monsters/monsters.gd")
const SlimeView := preload("res://modules/mining/monsters/slime_view.gd")
const SlimeBrain := preload("res://modules/mining/monsters/slime_brain.gd")
const MonsterBrain := preload("res://modules/mining/monsters/monster_brain.gd")
const Combat := preload("res://modules/mining/p0_mine_combat.gd")
const Layout := preload("res://modules/mining/mine_layout.gd")
const SLIME := {"kind": "mob_slime", "hp": 9, "max": 9}

## A brain that can be told it is hiding or stunned (a Shroomling's, a Rock Beetle's) and never moves.
class TestBrain extends MonsterBrain:
	var hiding := false
	var dazed := false
	func can_be_hit(_enemy: Dictionary) -> bool: return not hiding
	func stunned(_enemy: Dictionary) -> bool: return dazed

## The placeholder jsons carry the old mine table's slime and elite slime as they were, so the fight is unchanged.
func test_the_slimes_numbers_are_the_old_mine_tables() -> void:
	var old: Dictionary = Layout.data().combat.monsters
	for pair in [["mob_slime", "slime"], ["mob_elite_slime", "elite_slime"]]:
		var spec := Monsters.spec(str(pair[0]))
		var was: Dictionary = old[str(pair[1])]
		for key in ["radius", "move_speed", "aggro_range", "attack_range", "windup_seconds", "dash_speed", "dash_seconds",
				"recovery_seconds", "stun_resistant", "knockback_resistance"]:
			assert_that(spec[key]).override_failure_message("%s.%s" % [pair[0], key]).is_equal(was[key])
	assert_bool(Monsters.is_elite("mob_elite_slime")).is_true()
	assert_bool(Monsters.is_elite("mob_slime")).is_false()

## A spec is each monster's own copy: a test (or a brain) changing one never changes the next.
func test_a_spec_is_a_copy() -> void:
	var a := Monsters.spec("mob_slime")
	a.aggro_range = 100.0
	assert_float(float(Monsters.spec("mob_slime").aggro_range)).is_equal(5.0)

## A kind the client does not know yet (the server ahead of F) is drawn and fought as a slime: nothing breaks.
func test_an_unknown_kind_is_a_slime() -> void:
	assert_bool(Monsters.known("mob_unregistered_test")).is_false()
	var spec := Monsters.spec("mob_unregistered_test")
	assert_float(float(spec.radius)).is_equal(0.4)
	var node: Node3D = auto_free(Monsters.view("mob_unregistered_test", spec))
	assert_object(node.get_node_or_null("Body")).is_not_null()
	assert_object(Monsters.brain("mob_unregistered_test")).is_instanceof(SlimeBrain)

## The slime's look keeps the children the fight and its tests read, and the json's timings.
func test_the_slime_view_children_and_actions() -> void:
	var node = auto_free(Monsters.view("mob_elite_slime", Monsters.spec("mob_elite_slime")))
	for child in ["Body", "Warning", "Health", "HealthTrack", "HealthFill", "Band"]:
		assert_object(node.get_node_or_null(child)).override_failure_message(child).is_not_null()
	assert_object(node.get_node_or_null("Body/Crown")).is_not_null()   # the elite's
	assert_float(node.duration("windup")).is_equal(0.7)
	node.play("move")
	node.action_time = 0.5
	node.play("move")   # a loop already playing goes on
	assert_float(node.action_time).is_equal(0.5)
	node.play("attack")
	assert_str(node.action).is_equal("attack")
	assert_float(node.action_time).is_equal(0.0)

## A hit stuns a slime for a moment; the elite resists, as before.
func test_on_hit_stuns_unless_it_resists() -> void:
	var mover := _mover()
	var slime := {"spec": Monsters.spec("mob_slime"), "phase": "chase", "timer": 0.0, "mover": mover}
	SlimeBrain.new().on_hit(slime, 0.25)
	assert_str(str(slime.phase)).is_equal("stunned")
	assert_float(float(slime.timer)).is_equal(0.25)
	var elite := {"spec": Monsters.spec("mob_elite_slime"), "phase": "chase", "timer": 0.0, "mover": mover}
	SlimeBrain.new().on_hit(elite, 0.25)
	assert_str(str(elite.phase)).is_equal("chase")

## The band's size by the old table's names and by kind (the 288 report's numbers).
func test_band_of_takes_either_name() -> void:
	var c: Node3D = auto_free(Combat.new())
	assert_dict(c.band_of("slime")).is_equal(c.band_of("mob_slime"))
	assert_dict(c.band_of("elite_slime")).is_equal(SlimeView.band_size(Monsters.spec("mob_elite_slime")))

## The swing leaves out a monster that cannot be hit now and reports the ones it struck stunned.
func test_the_swing_skips_the_unhittable_and_reports_the_stunned() -> void:
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	var mover := _mover()
	var mobs := [SLIME.duplicate(), SLIME.duplicate(), SLIME.duplicate()]
	c.sync_p0({"mine": {"weapon": {"attack": 3, "speed": 2.0}, "at": {"mine": "wd-254-114", "floor": 3, "day": "2026-11-02",
		"floor_state": {"floor": 3, "mobs": mobs}}}}, 3, mover)
	assert_int(c.enemies.size()).is_equal(3)
	var ids: Array = c.enemies.keys()
	var brains := []
	for i in ids.size():
		var b := TestBrain.new()
		c.enemies[ids[i]].brain = b
		brains.append(b)
		c.enemies[ids[i]].node.position = mover.position + Vector3(0.0, 0.0, -0.9)   # right in front (the floor runs to −z), in the arc
	brains[0].hiding = true
	brains[1].dazed = true
	mover.facing = Vector3(0, 0, -1)
	var hit: Array = c.swing({}, mover)
	assert_bool(hit.has(ids[0])).is_false()
	assert_bool(hit.has(ids[1])).is_true()
	assert_bool(hit.has(ids[2])).is_true()
	assert_array(c.last_stunned).is_equal([ids[1]])

## A floor with every rock broken (as test_p0_mine_deep's Layout_bp): open ground around the spawn.
func _mover() -> PlayerMover:
	var nodes: Array = []
	for i in Layout.FALLBACK_POSITIONS.size(): nodes.append({"id": str(i), "position": Layout.FALLBACK_POSITIONS[i]})
	var bp: FarmBlueprint = Layout._navigation(nodes, nodes.map(func(n): return n.id))
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	mover.position = Layout.SPAWN
	return mover

## A model's json is laid over its placeholder's (周瑜 on the bat blockout, 11-02): the art's timings and hit point win,
## the movement only the placeholder has stays, and durations go action by action; a json that is not there is skipped.
func test_a_models_json_is_laid_over_the_placeholders() -> void:
	var dir := "user://test_p0_monsters_meta/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var write := func(name: String, data: Dictionary) -> String:
		var f := FileAccess.open(dir + name, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
		return dir + name
	var placeholder: String = write.call("placeholder.json", {"radius": 0.3, "hit_point": [0, 1.0, 0], "hit_at": 0.25,
		"durations": {"windup": 0.55, "die": 0.5, "stunned": 2.0}, "move": {"speed": 2.8, "aggro": 6.5}})
	var model: String = write.call("model.json", {"radius": 0.35, "hit_point": [0, 1.0, 0.05], "hit_at": 0.2,
		"durations": {"windup": 0.55, "die": 0.7}, "anims": {"die": {"length": 0.7, "loop": false}}})
	var m := Monsters.layered([placeholder, model, dir + "none.json"])
	assert_float(float(m.radius)).is_equal(0.35)
	assert_array(m.hit_point).is_equal([0.0, 1.0, 0.05])   # JSON numbers read as floats
	assert_float(float(m.hit_at)).is_equal(0.2)
	assert_that(m.durations).is_equal({"windup": 0.55, "die": 0.7, "stunned": 2.0})   # the placeholder's stunned kept
	assert_that(m.move).is_equal({"speed": 2.8, "aggro": 6.5})                       # only the placeholder has it
	assert_that(Monsters.layered([placeholder]).durations).is_equal({"windup": 0.55, "die": 0.5, "stunned": 2.0})
	for f in ["placeholder.json", "model.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
