extends GdUnitTestSuite
## SGODOT-355 C part 2 (C2-b): a city gathering spot's card in its six states (D2 332:183026–184280, v4q(4) ②,
## 不知火舞 3b2c6a43 ⑥), a wild site's mouth card (E1 / E1-HERE / E4, v4q(5) ⑩ ⑪, LOCK-21, view.mine.paid_today #705),
## its travel card (C3 354:186011, the viewport's cost #706), the place chip at a wild site (C2 326:182063), and the
## cooldown counted down between reads.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Map := preload("res://scenes/p0/p0_map.gd")
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")
const P0WildSites := preload("res://modules/p0/p0_wild_sites.gd")
const P0Travel := preload("res://modules/p0/p0_travel.gd")
const SF := "gn-5391959"
const WOOD := {"id": "gn-5391959~wood0", "cluster": SF, "kind": "wood", "tier": "T1", "name": "Badger Grove", "short": "Badger",
	"lat": 37.80, "lng": -122.41, "yield": [["wood", 4]], "energy": 3, "cooldown_h": 4}
const REEDS := {"id": "gn-5391959~reed0", "cluster": SF, "kind": "reed", "tier": "T1", "name": "Heron Reed Bank", "short": "Heron",
	"lat": 37.76, "lng": -122.44, "yield": [["fiber", 4], ["worm_bait", 2]], "energy": 3, "cooldown_h": 4}
const VEIN := {"id": "wd-254-115", "type": "vein", "lat": 37.25, "lng": -122.28, "name": "Ironvale Vein", "short": "Ironvale",
	"near_name": "San Jose", "open": true, "free": true, "best_floor": 12, "cost": {"energy": 0, "coins": 0},
	"mine": {"floors": 46, "main": "iron_ore", "yields": ["iron_ore"], "main_from": 10, "side": 1, "open_to": 40}}
const GEODE := {"id": "wd-255-114", "type": "geode", "lat": 37.6, "lng": -122.9, "name": "Glimmer Geode", "short": "Glimmer",
	"near_name": "San Jose", "open": false, "cost": {"energy": 20, "coins": 60}, "mine": {"floors": 0, "open_to": 0}}

func _view(extra := {}) -> Dictionary:
	var v := {"energy": {"value": 120, "max": 200}, "coins": 300, "travel": {"home": SF, "here": SF, "passes": {}},
		"bag": {"capacity": 20, "free": 5, "slots": []}, "gather": {"city_ready": {}}, "mine": {"paid_today": {}},
		"names": {"wood": "Timber", "fiber": "Reeds", "worm_bait": "Worm Bait", "iron_ore": "Iron Ore"}}
	v.merge(extra, true)
	return v

func test_a_gathering_spots_card_says_what_it_gives_and_its_key_in_the_servers_order() -> void:
	var c := P0MaterialLogic.gather_card(_view(), WOOD, true, 0.0, 1.2)
	assert_str(str(c.title)).is_equal("Badger Grove")
	assert_str(str(c.subtitle)).is_equal("Gathering spot · Timber")
	assert_array(c.facts).is_equal([["Gives", "4 Timber"]])   # in its city: no Distance
	assert_str(str(c.primary)).is_equal("Gather · 3 Energy")
	assert_bool(c.has("blocked")).is_false()
	assert_array(P0MaterialLogic.gather_card(_view(), REEDS, true, 0.0).facts).is_equal([["Gives", "4 Reeds · Worm Bait"]])
	# not in its city: Go, and how far
	var away := P0MaterialLogic.gather_card(_view(), WOOD, false, 0.0, 24.0)
	assert_str(str(away.primary)).is_equal("Go")
	assert_array(away.facts).is_equal([["Gives", "4 Timber"], ["Distance", "24 km"]])
	# cooling down: grey Ready in (before Energy and room, as the server checks)
	var cooling := P0MaterialLogic.gather_card(_view({"energy": {"value": 1}}), WOOD, true, (3 * 60 + 12) * 60000.0)
	assert_str(str(cooling.blocked)).is_equal("Ready in 3h 12m")
	assert_bool(bool(cooling.get("blocked_energy", false))).is_false()
	assert_str(str(P0MaterialLogic.gather_card(_view(), WOOD, true, 42 * 60000.0).blocked)).is_equal("Ready in 42m")
	# short of Energy: amber, before the bag
	var low := P0MaterialLogic.gather_card(_view({"energy": {"value": 2}, "bag": {"free": 0, "slots": []}}), WOOD, true, 0.0)
	assert_str(str(low.blocked)).is_equal("Gather · Need 3 Energy")
	assert_bool(bool(low.blocked_energy)).is_true()
	# the main yield does not fit: grey No room — never on the farm, where it goes to Farm Storage
	var full := _view({"bag": {"free": 0, "slots": [{"id": "wood", "qty": 97}]}})
	assert_str(str(P0MaterialLogic.gather_card(full, WOOD, true, 0.0).blocked)).is_equal("No room · free a slot first")
	assert_bool(P0MaterialLogic.gather_card(full, WOOD, true, 0.0, -1.0, true).has("blocked")).is_false()
	var fits := _view({"bag": {"free": 0, "slots": [{"id": "wood", "qty": 95}]}})   # 4 more fit a 99 stack
	assert_bool(P0MaterialLogic.gather_card(fits, WOOD, true, 0.0).has("blocked")).is_false()

func test_bag_room_counts_plain_stacks_and_free_slots_never_a_gift() -> void:
	var v := _view({"bag": {"free": 1, "slots": [{"id": "wood", "qty": 90}, {"id": "wood", "qty": 10, "gifted": true}, {"id": "stone", "qty": 5}]}})
	assert_int(P0MaterialLogic.bag_room(v, "wood")).is_equal(9 + 99)
	assert_int(P0MaterialLogic.bag_room(v, "clay")).is_equal(99)

func test_a_spots_cooldown_counts_down_between_reads_and_goes_once_ready() -> void:
	var v := _view({"gather": {"city_ready": {"gn-5391959~wood0": 60000.0, "gn-5391959~reed0": 5000.0}}})
	var later := P0Logic.project(v, 10000.0)
	assert_dict(later.gather.city_ready).is_equal({"gn-5391959~wood0": 50000.0})
	assert_float(float(v.gather.city_ready["gn-5391959~wood0"])).is_equal(60000.0)   # the server's view untouched

func test_a_mouth_card_away_here_paid_today_short_of_energy_and_not_open() -> void:
	var away := P0MaterialLogic.mine_card(_view(), VEIN, false, 48.0)
	assert_str(str(away.subtitle)).is_equal("Vein mine · Floors 1–40 · near San Jose")
	assert_str(str(away.primary)).is_equal("Go")
	var labels: Array = away.facts.map(func(f): return str(f[0]))
	assert_array(labels).contains_exactly(["Main ore", "Monsters", "Boss", "You", "Distance", "Cost"])
	assert_array(away.facts.filter(func(f): return f[0] == "Cost")).is_equal([["Cost", "Free"]])
	assert_array(away.facts.filter(func(f): return f[0] == "You")).is_equal([["You", "Best here F12"]])
	var priced := VEIN.duplicate(true)
	priced.cost = {"energy": 20, "coins": 60}
	assert_array(P0MaterialLogic.mine_card(_view(), priced, false, 48.0).facts.filter(func(f): return f[0] == "Cost")).is_equal([["Cost", "20 Energy · 60 coins"]])
	# at the site: Enter mine, Floor 1's fee once a day (LOCK-21)
	var here := P0MaterialLogic.mine_card(_view(), VEIN, true)
	assert_str(str(here.primary)).is_equal("Enter mine · 2 Energy")
	assert_array(here.facts.filter(func(f): return f[0] in ["Distance", "Cost"])).is_empty()
	var paid := P0MaterialLogic.mine_card(_view({"mine": {"paid_today": {"wd-254-115": [1, 10]}}}), VEIN, true)
	assert_str(str(paid.primary)).is_equal("Enter mine · Free")
	var deeper := P0MaterialLogic.mine_card(_view({"mine": {"paid_today": {"wd-254-115": [12]}}}), VEIN, true)   # a rollover in the mine
	assert_str(str(deeper.primary)).is_equal("Enter mine · 2 Energy")
	var low := P0MaterialLogic.mine_card(_view({"energy": {"value": 1}}), VEIN, true)
	assert_str(str(low.blocked)).is_equal("Enter mine · Need 2 Energy")
	assert_bool(bool(low.blocked_energy)).is_true()
	# not open yet (E4): the type line and Not open yet, no key
	var geode := P0MaterialLogic.mine_card(_view(), GEODE, false, 30.0)
	assert_str(str(geode.subtitle)).is_equal("Geode mine · near San Jose")
	assert_str(str(geode.line)).is_equal("Not open yet")
	assert_bool(bool(geode.no_primary)).is_true()
	assert_bool(geode.has("facts")).is_false()

func test_a_wild_travel_card_is_free_for_the_nearest_three_and_says_the_fare_else() -> void:
	var free := P0Map.wild_travel_card(_view(), VEIN, 48.0)
	assert_str(str(free.title)).is_equal("Ironvale Vein")
	assert_str(str(free.subtitle)).is_equal("Vein mine · Floors 1–40 · near San Jose")
	assert_array(free.facts).is_equal([["Distance", "48 km"], ["Energy", "Free"], ["Coins", "Free"]])
	assert_str(str(free.primary)).is_equal("Fly")
	assert_str(str(free.blocked)).is_equal("")
	assert_str(str(free.footer)).is_equal("Return home is always free")
	var priced := VEIN.duplicate(true)
	priced.cost = {"energy": 20, "coins": 60}
	var card := P0Map.wild_travel_card(_view(), priced, 95.0)
	assert_array(card.facts).is_equal([["Distance", "95 km"], ["Energy", "20 → 100 left"], ["Coins", "60 → 240 left"]])
	var poor := P0Map.wild_travel_card(_view({"coins": 80}), priced, 95.0)
	assert_str(str(poor.blocked)).is_equal("Need 20 more coins")   # fare + the 40 floor − the wallet

func test_the_place_chip_at_a_wild_site_names_it_with_its_day_pass() -> void:
	var v := _view({"now": 1000.0, "travel": {"home": SF, "here": "wd-254-115", "passes": {"wd-254-115": {"until": 1000.0 + 23 * 3600000.0}}},
		"wild": {"here": {"id": "wd-254-115", "name": "Ironvale Vein"}}})
	var chip: Dictionary = P0Travel.place(v, {"city": "San Francisco", "space": "Homestead"})
	assert_str(str(chip.city)).is_equal("Ironvale Vein")
	assert_str(str(chip.space)).is_equal("")
	assert_str(str(chip.day_pass)).is_equal("23h")
	assert_int(int(chip.kind)).is_equal(UiHud.PlaceKind.FOREIGN)

func test_a_place_sheet_can_have_no_key() -> void:
	var ui := P0Ui.new()
	add_child(auto_free(ui))
	var holder := P0PlaceSheet.open(ui, {"title": "Glimmer Geode", "subtitle": "Geode mine · near San Jose", "line": "Not open yet",
		"no_primary": true}, func(): pass)
	assert_object(holder.find_child("Primary", true, false)).is_null()

# ---- on the map

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

func test_the_gathering_card_gathers_and_stays_open_turning_its_key_to_ready_in() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	P0CityPlaces.accept(SF, {"ponds": [], "outposts": [], "residents": 0, "fish": [], "gather": [WOOD]})
	var rt: P0Runtime = m.rt
	var sent: Array = []
	rt.session.transport = func(_m: int, _p: String, body: Dictionary, cmd: Dictionary): sent.append(cmd)
	var v: Dictionary = rt.session.view.duplicate(true)
	v.merge(_view(), true)
	rt.session.view = v
	m._on_entry_selected(P0Map.gather_entry(WOOD))
	assert_str(rt.ui.modal_kind).is_equal("gather_card")
	var key := m._live_card.find_child("Primary", true, false) as UiCommandButton
	assert_str(key.label).is_equal("Gather · 3 Energy")
	key.activated.emit()
	assert_array(sent.filter(func(c): return str(c.get("type", "")) == "gather").map(func(c): return str(c.spot))).is_equal(["gn-5391959~wood0"])
	# the reply: the spot cooling down 4 h — the card stays, its key turns grey
	var after: Dictionary = v.duplicate(true)
	after.gather = {"city_ready": {"gn-5391959~wood0": 4 * 3600000.0}}
	rt.session.view = after
	rt.session._received_ms = Time.get_ticks_msec()   # just in: nothing counted down yet
	m.p0_frame(after, 0.0)
	assert_str(rt.ui.modal_kind).is_equal("gather_card")
	assert_str(key.reason).is_equal("Ready in 4h")

func test_a_wild_pin_opens_its_mouth_card_and_go_opens_its_travel_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	P0WildSites.accept("t", {"sites": [VEIN, GEODE]})
	m._on_entry_selected(P0Map.wild_entry(VEIN))
	assert_str(m.rt.ui.modal_kind).is_equal("mine_card")
	var key := m._live_card.find_child("Primary", true, false) as UiCommandButton
	assert_str(key.label).is_equal("Go")
	key.activated.emit()
	assert_str(m.rt.ui.modal_kind).is_equal("travel_card")
	m.rt.ui.close_modal()
	m._on_entry_selected(P0Map.wild_entry(GEODE))
	assert_str(m.rt.ui.modal_kind).is_equal("mine_card")
	assert_object(m._live_card.find_child("Primary", true, false)).is_null()
