extends GdUnitTestSuite
## P1 Compost Bin on the client (q(118) ③, q(121); 不知火舞 on 241: COMPOST-BIN 2231:122380, -LIMIT 2231:122659,
## FARM-5-FAC 2109:133018): it stands on a yard cell by the decor yard's rules, decor keeps off it, its drawer turns
## crops into Compost, its strip reads today's count.

const H := 3600000.0

func _view(extra := {}) -> Dictionary:
	var v := {"facilities": [{"id": 3.0, "kind": "compost_bin", "plot": -1.0, "covers": [], "cell": [5.0, 14.0]}],
		"decor": {"placed": [{"uid": 1.0, "id": "deco_planter", "x": 6.0, "y": 14.0, "rot": 0.0}], "cap": 20},
		"compost": {"cap": 5.0, "used": 2.0, "left": 3.0, "resets_in": 9 * H + 12 * 60000.0},
		"bag": {"capacity": 25, "slots": [{"id": "crop_radish", "qty": 24}, {"id": "seed_radish", "qty": 10},
			{"id": "crop_apple", "qty": 2}]},
		"names": {"crop_radish": "Radish", "crop_apple": "Apple"}}
	v.merge(extra, true)
	return v

## The yard's rules and words (the server's yardBlock): free, the field, a path, a yard object, a piece, itself.
func test_the_bin_keeps_to_the_yard() -> void:
	var v := _view()
	assert_str(P0FarmFacilities.yard_reason(v, Vector2i(4, 15))).is_empty()
	assert_str(P0FarmFacilities.yard_reason(v, Vector2i(5, 5))).is_equal("Outside your yard")
	assert_str(P0FarmFacilities.yard_reason(v, Vector2i(9, 0))).is_equal("Keep the path clear")
	assert_str(P0FarmFacilities.yard_reason(v, Vector2i(8, 15))).is_equal("Space taken")
	assert_str(P0FarmFacilities.yard_reason(v, Vector2i(6, 14))).is_equal("Space taken")   # the planter
	assert_str(P0FarmFacilities.yard_reason(v, Vector2i(5, 14))).is_equal("Space taken")   # another bin's cell
	assert_str(P0FarmFacilities.yard_reason(v, Vector2i(5, 14), 3)).is_empty()            # its own, while it moves
	assert_str(P0FarmFacilities.caption(v, -1, "compost_bin")).is_equal("Compost Bin · 1×1")
	# and a decor piece keeps off the bin, as the server's spotBlock
	assert_str(P0Decor.reason(v, "deco_planter", Vector2i(5, 14))).is_equal("Space taken")

## The preview starts on the free cell nearest where it is asked (beside the workbench), never a taken one.
func test_the_nearest_free_yard_cell() -> void:
	var v := _view()
	var c := P0FarmFacilities.nearest_yard_cell(v, Vector2i(5, 14))
	assert_bool(c != Vector2i(5, 14) and c != P0Decor.NONE).is_true()
	assert_str(P0FarmFacilities.yard_reason(v, c)).is_empty()
	assert_float(Vector2(c - Vector2i(5, 14)).length()).is_equal(1.0)   # one cell over
	assert_that(P0FarmFacilities.nearest_yard_cell(v, Vector2i(5, 14), 3)).is_equal(Vector2i(5, 14))   # moving: where it is
	# a new one beside the workbench's three cells (anchor 17, 16), not behind it where the bench would hide it
	assert_that(P0FarmFacilities.nearest_yard_cell({"facilities": [], "decor": {"placed": []}}, Vector2i(17, 16), -1, 1)).is_equal(Vector2i(15, 16))

## COMPOST-BIN: `Compost today 2/5` / `resets in 9h 12m`; at the cap red `Limit reached` (q(121)).
func test_the_days_line() -> void:
	var q := P0CompostDrawer.quota(_view())
	assert_that([q.text, q.full]).is_equal(["Compost today 2/5\nresets in 9h 12m", false])
	q = P0CompostDrawer.quota(_view({"compost": {"cap": 5, "used": 5, "left": 0, "resets_in": 9 * H + 12 * 60000.0}}))
	assert_that([q.text, q.full]).is_equal(["Limit reached\nresets in 9h 12m", true])
	assert_str(str(P0CompostDrawer.quota({}).text)).is_empty()

## The card: `Compost 1` / `Compost All · 3` (what the day still takes of 24); at the cap one grey
## `Limit reached · 9h 12m` (q(121)).
func test_the_card_buttons() -> void:
	var s := P0CompostDrawer.spec(_view(), "crop_radish")
	assert_that([s.title, s.facts, s.quantity]).is_equal(["Radish", ["Crop"], 24])
	assert_that((s.buttons as Array).map(func(b): return [b.label, b.kind, b.payload])).is_equal([
		["Compost 1", &"secondary", {qty = 1}], ["Compost All · 3", &"primary", {qty = 3}]])
	assert_str(str(P0CompostDrawer.spec(_view(), "crop_apple").buttons[1].label)).is_equal("Compost All · 2")   # all of 2
	var full := P0CompostDrawer.spec(_view({"compost": {"cap": 5, "used": 5, "left": 0, "resets_in": 9 * H + 12 * 60000.0}}), "crop_radish")
	assert_that((full.buttons as Array).map(func(b): return [b.label, b.kind])).is_equal([["Limit reached · 9h 12m", &"unavailable"]])

## The drawer: only the bag's crops in its grid; a crop's Compost All says the crop and how many.
func test_the_drawer_shows_crops_and_composts_them() -> void:
	var d := P0CompostDrawer.new(_view())
	d.animate = false
	var host := Control.new()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	host.add_child(d)
	await await_idle_frame()
	assert_array(d.grid.shown_items().map(func(it): return str(it.id))).contains_exactly_in_any_order(["crop_radish", "crop_apple"])
	var asked := []
	d.compost_requested.connect(func(id, qty): asked.append([id, qty]))
	d.select("crop_radish")
	await await_idle_frame()
	d.sheet.action_requested.emit(&"compost", "crop_radish", {qty = 3})
	assert_array(asked).is_equal([["crop_radish", 3]])

## Its strip: `Compost Bin · 2/5` (today's, of the day's), the strip greenhouses and the Fish Trap use.
func test_the_strip_reads_todays_count() -> void:
	var p := P0FarmFacilities.bin_prompt(_view(), {"id": 3.0, "kind": "compost_bin"})
	assert_that([p.text, p.fact]).is_equal(["Compost Bin", "2/5"])

## FARM-5-FAC: the blueprint card's line, the level first while it is locked; at the cap `Compost Bins 1/1`.
func test_the_blueprint_card() -> void:
	var r := {"id": "craft_compost_bin", "tab": "facilities", "item": "facility_compost_bin", "name": "Compost Bin", "to": "field",
		"cost": [{"id": "wood", "name": "Timber", "need": 6, "have": 12}, {"id": "stone", "name": "Stone", "need": 4, "have": 14}],
		"block": {"code": "skill_level_required", "detail": {"skill": "farming", "level": 7}}}
	var card: Dictionary = P0MaterialLogic.workbench_model({"workbench": {"recipes": [r]}}, "facilities")[0]
	assert_that([card.effect, card.button.label]).is_equal(["Farming Lv7 · 5 crops → 5 Compost a day", "Farming Lv7 needed"])
	r.block = {"code": "facility_cap", "detail": {"cap": 1, "used": 1, "farming_next": null}}
	card = P0MaterialLogic.workbench_model({"workbench": {"recipes": [r]}}, "facilities")[0]
	assert_that([card.effect, card.button.label]).is_equal(["5 crops → 5 Compost a day", "Compost Bins 1/1"])
