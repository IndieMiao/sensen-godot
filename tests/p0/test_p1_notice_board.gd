extends GdUnitTestSuite
## The Homestead Stall's Notice Board (q(164), SGODOT-284): Homestead Lv5; `San Francisco · Today`; Ponds — each home
## pond with today's best bite (the Bite Board's keeper line without its bait) and `Your trap · 2/3`; Outposts — each
## home outpost by its short name, its kind or its pin's reason, `3 online` (none at 0); Show on map to each pin.

const P0NoticeBoard := preload("res://modules/p0/p0_notice_board.gd")

func _view() -> Dictionary:
	return {"homestead": {"unlocks": {"notice_board": true}}, "skills": {"fishing": {"level": 4}},
		"fishing": {"caught": {}, "places": {
			"pond_san_francisco_03": {"name": "Fern Pond", "weather": "rain", "fish": ["fish_crucian", "fish_carp", "fish_trout"]},
			"pond_san_francisco_06": {"name": "Blossom Pond", "weather": "rain", "fish": ["fish_eel"]}},
			"trap": {"traps": [{"place": "pond_san_francisco_03", "fish": 2, "keep": 3}]}}}

func test_the_board_reads_as_q164() -> void:
	var m: Dictionary = P0NoticeBoard.model(_view(), {"sh_tea_1": 3})
	assert_array([m.title, m.subtitle]).is_equal(["Notice Board", "San Francisco · Today"])
	var fern: Dictionary = m.ponds.filter(func(p): return p.id == "pond_san_francisco_03")[0]
	assert_array([fern.name, fern.line, fern.trap, fern.go]).is_equal(
		["Fern Pond", "Rainbow Trout bite in the rain", "Your trap · 2/3", "pond:pond_san_francisco_03"])
	var blossom: Dictionary = m.ponds.filter(func(p): return p.id == "pond_san_francisco_06")[0]
	assert_array([blossom.line, blossom.trap]).is_equal(["Quiet day", ""])   # River Eel needs Lv9: nothing to land
	assert_int(m.ponds.size()).is_equal(2)   # only ponds the view knows
	var tea: Dictionary = m.outposts.filter(func(o): return o.id == "sh_tea_1")[0]
	assert_array([tea.name, tea.line, tea.online, tea.go]).is_equal(["Oak", "Tea house · Hot tea", "3 online", "outpost:sh_tea_1"])
	var post: Dictionary = m.outposts.filter(func(o): return o.id == "sh_post_1")[0]
	assert_array([post.name, post.online]).is_equal(["Union Square", ""])   # 0 online: nothing (q(72))
	assert_bool(P0NoticeBoard.unlocked(_view())).is_true()
	assert_bool(P0NoticeBoard.unlocked({})).is_false()

## A marked pin's reason replaces the outpost's kind (q(103)'s pin-card line).
func test_a_marked_outpost_says_why() -> void:
	var v := _view()
	v["map_markers"] = [{"place": "sh_market_1", "kind": "request", "why": {}}]
	var market: Dictionary = P0NoticeBoard.model(v).outposts.filter(func(o): return o.id == "sh_market_1")[0]
	assert_bool(market.marked).is_true()
	assert_str(str(market.line)).is_equal(str(P0Logic.PinReason.reason(v, "sh_market_1").text))
	assert_str(str(market.line)).is_not_equal("Market square · Requests")
