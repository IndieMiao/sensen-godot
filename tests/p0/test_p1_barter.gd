extends GdUnitTestSuite
## Specialty barter at a Market Square keeper (§8.4.5; 不知火舞's spec on 284): a group at the end of the counter's Buy
## page — `Barter · 2 for 1 · 4/6 today`, a row per mineral `For 2 Sweet Potato` / `3 of 6 left this level` / `2 items`
## / Barter, three grey keys, and `+1 Stone · −2 Sweet Potato` after it.

const P0Barter := preload("res://modules/p0/p0_barter.gd")

func _view(left := 2, items := [{"id": "crop_sweet_potato", "name": "Sweet Potato", "have": 5}, {"id": "fish_tilapia", "name": "Tilapia", "have": 2}]) -> Dictionary:
	return {"names": {"stone": "Stone", "clay": "Clay", "crop_sweet_potato": "Sweet Potato"},
		"shops": {"market": {"barter": {"give": 2, "daily": 6, "left": left, "resets_in": 33_120_000.0, "items": items,
			"minerals": [{"id": "stone", "name": "Stone", "room": 3, "share": 6}, {"id": "clay", "name": "Clay", "room": 0, "share": 4}]}}}}

func test_the_group_reads_as_the_spec() -> void:
	var v := _view()
	assert_that(P0Barter.header(v)).is_equal({title = "Barter · 2 for 1", quota = "4/6 today", red = false})
	var rows := P0Barter.rows(v)
	assert_array(rows.map(func(r): return r.title)).is_equal(["Stone", "Clay"])
	var stone: Dictionary = rows[0]
	assert_array([stone.effect, stone.gate, stone.price, stone.button, stone.reason]).is_equal(
		["For 2 Sweet Potato", "3 of 6 left this level", "2 items", "Barter", ""])   # the most the bag holds
	assert_dict(stone.cmd).is_equal({"type": "barter", "item": "crop_sweet_potato", "mineral": "stone", "shop": "market"})
	assert_str(str(rows[1].reason)).is_equal("Level quota used")
	assert_dict(rows[1].cmd).is_empty()
	assert_bool(P0Barter.header({}).is_empty()).is_true()   # an older server, or not the market: no group
	assert_array(P0Barter.rows({})).is_empty()

func test_the_grey_keys() -> void:
	var none := P0Barter.rows(_view(2, [{"id": "crop_sweet_potato", "name": "Sweet Potato", "have": 1}]))
	assert_str(str(none[0].effect)).is_equal("For 2 regional items")
	assert_str(str(none[0].reason)).is_equal("Need 2 regional items")
	assert_that(P0Barter.header(_view(0))).is_equal({title = "Barter · 2 for 1", quota = "Limit reached · resets in 9h 12m", red = true})   # BARTER-2: the quota part, red
	assert_bool(P0Barter.limit_reached(_view(0))).is_true()
	assert_bool(P0Barter.limit_reached(_view(2))).is_false()
	var used := P0Barter.rows(_view(0))
	assert_str(str(used[0].reason)).is_equal("Limit reached · 9h 12m")   # q(121): the day's six, and when they come back
	assert_str(str(used[1].reason)).is_equal("Limit reached · 9h 12m")   # the day's limit says first

func test_the_toast_after_a_barter() -> void:
	var v := _view()
	var reply := [{"kind": "item", "id": "crop_sweet_potato", "delta": -2}, {"kind": "item", "id": "stone", "delta": 1},
		{"kind": "barter", "item": "crop_sweet_potato", "give": 2, "mineral": "stone", "left": 5}]
	assert_str(P0Barter.toast(v, reply)).is_equal("+1 Stone · −2 Sweet Potato")
	assert_str(P0Barter.toast(v, reply.slice(0, 2))).is_empty()   # a bag upgrade also takes and gives: only a barter says so

# ---------------------------------------------------------------- the drawer (BARTER-1 / BARTER-2, q(166))
func _market(barter: Dictionary) -> Dictionary:
	var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))
	v.shops.market["barter"] = barter
	v.names.merge({"stone": "Stone", "clay": "Clay", "crop_sweet_potato": "Sweet Potato"}, true)
	return v

func _drawer(v: Dictionary, section := "buy") -> P0CounterDrawer:
	var top := CanvasLayer.new()
	add_child(auto_free(top))
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	top.add_child(host)
	var d := P0CounterDrawer.new(v, "market", {"keeper": "Mei", "place": "Mission Market Square"}, section)
	d.animate = false
	host.add_child(d)
	return d

## The group ends the Buy shelf: its heading in two parts, a row per mineral, the key or its grey reason.
func test_the_buy_page_ends_with_the_barter_group() -> void:
	var d := _drawer(_market(_view().shops.market.barter))
	for i in 3: await get_tree().process_frame
	assert_object(d.barter).is_not_null()
	assert_object(d.shelf.get_child(d.shelf.get_child_count() - 1)).is_same(d.barter)   # after the goods
	assert_str((d.barter.find_child("Title", true, false) as Label).text).is_equal("Barter · 2 for 1")
	var quota := d.barter.find_child("Quota", true, false) as Label
	assert_str(quota.text).is_equal(" · 4/6 today")
	assert_that(quota.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)
	var stone := d.barter.find_child("Barter_stone", true, false) as UiShopRow
	assert_array([stone._title.text, stone._effect.text, stone._gate.text, stone._price.text, stone.buy.text]).is_equal(
		["Stone", "For 2 Sweet Potato", "3 of 6 left this level", "2 items", "Barter"])
	assert_object(stone.stepper).is_null()   # one barter a press
	var clay := d.barter.find_child("Barter_clay", true, false) as UiShopRow
	assert_str(clay.buy.reason).is_equal("Level quota used")
	var sent := []
	d.action_requested.connect(func(a: StringName, id: String, p: Dictionary): sent.append([a, id, p]))
	stone.buy.activated.emit()
	assert_array(sent).is_equal([[&"barter", "stone", {item = "crop_sweet_potato"}]])
	clay.buy.activated.emit()   # a grey key sends nothing
	assert_int(sent.size()).is_equal(1)

## The day's six used: the quota part turns red with the wait, every key greys with it (BARTER-2).
func test_the_days_limit_turns_the_heading_red() -> void:
	var d := _drawer(_market(_view(0).shops.market.barter))
	for i in 3: await get_tree().process_frame
	var quota := d.barter.find_child("Quota", true, false) as Label
	assert_str(quota.text).is_equal(" · Limit reached · resets in 9h 12m")
	assert_that(quota.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_DANGER)
	assert_str((d.barter.find_child("Barter_stone", true, false) as UiShopRow).buy.reason).is_equal("Limit reached · 9h 12m")

## Not on the Market Board page, not without a barter block (an older server), never at another counter.
func test_no_group_elsewhere() -> void:
	var board := _drawer(_market(_view().shops.market.barter), "board")
	var none: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))
	var old := _drawer(none)
	for i in 3: await get_tree().process_frame
	assert_object(board.barter).is_null()
	assert_object(old.barter).is_null()

## The reply says both sides in one Success toast (q(166) ⑤), in place of a `+1 Stone` float.
func test_a_barters_reply_toasts_instead_of_floating() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var v := _view()
	v.merge({"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []}, "skills": {"farming": {"level": 6}}})
	rt.session.view = v
	rt._on_state(v, [{"kind": "item", "id": "crop_sweet_potato", "delta": -2}, {"kind": "item", "id": "stone", "delta": 1},
		{"kind": "barter", "item": "crop_sweet_potato", "give": 2, "mineral": "stone", "left": 3}])
	for i in 2: await get_tree().process_frame
	assert_str(rt.ui._toasts.current_text()).is_equal("+1 Stone · −2 Sweet Potato")
	assert_int(rt.ui._toasts.current_severity()).is_equal(ToastLayer.Severity.SUCCESS)
	var floats := rt.ui.root.get_children().filter(func(c): return c is UiFloatText and not c.is_queued_for_deletion())
	assert_array(floats.map(func(f): return f.text)).is_empty()
