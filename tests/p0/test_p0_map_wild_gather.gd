extends GdUnitTestSuite
## SGODOT-355 C part 2 (v4q(3) ⑤, v4q(4) ②, LOCK-24, 不知火舞 355 3b2c6a43): a city's gathering spots and the wild
## sites on the map — their pins, ranks and zoom, the ones nothing hides, the guide's !, the viewport's box and the
## Show targets `gather:` / `mine:`.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Map := preload("res://scenes/p0/p0_map.gd")
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")
const P0WildSites := preload("res://modules/p0/p0_wild_sites.gd")
const SF := "gn-5391959"

const SPOTS := [
	{"id": "gn-5391959~wood0", "cluster": SF, "kind": "wood", "tier": "T1", "name": "Badger Grove", "short": "Badger",
		"lat": 37.80, "lng": -122.41, "yield": [["wood", 4]], "energy": 3, "cooldown_h": 4},
	{"id": "gn-5391959~reed0", "cluster": SF, "kind": "reed", "tier": "T1", "name": "Heron Reed Bank", "short": "Heron",
		"lat": 37.76, "lng": -122.44, "yield": [["fiber", 4], ["worm_bait", 2]], "energy": 3, "cooldown_h": 4}]
const VEIN := {"id": "wd-254-115", "type": "vein", "lat": 37.25, "lng": -122.28, "name": "Ironvale Vein", "short": "Ironvale",
	"open": true, "km": 42.1, "trip": 2, "free": true, "mine": {"main": "iron_ore"}}
const QUARRY := {"id": "wd-253-116", "type": "quarry", "lat": 36.9, "lng": -121.9, "name": "Redstone Quarry", "short": "Redstone",
	"open": true, "km": 95.0, "trip": 2, "free": false}
const GEODE := {"id": "wd-255-114", "type": "geode", "lat": 37.6, "lng": -122.9, "name": "Glimmer Geode", "short": "Glimmer",
	"open": false, "km": 60.0, "trip": 2, "free": false}

func before_test() -> void:
	P0CityPlaces.clear()
	P0WildSites.clear()
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	P0CityPlaces.clear()
	P0WildSites.clear()
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var map := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(map)
	return map

func _read() -> void:
	P0CityPlaces.accept(SF, {"ponds": [], "outposts": [], "residents": 0, "fish": [], "gather": SPOTS})
	P0WildSites.accept("test", {"sites": [VEIN, QUARRY, GEODE]})

func test_gathering_spots_and_wild_sites_are_pinned_with_their_glyph_short_name_and_rank() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_read()
	m._set_outpost_places()
	var ids: Array = m.city_map.extra_places.map(func(e): return str(e.id))
	assert_array(ids).contains(["gn-5391959~wood0", "gn-5391959~reed0", "wd-254-115", "wd-253-116", "wd-255-114"])
	var wood: Dictionary = m._destination_style_of(P0Map.gather_entry(SPOTS[0]))
	assert_str(str(wood.label)).is_equal("Badger")
	assert_int(int(wood.rank)).is_equal(P0Map.PIN_RANK.gather)
	assert_object(wood.icon).is_equal(P0Logic.icon("wood"))
	assert_object(m._destination_style_of(P0Map.gather_entry(SPOTS[1])).icon).is_equal(P0Logic.icon("fiber"))
	var vein: Dictionary = m._destination_style_of(P0Map.wild_entry(VEIN))
	assert_str(str(vein.label)).is_equal("Ironvale")
	assert_int(int(vein.rank)).is_equal(P0Map.PIN_RANK.wild)
	assert_float(float(vein.order)).is_equal(42.1)   # nearest home first among the open ones
	assert_bool(bool(vein.locked)).is_false()
	assert_bool(vein.has("silhouette")).is_false()   # above the fog
	var geode: Dictionary = m._destination_style_of(P0Map.wild_entry(GEODE))
	assert_bool(bool(geode.locked)).is_true()
	assert_str(str(geode.label)).is_equal("Glimmer")   # its name kept
	assert_int(int(geode.rank)).is_equal(P0Map.PIN_RANK.wild_closed)
	# the order (3b2c6a43 ②): tackle shop, gathering spot, open wild, not open, silhouette
	var r: Dictionary = P0Map.PIN_RANK
	assert_bool(r.tackle < r.gather and r.gather < r.wild and r.wild < r.wild_closed and r.wild_closed < r.silhouette).is_true()

func test_gathering_spots_show_from_a_level_nearer_than_the_overview_and_wild_sites_from_nine() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_read()
	var from := P0Map.gather_zoom(SF)
	m.zoom = from - 0.1
	assert_bool(m.place_shown(P0Map.gather_entry(SPOTS[0]))).is_false()
	m.zoom = from
	assert_bool(m.place_shown(P0Map.gather_entry(SPOTS[0]))).is_true()
	m.zoom = 8.5
	assert_bool(m.place_shown(P0Map.wild_entry(QUARRY))).is_false()
	m.zoom = 9.0
	assert_bool(m.place_shown(P0Map.wild_entry(QUARRY))).is_true()
	assert_bool(m.place_shown({"id": "sh_tea_1", "kind": "place"})).is_true()   # every other place as ever

func test_the_guides_spot_the_free_three_where_the_player_is_and_the_show_target_are_always_in() -> void:
	var view := {"guide": {"step": "t_gather", "target": {"kind": "gather", "spot": "gn-5391959~wood0", "item": "wood"}},
		"wild": {"near3": ["wd-254-115"]}, "travel": {"home": SF, "here": "wd-253-116"}}
	assert_bool(P0Map.always_shown(view, "gn-5391959~wood0")).is_true()
	assert_bool(P0Map.always_shown(view, "gn-5391959~reed0")).is_false()
	assert_bool(P0Map.always_shown(view, "gn-5391959~reed0", "gn-5391959~reed0")).is_true()   # Show flew to it
	assert_bool(P0Map.always_shown(view, "wd-254-115")).is_true()   # free
	assert_bool(P0Map.always_shown(view, "wd-253-116")).is_true()   # here
	assert_bool(P0Map.always_shown(view, "wd-255-114")).is_false()
	assert_str(P0Map.guide_spot(view)).is_equal("gn-5391959~wood0")
	assert_str(P0Map.guide_spot({"guide": {"step": "t_gather"}})).is_equal("")   # no target: the key is absent

func test_the_guides_spot_wears_the_request_mark() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_read()
	var view: Dictionary = m._view().duplicate(true)
	view["guide"] = {"step": "t_gather", "target": {"kind": "gather", "spot": "gn-5391959~wood0", "item": "wood"}}
	m.p0_frame(view, 0.0)
	assert_array(m.city_map.marks.filter(func(x): return str(x.id) == "gn-5391959~wood0").map(func(x): return str(x.state))).is_equal(["request"])

func test_show_targets_find_a_gathering_spot_and_a_mine_read_or_only_in_near3() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_read()
	var spot: Dictionary = m.place_for("gather:gn-5391959~reed0")
	assert_str(str(spot.id)).is_equal("gn-5391959~reed0")
	assert_float(float(spot.lat)).is_equal(37.76)
	assert_str(str(m.place_for("mine:wd-254-115").id)).is_equal("wd-254-115")
	assert_dict(m.place_for("mine:wd-999-999")).is_empty()
	assert_dict(m.place_for("gather:gn-5391959~clay9")).is_empty()
	assert_str(P0Map._place_id("gather:gn-5391959~wood0")).is_equal("gn-5391959~wood0")
	assert_str(P0Map._place_id("mine:wd-254-115")).is_equal("wd-254-115")
	assert_str(P0Map._place_id("outpost:sh_tea_1")).is_equal("sh_tea_1")

func test_the_viewport_box_is_the_screen_and_a_margin_across_the_date_line_too() -> void:
	var box := P0Map.view_box(37.77, -122.42, 12.0, Vector2(360, 800))
	assert_bool(box[0] < 37.77 and box[2] > 37.77 and box[1] < -122.42 and box[3] > -122.42).is_true()
	assert_bool(box[3] - box[1] < 0.5).is_true()   # a city's few km at z12
	var wide := P0Map.view_box(10.0, 179.9, 9.0, Vector2(360, 800))
	assert_bool(wide[1] > wide[3]).is_true()   # west > east across 180°, as the server reads it
	var far := P0Map.view_box(0.0, 0.0, 2.0, Vector2(360, 800))
	assert_bool(far[2] - far[0] <= 19.0 and absf(wrapf(far[3] - far[1], 0.0, 360.0)) <= 19.0).is_true()   # under 20° each way

func test_a_place_not_open_yet_is_grey_with_a_lock_and_keeps_its_name() -> void:
	var pin := UiMapDestination.new(P0Logic.icon("geode"), "Glimmer")
	pin.theme = UiKit.theme()
	add_child(auto_free(pin))
	pin.locked = true
	var lock: Control = pin.find_child("Lock", true, false)
	assert_object(lock).is_not_null()
	assert_bool(lock.visible).is_true()
	assert_bool(pin._label_box.visible).is_true()
	assert_object(pin._icon.material).is_not_null()
	pin.locked = false
	assert_bool(lock.visible).is_false()
	assert_object(pin._icon.material).is_null()
