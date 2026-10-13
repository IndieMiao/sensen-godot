extends GdUnitTestSuite
## Specialty barter at a Market Square keeper (§8.4.5; 不知火舞's spec on 284): a group at the end of the counter's Buy
## page — `Barter · 2 for 1 · 4/6 today`, a row per mineral `For 2 Sweet Potato` / `3 of 6 left this level` / `2 items`
## / Barter, three grey keys, and `+1 Stone · −2 Sweet Potato` after it.

func _view(left := 2, items := [{"id": "crop_sweet_potato", "name": "Sweet Potato", "have": 5}, {"id": "fish_tilapia", "name": "Tilapia", "have": 2}]) -> Dictionary:
	return {"names": {"stone": "Stone", "clay": "Clay", "crop_sweet_potato": "Sweet Potato"},
		"shops": {"market": {"barter": {"give": 2, "daily": 6, "left": left, "resets_in": 33_120_000.0, "items": items,
			"minerals": [{"id": "stone", "name": "Stone", "room": 3, "share": 6}, {"id": "clay", "name": "Clay", "room": 0, "share": 4}]}}}}

func test_the_group_reads_as_the_spec() -> void:
	var v := _view()
	assert_str(P0Barter.header(v)).is_equal("Barter · 2 for 1 · 4/6 today")
	var rows := P0Barter.rows(v)
	assert_array(rows.map(func(r): return r.title)).is_equal(["Stone", "Clay"])
	var stone: Dictionary = rows[0]
	assert_array([stone.effect, stone.gate, stone.price, stone.button, stone.reason]).is_equal(
		["For 2 Sweet Potato", "3 of 6 left this level", "2 items", "Barter", ""])   # the most the bag holds
	assert_dict(stone.cmd).is_equal({"type": "barter", "item": "crop_sweet_potato", "mineral": "stone", "shop": "market"})
	assert_str(str(rows[1].reason)).is_equal("Level quota used")
	assert_dict(rows[1].cmd).is_empty()
	assert_str(P0Barter.header({})).is_empty()   # an older server, or not the market: no group
	assert_array(P0Barter.rows({})).is_empty()

func test_the_grey_keys() -> void:
	var none := P0Barter.rows(_view(2, [{"id": "crop_sweet_potato", "name": "Sweet Potato", "have": 1}]))
	assert_str(str(none[0].effect)).is_equal("For 2 regional crops or fish")
	assert_str(str(none[0].reason)).is_equal("Need 2 regional items")
	assert_str(P0Barter.header(_view(0))).is_equal("Limit reached · resets in 9h 12m")   # q(166) ⑤: the heading too, red
	assert_bool(P0Barter.limit_reached(_view(0))).is_true()
	assert_bool(P0Barter.limit_reached(_view(2))).is_false()
	var used := P0Barter.rows(_view(0))
	assert_str(str(used[0].reason)).is_equal("Limit reached · 9h 12m")   # q(121): the day's six, and when they come back
	assert_str(str(used[1].reason)).is_equal("Limit reached · 9h 12m")   # the day's limit says first

func test_the_toast_after_a_barter() -> void:
	var v := _view()
	assert_str(P0Barter.toast(v, [{"kind": "item", "id": "crop_sweet_potato", "delta": -2}, {"kind": "item", "id": "stone", "delta": 1}])) \
		.is_equal("+1 Stone · −2 Sweet Potato")
	assert_str(P0Barter.toast(v, [{"kind": "item", "id": "crop_sweet_potato", "delta": 3}])).is_empty()
