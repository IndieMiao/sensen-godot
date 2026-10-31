extends GdUnitTestSuite
## SGODOT-375 (LOCK-02, q(45); the user's C45 ok, 10-31): the water takes no taps — a tap on it neither casts, nor walks,
## nor opens the Energy card; a tap on the ground still walks there, and the main key still casts at the water in front.

const P0Pond := preload("res://scenes/p0/p0_pond.gd")
const PHONE := Vector2(360, 800)
const STORE := "user://test_p0_pond_water_tap.json"

var rt: P0Runtime
var sent := []

func before_test() -> void:
	sent = []
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, path, body, _c): sent.append([path, body])   # no server
	add_child(rt)
	await get_tree().process_frame
	rt.session.busy = false
	sent.clear()

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

## Fern Pond as the world is when the player walks it (catch moment's stand-in: the scene without its _ready).
func _pond(energy: int) -> Node3D:
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
	rt.session.view = {"energy": {"value": energy, "max": 200}, "bag": {"capacity": 25, "slots": []}, "fishing": {}}
	return pond

func _water_in_front(pond: Node3D) -> Vector2:
	var at: Vector3 = FishingModel.default_target(str(pond.entry.id), pond.actor.position, pond.site_spec)
	assert_bool(FishingModel.contains(str(pond.entry.id), at, 0, pond.site_spec)).is_true()   # on the water indeed
	return pond.cam.unproject_position(at)

func test_a_tap_on_the_water_does_nothing() -> void:
	var pond := _pond(200)
	var at: Vector3 = pond.actor.position
	pond.p0_tap(_water_in_front(pond))
	assert_dict(pond._plan).is_empty()                     # no walk to the bank for a cast
	assert_bool(pond.panel.visible).is_false()             # no cast
	assert_bool(pond.actor.mover.is_moving()).is_false()   # no walk either
	assert_vector(pond.actor.position).is_equal(at)
	assert_array(sent).is_empty()                          # nothing sent, no Energy spent

func test_with_no_energy_a_tap_on_the_water_does_not_open_the_energy_card() -> void:
	var pond := _pond(0)
	pond.p0_tap(_water_in_front(pond))
	assert_bool(rt.ui.has_modal()).is_false()
	assert_dict(pond._plan).is_empty()

func test_a_tap_on_the_ground_still_walks_there() -> void:
	var pond := _pond(200)
	var ground: Vector3 = pond.actor.position + Vector3(1.0, 0, 0.5)
	assert_bool(FishingModel.contains(str(pond.entry.id), ground, 0, pond.site_spec)).is_false()
	pond.p0_tap(pond.cam.unproject_position(ground))
	assert_bool(pond.actor.mover.is_moving()).is_true()

func test_the_main_key_still_casts_at_the_water_in_front() -> void:
	var pond := _pond(200)
	pond.p0_action({"type": "cast"})   # away from the bank: it walks there first (q(44) ①), then casts
	assert_bool(not pond._plan.is_empty() or pond.panel.visible).is_true()
