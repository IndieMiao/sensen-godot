extends GdUnitTestSuite
## 355 C2-c (亚瑟's split, SGODOT-355), U2 (the ponds alone): the guide's and Today's Show targets for the ponds' points
## and the wild mines — S6a's row to view.guide.target's point, a Homestead material to its pond's point or mine, the
## `gather:` / `mine:` Show labels — and the maintenance guard on an old save.

const HOME := "gn-test"
const PLACES := preload("res://modules/p0/p0_city_places.gd")
const MAP := preload("res://scenes/p0/p0_map.gd")

func after_test() -> void:
	PLACES.clear()
	for id in ["p_far", "p_near", "p_clay", "p_away"]: SystemPonds._remote.erase(id)

## U2: the home city's ponds as view.gather.ponds sends them — a far pond with a Grove first in the server's order, a
## near one with a Grove and a Reed Bank, one with a Clay Pit — each at a lat / lng the pond table knows.
func _ponds() -> Dictionary:
	for p in [["p_far", 10.05], ["p_near", 10.01], ["p_clay", 10.02], ["p_away", 40.0]]:
		SystemPonds._remote[p[0]] = {"id": p[0], "lat": p[1], "lng": 20.0 if p[0] != "p_away" else 50.0, "enabled": true}
	return {
		"p_far": {"name": "Far Pond", "cluster": HOME, "points": [{"id": "p_far#0", "kind": "wood", "item": "wood", "ready_in": 0}]},
		"p_near": {"name": "Fern Pond", "cluster": HOME, "points": [{"id": "p_near#0", "kind": "wood", "item": "wood", "ready_in": 0},
			{"id": "p_near#1", "kind": "reed", "item": "fiber", "ready_in": 0}]},
		"p_clay": {"name": "Clay Pond", "cluster": HOME, "points": [{"id": "p_clay#0", "kind": "clay", "item": "clay", "ready_in": 0}]}}

func _view(extra := {}) -> Dictionary:
	var v := {"save_version": 7, "travel": {"home": HOME}, "home": {"city": HOME, "farm": {"lat": 10.0, "lng": 20.0}},
		"bag": {"free": 5, "slots": []}, "gather": {"city_ready": {}, "ponds": _ponds()},
		"wild": {"near3_sites": [{"id": "wq1", "type": "quarry", "main": null, "name": "Pebble Quarry"},
			{"id": "wv1", "type": "vein", "main": "iron_ore", "name": "Iron Vein"},
			{"id": "wv2", "type": "vein", "main": "quartz", "name": "Quartz Vein"}]}}
	v.merge(extra, true)
	return v

## U2 (target.pond): S6a's row goes to the pond's point — Show on the map (its pond's pin), Show on map elsewhere, Show in
## that very pond (the camera to the point), Show on map from another pond.
func test_s6a_row_goes_to_the_targets_spot_and_reads_show_by_where_the_player_is() -> void:
	var g := {"step": "t_gather", "row": {"line": "Gather Timber · Fern Pond", "icon": "wood", "go": "map"}}
	var without := P0Guide.guide_rows({"guide": g})
	assert_str(str(without[0].go)).is_equal("map")   # no target (the key absent): the server's go as it was
	g.target = {"kind": "gather", "spot": "p_near#0", "item": "wood", "pond": "p_near"}
	var row: Dictionary = P0Guide.guide_rows({"guide": g})[0]
	assert_str(str(row.go)).is_equal("gather:p_near#0")
	assert_str(P0Ui.show_label(str(row.go), "map", true)).is_equal("Show")
	assert_str(P0Ui.show_label(str(row.go), "farm", true)).is_equal("Show on map")
	assert_str(P0Ui.show_label(str(row.go), "pond", true, "p_near")).is_equal("Show")
	assert_str(P0Ui.show_label(str(row.go), "pond", true, "p_far")).is_equal("Show on map")
	assert_str(P0Ui.map_target(str(row.go))).is_equal("pond:p_near")   # the pond's pin (P0Map.show_place)
	assert_str(MAP.guide_spot({"guide": g})).is_equal("p_near")   # the map's ! on the pond's pin
	assert_str(P0Ui.show_label("mine:wv1", "home", true)).is_equal("Show on map")
	assert_str(P0Ui.show_label("mine:wv1", "map", true)).is_equal("Show")
	assert_str(P0Ui.show_label("mine:wv1", "mine", true, "wv1")).is_equal("")   # down that mine: no button
	assert_str(P0Ui.show_label("mine:wv2", "mine", true, "wv1")).is_equal("Show on map")

func test_a_gathered_material_goes_to_the_point_the_server_would_pick() -> void:
	assert_dict(P0Logic._home_material_go(_view({"gather": {"ponds": {}}}), "wood")).is_equal({"go": "", "now": false})   # no pond with it
	assert_dict(P0Logic._home_material_go(_view(), "wood")).is_equal({"go": "gather:p_near#0", "now": true})   # the nearest pond
	var near_cooling := _view({"gather": {"city_ready": {"p_near#0": 60000}, "ponds": _ponds()}})
	assert_dict(P0Logic._home_material_go(near_cooling, "wood")).is_equal({"go": "gather:p_far#0", "now": true})   # the ready one
	var all_cooling := _view({"gather": {"city_ready": {"p_near#0": 60000, "p_far#0": 1000}, "ponds": _ponds()}})
	assert_dict(P0Logic._home_material_go(all_cooling, "wood")).is_equal({"go": "gather:p_near#0", "now": false})   # the nearest
	var full := _view({"bag": {"free": 0, "slots": [{"id": "fiber", "qty": 99}]}})
	assert_dict(P0Logic._home_material_go(full, "fiber")).is_equal({"go": "gather:p_near#1", "now": true})   # eb1d7c20: the bag is not asked
	assert_dict(P0Logic._home_material_go(full, "wild_herb")).is_equal({"go": "", "now": false})   # no pond of this city has it
	var in_far := _view({"gather": {"pond": {"pond": "p_far", "points": []}, "ponds": _ponds()}})
	assert_dict(P0Logic._home_material_go(in_far, "wood")).is_equal({"go": "gather:p_far#0", "now": true})   # nearest to the pond the player is in

## eb1d7c20: in another town its ponds come first; one without the material points home; mines are always home's.
func test_in_another_town_its_ponds_come_first() -> void:
	var ponds := _ponds()
	ponds["p_away"] = {"name": "Away Pond", "cluster": "gn-away", "points": [{"id": "p_away#0", "kind": "wood", "item": "wood", "ready_in": 0}]}
	var away := _view({"travel": {"home": HOME, "here": "gn-away"}, "gather": {"ponds": ponds}})
	assert_dict(P0Logic._home_material_go(away, "wood")).is_equal({"go": "gather:p_away#0", "now": true})
	assert_dict(P0Logic._home_material_go(away, "fiber")).is_equal({"go": "gather:p_near#1", "now": true})
	assert_dict(P0Logic._home_material_go(away, "iron_ore")).is_equal({"go": "mine:wv1", "now": false})

func test_ores_go_to_the_free_vein_or_quarry_and_clay_falls_back_to_the_quarry() -> void:
	assert_dict(P0Logic._home_material_go(_view(), "iron_ore")).is_equal({"go": "mine:wv1", "now": false})
	assert_dict(P0Logic._home_material_go(_view(), "quartz")).is_equal({"go": "mine:wv2", "now": false})
	for ore in ["copper_ore", "coal", "rock_salt"]:
		assert_dict(P0Logic._home_material_go(_view(), ore)).override_failure_message(ore).is_equal({"go": "mine:wq1", "now": false})
	assert_dict(P0Logic._home_material_go(_view({"mine": {"at": {"mine": "wv1"}}}), "iron_ore")).is_equal({"go": "mine:wv1", "now": true})
	# the server's view out of a mine: `at` null (SGODOT-394: the HOME-1 line for an ore came back as the bare name)
	assert_dict(P0Logic._home_material_go(_view({"mine": {"at": null}}), "iron_ore")).is_equal({"go": "mine:wv1", "now": false})
	assert_str(str(P0MaterialLogic.material_source(_view({"mine": {"at": null}}), "quartz").text).replace("\u00a0", " ")).ends_with(" · Quartz veins from Floor 10")
	assert_dict(P0Logic._home_material_go(_view(), "clay")).is_equal({"go": "gather:p_clay#0", "now": true})   # the Clay Pit first
	var pit_cooling := _view({"gather": {"city_ready": {"p_clay#0": 5000}, "ponds": _ponds()}})
	assert_dict(P0Logic._home_material_go(pit_cooling, "clay")).is_equal({"go": "mine:wq1", "now": false})   # then the quarry
	pit_cooling.wild = {"near3_sites": []}
	assert_dict(P0Logic._home_material_go(pit_cooling, "clay")).is_equal({"go": "gather:p_clay#0", "now": false})
	assert_dict(P0Logic._home_material_go(_view({"wild": {}}), "iron_ore")).is_equal({"go": "", "now": false})

func test_a_material_whose_points_all_cool_down_waits_with_whats_still_to_go() -> void:
	var next := {"level": 3, "skills": [], "materials": [{"id": "wood", "name": "Timber", "need": 6, "have": 2}]}
	var v := _view({"homestead": {"level": 2, "next": next}})
	var ready := P0Logic.homestead_row(v)
	assert_bool(bool(ready.now)).is_true()
	assert_str(str(ready.row.go)).is_equal("gather:p_near#0")
	v.gather = {"city_ready": {"p_near#0": 60000, "p_far#0": 60000}, "ponds": _ponds()}
	var waiting := P0Logic.homestead_row(v)
	assert_bool(bool(waiting.now)).is_false()   # q(255) ⑥: with the rows still to go
	assert_str(str(waiting.row.go)).is_equal("gather:p_near#0")

func test_an_old_save_shows_the_maintenance_card() -> void:
	assert_bool(P0Session.save_too_old({})).is_true()   # no save_version
	assert_bool(P0Session.save_too_old({"save_version": 6})).is_true()
	assert_bool(P0Session.save_too_old({"save_version": 7})).is_false()
	var card := P0SysScreen.card_spec(P0SysScreen.Kind.MAINT, {})
	assert_array([card.title, card.body, card.primary]).is_equal(["Down for maintenance", "We'll be back soon.", "Check again"])

func test_an_old_saves_reply_blocks_with_maintenance_and_never_becomes_the_view() -> void:
	var s := P0Session.new()
	var got := []
	s.blocked.connect(func(code, detail): got.append([code, detail.get("back_at", "")]))
	var reply := func(v: Dictionary) -> PackedByteArray: return JSON.stringify({"ok": true, "state": v}).to_utf8_buffer()
	for old in [{"energy": {"value": 1}}, {"save_version": 6}]:
		var r: Dictionary = s._handle(HTTPRequest.RESULT_SUCCESS, 200, reply.call(old), {})
		assert_str(str(r.code)).is_equal("maintenance")
	assert_array(got).is_equal([["maintenance", ""], ["maintenance", ""]])   # no back_at: `We'll be back soon.`
	assert_dict(s.view).is_empty()
	assert_bool(bool(s._handle(HTTPRequest.RESULT_SUCCESS, 200, reply.call({"save_version": 7}), {}).ok)).is_true()
	assert_int(int(s.view.save_version)).is_equal(7)
	s.free()

## 355 3b2c6a43 / U2 (不知火舞's spec v1.2 §4): the twelve NeedSource lines — a gathered material names the pond its Show
## goes to, none of the two cities' ponds having it `Ponds in some towns` (no Show); a long one breaks only before ` · or `
## (no-break spaces everywhere else, two lines at most); Show where Today points.
func test_need_sources_name_the_ponds_and_the_mines() -> void:
	var v := _view({"names": {"wood": "Timber", "stone": "Stone", "fiber": "Reeds", "wild_herb": "Herb", "clay": "Clay",
		"hardwood": "Hardwood", "flax": "Flax", "copper_ore": "Copper Ore", "coal": "Coal", "rock_salt": "Rock Salt",
		"iron_ore": "Iron Ore", "quartz": "Quartz"}})
	var lines := {"wood": "Timber · Fern Pond", "stone": "Stone · Ponds in some towns · or any mine",
		"fiber": "Reeds · Fern Pond", "wild_herb": "Herb · Ponds in some towns",
		"clay": "Clay · Clay Pond · or Quarries", "hardwood": "Hardwood · Ponds in some towns",
		"flax": "Flax · Ponds in some towns", "copper_ore": "Copper Ore · Quarries", "coal": "Coal · Quarries",
		"rock_salt": "Rock Salt · Quarries", "iron_ore": "Iron Ore · Iron veins from Floor 10",
		"quartz": "Quartz · Quartz veins from Floor 10"}
	for id in lines:
		var src := P0MaterialLogic.material_source(v, id)
		assert_str(str(src.text).replace("\u00a0", " ")).override_failure_message(id).is_equal(str(lines[id]))
		assert_str(str(src.go)).override_failure_message(id).is_equal(str(P0Logic._home_material_go(v, id).go))
	assert_str(str(P0MaterialLogic.material_source(v, "wood").go)).is_equal("gather:p_near#0")
	assert_str(str(P0MaterialLogic.material_source(v, "hardwood").go)).is_equal("")   # no pond: no Show
	assert_str(str(P0MaterialLogic.material_source(v, "iron_ore").go)).is_equal("mine:wv1")
	var clay := str(P0MaterialLogic.material_source(v, "clay").text)
	assert_str(clay).is_equal("Clay · Clay\u00a0Pond · or\u00a0Quarries")   # breakable only at a ` · `
	assert_dict(P0MaterialLogic.material_source(v, "bait_worm")).is_empty()
	assert_dict(P0MaterialLogic.material_source(v, "seed_radish")).is_empty()

## eb1d7c20: the card breaks only at a ` · `, the dot dropped — before ` · or ` first, else after the material.
func test_the_source_card_breaks_at_a_dot() -> void:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(host)
	var pill := UiNeedSource.new("Clay · Clay\u00a0Pits\u00a0in\u00a0town · or\u00a0Quarries", true)
	host.add_child(pill)
	pill.fit_to(317.0)   # the card's width on a 360 screen
	assert_str(pill._label.text).is_equal("Clay · Clay\u00a0Pits\u00a0in\u00a0town\nor\u00a0Quarries")
	pill.text = "Iron\u00a0Ore · Iron\u00a0veins\u00a0from\u00a0Floor\u00a010"
	pill.fit_to(200.0)
	assert_str(pill._label.text).is_equal("Iron\u00a0Ore\nIron\u00a0veins\u00a0from\u00a0Floor\u00a010")
	pill.text = "Coal · Quarries"
	pill.fit_to(317.0)
	assert_str(pill._label.text).is_equal("Coal · Quarries")   # one that fits stays one line
	host.queue_free()
