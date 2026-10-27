extends GdUnitTestSuite
## The Homestead Stall's Notice Board (q(164), 不知火舞's spec on SGODOT-284): Homestead Lv5; `San Francisco · Today ·
## tap a place…`; Ponds — the beginner pond first, the rest nearest home first, each by its short name with today's best
## bite (the Bite Board's keeper line without its bait) and the player's trap `2/3`; Outposts — market, tea house, tackle
## shop, travel post, by short name, kind or the pin's reason, who is in (0 shows none); each row goes to its pin.

const P0NoticeBoard := preload("res://modules/p0/p0_notice_board.gd")
const FarmArt = preload("res://modules/farm/farm_art.gd")
const P0City := preload("res://modules/p0/p0_city.gd")
const P0Ponds := preload("res://modules/p0/p0_ponds.gd")

func _view() -> Dictionary:
	return {"homestead": {"unlocks": {"notice_board": true}}, "skills": {"fishing": {"level": 4}},
		"fishing": {"caught": {}, "places": {
			"pond_san_francisco_03": {"name": "Fern Pond", "weather": "rain", "fish": ["fish_crucian", "fish_carp", "fish_trout"]},
			"pond_san_francisco_06": {"name": "Blossom Pond", "weather": "rain", "fish": ["fish_eel"]}},
			"trap": {"traps": [{"place": "pond_san_francisco_03", "fish": 2, "keep": 3}]}}}

func test_the_board_reads_as_q164() -> void:
	var m: Dictionary = P0NoticeBoard.model(_view(), {"sh_tea_1": 3})
	assert_array([m.title, m.subtitle]).is_equal(["Notice Board", "San Francisco · Today · tap a place to see it on the map"])
	var fern: Dictionary = m.ponds[0]   # the beginner pond first
	assert_array([fern.id, fern.name, fern.icon, fern.line, fern.trap, fern.go]).is_equal(
		["pond_san_francisco_03", "Fern", "pond", "Rainbow Trout bite in the rain", "2/3", "pond:pond_san_francisco_03"])
	var blossom: Dictionary = m.ponds[1]
	assert_array([blossom.name, blossom.line, blossom.trap]).is_equal(["Blossom", "Quiet day", ""])   # River Eel needs Lv9
	assert_int(m.ponds.size()).is_equal(2)   # only ponds the view knows
	assert_array(m.outposts.map(func(o): return o.id)).is_equal(["sh_market_1", "sh_tea_1", "sh_tackle_1", "sh_post_1"])
	var tea: Dictionary = m.outposts[1]
	assert_array([tea.name, tea.icon, tea.line, tea.online, tea.go]).is_equal(["Oak", "pot", "Tea house · Hot tea", 3, "outpost:sh_tea_1"])
	assert_bool(tea.reason.is_empty()).is_true()
	var post: Dictionary = m.outposts[3]
	assert_array([post.name, post.icon, post.online]).is_equal(["Union Square", "travel", 0])   # 0: no badge (q(72))
	assert_bool(P0NoticeBoard.unlocked(_view())).is_true()
	assert_bool(P0NoticeBoard.unlocked({})).is_false()

## The card room posts nothing on the board (SGODOT-351), with a home set as without one (above): open or not.
func test_the_board_never_lists_the_card_room() -> void:
	var v := _view()
	v["home"] = {"city": "gn-5391959", "set": {"market": "sh_market_1", "tea": "sh_tea_1", "tackle": "sh_tackle_1", "post": "sh_post_1"}}
	for bj in [null, {"open": true}]:
		if bj != null: v["blackjack"] = bj
		var ids: Array = P0NoticeBoard.model(v).outposts.map(func(o): return o.id)
		assert_array(ids).contains(["sh_market_1", "sh_tea_1", "sh_tackle_1", "sh_post_1"])
		assert_array(ids).not_contains(["sf_card_room_1"])

## A marked pin's reason replaces the outpost's kind (q(103)'s pin-card line).
func test_a_marked_outpost_says_why() -> void:
	var v := _view()
	v["map_markers"] = [{"place": "sh_market_1", "kind": "request", "why": {}}]
	var market: Dictionary = P0NoticeBoard.model(v).outposts.filter(func(o): return o.id == "sh_market_1")[0]
	assert_str(str(market.reason.get("state", ""))).is_not_empty()
	assert_str(str(market.line)).is_equal(str(P0Logic.PinReason.reason(v, "sh_market_1").text))
	assert_str(str(market.line)).is_not_equal("Market square · Requests")

## The rest of the ponds nearest the homestead first (Fern is the beginner pond and leads whatever its distance).
func test_ponds_after_the_beginner_go_nearest_home_first() -> void:
	var v := _view()
	for id in ["pond_san_francisco_01", "pond_san_francisco_02", "pond_san_francisco_04", "pond_san_francisco_05"]:
		v.fishing.places[id] = {"name": id, "weather": "sun", "fish": []}
	var ids: Array = P0NoticeBoard.model(v).ponds.map(func(p): return p.id)
	assert_str(str(ids[0])).is_equal("pond_san_francisco_03")
	var home := P0City.farm_at()
	var km := func(id): return P0NoticeBoard._km(home, P0Ponds.location(id))   # the map's km, cos(lat) on longitude
	for i in range(1, ids.size() - 1): assert_bool(km.call(ids[i]) <= km.call(ids[i + 1])).is_true()
	# Blossom 1.5 km, Reed 4.3 km just before Pebble 4.4 km (without cos(lat) they swap), Willow, Clover
	assert_array(ids).is_equal(["pond_san_francisco_03", "pond_san_francisco_06", "pond_san_francisco_05",
		"pond_san_francisco_04", "pond_san_francisco_01", "pond_san_francisco_02"])

# ---------------------------------------------------------------- the drawer (不知火舞's spec on 284)
const Drawer := preload("res://scenes/p0/panels/p0_notice_board_drawer.gd")

func _drawer(v: Dictionary, online := {}) -> UiDrawer:
	var top := CanvasLayer.new()
	add_child(auto_free(top))
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	top.add_child(host)
	var d: UiDrawer = Drawer.new(v, online)
	d.animate = false
	host.add_child(d)
	return d

func _text(d: Node, path: String) -> String: return (d.find_child(path, true, false) as Label).text

## Head, the two sections, a 64 row per place: icon, short name, line, the trap and online badges, the `›`.
func test_the_drawer_reads_as_the_spec() -> void:
	var d := _drawer(_view(), {"sh_tea_1": 3})
	for i in 3: await get_tree().process_frame
	assert_str(_text(d, "Title")).is_equal("Notice Board")
	assert_str(_text(d, "Subtitle")).is_equal("San Francisco · Today · tap a place to see it on the map")
	assert_object(d.find_child("Section_Ponds", true, false)).is_not_null()
	assert_object(d.find_child("Section_Outposts", true, false)).is_not_null()
	var fern := d.find_child("Row_pond_san_francisco_03", true, false) as Button
	assert_float(fern.custom_minimum_size.y).is_equal(64.0)
	assert_str((fern.find_child("Name", true, false) as Label).text).is_equal("Fern")
	assert_str((fern.find_child("Line", true, false) as Label).text).is_equal("Rainbow Trout bite in the rain")
	assert_str(((fern.find_child("Trap", true, false) as Node).find_child("Count", true, false) as Label).text).is_equal("2/3")
	assert_object(fern.find_child("Online", true, false)).is_null()
	var tea := d.find_child("Row_sh_tea_1", true, false) as Button
	assert_str(((tea.find_child("Online", true, false) as Node).find_child("Count", true, false) as Label).text).is_equal("3")
	assert_object((d.find_child("Row_sh_post_1", true, false) as Node).find_child("Online", true, false)).is_null()   # 0: none
	var went := []
	d.connect(&"place_pressed", func(go: String): went.append(go))
	tea.pressed.emit()
	assert_array(went).is_equal(["outpost:sh_tea_1"])

## A marked pin's row carries its mark and reason (q(103)); the online counts come later and add their badge.
func test_a_marked_row_and_late_online_counts() -> void:
	var v := _view()
	v["map_markers"] = [{"place": "sh_market_1", "kind": "request", "why": {}}]
	var d := _drawer(v)
	for i in 2: await get_tree().process_frame
	var market := d.find_child("Row_sh_market_1", true, false) as Node
	assert_object(market.find_child("Reason", true, false)).is_not_null()
	assert_object(market.find_child("Line", true, false)).is_null()
	assert_object((d.find_child("Row_pond_san_francisco_03", true, false) as Node).find_child("Reason", true, false)).is_null()
	d.call("set_online", {"sh_market_1": 2})
	await get_tree().process_frame   # the old rows go at the end of the frame
	market = d.find_child("Row_sh_market_1", true, false) as Node
	assert_str(((market.find_child("Online", true, false) as Node).find_child("Count", true, false) as Label).text).is_equal("2")

## From the P0 UI: a row closes the board and asks the map for that pin; nothing else moves.
func test_a_row_closes_the_board_and_shows_the_pin_on_the_map() -> void:
	var ui := P0Ui.new()
	ui.quick_store = "user://test_p1_notice_board.json"
	add_child(auto_free(ui))
	await get_tree().process_frame
	ui.set_view(_view())
	var asked := [0]
	ui.notice_board_opened.connect(func(): asked[0] += 1)
	var shown := []
	ui.show_on_map.connect(func(t: String): shown.append(t))
	var d := ui.open_notice_board()
	assert_str(ui.modal_kind).is_equal("notice_board")
	assert_int(asked[0]).is_equal(1)
	ui.set_notice_online({"sh_tea_1": 4})
	await get_tree().process_frame
	assert_str(((d.find_child("Row_sh_tea_1", true, false) as Node).find_child("Count", true, false) as Label).text).is_equal("4")
	(d.find_child("Row_pond_san_francisco_06", true, false) as Button).pressed.emit()
	assert_bool(ui.notice_board() == null).is_true()
	assert_array(shown).is_equal(["pond:pond_san_francisco_06"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_p1_notice_board.json"))

# ---------------------------------------------------------------- the board by the stall (q(164) ①)
## Its cell is yard beside the stall: walkable, no bed, no path, nothing else's; a yard object so no decor goes there.
func test_its_cell_is_yard_beside_the_stall_off_the_field_the_paths_and_the_others() -> void:
	var c := P0Garden.NOTICE_BOARD_CELL
	var yard: Dictionary = P0Decor.yard()
	var inside := func(rects: Array) -> bool:
		return rects.any(func(r): return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).has_point(c))
	assert_bool(P0Garden.WALK_RECT.has_point(c)).is_true()
	assert_bool(inside.call(yard.get("field", []))).is_false()
	assert_bool(inside.call(yard.get("paths", []))).is_false()
	assert_bool(inside.call(yard.get("objects", []))).is_true()   # no decor on it (the server's rules too)
	for k in P0Garden.FOOTPRINTS: assert_bool((P0Garden.FOOTPRINTS[k] as Rect2i).has_point(c)).is_false()
	assert_bool(c != P0Garden.CHEF_SIGN_CELL and c != P0Garden.MAILBOX_CELL and c != P0Garden.SIGN_CELL).is_true()
	assert_int(absi(c.x - P0Garden.ANCHORS.storage.x) + absi(c.y - P0Garden.ANCHORS.storage.y)).is_equal(1)   # beside the stall
	assert_bool(P0Garden.blueprint().is_walkable(c)).is_true()

## 刘备's model (#395; 上官婉儿 284 c8ab943e): 1.595 m, inside ±0.35 (roof) of its cell's middle, the tap on its board's
## centre (board_center (0, 1.17)), the strip over it at the `mark` socket; its strip `Notice Board`.
func test_the_board_is_the_model_and_its_strip() -> void:
	var farm = load("res://scenes/p0/p0_farm.gd")
	var b: MeshInstance3D = auto_free(farm.notice_board_prop(Vector3.ZERO))
	assert_object(b.mesh).is_same(FarmArt.mesh_for("notice_board"))
	var box := b.mesh.get_aabb()
	assert_float(box.end.y).is_equal_approx(1.595, 0.01)
	assert_float(maxf(absf(box.position.x), absf(box.end.x))).is_less_equal(0.351)   # the roof; the feet ±0.30 under it
	assert_bool(box.has_point(farm.NOTICE_HIT)).is_true()
	assert_vector(farm.NOTICE_HIT).is_equal(Vector3(0, 1.17, 0))
	assert_vector(farm.NOTICE_MARK).is_equal(Vector3(0, 1.75, 0))
	assert_str(str(P0WorldPrompts.notice_board({}).text)).is_equal("Notice Board")

## A marked pond says why too, in place of its bite (NOTICE-BOARD 2608:133862: `Pond Catch · Pond Crucian 0/2`).
func test_a_marked_pond_says_why_instead_of_its_bite() -> void:
	var v := _view()
	v["map_markers"] = [{"place": "pond_san_francisco_03", "kind": "request", "why": {}}]
	var fern: Dictionary = P0NoticeBoard.model(v).ponds[0]
	assert_str(str(fern.line)).is_equal(str(P0Logic.PinReason.reason(v, "pond_san_francisco_03").text))
	assert_bool((fern.reason as Dictionary).is_empty()).is_false()
	var d := _drawer(v)
	for i in 2: await get_tree().process_frame
	var row := d.find_child("Row_pond_san_francisco_03", true, false) as Node
	assert_object(row.find_child("Reason", true, false)).is_not_null()
	assert_object(row.find_child("Line", true, false)).is_null()
	assert_object(row.find_child("Trap", true, false)).is_not_null()   # the trap stays beside it (the frame's `2/3`)

# ---------------------------------------------------------------- the player's own home (view.home, SGODOT-303)
func _homed(v: Dictionary, h: Dictionary) -> Dictionary:
	v["home"] = h
	return v

const SF_SET := {"market": "sh_market_1", "tea": "sh_tea_1", "tackle": "sh_tackle_1", "post": "sh_post_1", "pond": "pond_san_francisco_03"}

## The home's name, set and farm come from view.home: the same board for San Francisco; its own beginner pond leads.
func test_the_board_reads_the_players_home() -> void:
	var v := _homed(_view(), {"city": "gn-5391959", "name": "San Francisco", "set": SF_SET, "farm": {"lat": 37.7558, "lng": -122.4345}})
	var m: Dictionary = P0NoticeBoard.model(v)
	assert_array(m.ponds.map(func(p): return p.id)).is_equal(["pond_san_francisco_03", "pond_san_francisco_06"])
	assert_array(m.outposts.map(func(o): return o.id)).is_equal(["sh_market_1", "sh_tea_1", "sh_tackle_1", "sh_post_1"])
	var other := SF_SET.duplicate()
	other.pond = "pond_san_francisco_06"
	v = _homed(_view(), {"city": "gn-5391959", "name": "Frisco", "set": other, "farm": {"lat": 37.7558, "lng": -122.4345}})
	m = P0NoticeBoard.model(v)
	assert_str(str(m.ponds[0].id)).is_equal("pond_san_francisco_06")   # the home set's beginner pond first
	assert_str(str(m.subtitle)).is_equal("Frisco · Today · tap a place to see it on the map")   # the home's own name

## Another city's ponds are not this home's; without view.home (an older server) the written city's board.
func test_another_home_city_lists_none_of_san_franciscos_ponds_and_an_old_view_falls_back() -> void:
	var m: Dictionary = P0NoticeBoard.model(_homed(_view(), {"city": "gn-1850147", "name": "Tokyo", "set": {}, "farm": {"lat": 35.68, "lng": 139.76}}))
	assert_array(m.ponds).is_empty()
	assert_str(str(m.subtitle)).starts_with("Tokyo · Today")
	var old: Dictionary = P0NoticeBoard.home({})
	assert_array([old.city, old.name, old.set]).is_equal(["", "San Francisco", {}])
	assert_that(old.farm).is_equal(P0City.farm_at())
