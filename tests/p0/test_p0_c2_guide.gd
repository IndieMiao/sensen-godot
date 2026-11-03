extends GdUnitTestSuite
## 355 C2-c (亚瑟's split, SGODOT-355): the guide's and Today's Show targets for the city's gathering spots and the wild
## mines — S6a's row to view.guide.target's spot, a Homestead material to its spot or mine (as the server's gatherTarget
## picks), the `gather:` / `mine:` Show labels — and the maintenance guard on an old save.

const HOME := "gn-test"
const PLACES := preload("res://modules/p0/p0_city_places.gd")

func after_test() -> void:
	PLACES.clear()

## The home city's spots: two Groves (the far one first in the table), a Clay Pit, a Reed Bank.
func _spots() -> void:
	PLACES.accept(HOME, {"gather": [
		{"id": HOME + "~wood1", "kind": "wood", "name": "Far Grove", "lat": 10.05, "lng": 20.0, "yield": [["wood", 4]]},
		{"id": HOME + "~wood0", "kind": "wood", "name": "Near Grove", "lat": 10.01, "lng": 20.0, "yield": [["wood", 4]]},
		{"id": HOME + "~clay0", "kind": "clay", "name": "Clay Pit", "lat": 10.02, "lng": 20.0, "yield": [["clay", 4]]},
		{"id": HOME + "~reed0", "kind": "reed", "name": "Reed Bank", "lat": 10.03, "lng": 20.0, "yield": [["fiber", 4], ["bait_worm", 2]]}]})

func _view(extra := {}) -> Dictionary:
	var v := {"save_version": 7, "travel": {"home": HOME}, "home": {"city": HOME, "farm": {"lat": 10.0, "lng": 20.0}},
		"bag": {"free": 5, "slots": []}, "gather": {"city_ready": {}},
		"wild": {"near3_sites": [{"id": "wq1", "type": "quarry", "main": null, "name": "Pebble Quarry"},
			{"id": "wv1", "type": "vein", "main": "iron_ore", "name": "Iron Vein"},
			{"id": "wv2", "type": "vein", "main": "quartz", "name": "Quartz Vein"}]}}
	v.merge(extra, true)
	return v

func test_s6a_row_goes_to_the_targets_spot_and_reads_show_by_where_the_player_is() -> void:
	var g := {"step": "t_gather", "row": {"line": "Gather Timber · Near Grove", "icon": "wood", "go": "map"}}
	var without := P0Guide.guide_rows({"guide": g})
	assert_str(str(without[0].go)).is_equal("map")   # no target (the key absent): the server's go as it was
	g.target = {"kind": "gather", "spot": HOME + "~wood0", "item": "wood"}
	var row: Dictionary = P0Guide.guide_rows({"guide": g})[0]
	assert_str(str(row.go)).is_equal("gather:" + HOME + "~wood0")
	assert_str(P0Ui.show_label(str(row.go), "map", true)).is_equal("Show")
	assert_str(P0Ui.show_label(str(row.go), "farm", true)).is_equal("Show on map")
	assert_str(P0Ui.map_target(str(row.go))).is_equal(str(row.go))   # handed to P0Map.show_place as it is
	assert_str(P0Ui.show_label("mine:wv1", "home", true)).is_equal("Show on map")
	assert_str(P0Ui.show_label("mine:wv1", "map", true)).is_equal("Show")
	assert_str(P0Ui.show_label("mine:wv1", "mine", true, "wv1")).is_equal("")   # down that mine: no button
	assert_str(P0Ui.show_label("mine:wv2", "mine", true, "wv1")).is_equal("Show on map")

func test_a_gathered_material_goes_to_the_spot_the_server_would_pick() -> void:
	assert_dict(P0Logic._home_material_go(_view(), "wood")).is_equal({"go": "", "now": false})   # spots not read yet
	_spots()
	assert_dict(P0Logic._home_material_go(_view(), "wood")).is_equal({"go": "gather:" + HOME + "~wood0", "now": true})   # the nearest
	var near_cooling := _view({"gather": {"city_ready": {HOME + "~wood0": 60000}}})
	assert_dict(P0Logic._home_material_go(near_cooling, "wood")).is_equal({"go": "gather:" + HOME + "~wood1", "now": true})   # the ready one
	var all_cooling := _view({"gather": {"city_ready": {HOME + "~wood0": 60000, HOME + "~wood1": 1000}}})
	assert_dict(P0Logic._home_material_go(all_cooling, "wood")).is_equal({"go": "gather:" + HOME + "~wood0", "now": false})
	var full := _view({"bag": {"free": 0, "slots": [{"id": "fiber", "qty": 97}]}})
	assert_dict(P0Logic._home_material_go(full, "fiber")).is_equal({"go": "gather:" + HOME + "~reed0", "now": false})   # 2 of room < 4
	assert_dict(P0Logic._home_material_go(full, "wild_herb")).is_equal({"go": "", "now": false})   # no Herb Patch in this city
	assert_int(P0Logic.bag_room(full, "fiber")).is_equal(2)

func test_ores_go_to_the_free_vein_or_quarry_and_clay_falls_back_to_the_quarry() -> void:
	_spots()
	assert_dict(P0Logic._home_material_go(_view(), "iron_ore")).is_equal({"go": "mine:wv1", "now": false})
	assert_dict(P0Logic._home_material_go(_view(), "quartz")).is_equal({"go": "mine:wv2", "now": false})
	for ore in ["copper_ore", "coal", "rock_salt"]:
		assert_dict(P0Logic._home_material_go(_view(), ore)).override_failure_message(ore).is_equal({"go": "mine:wq1", "now": false})
	assert_dict(P0Logic._home_material_go(_view({"mine": {"at": {"mine": "wv1"}}}), "iron_ore")).is_equal({"go": "mine:wv1", "now": true})
	assert_dict(P0Logic._home_material_go(_view(), "clay")).is_equal({"go": "gather:" + HOME + "~clay0", "now": true})   # the Clay Pit first
	var pit_cooling := _view({"gather": {"city_ready": {HOME + "~clay0": 5000}}})
	assert_dict(P0Logic._home_material_go(pit_cooling, "clay")).is_equal({"go": "mine:wq1", "now": false})   # then the quarry
	pit_cooling.wild = {"near3_sites": []}
	assert_dict(P0Logic._home_material_go(pit_cooling, "clay")).is_equal({"go": "gather:" + HOME + "~clay0", "now": false})
	assert_dict(P0Logic._home_material_go(_view({"wild": {}}), "iron_ore")).is_equal({"go": "", "now": false})

func test_a_material_whose_spots_all_cool_down_waits_with_whats_still_to_go() -> void:
	_spots()
	var next := {"level": 3, "skills": [], "materials": [{"id": "wood", "name": "Timber", "need": 6, "have": 2}]}
	var v := _view({"homestead": {"level": 2, "next": next}})
	var ready := P0Logic.homestead_row(v)
	assert_bool(bool(ready.now)).is_true()
	assert_str(str(ready.row.go)).is_equal("gather:" + HOME + "~wood0")
	v.gather = {"city_ready": {HOME + "~wood0": 60000, HOME + "~wood1": 60000}}
	var waiting := P0Logic.homestead_row(v)
	assert_bool(bool(waiting.now)).is_false()   # q(255) ⑥: with the rows still to go
	assert_str(str(waiting.row.go)).is_equal("gather:" + HOME + "~wood0")

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

## 355 3b2c6a43 (李白's note 547a1962, pending the user's word): the twelve NeedSource lines; a long one breaks only
## before ` · or ` (no-break spaces everywhere else, two lines at most); Show where Today points.
func test_need_sources_name_the_city_spots_and_the_mines() -> void:
	_spots()
	var v := _view({"names": {"wood": "Timber", "stone": "Stone", "fiber": "Reeds", "wild_herb": "Herb", "clay": "Clay",
		"hardwood": "Hardwood", "flax": "Flax", "copper_ore": "Copper Ore", "coal": "Coal", "rock_salt": "Rock Salt",
		"iron_ore": "Iron Ore", "quartz": "Quartz"}})
	var lines := {"wood": "Timber · Groves in town", "stone": "Stone · Rocks in town · or any mine",
		"fiber": "Reeds · Reed Banks in town", "wild_herb": "Herb · Herb Patches in town",
		"clay": "Clay · Clay Pits in town · or Quarries", "hardwood": "Hardwood · Woods in some towns",
		"flax": "Flax · Flax Fields in some towns", "copper_ore": "Copper Ore · Quarries", "coal": "Coal · Quarries",
		"rock_salt": "Rock Salt · Quarries", "iron_ore": "Iron Ore · Iron veins from Floor 10",
		"quartz": "Quartz · Quartz veins from Floor 10"}
	for id in lines:
		var src := P0MaterialLogic.material_source(v, id)
		assert_str(str(src.text).replace(" ", " ")).override_failure_message(id).is_equal(str(lines[id]))
		assert_str(str(src.go)).override_failure_message(id).is_equal(str(P0Logic._home_material_go(v, id).go))
	assert_str(str(P0MaterialLogic.material_source(v, "wood").go)).is_equal("gather:" + HOME + "~wood0")
	assert_str(str(P0MaterialLogic.material_source(v, "iron_ore").go)).is_equal("mine:wv1")
	var clay := str(P0MaterialLogic.material_source(v, "clay").text)
	assert_int(clay.count(" ")).is_equal(1)   # the one breakable space: before `· or`
	assert_bool(clay.contains(" · or Quarries")).is_true()
	assert_dict(P0MaterialLogic.material_source(v, "bait_worm")).is_empty()
	assert_dict(P0MaterialLogic.material_source(v, "seed_radish")).is_empty()
