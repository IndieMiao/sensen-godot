extends GdUnitTestSuite
## User int11 (SGODOT-231, 不知火舞): ① the mine's exits — the elevator's Ground, the exit ladder, the 04:00 kick-out —
## go back to the farm under the mine, not to the map; ② a tap on the mouth walks up to it and opens its EntryCard, whose
## button carries the fee (SGODOT-266, LOCK-21 复议: never the main key, never the tap itself) — with today's runs used
## up too, its grey `Resets in …` pill (MINE-GATE-EXPRESS-3 / -4).

const P0Mine := preload("res://scenes/p0/p0_mine.gd")
const PROBE := "res://tests/fixtures/scenes/stack_probe.tscn"

func after_test() -> void:
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame

## The mine sits on the farm (the farm itself on the map, or the farm as the first session's root): leaving it pops that
## one layer. leave_world, the place chip's way to the map, took every exit to the map.
func test_leaving_the_mine_pops_only_the_mine() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.swap_root = func(): pass   # never the real scene change in a test
	var farm := AppRouter.push_instance(PROBE)
	var mine_layer := AppRouter.push_instance(PROBE)
	rt.world = mine_layer
	var mine = auto_free(P0Mine.new())   # not in the tree: only its exit
	mine.rt = rt
	mine.actor = auto_free(P0Actor.new())
	mine._leave()
	await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_bool(AppRouter.top_instance() == farm).is_true()
	assert_bool(is_instance_valid(mine_layer)).is_false()
	assert_bool(P0Runtime.room_leaves_for_map(1, true)).is_false()   # the mine on the farm root: also just one layer

## Where a tap from afar walks to: walkable cells by the mouth, inside the reach where its card stays, nearest the
## player first.
func test_the_walk_ends_by_the_mouth_within_its_reach() -> void:
	var bp := P0Garden.blueprint()
	var grid := BlueprintGrid.new(bp)
	var mouth := bp.cell_to_world(bp.anchor("mine")) + Vector3(-0.3, 0, 0.3)
	var spawn := bp.cell_to_world(bp.anchor("spawn"))
	var stands := P0FarmMaterials.mouth_stands(grid, mouth, spawn)
	assert_bool(stands.is_empty()).is_false()
	var last := -1.0
	for p in stands:
		assert_bool(grid.astar.is_point_solid(bp.world_to_cell(p))).is_false()
		assert_float(P0FarmMaterials.flat(p, mouth)).is_less(P0FarmMaterials.MOUTH_REACH)
		assert_float(P0FarmMaterials.flat(p, spawn)).is_greater_equal(last)
		last = P0FarmMaterials.flat(p, spawn)
	assert_bool(grid.point_path(spawn, stands[0]).is_empty()).is_false()   # reachable from where a session starts

## A tap anywhere on the mouth's model counts, not only near its foot: its meshes' bounds on screen.
func test_the_whole_model_takes_the_tap() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 800)
	add_child(auto_free(vp))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.72
	vp.add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(0, 8, 8), Vector3.ZERO)
	var art: Node3D = preload("res://modules/mining/mine_art.gd").entrance()
	vp.add_child(art)
	var box := P0FarmMaterials.screen_box(cam, art)
	assert_bool(box.has_area()).is_true()
	assert_bool(box.has_point(cam.unproject_position(Vector3(0, 1.6, 0)))).is_true()   # high on the arch
	assert_bool(box.has_point(cam.unproject_position(Vector3(0, 0.1, 0)))).is_true()   # at its foot
	assert_bool(box.has_point(cam.unproject_position(Vector3(6, 0, 0)))).is_false()    # well beside it

## The mouth's box reaches the Herb Patch's 64 px tap circle (苏烈 on #156): a tap on both goes to the nearer one.
func test_a_tap_on_both_the_mouth_and_a_spot_goes_to_the_nearer() -> void:
	var mouth := Vector2(100, 300)
	var herb := Vector2(170, 330)
	assert_bool(P0FarmMaterials.mouth_nearest(Vector2(110, 300), mouth, [herb])).is_true()    # by the gate
	assert_bool(P0FarmMaterials.mouth_nearest(Vector2(160, 325), mouth, [herb])).is_false()   # by the Herb Patch
	assert_bool(P0FarmMaterials.mouth_nearest(Vector2(60, 250), mouth, [herb])).is_true()     # outside the spot's circle

const STORE := "user://test_p0_mine_mouth.json"

func _mouth_view(run = null, energy := 200, used := 0) -> Dictionary:
	return {"energy": {"value": energy, "max": 200, "next_in": null, "regen_ms": 240000}, "coins": 40, "skills": {}, "plots": [],
		"bag": {"capacity": 25, "free": 25, "slots": []}, "names": {}, "inbox": {"parcels": [], "letters": []},
		"rest": {"used": 0, "limit": 1, "resets_in": 1},
		"mine": {"runs": {"used": used, "limit": 2, "resets_in": 33120000}, "ended": null, "floor_energy": 2, "rock_energy": 2,
			"rocks": 6, "run": run}}

## The real farm scene without its _ready, its mine mouth helper on a runtime with no server.
func _farm(v: Dictionary, sent: Array) -> Node3D:
	UiCommandButton.offline = false
	P0Runtime.free_instance_for_tests()
	var rt := P0Runtime.ensure()
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	rt.session.sent.connect(func(cmd): sent.append(cmd))
	await get_tree().process_frame
	rt.session.view = v
	rt.ui.set_view(v)
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_farm.gd\"\nfunc _ready() -> void: pass\nfunc _exit_tree() -> void: pass\nfunc _process(_d) -> void: pass\nfunc p0_frame(_v, _d) -> void: pass\n"
	stub.reload()
	var farm: Node3D = load("res://scenes/p0/p0_farm.tscn").instantiate()
	farm.set_script(stub)
	add_child(farm)
	farm.rt = rt
	farm.bp = P0Garden.blueprint()
	farm.grid = BlueprintGrid.new(farm.bp)
	farm.actor = P0Actor.new()
	farm.add_child(farm.actor)
	farm.actor.setup(farm.bp, farm.grid, farm.cam)
	farm._mine = farm.bp.cell_to_world(farm.bp.anchor("mine")) + Vector3(-0.3, 0, 0.3)
	farm._materials = P0FarmMaterials.new().setup(farm, farm._mine)
	farm.add_child(farm._materials)
	rt.world = farm
	await get_tree().process_frame
	return farm

func _end(farm: Node3D) -> void:
	farm.queue_free()
	P0Runtime.free_instance_for_tests()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	await get_tree().process_frame

## SGODOT-266: tapped from afar the player walks up; pushing the stick on the way cancels and nothing opens.
func test_a_tap_on_the_mouth_walks_up_and_the_stick_cancels() -> void:
	var sent: Array = []
	var farm := await _farm(_mouth_view(), sent)
	var m: P0FarmMaterials = farm._materials
	assert_bool(m.near_mouth()).is_false()
	m.tap_mouth()
	assert_bool(m._to_mouth).is_true()
	assert_bool(farm.actor.mover.is_moving()).is_true()
	farm.p0_joystick(Vector2(1, 0))
	assert_bool(m._to_mouth).is_false()
	farm.p0_joystick(Vector2.ZERO)
	assert_bool(m.card_open()).is_false()
	assert_array(sent).is_empty()
	await _end(farm)

## At the mouth: the card with the fee button; only its button enters (the farm's key stays Farming's: p0_farm.gd and
## the P0_SHOT walkthrough on SGODOT-266).
func test_at_the_mouth_the_card_carries_the_fee() -> void:
	var sent: Array = []
	var farm := await _farm(_mouth_view(), sent)
	var m: P0FarmMaterials = farm._materials
	farm.actor.teleport(P0FarmMaterials.mouth_stands(farm.grid, farm._mine, farm.actor.position)[0])
	m.tap_mouth()
	m.frame(farm.rt.session.current())
	assert_bool(m.card_open()).is_true()
	assert_bool(m.card_wanted()).is_true()   # it holds the farm's one card meanwhile (LOCK-07, 亚瑟 on #190)
	var card: UiEntryCard = m._entry
	assert_str("%s · %s" % [card.title, card.title_fact]).is_equal("The mine · Runs today 0/2")
	assert_str(card.main_text()).is_equal("Enter mine · 2 Energy")
	assert_bool(card.second_shown()).is_false()
	assert_array(sent).is_empty()   # the tap spent nothing
	card.pressed.emit()
	assert_array(sent).is_equal([{"type": "mine_enter"}])
	assert_bool(m.card_open()).is_false()
	assert_bool(m.card_wanted()).is_false()
	await _end(farm)

## With a run: Continue run · Free, New run under it; short of Energy the main is amber and opens the Energy card;
## today's runs used up: the card still (MINE-GATE-EXPRESS-3 / -4, 不知火舞 B7 on 286 — the P0 MINE-P0-8 drawer for
## that state is gone), its grey pill `Resets in …` toasting the whole line; with the run in hand Continue run over it.
func test_the_mouth_card_states() -> void:
	var sent: Array = []
	var run := {"id": 1, "deepest": 1, "can_new_run": false, "new_run_block": "clear_floor_2", "floors": [{"floor": 1, "paid": true}]}
	var farm := await _farm(_mouth_view(run, 200, 1), sent)
	var m: P0FarmMaterials = farm._materials
	farm.actor.teleport(P0FarmMaterials.mouth_stands(farm.grid, farm._mine, farm.actor.position)[0])
	m.tap_mouth()
	m.frame(farm.rt.session.current())
	var card: UiEntryCard = m._entry
	assert_str(card.main_text()).is_equal("Continue run · Free")
	assert_str(card.second).is_equal("New run · Clear Floor 2 first")
	card.second_pressed.emit()
	assert_str(farm.rt.ui.toast_text()).is_equal("New run · Clear Floor 2 first")
	farm.rt.session.view = _mouth_view(null, 1)
	m.frame(farm.rt.session.current())
	assert_str(card.main_text()).is_equal("Enter mine · Need 2 Energy")
	assert_bool(card.is_amber()).is_true()
	card.pressed.emit()
	assert_str(farm.rt.ui.modal_kind).is_equal("energy")
	farm.rt.ui.close_modal()
	assert_array(sent).is_empty()
	farm.rt.session.view = _mouth_view(null, 200, 2)   # no run, 2/2: the card stays, the pill alone (EXPRESS-3)
	m.frame(farm.rt.session.current())
	assert_bool(m.card_open()).is_true()
	m.close_card()
	m.tap_mouth()   # a fresh tap in this state opens the card too, not a drawer
	m.frame(farm.rt.session.current())
	assert_bool(m.card_open()).is_true()
	assert_str(card.main_text()).starts_with("Resets in ")
	assert_bool(card.state == UiEntryCard.State.UNAVAILABLE).is_true()
	assert_bool(card.second_shown() or card.third_shown() or card.pill_text() != "").is_false()
	card.pressed.emit()
	assert_str(farm.rt.ui.toast_text()).starts_with("Mine runs today 2/2 · Resets in ")
	assert_str(farm.rt.ui.modal_kind).is_empty()   # no MINE-P0-8 drawer
	run.new_run_block = "no_runs"
	farm.rt.session.view = _mouth_view(run, 200, 2)   # the run in hand, 2/2: Continue run over the pill (EXPRESS-4)
	m.frame(farm.rt.session.current())
	assert_str(card.main_text()).is_equal("Continue run · Free")
	assert_str(card.pill_text()).starts_with("Resets in ")
	assert_bool(card.second_shown() or card.third_shown() or card.note_shown()).is_false()   # no New run, Express or note
	card.second_pressed.emit()   # the pill's tap
	assert_str(farm.rt.ui.toast_text()).starts_with("Mine runs today 2/2 · Resets in ")
	assert_array(sent).is_empty()
	await _end(farm)
