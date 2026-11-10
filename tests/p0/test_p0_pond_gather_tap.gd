extends GdUnitTestSuite
## SGODOT-475 ② (the user 11-10, bot 682 「点击 走到附近, 采摘」; 不知火舞's gather-compact spec v1 ②): a tap on a point's
## mark or within 36 px of its piece walks to its stand and, arrived and facing it, gathers once — the key's own command.
## Cooling: no walk, when it is ready (once in 2 s), its mark pulsed. Short of Energy or with the bag full: walked there,
## nothing gathered. The stick or a tap elsewhere stops it; before the points come a tap is a tap on the ground.

const P0Pond := preload("res://scenes/p0/p0_pond.gd")
const PondGather := preload("res://scenes/p0/p0_pond_gather.gd")
const PHONE := Vector2(360, 800)
const STORE := "user://test_p0_pond_gather_tap.json"

var rt: P0Runtime
var pressed := []

func before_test() -> void:
	pressed = []
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _path, _body, _c): pass   # no server
	add_child(rt)
	await get_tree().process_frame
	rt.session.busy = false
	rt.ui.action_pressed.connect(func(cmd): pressed.append(cmd))
	rt.session.sent.connect(func(cmd): pressed.append(cmd))   # arrived, the point's own command goes straight out

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

## Fern Pond as the player walks it (the scene without its _ready, as test_p0_pond_water_tap), and one point 2.5 m
## east of the player on the walk, its stand 0.8 m short of it.
func _pond(energy := 50, free := 5, ready := 0.0, with_points := true) -> Node3D:
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_pond.gd\"\nfunc _ready() -> void: pass\n"
	stub.reload()
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	add_child(auto_free(vp))
	var pond: Node3D = Node3D.new()
	pond.set_script(stub)
	vp.add_child(pond)
	pond.rt = rt
	pond.entry = preload("res://modules/p0/p0_ponds.gd").location("pond_san_francisco_03")
	pond.site_spec = SystemPonds.site(pond.entry)
	pond.bp = SystemPonds.blueprint(pond.entry)
	pond.grid = BlueprintGrid.new(pond.bp)
	pond.cam = Camera3D.new()
	pond.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	pond.cam.keep_aspect = Camera3D.KEEP_WIDTH
	pond.add_child(pond.cam)
	pond.cam.make_current()
	pond.actor = P0Actor.new()
	pond.add_child(pond.actor)
	pond.actor.setup(pond.bp, pond.grid, pond.cam)
	pond.panel = P0FishingPanel.new()
	pond.add_child(pond.panel)
	pond.panel.hide()
	pond.cam.size = P0Pond.view_size(PHONE, 1.0)
	P0Pond.place(pond.cam, pond.actor.position)
	pond.gather = PondGather.new()
	pond.gather.pond = str(pond.entry.id)
	pond.add_child(pond.gather)
	var at: Vector3 = pond.actor.position + Vector3(2.5, 0, 0)
	var p := {"id": "pt#1", "slot": "L1", "kind": "stone", "name": "Rocks", "yield": [["stone", 2]], "energy": 3,
		"x": at.x, "z": at.z, "stand": [at.x - 0.8, at.z], "ready_in": ready}
	if with_points: pond.gather.points = [p]
	rt.session.view = {"energy": {"value": energy, "max": 200}, "bag": {"capacity": 25, "free": free, "slots": []}, "fishing": {}}
	return pond

func _piece(pond: Node3D) -> Vector2:
	var p: Dictionary = pond.gather.points[0]
	return pond.cam.unproject_position(Vector3(float(p.x), 0.5, float(p.z)))

func _arrive(pond: Node3D) -> void:
	pond.actor.mover.stop()
	pond.actor.teleport(PondGather.stand_of(pond.gather.points[0]))
	pond._tap_gather_check(rt.session.view)

func test_a_tap_on_the_piece_walks_to_its_stand_and_gathers_once_there() -> void:
	var pond := _pond()
	assert_bool(pond.bp.is_walkable(pond.bp.world_to_cell(PondGather.stand_of(pond.gather.points[0])))).is_true()
	pond.p0_tap(_piece(pond) + Vector2(20, 0))   # within 36 px of its middle
	assert_str(pond._tap_gather).is_equal("pt#1")
	assert_bool(pond.actor.mover.is_moving()).is_true()
	assert_array(pressed).is_empty()   # nothing until it is there
	_arrive(pond)
	assert_array(pressed).is_equal([{"type": "gather", "spot": "pt#1", "space": "pond", "place": str(pond.entry.id)}])
	assert_str(pond._tap_gather).is_equal("")   # once: not again next frame
	pond._tap_gather_check(rt.session.view)
	assert_int(pressed.size()).is_equal(1)

func test_its_mark_is_a_tap_on_it_and_a_tap_past_36_px_is_the_ground() -> void:
	var pond := _pond()
	pond.p0_tap(_piece(pond) + Vector2(0, 40))   # past 36 px: the ground
	assert_str(pond._tap_gather).is_equal("")
	rt.ui.tapped_card = "gather:pt#1"   # 亚瑟's mark (① ), wherever it stands
	pond.p0_tap(Vector2(10, 10))
	assert_str(pond._tap_gather).is_equal("pt#1")

func test_cooling_it_says_when_once_and_does_not_walk() -> void:
	var pond := _pond(50, 5, 3 * 3600 * 1000.0 + 12 * 60 * 1000.0)
	pond.p0_tap(_piece(pond))
	assert_bool(pond.actor.mover.is_moving()).is_false()
	assert_str(pond._tap_gather).is_equal("")
	assert_str(str(pond._gather_told.id)).is_equal("pt#1")
	var told := int(pond._gather_told.at)
	pond.p0_tap(_piece(pond))   # again within 2 s: nothing said again
	assert_int(int(pond._gather_told.at)).is_equal(told)
	assert_array(pressed).is_empty()

func test_short_of_energy_or_with_the_bag_full_it_walks_there_and_gathers_nothing() -> void:
	var pond := _pond(1)
	pond.p0_tap(_piece(pond))
	_arrive(pond)
	assert_array(pressed).is_empty()
	assert_bool(rt.ui.has_modal()).is_false()   # no Energy card: the key says it, amber
	pond = _pond(50, 0)
	pond.p0_tap(_piece(pond))
	_arrive(pond)
	assert_array(pressed).is_empty()

func test_the_stick_or_a_tap_elsewhere_stops_it() -> void:
	var pond := _pond()
	pond.p0_tap(_piece(pond))
	pond.p0_joystick(Vector2(1, 0))
	assert_str(pond._tap_gather).is_equal("")
	pond.p0_joystick(Vector2.ZERO)
	pond.p0_tap(_piece(pond))
	assert_str(pond._tap_gather).is_equal("pt#1")
	rt.ui.tapped_card = ""
	pond.p0_tap(pond.cam.unproject_position(pond.actor.position + Vector3(-1.0, 0, 0.5)))   # the ground
	assert_str(pond._tap_gather).is_equal("")

## #947's iOS crash: before the points come (or with no gathering here) a tap is the ground's, and nothing reads a null.
func test_before_the_points_come_a_tap_is_the_grounds() -> void:
	var pond := _pond(50, 5, 0.0, false)
	var screen: Vector2 = pond.cam.unproject_position(pond.actor.position + Vector3(2.5, 0.5, 0))
	pond.p0_tap(screen)
	assert_str(pond._tap_gather).is_equal("")
	pond.gather = null
	pond.p0_tap(screen)
	assert_str(pond._tap_gather).is_equal("")

## The key's walk to the bank (Cast) on the way to a point, then a tap on the point: the cast is off, the point it is.
func test_a_tap_on_a_point_takes_over_the_walk_to_cast() -> void:
	var pond := _pond()
	pond._plan = {"origin": pond.actor.position + Vector3(0, 0, 3)}
	pond.p0_tap(_piece(pond))
	assert_dict(pond._plan).is_empty()
	assert_str(pond._tap_gather).is_equal("pt#1")

## 奕星 v4q(13) 14: a tap on the trap on the way drops the tapped gather — there, it does not turn to the piece or gather.
func test_a_tap_on_the_trap_drops_a_tapped_gather() -> void:
	var pond := _pond()
	pond.p0_tap(_piece(pond))
	assert_str(pond._tap_gather).is_equal("pt#1")
	rt.ui.tapped_card = P0Pond.TRAP_ID
	pond.p0_tap(Vector2(10, 10))
	assert_str(pond._tap_gather).is_equal("")
	_arrive(pond)
	assert_array(pressed).is_empty()

## 奕星 v4q(13) 15: the key's cast drops a tapped gather however it goes — also when the player already stands on the
## cast origin and the panel opens at once.
func test_the_keys_cast_drops_a_tapped_gather_even_where_it_stands() -> void:
	var pond := _pond()
	pond.p0_tap(_piece(pond))
	var plan := FishingModel.plan(str(pond.entry.id), pond.actor.position, Vector3.INF, pond.grid, pond.site_spec)
	pond.actor.mover.stop()
	pond.actor.teleport(plan.origin)
	pond._go_cast(Vector3.INF)
	assert_str(pond._tap_gather).is_equal("")

## 奕星 v4q(13) 16: arrived, the tapped point is the one gathered — its own command — and the key and marks stay on it
## while the player is in its reach, though another point's stand is as near; out of its reach the nearest again.
func test_arrived_the_tapped_point_is_gathered_and_stays_the_keys() -> void:
	var pond := _pond()
	var other: Dictionary = (pond.gather.points[0] as Dictionary).duplicate()
	other.id = "pt#2"
	other.x = float(other.x) - 1.6   # another piece, its stand where pt#1's is and listed first: the nearest by stand
	pond.gather.points = [other, pond.gather.points[0]]
	assert_str(str(PondGather.nearest(pond.gather.points, PondGather.stand_of(other)).id)).is_equal("pt#2")
	rt.ui.tapped_card = "gather:pt#1"
	pond.p0_tap(Vector2(10, 10))
	rt.ui.tapped_card = ""
	pond.actor.mover.stop()
	pond.actor.teleport(PondGather.stand_of(other))
	pond._tap_gather_check(rt.session.view)
	assert_array(pressed).is_equal([{"type": "gather", "spot": "pt#1", "space": "pond", "place": str(pond.entry.id)}])
	assert_str(str(pond._gather_current().id)).is_equal("pt#1")
	pond.actor.teleport(PondGather.stand_of(other) + Vector3(-4, 0, 0))
	assert_str(str(pond._gather_current().get("id", ""))).is_not_equal("pt#1")

## 奕星 v4q(13) ⑤: the guide's `!` takes no tap of its own; a tap on it is a tap on the point it hangs over (S6a).
func test_a_tap_on_the_guides_mark_is_a_tap_on_its_point() -> void:
	var pond := _pond()
	var v := rt.session.view.merged({"guide": {"target": {"kind": "gather", "spot": "pt#1"}}})
	pond._gather_marks(v, {})
	var mark := rt.ui.badge_rect("gather_mark:pt#1")
	assert_bool(mark.has_area()).is_true()
	assert_float(mark.get_center().distance_to(_piece(pond))).is_greater(P0Pond.GATHER_TAP_PX)   # not the piece's 36 px
	pond.p0_tap(mark.get_center())
	assert_str(pond._tap_gather).is_equal("pt#1")

## 奕星 v4q(13) ⑥: a tap on a cooling point stops a walk on the way somewhere else.
func test_a_tap_on_a_cooling_point_stops_the_walk() -> void:
	var pond := _pond(50, 5, 3600 * 1000.0)
	pond.p0_tap(pond.cam.unproject_position(pond.actor.position + Vector3(-1.0, 0, 0.5)))   # the ground: walking
	assert_bool(pond.actor.mover.is_moving()).is_true()
	pond.p0_tap(_piece(pond))
	assert_bool(pond.actor.mover.is_moving()).is_false()
