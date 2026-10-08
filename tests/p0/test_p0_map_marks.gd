extends GdUnitTestSuite
## Map marks on pins (SGODOT-227 follow-up; data from SGODOT-232 U6, plan §9.5.2 / q(48)): the server's
## view.map_markers become CityMapView marks, and at most five of those on screen show, in priority order.

const P0Map := preload("res://scenes/p0/p0_map.gd")

func test_server_markers_become_pin_marks_in_their_order() -> void:
	var view := {"map_markers": [
		{"place": "sh_market_1", "kind": "deliver", "why": {"request": "mk_1"}},
		{"place": "pond_shanghai_05", "kind": "request", "why": {"request": "req_tutorial", "tracked": true}},
		{"place": "home", "kind": "deliver", "why": {"request": "st_1"}},
		{"place": "sh_tackle_1", "kind": "new", "why": {"item": "rod_reed"}},
		{"place": "sh_tea_1", "kind": "event"},
	]}
	assert_array(P0Map.marks_from(view)).is_equal([
		{"id": "sh_market_1", "state": "deliverable"},
		{"id": "pond_shanghai_05", "state": "request"},
		{"id": "sh_tackle_1", "state": "new"},
	])
	assert_array(P0Map.marks_from({})).is_empty()

func test_at_most_five_marks_show_and_only_on_pins_on_screen() -> void:
	var list := []
	for i in 8: list.append({"id": "p%d" % i, "state": "request"})
	list.insert(0, {"id": "off_screen", "state": "deliverable"})
	var shown := ["p0", "p1", "p2", "p3", "p4", "p5", "p6", "p7"]
	var on := CityMapView.pick_marks(list, shown)
	assert_array(on.keys()).is_equal(["p0", "p1", "p2", "p3", "p4"])   # the off-screen one takes no slot
	assert_dict(CityMapView.pick_marks([{"id": "a", "state": "new"}, {"id": "a", "state": "request"}], ["a"])).is_equal({"a": "new"})

# ---------------------------------------------------------------- pond card (TUT-3-04, q(48))
const PondCard := preload("res://modules/p0/p0_pond_card.gd")

func _view(fishing_level := 1, caught := []) -> Dictionary:
	return {"skills": {"fishing": {"level": fishing_level}},
		"fishing": {"dex": caught.map(func(id): return {"id": id, "caught": 1})}}

func test_the_beginner_pond_card_and_tag() -> void:
	var reed := PondCard.info(_view(), "pond_shanghai_05", 0.84)
	assert_str(str(reed.title)).is_equal("Reed Pond")
	assert_str(str(reed.subtitle)).is_equal("Beginner")
	assert_str(str(reed.line)).is_equal("A nearby pond for your first catch.")
	assert_array(reed.facts).is_equal([["Distance", "0.8 km"], ["Recommended", "Lv1–3"]])
	assert_str(str(reed.tag)).is_equal("Beginner pond · 0.8 km")

func test_other_ponds_name_their_template_and_have_no_beginner_line() -> void:
	var willow := PondCard.info(_view(), "pond_shanghai_01", 1.6)
	assert_str(str(willow.subtitle)).is_equal("Pond")
	assert_str(str(willow.line)).is_empty()
	assert_str(str(willow.tag)).is_equal("Pond · 1.6 km")
	var pebble := PondCard.info(_view(), "pond_shanghai_04", 2.3)
	assert_str(str(pebble.subtitle)).is_equal("River")
	assert_array(pebble.facts[1]).is_equal(["Recommended", "Lv4–5"])
	assert_dict(PondCard.info(_view(), "pond_sf_01", 1.0)).is_empty()   # not a P0 pond

func test_recommended_turns_outleveled_when_no_fish_pays_xp() -> void:
	assert_array(PondCard.info(_view(8), "pond_shanghai_05", 1.0).facts[1]).is_equal(["Recommended", "Lv1–3"])   # Koi Lv4: a 4-level gap still pays 25 %
	assert_array(PondCard.info(_view(99), "pond_shanghai_05", 1.0).facts[1]).is_equal(["Recommended", "Outleveled"])

func test_the_fish_list_is_easiest_first_with_caught_ones_marked() -> void:
	var rows := PondCard.fish_rows(_view(1, ["fish_crucian"]), "pond_shanghai_05")
	var ids := rows.map(func(r): return str(r.id))
	assert_array(ids).contains(["fish_crucian", "fish_koi"])
	assert_str(str(ids[-1])).is_equal("fish_koi")   # Golden Koi, the hardest, last: its silhouette tells Old Kai's quest
	assert_bool(rows.filter(func(r): return r.id == "fish_crucian")[0].caught).is_true()
	assert_bool(rows.filter(func(r): return r.id == "fish_koi")[0].caught).is_false()
	assert_float(PondCard.km_between(Vector2(31.2, 121.4), Vector2(31.2, 121.4))).is_equal(0.0)
	assert_str(PondCard.distance_text(0.0)).is_equal("0.1 km")

func test_the_homestead_mark_hangs_on_the_farm_pin() -> void:
	assert_str(P0Map.home_mark({"map_markers": [{"place": "sh_market_1", "kind": "request"}, {"place": "home", "kind": "deliver"}]})).is_equal("deliverable")
	assert_str(P0Map.home_mark({"map_markers": [{"place": "sh_market_1", "kind": "request"}]})).is_empty()
	var fm: FarmMarkers = auto_free(FarmMarkers.new())
	var target := Button.new()
	fm.add_child(target)
	fm._avatar_targets["self"] = target
	fm.set_mark("self", Control.new())
	assert_object(target.get_node_or_null("MapMark")).is_not_null()
	fm.set_mark("self", null)
	await get_tree().process_frame
	assert_object(target.get_node_or_null("MapMark")).is_null()
