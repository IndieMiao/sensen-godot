extends GdUnitTestSuite
## The four-things gate card (SGODOT-233; §4.8.7, q(49), SKILL-2 482:169): what is locked, which level, how far in
## XP and in an action amount, what crossing it does, the level-up gift, one guiding button; a tap outside or Back
## closes it one layer at a time.

const STORE := "user://test_p0_gate_card.json"

func _view(farming_xp := 32, fishing_xp := 100) -> Dictionary:
	var fl := 1
	for i in P0Logic.content().skills.fishing.size():
		if fishing_xp >= int(P0Logic.content().skills.fishing[i]): fl = i + 1
	return {
		"coins": 40, "energy": {"value": 150, "max": 200},
		"skills": {"farming": {"level": 1 if farming_xp < 50 else 2, "xp": farming_xp},
			"fishing": {"level": fl, "xp": fishing_xp}, "cooking": {"level": 1, "xp": 0}},
		"homestead": {"level": 2},
		"fishing": {"rod_reach": 2},
		"gear": {"rods": [{"id": "rod_reed", "name": "Reed Rod", "reach": 3, "level": 3, "price": 80, "owned": false}]},
		"names": {"fish_koi": "Golden Koi", "seed_carrot": "Carrot Seeds"},
		"bag": {"capacity": 25, "slots": []},
	}

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func test_a_seed_gate_reads_the_four_things() -> void:
	var s := P0Logic.gate_spec(_view(), {"skill": "farming", "level": 2, "what": "Carrot Seeds", "icon": "seed_carrot"})
	assert_that([s.title, s.rarity_text, s.badge]).is_equal(["Carrot Seeds", "Locked", &"locked"])
	assert_str(s.lead).is_equal("Farming Lv2 unlocks Carrot and Herb")
	assert_that([s.need.name, s.need.have, s.need.need]).is_equal(["Farming XP", 32, 50])
	assert_str(s.need.note).is_equal("18 XP to go · harvest 9 radishes")
	assert_that([s.info_row.title, s.info_row.qty, s.info_row.lines]).is_equal(["Carrot Seeds", "×5", ["Level-up gift", "At Lv2"]])
	assert_that(s.buttons.map(func(b): return [b.label, b.kind, b.payload.go])).is_equal([["Show my plots", &"nav", "plots"]])

func test_the_action_amounts_follow_the_plan() -> void:
	var v := _view(260)   # Farming Lv3 → Lv4 at 300
	v.skills.farming.level = 3
	# Lv3 sows Chamomile at full XP (4 a plant); the main crops unlock first in the lead (§4.8.7).
	assert_str(P0Logic.gate_action(v, "farming", 40)).is_equal("harvest 10 chamomile")
	assert_str(P0Logic.gate_spec(v, {"skill": "farming", "level": 3}).lead).is_equal("Farming Lv3 unlocks Potato and Chamomile")
	v.skills.farming.level = 2
	assert_str(P0Logic.gate_action(v, "farming", 40)).is_equal("harvest 14 carrots")   # §4.8.7 sample
	assert_str(P0Logic.gate_action(_view(32, 220), "fishing", 30)).is_equal("about 7 casts")   # Lv3 at Pond 4.9 (§4.4.2)
	assert_str(P0Logic.gate_action(_view(32, 0), "fishing", 1)).is_equal("about 1 cast")
	assert_that([P0Logic.crop_plural("Radish", 9), P0Logic.crop_plural("Potato", 2), P0Logic.crop_plural("Radish", 1),
		P0Logic.crop_plural("Corn", 63)]).is_equal(["radishes", "potatoes", "radish", "corn"])

func test_cooking_counts_new_dishes_first() -> void:
	var v := _view()
	v.skills.cooking = {"level": 3, "xp": 135}
	v["cooking"] = {"cookbook": [
		{"p0": true, "cooked": false, "lock": null, "rarity": 2},
		{"p0": true, "cooked": false, "lock": null, "rarity": 2},
		{"p0": true, "cooked": true, "lock": null, "rarity": 2},
		{"p0": true, "cooked": false, "lock": {"level": 4}, "rarity": 2}]}
	var first := int(P0Logic.content().cooking.tiers["2"].first_xp)
	assert_str(P0Logic.gate_action(v, "cooking", first * 2)).is_equal("about 2 new dishes")
	v.cooking.cookbook = []
	var fine := int(P0Logic.content().cooking.tiers["2"].xp)
	assert_str(P0Logic.gate_action(v, "cooking", fine * 3)).is_equal("about 3 Fine dishes")

func test_fish_dex_silhouettes_gate_on_level_then_rod() -> void:
	var g := P0Logic.fish_gate(_view(32, 100), "fish_koi")   # Fishing Lv3, Golden Koi is Lv4
	assert_that([g.what, g.sub, g.skill, g.level]).is_equal(["Golden Koi", "Rare · Locked", "fishing", 4])
	var s := P0Logic.gate_spec(_view(32, 100), g)
	assert_str(s.lead).is_equal("Fishing Lv4 keeps Golden Koi on the hook")
	assert_str(s.need.note).is_equal("380 XP to go · about 100 casts")   # Lv2 at Pond 3.8
	assert_bool(s.buttons.is_empty()).is_true()   # Fishing has nowhere to show (§4.8.7 —)
	var rod := P0Logic.fish_gate(_view(32, 480), "fish_koi")   # Lv4: the rod holds it back now
	assert_bool(rod.has("rod")).is_true()
	var rs := P0Logic.gate_spec(_view(32, 480), rod)
	assert_str(rs.lead).is_equal("Reed Rod lands up to Rare fish")
	assert_that([rs.need.name, rs.need.have, rs.need.need, rs.need.note]).is_equal(["Coins", 40, 80, "80 coins at Tackle Shop"])
	assert_bool(P0Logic.fish_gate(_view(32, 100), "fish_crucian").is_empty()).is_true()

func test_a_homestead_gate_counts_levels() -> void:
	var s := P0Logic.gate_spec(_view(), {"homestead": 3, "what": "Bag Upgrade I", "after": "opens Bag Upgrade I", "guide": {}})
	assert_str(s.lead).is_equal("Homestead Lv3 opens Bag Upgrade I")
	assert_that([s.need.have, s.need.need, s.need.note]).is_equal([2, 3, "1 level to go"])
	assert_bool(s.buttons.is_empty()).is_true()

func test_the_card_closes_one_layer_at_a_time_and_its_button_only_guides() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_surface("farm")
	ui.can_show_spot = func(): return true
	var reopened := [0]
	var sheet := ui.open_gate_card({"skill": "farming", "level": 2, "what": "Carrot Seeds", "icon": "seed_carrot"},
		func(): reopened[0] += 1)
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("gate")
	assert_bool(sheet.is_visible_in_tree()).is_true()
	ui.close_top_layer()   # Android Back: back to the panel it came from
	assert_int(reopened[0]).is_equal(1)
	sheet = ui.open_gate_card({"skill": "farming", "level": 2, "what": "Carrot Seeds"})
	await await_idle_frame()
	var shown := []
	ui.show_spot.connect(func(w): shown.append(w))
	sheet.action_requested.emit(&"guide", "gate", {"go": "plots"})
	assert_str(ui.modal_kind).is_equal("")   # the card closes first …
	assert_array(shown).is_equal(["plots"])   # … then only the camera moves (LOCK-08)
