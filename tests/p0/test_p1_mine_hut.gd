extends GdUnitTestSuite
## The Mine Hut on the client (q(204), SGODOT-308; q(193)): Ivo's home in a highland city, sent apart from the outposts
## as the city's detail.huts (an older client never sees it), pinned with its crossed picks and short name, carded as an
## outpost is, opened in the outpost room; Today's request to Ivo points at it by the resident's `place`.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")
const P0Outposts := preload("res://modules/p0/p0_outposts.gd")
const P0City := preload("res://modules/p0/p0_city.gd")
const OutpostScript := preload("res://scenes/p0/p0_outpost.gd")
const DENVER := "gn-5419384"
const HUT := "gn-5419384~hut0"
const ROOM := {"art": "mine_hut", "anchors": "res://assets/p0/outposts/mine_hut.anchors.json", "category": "Mine hut · Old miner"}

## Denver as the server sends it once the hut is in (后裔's world.ts; one outpost kept for the test).
const CITY := {
	"ponds": [], "outposts": ["gn-5419384~post0"], "residents": 6, "fish": [],
	"detail": {
		"ponds": [],
		"outposts": [
			{"id": "gn-5419384~post0", "role": "post", "name": "Denver Travel Post", "lat": 39.7392, "lng": -104.9903,
				"category": "Travel post · Coffee", "keeper": {"role": "Post Clerk", "name": "Tom", "look": "post_cool_0"},
				"residents": ["res_pip", "res_sam"], "art": "post_office", "anchors": "res://assets/p0/outposts/post.anchors.json", "capacity": 12}],
		"huts": [
			{"id": HUT, "role": "mine_hut", "name": "Golden Mine Hut", "lat": 39.7555, "lng": -105.2211, "category": "Mine hut · Old miner",
				"keeper": null, "residents": ["res_ivo"], "art": "mine_hut", "anchors": "res://assets/p0/outposts/mine_hut.anchors.json",
				"capacity": 12}]},
	"preview": {"cluster": DENVER, "name": "Denver"},
}

var _had_room := false

class Hut extends "res://scenes/p0/p0_outpost.gd":
	func setup(a: Dictionary) -> void:
		super.setup(a)
		use_runtime = false

func before_test() -> void:
	P0CityPlaces.clear()
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}
	var rooms: Dictionary = P0Logic.content().world.room
	_had_room = rooms.has("mine_hut")
	if not _had_room: rooms["mine_hut"] = ROOM   # 后裔's server PR brings it; the client reads the same world_gen.json

func after_test() -> void:
	if not _had_room: (P0Logic.content().world.room as Dictionary).erase("mine_hut")
	P0CityPlaces.clear()
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

## The hut is found by its id as an outpost is (its room opens in the outpost scene), but it is no outpost: the city's
## huts list holds it, the outposts list does not; no keeper, Ivo alone, its room kind's art and anchors.
func test_a_city_read_registers_its_mine_hut_apart_from_the_outposts() -> void:
	P0CityPlaces.accept(DENVER, CITY)
	var hut := P0Outposts.find(HUT)
	assert_that([hut.role, hut.name, hut.cluster, hut.art, hut.anchors, hut.category]).is_equal(["mine_hut", "Golden Mine Hut",
		DENVER, "mine_hut", "res://assets/p0/outposts/mine_hut.anchors.json", "Mine hut · Old miner"])
	assert_dict(hut.keeper).is_empty()
	assert_array(hut.residents).is_equal(["res_ivo"])
	assert_array(P0CityPlaces.huts(DENVER).map(func(h): return h.id)).is_equal([HUT])
	assert_array(P0CityPlaces.city(DENVER).outposts.map(func(o): return o.id)).is_equal(["gn-5419384~post0"])
	assert_array(P0CityPlaces.huts("gn-1850147")).is_empty()   # a city not read, or without one
	assert_str(P0City.chip_for(str(hut.name), HUT)).is_equal("Denver · Golden Mine Hut")   # the location chip in there

## Without world.room.mine_hut in content (before 后裔's PR) the hut is not taken: no room kind to open it in.
func test_no_room_kind_no_hut() -> void:
	(P0Logic.content().world.room as Dictionary).erase("mine_hut")
	P0CityPlaces.accept(DENVER, CITY)
	assert_dict(P0Outposts.find(HUT)).is_empty()
	assert_array(P0CityPlaces.huts(DENVER)).is_empty()
	if _had_room: (P0Logic.content().world.room as Dictionary)["mine_hut"] = ROOM

## The anchors file: Ivo and his talking spot, the way in and out; nothing else to tap (the shaft and the grill are set
## dressing; q(193)).
func test_the_mine_hut_anchors() -> void:
	var names: Array = P0RoomAnchors.read_json(str(ROOM.anchors)).get("anchors", []).map(func(a): return str(a.name))
	assert_array(names).contains_exactly_in_any_order(["npc_ivo", "stand_ivo", "spawn", "exit", "badge_exit"])
	var npcs: Dictionary = P0RoomAnchors.read_json(P0CityPlaces.NPCS_PATH).get("npcs", {})
	assert_str(str(npcs.res_ivo.anchor)).is_equal("npc_ivo")

## q(204) ⑦ ⑧: the pin — the crossed picks, `Golden`, ranked with the travel post and the cabin; the card — `Golden Mine
## Hut`, `Mine hut · Old miner`, Distance, `Go` (no Online now at 0); Show on map finds it by id.
func test_its_pin_and_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var v: Dictionary = rt.session.view.duplicate(true)
	v["travel"] = {"home": "gn-5391959", "here": "gn-5391959", "passes": {}, "visits": {DENVER: 1}, "stamps": [],
		"fallback": {"near3": [], "near10": []}, "explorer": 0}
	rt.session.view = v
	P0CityPlaces.accept(DENVER, CITY)
	assert_str(m.short_name("Golden Mine Hut")).is_equal("Golden")
	var entry := P0Outposts.place_entry(P0Outposts.find(HUT))
	var style: Dictionary = m._destination_style(entry)
	assert_object(style.icon).is_same(P0Logic.icon("mine_hut"))
	assert_str(str(style.label)).is_equal("Golden")
	assert_int(int(style.rank)).is_equal(int(m.PIN_RANK.post))
	assert_bool(bool(style.get("silhouette", false))).is_false()   # Denver visited
	var card: Dictionary = m.place_card(entry)
	assert_that([card.title, card.subtitle, card.primary]).is_equal(["Golden Mine Hut", "Mine hut · Old miner", "Go"])
	assert_array(card.facts.map(func(f): return f[0])).is_equal(["Distance"])
	assert_float(float(m.place_for("outpost:" + HUT).lat)).is_equal_approx(39.7555, 0.000001)
	# a home place by its id (a resident's `place`) and by its role, as before
	assert_str(str(m.place_for("outpost:sh_tea_1").id)).is_equal("sh_tea_1")
	assert_str(str(m.place_for("outpost:market").id)).is_equal("sh_market_1")
	m._show_city_places(P0CityPlaces.city(DENVER), DENVER)
	assert_array(m.city_map.extra_places.map(func(e): return str(e.id))).contains([HUT])

## q(204) ⑨: Today's row for Ivo's request goes to his hut — the view's `place` for the resident (后裔); an older server
## without it falls back to the role of the home outpost the resident lives at.
func test_today_delivers_to_the_residents_place() -> void:
	var v := {"residents": {"res_ivo": {"request_state": "accepted", "place": HUT,
		"request": {"id": "req_res_ivo_1", "kind": "material", "have": 3, "qty": 8}}}}
	var rows: Array = P0Logic.PinReason.taken(v)
	assert_str(str(rows[0].deliver_go)).is_equal("outpost:" + HUT)
	assert_str(str(rows[0].deliver)).is_equal("Deliver to Ivo")
	assert_str(P0Logic.PinReason.resident_place({}, "res_old_kai")).is_equal("tackle")   # an older server
	assert_str(P0Logic.PinReason.resident_place({"place": null}, "res_old_kai")).is_equal("tackle")
	assert_str(P0Logic.PinReason.resident_place({"place": "sh_tackle_1"}, "res_old_kai")).is_equal("sh_tackle_1")

## In the hut (or any outpost) a row handed in there reads Show and moves the camera; elsewhere Show on map.
func test_show_in_the_place_itself() -> void:
	var go := "outpost:" + HUT
	assert_str(P0Ui.show_label(go, "outpost", true, HUT)).is_equal("Show")
	assert_str(P0Ui.show_label(go, "outpost", true, "sh_tea_1")).is_equal("Show on map")
	assert_str(P0Ui.show_label(go, "home", true, "")).is_equal("Show on map")
	assert_str(P0Ui.show_label(go, "map", true, "")).is_equal("Show")

## The opening shot with no keeper (不知火舞 / 上官婉儿 on 308): the room's first resident takes the keeper's place — on
## a phone the player, Ivo's feet and the whole name tag over his head are on screen, the tag's anchor inside the band
## world marks show in (below the HUD, above the bottom controls).
func test_the_opening_shot_frames_ivo_with_his_name_tag() -> void:
	P0CityPlaces.accept(DENVER, CITY)
	var r := Hut.new()
	r.setup({"outpost_id": HUT})
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 800)
	add_child(auto_free(vp))
	vp.add_child(r)
	auto_free(r)
	await get_tree().process_frame
	r.p0_frame({}, 1.0 / 30.0)
	assert_bool(r.npcs.has("npc_keeper")).is_false()
	assert_array(r.npcs.keys()).is_equal(["npc_ivo"])
	var ivo := r.npcs.npc_ivo.root as Node3D
	var view := r._view()
	var band := Rect2(0.0, P0Room.HUD_BOTTOM, view.x, view.y - P0Room.HUD_BOTTOM - r._bottom_px().x)
	for p in [r.actor.position, r.actor.position + Vector3(0, 1.75, 0)]:
		assert_bool(band.has_point(r.cam.unproject_position(p))).override_failure_message("player %s" % r.cam.unproject_position(p)).is_true()
	var feet := r.cam.unproject_position(ivo.global_position)
	assert_bool(band.has_point(feet)).override_failure_message("ivo's feet %s" % feet).is_true()
	var head := r.cam.unproject_position(ivo.to_global(OutpostScript.NAME_OVER_HEAD))
	assert_bool(band.has_point(head)).override_failure_message("tag anchor %s" % head).is_true()
	# the tag's two top corners at its highlighted height, a long name's half width either side: whole on screen (the
	# opening on the player alone put Ivo at the screen's edge, his tag half off it)
	var forward := -r._cam_dir
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var m := r.cam.size / view.x
	var tag := ivo.to_global(OutpostScript.NAME_OVER_HEAD) + up * OutpostScript.COUNTER_TAG_PX * m
	for side in [-1.0, 1.0]:
		var at := r.cam.unproject_position(tag + right * side * OutpostScript.OPENING_TAG_HALF_PX * m)
		assert_bool(Rect2(Vector2.ZERO, view).has_point(at)).override_failure_message("tag corner %s" % at).is_true()
	var groups: Array = r.opening_subjects()
	assert_int(groups.size()).is_equal(1)   # Ivo; no counter in the hut
	assert_vector(groups[0][0]).is_equal(ivo.global_position)

## The server's presence carries the hut's id while someone is in it (#442): the hut's pin shows the count (q(137) ③)
## and its card `Online now`, as an outpost's; empty again, the count goes (0 tells nothing, q(72)).
func test_its_pin_and_card_say_who_is_in() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var v: Dictionary = rt.session.view.duplicate(true)
	v["travel"] = {"home": "gn-5391959", "here": "gn-5391959", "passes": {}, "visits": {DENVER: 1}, "stamps": [],
		"fallback": {"near3": [], "near10": []}, "explorer": 0}
	rt.session.view = v
	P0CityPlaces.accept(DENVER, CITY)
	m._show_city_places(P0CityPlaces.city(DENVER), DENVER)
	var body := JSON.stringify({"ok": true, "outposts": {"sh_tea_1": {"online": 0, "rooms": 0}, HUT: {"online": 2, "rooms": 1}}})
	m._on_presence(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body.to_utf8_buffer())
	var pin: Array = m.city_map.extra_places.filter(func(e): return str(e.id) == HUT)
	assert_int(int(pin[0].online)).is_equal(2)
	var entry := P0Outposts.place_entry(P0Outposts.find(HUT))
	assert_array(m.place_card(entry).facts).contains([["Online now", "2"]])
	body = JSON.stringify({"ok": true, "outposts": {"sh_tea_1": {"online": 0, "rooms": 0}}})   # empty: the room is let go
	m._on_presence(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body.to_utf8_buffer())
	pin = m.city_map.extra_places.filter(func(e): return str(e.id) == HUT)
	assert_int(int(pin[0].online)).is_equal(0)
	assert_array(m.place_card(entry).facts.map(func(f): return f[0])).is_equal(["Distance"])
