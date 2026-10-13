extends GdUnitTestSuite
## The Homestead Stall's Notice Board (q(164), 不知火舞's spec on SGODOT-284): Homestead Lv5; `San Francisco · Today ·
## tap a place…`; Ponds — the beginner pond first, the rest nearest home first, each by its short name with today's best
## bite (the Bite Board's keeper line without its bait) and the player's trap `2/3`; Outposts — market, tea house, tackle
## shop, travel post, by short name, kind or the pin's reason, who is in (0 shows none); each row goes to its pin.

const P0NoticeBoard := preload("res://modules/p0/p0_notice_board.gd")
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
