extends GdUnitTestSuite
## q(165) (§9.11.4 / §17.3.1; FARE-BOARD 2631:134814, 不知火舞's spec on 302): the Travel Post's counters, read only.
## The Stamp Desk (`Stamp Desk`, the stamp icon) opens the Passport, Back returning to the room; the Fare Board
## (`Fare Board`, the board icon; on the world map until its own board is made) opens Trip fares: the seven tiers with
## their bounds, every fare Free while travel is.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Travel := preload("res://modules/p0/p0_travel.gd")

class Post extends "res://scenes/p0/p0_outpost.gd":
	var opened: Array = []   # the P0Ui entries the counters asked for
	func setup(a: Dictionary) -> void:
		super.setup(a)
		use_runtime = false
	func _open_entry(method: String, args: Array, _fallback: String) -> void:
		opened.append([method, args])

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

func after() -> void:
	P0Runtime.free_instance_for_tests()

func test_the_fares_are_the_seven_tiers_all_free() -> void:
	var rows: Array = P0Travel.fares()
	assert_array(rows.map(func(r): return str(r.title))).is_equal(["Trip 1 · Local", "Trip 2 · Nearby", "Trip 3 · Regional",
		"Trip 4 · Long Haul", "Trip 5 · Continental", "Trip 6 · Intercontinental", "Trip 7 · Antipodal"])
	assert_array(rows.map(func(r): return str(r.line))).is_equal(["Up to 30 km, or the 3 nearest cities",
		"Up to 100 km, or the 10 nearest cities", "Up to 500 km", "Up to 1,600 km", "Up to 4,000 km", "Up to 10,000 km",
		"Over 10,000 km"])
	assert_array(rows.map(func(r): return str(r.fare))).is_equal(["Free", "Free", "Free", "Free", "Free", "Free", "Free"])

func test_the_stamp_desk_and_the_fare_board_are_counters_with_their_names() -> void:
	var r := Post.new()
	r.setup({"outpost_id": "sh_post_1"})
	add_child(auto_free(r))
	var taps := r._tappable()
	assert_bool(taps.has("use_stamp_desk")).is_true()
	assert_bool(taps.has("use_fee_board")).is_true()
	var desk: Dictionary = r._marker("use_stamp_desk", {})
	assert_that([desk.get("kind"), desk.get("name")]).is_equal(["facility", "Stamp Desk"])
	assert_object(desk.get("icon")).is_same(P0Logic.icon("stamp"))
	var board: Dictionary = r._marker("use_fee_board", {})
	assert_that([board.get("kind"), board.get("name")]).is_equal(["facility", "Fare Board"])
	assert_object(board.get("icon")).is_same(P0Logic.icon("board"))
	r._on_facility("use_stamp_desk")
	r._on_facility("use_fee_board")
	assert_array(r.opened).is_equal([["open_passport", []], ["open_fare_board", []]])

## SGODOT-275 (刘备's fare_board.glb, #396): the Fare Board is its own board on the left wall under the POST OFFICE sign,
## on the kit's shared atlas; its tap and name strip at the model's board_center.
func test_the_fare_board_is_its_own_board_and_taps_at_its_centre() -> void:
	var r := Post.new()
	r.setup({"outpost_id": "sh_post_1"})
	add_child(auto_free(r))
	var board := r.art.get_node_or_null("fare_board") as Node3D
	assert_object(board).is_not_null()
	assert_vector(board.position).is_equal(Vector3(-3.208, 1.65, -1.65))
	assert_float(rad_to_deg(board.rotation.y)).is_equal_approx(90.0, 0.001)
	var meshes := board.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_equal(1)
	assert_object(((meshes[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_texture).is_same(load("res://assets/rooms/post_office/room_albedo_ao.png"))
	var centre := board.find_child("board_center", true, false) as Node3D
	assert_object(centre).is_not_null()
	assert_vector(r.anchor("use_fee_board").global_position).is_equal_approx(centre.global_position, Vector3.ONE * 0.001)
	assert_bool(r._tappable().has("use_fee_board")).is_true()

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var m := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(m)
	return m

## FARE-BOARD: the sheet's top at y 324 (476 high); `Trip fares` in a 27 row from y 340, 16 in; seven rows of 58 straight
## under it, not tappable; the tier and its bounds 10 from the row's top, 2 apart; `Free` in the primary green, its right
## at 344 and centred on the row; a Close 44 over the sheet. Its Close and Back close it.
func test_trip_fares_reads_as_the_frame() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	var d: UiDrawer = rt.ui.open_fare_board()
	assert_str(rt.ui.modal_kind).is_equal("fare_board")
	await get_tree().create_timer(0.6).timeout   # slid up
	assert_float(d.height).is_equal(496.0)   # with q(257) ①'s footnote (FARE-BOARD 9:133836)
	var sheet := d.get_global_rect()   # P0Ui's root is the window's (headless 640 wide): measured from the sheet
	var head: Control = d.find_child("Head", true, false)
	assert_str((d.find_child("Title", true, false) as Label).text).is_equal("Trip fares")
	assert_vector(head.get_global_rect().position - sheet.position).is_equal(Vector2(16, 16))
	assert_float(head.size.y).is_equal(27.0)
	var rows: Array = (d.find_child("Fares", true, false) as Node).get_children()
	assert_int(rows.size()).is_equal(7)
	for i in rows.size():
		var row: Control = rows[i]
		var at := row.get_global_rect()
		assert_float(at.position.y - sheet.position.y).is_equal_approx(16.0 + 27.0 + 58.0 * i, 0.01)
		assert_float(at.size.y).is_equal(58.0)
		assert_float(sheet.end.x - at.end.x).is_equal(16.0)
		assert_int(row.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		var tier: Label = row.find_child("Tier", true, false)
		var bounds: Label = row.find_child("Bounds", true, false)
		assert_str(tier.text).is_equal(str(P0Travel.fares()[i].title))
		assert_str(bounds.text).is_equal(str(P0Travel.fares()[i].line))
		assert_float(bounds.get_global_rect().position.y - tier.get_global_rect().end.y).is_equal(2.0)
		var fare: Label = row.find_child("Fare", true, false)
		assert_str(fare.text).is_equal("Free")
		assert_that(fare.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_PRIMARY_INK)
		assert_float(fare.get_global_rect().end.x).is_equal(at.end.x)
		assert_float(fare.get_global_rect().get_center().y).is_equal_approx(at.get_center().y, 0.5)
	rt.ui.close_modal()
	assert_str(rt.ui.modal_kind).is_empty()
