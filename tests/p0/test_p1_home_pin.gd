extends GdUnitTestSuite
## SGODOT-342 PR-2, the free pin's rules on the client (q(216) ②③⑨; P0HomePin): the area from the spots read, where
## the pin may stand (a little inside the server's 10 km / 300 m), the card's line, the grey key and its toast, the
## start and the back-to-start target, the command. Distances and sides checked against the server's world.km / toward.

const P0HomePin := preload("res://modules/p0/p0_home_pin.gd")

const BASE := {"lat": 37.76, "lng": -122.44}
const POND := Vector2(37.76, -122.44)   # Fern Pond at the base, for round numbers
## Points the server's offset() puts at these km and bearings from BASE, with its km and side (server, 10-27).
const W08 := Vector2(37.76, -122.44909)        # 0.7991 km, west
const NE4 := Vector2(37.785408, -122.407862)   # 3.9951 km, northeast
const S996 := Vector2(37.670528, -122.44)      # 9.9488 km, south
const E1002 := Vector2(37.76, -122.326146)     # 10.0088 km, east
const N11 := Vector2(37.858814, -122.44)       # 10.9876 km, north

static func _pin(clear := 300.0) -> Dictionary:
	return {"base": BASE, "range_km": 10, "clear_m": clear, "start": {"lat": 37.765, "lng": -122.43},
		"blocks": [{"id": "pond_fern", "lat": 37.76, "lng": -122.44}, {"id": "outpost_mission_market", "lat": 37.78, "lng": -122.42}]}

func after_test() -> void:
	P0HomePin.repin_starts_on_farm = false

func test_the_area_reads_the_pin_and_refuses_a_part_one() -> void:
	var a := P0HomePin.area(_pin())
	assert_object(a.base).is_equal(Vector2(37.76, -122.44))
	assert_float(a.range_km).is_equal(10.0)
	assert_float(a.clear_m).is_equal(300.0)
	assert_object(a.start).is_equal(Vector2(37.765, -122.43))
	assert_array(a.blocks.map(func(b): return b.id)).is_equal(["pond_fern", "outpost_mission_market"])
	# an older server (no pin), a city that cannot be a home (pin null), a broken one: no area — the page's read failed
	for bad in [null, {}, {"base": BASE, "range_km": 10}, {"start": BASE, "range_km": 10}, {"base": BASE, "start": BASE}]:
		assert_dict(P0HomePin.area(bad)).is_empty()

func test_distances_and_sides_match_the_server() -> void:
	assert_float(P0HomePin.km(POND, W08)).is_equal_approx(0.7991, 0.0005)
	assert_float(P0HomePin.km(POND, NE4)).is_equal_approx(3.9951, 0.0005)
	assert_float(P0HomePin.km(POND, N11)).is_equal_approx(10.9876, 0.0005)
	assert_str(P0HomePin.toward(POND, W08)).is_equal("west")
	assert_str(P0HomePin.toward(POND, NE4)).is_equal("northeast")
	assert_str(P0HomePin.toward(POND, S996)).is_equal("south")

func test_the_pin_stands_a_little_inside_the_servers_circle() -> void:
	var a := P0HomePin.area(_pin(0.0))
	assert_dict(P0HomePin.refusal(a, NE4)).is_empty()
	assert_dict(P0HomePin.refusal(a, S996)).is_empty()   # 9.949 km: inside 9.95
	assert_str(P0HomePin.refusal(a, E1002).code).is_equal("far")   # 10.009: the server refuses too
	assert_str(P0HomePin.refusal(a, Vector2(37.76, -122.3265)).code).is_equal("far")   # 9.98 km: the client's margin
	assert_str(P0HomePin.refusal({}, NE4).code).is_equal("far")   # no area, nothing stands
	# the server's start stands even inside the client's margins (Build here at once)
	var tight := _pin()
	tight.start = {"lat": 37.76271, "lng": -122.44}   # 301 m from the pond: the server's 300 passes, the client's 305 not
	var t := P0HomePin.area(tight)
	assert_dict(P0HomePin.refusal(t, t.start)).is_empty()
	assert_str(P0HomePin.refusal(t, Vector2(37.76268, -122.44)).code).is_equal("near")   # 3 m off it: judged again

func test_a_pin_near_a_place_names_the_nearest() -> void:
	var a := P0HomePin.area(_pin())
	var no := P0HomePin.refusal(a, Vector2(37.7615, -122.44))   # 167 m north of the pond
	assert_str(no.code).is_equal("near")
	assert_str(no.id).is_equal("pond_fern")
	assert_float(no.m).is_equal_approx(166.8, 1.0)
	# 302 m: clear of the server's 300, inside the client's 305
	assert_str(P0HomePin.refusal(a, Vector2(37.76272, -122.44)).get("code", "")).is_equal("near")
	assert_dict(P0HomePin.refusal(a, Vector2(37.7628, -122.44))).is_empty()   # 311 m
	# the circles show within 600 m, nearest first
	assert_array(P0HomePin.shown_blocks(a, Vector2(37.7615, -122.44)).map(func(b): return b.id)).is_equal(["pond_fern"])
	assert_array(P0HomePin.shown_blocks(a, NE4)).is_empty()
	assert_array(P0HomePin.shown_blocks(P0HomePin.area(_pin(0.0)), POND)).is_empty()   # no clearance, no circles

func test_the_card_line_and_the_confirm_line() -> void:
	var pond := {"name": "Fern Pond", "at": POND}
	assert_str(P0HomePin.card_line(W08, pond)).is_equal("0.8 km to Fern Pond · west")
	assert_str(P0HomePin.card_line(N11, pond)).is_equal("11 km to Fern Pond · north")   # HOME-PIN-4
	assert_str(P0HomePin.confirm_line("San Francisco", W08, pond)).is_equal("San Francisco · 0.8 km to Fern Pond")
	assert_str(P0HomePin.km_text(8269.4)).is_equal("8,269 km")   # q(132)
	assert_str(P0HomePin.km_text(0.04)).is_equal("0.0 km")

func test_the_grey_key_and_its_toast() -> void:
	var far := P0HomePin.refusal_text({"code": "far", "km": 11.0}, {})
	assert_str(far.key).is_equal("Too far from the city")
	assert_str(far.toast).is_equal("Move the pin back inside the circle.")
	var names := {"pond_fern": {"name": "Fern Pond", "kind": "pond"}}
	var near := P0HomePin.refusal_text({"code": "near", "id": "pond_fern", "m": 120.0}, names)
	assert_str(near.key).is_equal("Too close to Fern Pond")
	assert_str(near.short).is_equal("Too close to a pond")
	assert_str(near.toast).is_equal("Leave some room around ponds and shops.")
	# a place the tables do not name: its general word from the id (a hut is not a shop)
	assert_str(P0HomePin.refusal_text({"code": "near", "id": "gn-1850147~hut0", "m": 1.0}, {}).key).is_equal("Too close to a hut")
	assert_str(P0HomePin.refusal_text({"code": "near", "id": "gn-1850147~pond2", "m": 1.0}, {}).key).is_equal("Too close to a pond")
	assert_str(P0HomePin.refusal_text({"code": "near", "id": "gn-1850147~tackle0", "m": 1.0}, {}).short).is_equal("Too close to a shop")
	assert_dict(P0HomePin.refusal_text({}, names)).is_empty()

func test_the_start_and_the_back_to_start_target() -> void:
	var a := P0HomePin.area(_pin())
	var farm := Vector2(37.75, -122.45)
	assert_object(P0HomePin.start(a, false, farm)).is_equal(a.start)   # a first pick, another city: spot 1
	assert_object(P0HomePin.start(a, true, farm)).is_equal(farm)       # the home city again (⑨): the farm
	assert_object(P0HomePin.start(a, true, null)).is_equal(a.start)
	# the key's target: spot 1 till the q row is approved (q(216) ③), then the farm for the home city
	assert_object(P0HomePin.back_target(a, true, farm)).is_equal(a.start)
	P0HomePin.repin_starts_on_farm = true
	assert_object(P0HomePin.back_target(a, true, farm)).is_equal(farm)
	assert_object(P0HomePin.back_target(a, false, farm)).is_equal(a.start)

func test_the_command_sends_the_pin_and_spot_minus_one() -> void:
	assert_dict(P0HomePin.command("choose_home", "gn-5391959", 37.76, -122.44909)).is_equal(
		{"type": "choose_home", "city": "gn-5391959", "at": [37.76, -122.44909], "spot": -1})
