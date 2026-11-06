extends GdUnitTestSuite
## SGODOT-406 (安其拉's B set, 不知火舞 9b2d28ae; on #740: by the template, as the card): a pond's map pin wears its fishing
## template's icon — still water (Pond), a stream (River), a cove (Coast). The city panel's Ponds / Local pond rows keep
## the pond's. The two new icons carry a .import with a uid of their own (feedback: an .import without one is rewritten
## by the build's import, and publish refuses).

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const PondCard := preload("res://modules/p0/p0_pond_card.gd")
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")
const TOKYO := "gn-1850147"

var _content: Dictionary

func before_test() -> void:
	_content = P0Logic.content()
	P0CityPlaces.clear()
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	P0Logic._content = _content
	P0CityPlaces.clear()
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

func after() -> void:
	P0Runtime.free_instance_for_tests()

func test_a_ponds_pin_icon_is_its_templates() -> void:
	# San Francisco's: Fern 03 and Willow 01 are ponds, Blossom 06 and Pebble 04 rivers, Clover 02 the coast (Coast from
	# the P1 fragment, fishing_p1.json) — the same template the card's subtitle says (Fern's says Beginner)
	for id in ["pond_san_francisco_01", "pond_san_francisco_06", "pond_san_francisco_02"]:
		assert_str(str(PondCard.info({}, id, 1.0).subtitle)).is_equal(PondCard.template_of(id))
	assert_str(PondCard.pin_icon("pond_san_francisco_03")).is_equal("pond")
	assert_str(PondCard.pin_icon("pond_san_francisco_01")).is_equal("pond")
	assert_str(PondCard.pin_icon("pond_san_francisco_06")).is_equal("pond_river")
	assert_str(PondCard.pin_icon("pond_san_francisco_04")).is_equal("pond_river")
	assert_str(PondCard.pin_icon("pond_san_francisco_02")).is_equal("pond_coast")
	assert_str(PondCard.pin_icon("gn-1816670~pond0")).is_equal("pond")   # a city not read yet: the still water

## The pin follows the template, not the site's name: a site whose template is Pond wears the still water.
func test_a_site_without_a_template_of_its_own_wears_the_pond() -> void:
	P0Logic._content = _content.duplicate(true)
	P0Logic._content.fishing.sites.erase("coast")   # as before P1's fragment: the card reads Pond, Lv1–3
	assert_str(str(PondCard.info({}, "pond_san_francisco_02", 1.0).subtitle)).is_equal("Pond")
	assert_str(PondCard.pin_icon("pond_san_francisco_02")).is_equal("pond")
	P0Logic._content.fishing.sites["pond"]["template"] = "River"
	assert_str(PondCard.pin_icon("pond_san_francisco_03")).is_equal("pond_river")

func test_another_citys_generated_ponds_take_their_templates_icon() -> void:
	P0CityPlaces.accept(TOKYO, {"ponds": ["gn-1850147~pond0", "gn-1850147~pond1", "gn-1850147~pond2"], "outposts": [],
		"residents": 0, "fish": [], "detail": {"ponds": [
			{"id": "gn-1850147~pond0", "name": "Willow Pond", "site": "pond", "beginner": true, "lat": 35.68, "lng": 139.71,
				"template_id": "crescent"},
			{"id": "gn-1850147~pond1", "name": "Reed Creek", "site": "river", "beginner": false, "lat": 35.67, "lng": 139.67,
				"template_id": "gourd"},
			{"id": "gn-1850147~pond2", "name": "Gull Cove", "site": "coast", "beginner": false, "lat": 35.62, "lng": 139.78,
				"template_id": "crescent"}]}})
	assert_array(["gn-1850147~pond0", "gn-1850147~pond1", "gn-1850147~pond2"].map(func(id): return PondCard.pin_icon(id))) \
		.is_equal(["pond", "pond_river", "pond_coast"])

func test_the_maps_pond_pin_takes_the_icon_its_template_gives() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var m := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(m)
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	for id in ["pond_san_francisco_03", "pond_san_francisco_06", "pond_san_francisco_02"]:
		var style: Dictionary = m._destination_style_of({"kind": "pond", "id": id, "name": "Pond"})
		assert_object(style.icon).is_same(P0Logic.icon(PondCard.pin_icon(id)))
	# the pond pin of Fern is the pond icon itself, not another one (an unimported checkout loads the new two as null)
	assert_object(m._destination_style_of({"kind": "pond", "id": "pond_san_francisco_03", "name": "Fern Pond"}).icon) \
		.is_same(P0Logic.icon("pond"))

func test_the_new_icons_are_imported_with_a_uid_of_their_own() -> void:
	var uids := {}
	for name in ["pond", "pond_river", "pond_coast"]:
		var path := "res://assets/p0/icons/%s.svg" % name
		assert_bool(FileAccess.file_exists(path)).is_true()
		var cfg := ConfigFile.new()
		assert_int(cfg.load(path + ".import")).is_equal(OK)
		var uid := str(cfg.get_value("remap", "uid", ""))
		# Godot's own form, base 34: a–y and 0–8 (ResourceUID::id_to_text) — a z or a 9 is rewritten by every import (亚瑟 on #740)
		var form := RegEx.create_from_string("^uid://[a-y0-8]+$")
		assert_object(form.search(uid)).override_failure_message("%s: %s is no uid Godot writes" % [name, uid]).is_not_null()
		assert_bool(uids.has(uid)).is_false()
		uids[uid] = true
		assert_str(str(cfg.get_value("deps", "source_file", ""))).is_equal(path)
		# the same import as the pond's: lossless, no mipmaps, the svg at its own size (128 for the 64 viewBox)
		assert_int(int(cfg.get_value("params", "compress/mode", -1))).is_equal(0)
		assert_bool(bool(cfg.get_value("params", "mipmaps/generate", true))).is_false()
		assert_float(float(cfg.get_value("params", "svg/scale", 0.0))).is_equal(1.0)
