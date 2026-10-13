extends GdUnitTestSuite
## Prompt buttons kept apart in every room (不知火舞 on 282): ① of two folded buttons nearer than 44, the later in
## spread_rank moves out along the line to 44 (door, stoves, Spice Rack, Warming Cabinet, the rest), 22 off the screen's
## sides; ② buttons under the open strip line up 6 above it, 44 apart, or beside it where that row does not fit; a button
## in that row stays until 4 px clear; nothing is hidden, and each change of place eases in 0.12 s.

const SCREEN := Rect2(0, 0, 360, 800)
const TOP := 100.0

func _spread(spots: Dictionary, buttons: Array, strip := Rect2(), in_row := {}) -> Dictionary:
	return P0Room.spread(spots, buttons, strip, SCREEN, TOP, in_row)

func test_the_later_one_moves_out_along_the_line_to_44() -> void:
	# the Basic Room as it was (282 c62a6ed9 shots): rack and cabinet buttons 35 px apart
	var rack := Vector2(35.4, 323.9)
	var cabinet := Vector2(47.35, 356.7)
	var out: Dictionary = _spread({"use_spice_rack": rack, "use_warming_cabinet": cabinet}, ["use_spice_rack", "use_warming_cabinet"]).spots
	assert_vector(out.use_spice_rack).is_equal(rack)   # the rack stays; the cabinet moves
	assert_float((out.use_warming_cabinet as Vector2).distance_to(rack)).is_equal_approx(44.0, 0.01)
	assert_float(((out.use_warming_cabinet as Vector2) - rack).normalized().dot((cabinet - rack).normalized())).is_greater(0.999)   # along the line
	# apart already: nothing moves
	var far: Dictionary = _spread({"use_spice_rack": rack, "use_warming_cabinet": rack + Vector2(0, 50)}, ["use_spice_rack", "use_warming_cabinet"]).spots
	assert_vector(far.use_warming_cabinet).is_equal(rack + Vector2(0, 50))

func test_the_door_and_the_stoves_never_move() -> void:
	var spots := {"exit": Vector2(200, 400), "use_stove_1": Vector2(230, 400), "use_spice_rack": Vector2(250, 390), "use_bench": Vector2(205, 410)}
	var out: Dictionary = _spread(spots, spots.keys()).spots
	assert_vector(out.exit).is_equal(spots.exit)
	assert_vector(out.use_stove_1).is_equal(spots.use_stove_1)   # 30 from the door: the farmhouse's row decides stoves
	for n in ["use_spice_rack", "use_bench"]:
		for m in ["exit", "use_stove_1", "use_spice_rack", "use_bench"]:
			if m != n: assert_float((out[n] as Vector2).distance_to(out[m])).override_failure_message("%s ~ %s" % [n, m]).is_greater_equal(43.99)

func test_kept_off_the_screens_sides() -> void:
	var out: Dictionary = _spread({"use_spice_rack": Vector2(330, 400), "use_warming_cabinet": Vector2(335, 410)},
		["use_spice_rack", "use_warming_cabinet"]).spots
	assert_float((out.use_warming_cabinet as Vector2).x).is_less_equal(SCREEN.end.x - 22.0 + 0.01)

## ② the Standard Room by its cabinet (282 shots): the rack's button under the cabinet's open strip goes up into a row 6
## above it; two under it stand 44 apart, centred over it; under the HUD there is no room, so beside it.
func test_buttons_under_the_open_strip_line_up_above_it() -> void:
	var strip := Rect2(140, 345, 179, 32)
	var spots := {"use_spice_rack": Vector2(332.5, 338.8), "use_stove_1": Vector2(300, 360)}
	var laid := _spread(spots, spots.keys(), strip)
	var y := strip.position.y - 6.0 - 14.0
	assert_float((laid.spots.use_stove_1 as Vector2).y).is_equal(y)
	assert_float((laid.spots.use_spice_rack as Vector2).y).is_equal(y)
	assert_float((laid.spots.use_spice_rack as Vector2).x - (laid.spots.use_stove_1 as Vector2).x).is_equal_approx(44.0, 0.01)   # stoves first
	assert_float(((laid.spots.use_stove_1 as Vector2).x + (laid.spots.use_spice_rack as Vector2).x) * 0.5).is_equal_approx(strip.get_center().x, 0.01)
	assert_dict(laid.row).is_equal({"use_spice_rack": true, "use_stove_1": true})
	var low: Dictionary = P0Room.spread(spots, spots.keys(), strip, SCREEN, 340.0).spots   # the HUD reaches 340: beside it
	for n in spots: assert_bool(strip.grow(14.0).has_point(low[n])).override_failure_message(n).is_false()
	assert_float((low.use_stove_1 as Vector2).y).is_equal(strip.get_center().y)

## Beside the strip with little room on its left (刘邦 on #379): as many as fit there, the rest on its right, none stacked.
func test_beside_the_strip_they_split_left_and_right() -> void:
	var strip := Rect2(60, 300, 200, 32)   # its left has room for one (x 40), not two
	var spots := {"use_spice_rack": Vector2(100, 310), "use_warming_cabinet": Vector2(150, 310), "use_bench": Vector2(200, 310)}
	var out: Dictionary = P0Room.spread(spots, spots.keys(), strip, SCREEN, 320.0).spots   # the HUD to 320: no row above
	assert_vector(out.use_spice_rack).is_equal(Vector2(40, 316))
	assert_vector(out.use_warming_cabinet).is_equal(Vector2(280, 316))
	assert_vector(out.use_bench).is_equal(Vector2(324, 316))
	for n in spots: assert_bool(strip.grow(14.0).has_point(out[n])).override_failure_message(n).is_false()

func test_a_button_in_the_row_stays_until_4_px_clear() -> void:
	var strip := Rect2(100, 300, 150, 32)
	var edge := Vector2(175, strip.end.y + 14.0 + 2.0)   # 2 px clear of the strip's reach
	var fresh := _spread({"use_bench": edge}, ["use_bench"], strip)
	assert_vector(fresh.spots.use_bench).is_equal(edge)   # never in the row: stays put
	var held := _spread({"use_bench": edge}, ["use_bench"], strip, {"use_bench": true})
	assert_float((held.spots.use_bench as Vector2).y).is_equal(strip.position.y - 20.0)   # was in the row: stays in it
	var clear := _spread({"use_bench": edge + Vector2(0, 3)}, ["use_bench"], strip, {"use_bench": true})
	assert_vector(clear.spots.use_bench).is_equal(edge + Vector2(0, 3))   # 5 px clear: out

## The farmhouse at Lv3, its rack and cabinet buttons as drawn: 44 apart once eased (0.12 s), the rack where it was.
func test_the_farmhouse_draws_its_rack_and_cabinet_apart() -> void:
	var r: P0Room = load("res://scenes/p0/rooms/p0_farmhouse.gd").new()
	r.use_runtime = false
	r.level = 3
	add_child(auto_free(r))
	var marks := {"use_spice_rack": {kind = "facility"}, "use_warming_cabinet": {kind = "facility"}}
	var raw := {"use_spice_rack": Vector2(35.4, 323.9), "use_warming_cabinet": Vector2(47.35, 356.7)}
	r.set("_dt", 0.06)
	var half: Dictionary = r.call("_spread_markers", marks, raw)
	var mid := (half.use_warming_cabinet as Vector2).distance_to(half.use_spice_rack)
	assert_bool(mid > raw.use_warming_cabinet.distance_to(raw.use_spice_rack) and mid < 44.0).override_failure_message("half way: %.1f" % mid).is_true()
	var done: Dictionary = r.call("_spread_markers", marks, raw)
	assert_float((done.use_warming_cabinet as Vector2).distance_to(done.use_spice_rack)).is_equal_approx(44.0, 0.01)
	assert_vector(done.use_spice_rack).is_equal(raw.use_spice_rack)
