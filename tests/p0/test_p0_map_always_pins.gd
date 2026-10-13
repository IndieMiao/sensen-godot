extends GdUnitTestSuite
## q(146) (李元芳's 0.2.1 smoke, 293 1952561a; 不知火舞 on 293 378fd255): the always-in pins (selected, where the player
## is, marked ✓ / ! / ◆) near each other. Their discs all stay, stacked by priority — selected > where the player is >
## marked, the marked by kind (beginner pond > ponds > market > tea house > post and cabin > tackle shop), then id — the
## highest on top; a name that runs into a higher-priority pin's name or disc hides whole and comes back once they part.
## The San Francisco cluster out at the city level: Mission (! market) says its name, Oak (✓ tea) and Union Square
## (✓ post) hide theirs where they run into it, all four discs show and Mission's is on top.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Outposts := preload("res://modules/p0/p0_outposts.gd")
const IDS := ["sh_market_1", "sh_tea_1", "sh_post_1", "sh_tackle_1"]

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var map := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(map)
	return map

func _look(m: Node, at: Vector2, zoom: float) -> void:
	(m.city_map as CityMapView)._shown_last.clear()
	(m.city_map as CityMapView)._hidden_until.clear()
	(m.city_map as CityMapView)._dest_names_last.clear()
	m.center_lat = at.x
	m.center_lng = at.y
	m.zoom = zoom
	m.bearing = 0.0
	m._update_cameras()
	m._sync_farm_markers()
	m.p0_frame(m.rt.session.view, 0.016)
	(m.city_map as CityMapView)._update_markers()

## id -> {disc: Rect2 (screen), name: Rect2 or null, index: node index} for the four outposts on screen.
func _pins(city: CityMapView) -> Dictionary:
	var out := {}
	for mk in city.displayed:
		if not mk.has("dest") or not IDS.has(str(mk.entry.id)): continue
		var pin: UiMapDestination = mk.dest
		out[str(mk.entry.id)] = {disc = mk.rect, named = pin.name_shown, index = (mk.node as Node).get_index()}
	return out

func _marked(rt: P0Runtime) -> Dictionary:
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["map_markers"] = [{"place": "sh_market_1", "kind": "request"}, {"place": "sh_tea_1", "kind": "deliver"},
		{"place": "sh_post_1", "kind": "deliver"}, {"place": "sh_tackle_1", "kind": "deliver"}]
	rt.session.view = v
	return saved

func test_crowded_always_in_pins_keep_their_discs_stacked_by_priority_and_the_lower_names_give_way() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _marked(rt)
	assert_dict(m.city_pin_markers()).has_size(4)
	var c := Vector2.ZERO
	for id in IDS:
		var o := P0Outposts.find(id)
		c += Vector2(float(o.lat), float(o.lng)) / IDS.size()
	var city: CityMapView = m.city_map
	# out until the four crowd: every disc stays, and some name meets a higher one
	var crowded := false
	for z in [13.5, 13.0, 12.5, 12.0, 11.5, 11.2]:
		_look(m, c, z)
		var pins := _pins(city)
		assert_int(pins.size()).override_failure_message("z %.1f: all four discs stay" % z).is_equal(4)
		if not pins.sh_tea_1.named or not pins.sh_post_1.named: crowded = true
		# the market (!, the highest of the four by kind) always says its name and is drawn over the other three
		assert_bool(pins.sh_market_1.named).override_failure_message("z %.1f: Mission keeps its name" % z).is_true()
		for id in ["sh_tea_1", "sh_post_1", "sh_tackle_1"]:
			assert_int(pins.sh_market_1.index).is_greater(pins[id].index)
		assert_int(pins.sh_tea_1.index).is_greater(pins.sh_post_1.index)   # tea house over post
		assert_int(pins.sh_post_1.index).is_greater(pins.sh_tackle_1.index)   # post over tackle shop
		# a name shown is never on a higher pin's disc or name (no half names: it shows whole or not at all)
		var order := ["sh_market_1", "sh_tea_1", "sh_post_1", "sh_tackle_1"]
		for i in order.size():
			var mk = city.markers[order[i]]
			if not pins[order[i]].named: continue
			var box: Control = (mk.dest as UiMapDestination)._label_box
			var name_rect := Rect2(box.global_position - city.global_position, box.size * box.get_global_transform().get_scale())
			for j in i:
				assert_bool((pins[order[j]].disc as Rect2).intersects(name_rect)).override_failure_message(
					"z %.1f: %s's name on %s's disc" % [z, order[i], order[j]]).is_false()
	assert_bool(crowded).override_failure_message("never crowded: zoom further out").is_true()
	# in close they part and every name comes back
	_look(m, c, 16.0)
	var close := _pins(city)
	for id in ["sh_market_1", "sh_tea_1", "sh_post_1"]:
		if close.has(id): assert_bool(close[id].named).override_failure_message("%s back in close" % id).is_true()
	rt.session.view = saved

## The order itself: where the player is > marked by kind > the rest by kind; the mark does not order them.
func test_the_always_in_ranks() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _marked(rt)
	var city: CityMapView = m.city_map
	var rank := func(id): return city._dest_rank(P0Outposts.place_entry(P0Outposts.find(id)))
	assert_int(rank.call("sh_market_1")).is_less(rank.call("sh_tea_1"))   # ! market over ✓ tea: by kind, not mark
	assert_int(rank.call("sh_tea_1")).is_less(rank.call("sh_post_1"))
	assert_int(rank.call("sh_post_1")).is_less(rank.call("sh_tackle_1"))
	rt.session.view = saved
	var unmarked: int = rank.call("sh_market_1")
	assert_int(rank.call("sh_tackle_1")).is_greater(unmarked)   # the rest after
	assert_int(unmarked).is_greater(200)
