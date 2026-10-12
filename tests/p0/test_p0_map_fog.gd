extends GdUnitTestSuite
## SGODOT-275 fog (plan v2 §11.7, three states, the user's call 10-10): the world under a grey veil but for the explored
## cities (home, visited; Second Home when the server sets one), city bubbles saying Unexplored / Visited and the home
## city's players online with a house (不知火舞 on #227: no Second Home line this version), and a pond or outpost of a
## city without a pass opening its travel card instead of going in. Colour only: nothing is hidden; the veil stays at
## every zoom, so a neighbour city's pins never turn full colour up close.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Map := preload("res://scenes/p0/p0_map.gd")
const P0Travel := preload("res://modules/p0/p0_travel.gd")
const SF := "gn-5391959"
const TOKYO := "gn-1850147"
const LA := "gn-5368361"

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
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

func _travel(rt: P0Runtime, travel: Dictionary) -> Dictionary:
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = travel
	rt.session.view = v
	return saved

func _look(m: Node, lat: float, lng: float, z: float) -> void:
	m.center_lat = lat
	m.center_lng = lng
	m._set_zoom(z)
	m.pitch = 0.0
	m._zoom_elastic = 0.0

func test_three_states_from_the_travel_block() -> void:
	var v := {"travel": {home = SF, here = SF, visits = {TOKYO: {n = 1}}, second_homes = [LA]}}
	assert_str(P0Travel.fog(v, SF)).is_equal("explored")
	assert_str(P0Travel.fog(v, TOKYO)).is_equal("explored")
	assert_str(P0Travel.fog(v, LA)).is_equal("second_home")
	assert_str(P0Travel.fog(v, "gn-1816670")).is_equal("unexplored")   # Beijing
	assert_array(P0Travel.explored(v)).contains_exactly_in_any_order([SF, TOKYO, LA])

func test_the_veil_holes_the_explored_cities_only_at_every_zoom() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _travel(rt, {home = SF, here = SF, visits = {}, passes = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0})
	_look(m, 36.0, -120.3, 5.0)   # California: San Francisco and Los Angeles on screen
	var holes: Array = m.fog_holes()
	var vp := Rect2(Vector2.ZERO, Vector2(360, 800))
	for p in [m.geo_to_screen(37.7749, -122.4194), m.geo_to_screen(34.0522, -118.2437)]:
		assert_bool(vp.has_point((p as Vector2) - m.city_map.global_position)).is_true()
	assert_int(holes.size()).is_equal(1)   # home only: Los Angeles is not explored
	var sf = m.geo_to_screen(37.7749, -122.4194)
	assert_float((holes[0].at as Vector2).distance_to((sf as Vector2) - m.city_map.global_position)).is_less(40.0)
	assert_float(float(holes[0].r)).is_greater(2.0)
	rt.session.view.travel.visits = {LA: {n = 1}}
	assert_int(m.fog_holes().size()).is_equal(2)
	var fog: ColorRect = m.city_map.fog
	m.city_map._update_fog()
	assert_bool(fog.visible).is_true()
	assert_int(fog.get_index()).is_equal(0)   # under every pin, bubble and name
	assert_int(fog.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# edge to edge: the view sits inside the safe-area margins, the veil covers the whole screen and its holes stay
	# on the cities (a hole's centre in the shader is the city's screen point)
	assert_vector(fog.get_global_rect().position).is_equal(Vector2.ZERO)
	assert_vector(fog.get_global_rect().size).is_equal(Vector2(360, 800))
	var packed: Array = (fog.material as ShaderMaterial).get_shader_parameter("holes")
	assert_float(Vector2(packed[0].x, packed[0].y).distance_to(sf as Vector2)).is_less(40.0)
	_look(m, 37.7558, -122.4345, 15.0)
	m.city_map._update_fog()
	assert_bool(fog.visible).is_true()   # street zoom too (不知火舞 on #227): the home city's hole covers the screen
	var street: Array = m.fog_holes()
	assert_int(street.size()).is_equal(1)
	# the screen (its far corner included) lies inside the hole: the home city reads in full colour up close
	var corner: Vector2 = Vector2(360, 800) - m.city_map.global_position
	assert_float((street[0].at as Vector2).distance_to(Vector2.ZERO)).is_less(float(street[0].r))
	assert_float((street[0].at as Vector2).distance_to(corner)).is_less(float(street[0].r))
	_look(m, 37.80, -122.27, 15.0)   # still inside San Francisco's cluster (Oakland)
	assert_int(m.fog_holes().size()).is_greater(0)
	rt.session.view = saved

func test_the_hole_edge_is_a_fixed_24_px() -> void:
	var sh: Shader = load("res://modules/map/shaders/map_fog.gdshader")
	assert_str(sh.code).contains("uniform float feather = 24.0")
	assert_str(sh.code).contains("min(feather, max(1.0, h.z))")

func test_city_bubbles_say_their_state() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _travel(rt, {home = SF, here = SF, visits = {TOKYO: {n = 1}}, second_homes = [LA], passes = {}, stamps = [],
		fallback = {near3 = [], near10 = []}, explorer = 0})
	m._online = {"sh_tea_1": 3, "sh_market_1": 2}
	var state: Callable = m.city_map.bubble_state
	assert_dict(state.call("san_francisco")).is_equal({text = "5 online", icon = "house"})
	assert_dict(state.call(TOKYO)).is_equal({text = "Visited"})
	assert_dict(state.call("los_angeles")).is_equal({text = "Visited"})   # a Second Home reads Visited this version
	assert_dict(state.call("gn-1816670")).is_equal({text = "Unexplored"})
	m._online = {}
	assert_dict(state.call("san_francisco")).is_equal({text = "", icon = "house"})   # nobody online: the house alone (q(72))
	# 不知火舞 on #238: the bubble keeps its size as the count comes and goes (the glyph alone keeps a text line's height)
	_look(m, 37.55, -122.0, 7.0)
	m.city_map._update_bubbles()
	var node: Control = m.city_map.bubbles["san_francisco"].node
	var empty_size := node.size
	m._online = {"sh_tea_1": 1}
	m.city_map._update_bubbles()
	assert_float(node.size.y).is_equal_approx(empty_size.y, 0.5)
	# … and is no taller than the text line itself: no bubble grows for it
	var count: Label = m.city_map.bubbles["san_francisco"].count
	assert_float((count.get_parent() as Control).custom_minimum_size.y).is_less_equal(count.get_minimum_size().y + 0.5)
	rt.session.view = saved

## 李元芳 / 司空震 (SGODOT-275): a bubble the last list had and this one does not is hidden with its dot, never left
## frozen where it was drawn (Northern California's bubbles over Los Angeles after flying there).
func test_bubbles_the_list_no_longer_has_hide() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_look(m, 38.6, -121.5, 6.0)   # Northern California at the region zoom: Sacramento, Redding, Chico …
	m.city_map._update_bubbles()
	var north: Array = m.city_regions().map(func(r): return str(r.id))
	assert_bool(north.has("gn-5389489")).is_true()   # Sacramento
	assert_bool(m.city_map.bubbles["gn-5389489"].node.visible).is_true()
	_look(m, 33.9, -118.2, 6.0)   # Los Angeles: a new list
	m.city_map._update_bubbles()
	var south: Array = m.city_regions().map(func(r): return str(r.id))
	for id in m.city_map.bubbles:
		if not south.has(id):
			assert_bool(m.city_map.bubbles[id].node.visible).override_failure_message("%s left visible" % id).is_false()
			assert_bool(m.city_map.bubbles[id].dot.visible).is_false()
	assert_bool(south.has("los_angeles")).is_true()   # Los Angeles itself (its curated region)
	assert_bool(m.city_map.bubbles["los_angeles"].node.visible).is_true()

## 不知火舞 on #216: a visited city has a bubble at any zoom, whatever its size (the population cutoff is for the rest).
func test_a_visited_small_city_has_a_bubble_at_the_country_zoom() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var small := ""
	for c in load("res://modules/p0/p0_clusters.gd").in_box(36.0, -122.5, 39.5, -119.0, 0, 400):
		if int(c.population) < 50000: small = str(c.id)
	assert_str(small).is_not_empty()
	var saved := _travel(rt, {home = SF, here = SF, visits = {small: {n = 1}}, passes = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0})
	_look(m, 37.5, -120.5, 4.0)   # cutoff 400,000 at this zoom
	assert_int(P0Map.city_min_population(4.0)).is_greater(50000)
	assert_array(m.city_regions().map(func(r): return str(r.id))).contains([small])
	rt.session.view = saved

func test_a_pin_of_a_city_without_a_pass_opens_its_city_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	var saved := _travel(rt, {home = SF, here = SF, visits = {}, passes = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0})
	assert_str(P0Map.cluster_of_entry({"id": TOKYO + "~pond0"}, SF)).is_equal(TOKYO)
	assert_str(P0Map.cluster_of_entry({"id": "pond_san_francisco_01"}, SF)).is_equal(SF)
	assert_bool(m._travel_first({"kind": "pond", "id": TOKYO + "~pond0"})).is_true()
	assert_str(rt.ui.modal_kind).is_equal("city_card")   # unexplored: its silhouette card (MAP-3-FREE), then Travel details
	rt.ui.close_modal()
	assert_bool(m._travel_first({"kind": "pond", "id": "pond_san_francisco_01"})).is_false()   # the home city's: as ever
	assert_bool(m._travel_first({"kind": "place", "id": "home"})).is_false()
	rt.session.view.travel.passes = {TOKYO: {kind = "day", from = 1.0, until = 2_000_000_000.0}}
	assert_bool(m._travel_first({"kind": "pond", "id": TOKYO + "~pond0"})).is_false()   # a pass: go in
	rt.session.view = saved

## 不知火舞 on 279 (6c0377f7): the veil is the design's COLOR_SECONDARY at 40 % (the light blue-grey washed out on the
## phone); and a city bubble under the HUD rows, the right-hand keys or the quick bar is not drawn — its dot stays.
func test_the_veil_is_the_secondary_ink_at_40_percent() -> void:
	var FogLayer := load("res://modules/map/map_fog_layer.gd")
	assert_that(FogLayer.FOG).is_equal(Color(UiTokens.COLOR_SECONDARY, 0.40))

func test_a_bubble_under_the_hud_is_not_drawn_but_its_dot_is() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_look(m, 37.2, -121.2, 6.5)
	var rects: Array = m.bubble_clear_rects()
	assert_int(rects.size()).is_greater_equal(2)
	m.city_map.bubble_clear_rects = func(): return [Rect2(0, 0, 360, 800)]   # everything is in the way
	m.city_map._update_bubbles()
	var shown := 0
	var dots := 0
	for id in m.city_map.bubbles:
		if m.city_map.bubbles[id].node.visible: shown += 1
		if m.city_map.bubbles[id].dot.visible: dots += 1
	assert_int(shown).is_equal(0)
	assert_int(dots).is_greater(0)
	m.city_map.bubble_clear_rects = m.bubble_clear_rects
	m.city_map._update_bubbles()
	for id in m.city_map.bubbles:
		var b: Dictionary = m.city_map.bubbles[id]
		if not b.node.visible: continue
		var at := Rect2((b.node as Control).position + m.city_map.global_position, (b.node as Control).size)
		for r in rects: assert_bool((r as Rect2).intersects(at)).override_failure_message("%s under the chrome" % id).is_false()

## 李元芳 0.2.1 smoke (286 bfae88c7): at the country view a visited city right by home (Chico) has its bubble where the
## player's avatar stands; the bubble draws over the avatar and takes the tap — the avatar no longer does.
## 李元芳 0.2.1 smoke (293 378fd255): at the country view, away in LA, home's bubble (San Francisco) sits over the
## bottom of Chico's. A tap on the part of Chico's bubble that shows took home's 6 px margin and went home; the bubble
## drawn under the finger takes it now, and the margin only answers taps off every bubble.
func test_a_tap_on_a_bubble_that_shows_is_not_taken_by_a_neighbours_margin() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	var chico := ""
	for c in load("res://modules/p0/p0_clusters.gd").in_box(39.5, -122.1, 39.9, -121.6, 0, 50):
		if str(c.get("name", "")) == "Chico": chico = str(c.id)
	assert_str(chico).is_not_empty()
	var saved := _travel(rt, {home = SF, here = LA, visits = {chico: {n = 1}, LA: {n = 1}}, passes = {}, stamps = [],
		fallback = {near3 = [], near10 = []}, explorer = 0})
	_look(m, 38.8, -122.1, 3.0)
	m._sync_farm_markers()
	m.city_map._update_bubbles()
	var home_id := ""
	for id in m.city_map.bubbles:
		if m.city_map.bubbles[id].node.visible and m.city_map.bubbles[id].name.text == "San Francisco": home_id = str(id)
	assert_str(home_id).is_not_empty()
	assert_bool(m.city_map.bubbles[chico].node.visible).is_true()
	var home: Rect2 = m.city_map.bubbles[home_id].node.get_global_rect()
	var mine: Rect2 = m.city_map.bubbles[chico].node.get_global_rect()
	# just above home's bubble, on Chico's: drawn there is Chico's alone, within home's old 6 px margin
	var on_chico := Vector2(mine.get_center().x, home.position.y - 3.0)
	assert_bool(mine.has_point(on_chico) and not home.has_point(on_chico)).is_true()
	# just left of home's bubble, off every bubble: the margin still takes it
	var off_all := Vector2(home.position.x - 3.0, home.get_center().y)
	assert_bool(mine.has_point(off_all) or m.farm_markers._avatar_targets["self"].get_global_rect().has_point(off_all)).is_false()
	for c in m.city_map.city_requested.get_connections(): m.city_map.city_requested.disconnect(c.callable)
	var asked: Array = []
	m.city_map.city_requested.connect(func(id): asked.append(str(id)))
	for at in [on_chico, off_all]:
		for pressed in [true, false]:
			var tap := InputEventScreenTouch.new()
			tap.position = at
			tap.pressed = pressed
			m._unhandled_input(tap)
		m._last_tap_ms = 0
	assert_array(asked).is_equal([chico, home_id])
	rt.ui.close_modal()
	rt.session.view = saved

func test_a_city_bubble_over_the_avatar_takes_the_tap() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	rt.ui.close_modal()
	var chico := ""
	for c in load("res://modules/p0/p0_clusters.gd").in_box(39.5, -122.1, 39.9, -121.6, 0, 50):
		if str(c.get("name", "")) == "Chico": chico = str(c.id)
	assert_str(chico).is_not_empty()
	var saved := _travel(rt, {home = SF, here = SF, visits = {chico: {n = 1}}, passes = {}, stamps = [],
		fallback = {near3 = [], near10 = []}, explorer = 0})
	_look(m, 38.9, -121.9, 4.6)
	m._sync_farm_markers()
	m.city_map._update_bubbles()
	assert_bool(m.city_map.bubbles.has(chico) and m.city_map.bubbles[chico].node.visible).is_true()
	var node: Control = m.city_map.bubbles[chico].node
	var at: Vector2 = node.get_global_rect().get_center()
	# the avatar's tap target over the bubble, as it stands by home at this zoom
	var fm: FarmMarkers = m.farm_markers
	var target: Control = fm._avatar_targets["self"]
	target.global_position = at - target.size * 0.5
	assert_bool(target.get_global_rect().has_point(at)).is_true()
	var asked: Array = []
	m.city_map.city_requested.connect(func(id): asked.append(str(id)))
	for pressed in [true, false]:
		var tap := InputEventScreenTouch.new()
		tap.position = at
		tap.pressed = pressed
		m._unhandled_input(tap)
	assert_array(asked).is_equal([chico])
	assert_str(fm.selected_id).is_empty()   # the avatar was not selected
	rt.ui.close_modal()
	rt.session.view = saved
