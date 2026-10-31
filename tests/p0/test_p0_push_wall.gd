extends GdUnitTestSuite
## SGODOT-306 (不知火舞 2a96260f): the stick held against something the body cannot pass stands it (idle) after 0.1 s of
## steps that went nowhere, still turning with the stick; a step that moves runs again at once; the stick let go is
## idle as ever. Only the clip: state stays "move" and the mover's is_moving keeps its meaning.

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func _actor() -> P0Actor:
	var bp := FarmBlueprint.load_file(FIX)
	var cam := Camera3D.new()   # the default basis: the stick's right is +x, its up is -z
	add_child(auto_free(cam))
	var a: P0Actor = auto_free(P0Actor.new())
	add_child(a)
	a.setup(bp, BlueprintGrid.new(bp), cam, bp.cell_to_world(Vector2i(5, 7)))
	return a

func _frames(a: P0Actor, n: int) -> void:
	for i in n: a.step(1.0 / 60.0)

func test_pushing_against_the_pond_stands_after_a_tenth_of_a_second_and_runs_again_on_moving() -> void:
	var a := _actor()
	a.set_input(Vector2(1, 0))   # east, into the pond at (6,7)
	var walked := 0
	while not a.mover.stuck and walked < 120:   # walks to its edge, running
		a.step(1.0 / 60.0)
		walked += 1
		if not a.mover.stuck: assert_str(a._clip).is_equal("run")
	assert_bool(a.mover.stuck).is_true()        # the first step that went nowhere
	assert_int(walked).is_greater(1)
	_frames(a, 3)                # 0.067 s against it: still the run (debounce)
	assert_str(a._clip).is_equal("run")
	_frames(a, 4)                # past 0.1 s: stands
	assert_str(a._clip).is_equal("idle")
	assert_str(a.state).is_equal("move")
	assert_bool(a.mover.is_moving()).is_true()
	assert_float(a.mover.facing.x).is_greater(0.9)   # still facing the push
	a.set_input(Vector2(-1, 0))  # away: runs at once
	a.step(1.0 / 60.0)
	assert_str(a._clip).is_equal("run")
	a.set_input(Vector2.ZERO)    # let go: idle, as before
	a.step(1.0 / 60.0)
	assert_str(a._clip).is_equal("idle")
	assert_str(a.state).is_equal("idle")
