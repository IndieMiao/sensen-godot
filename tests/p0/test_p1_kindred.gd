extends GdUnitTestSuite
## Kindred on the client (q(171), SGODOT-284; 不知火舞's frames KINDRED-PIP, PASS-POSTCARDS, PostcardStamp): the arrival
## card after the `kindred` event, the stamp, and the Passport — a drawer with `Cities` / `Postcards` pills, Close going
## back where it was opened from.

const Kindred := preload("res://modules/p0/p0_kindred.gd")
const Stamp := preload("res://scenes/p0/panels/p0_postcard_stamp.gd")
const STORE := "user://test_p1_kindred_quick.json"

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _view(earned := {"res_pip": "Best friend on the whole route. Don't tell the pigeons."}) -> Dictionary:
	var residents := {}
	for id in P0Logic.content().get("residents", {}):
		residents[id] = {"affinity": 160 if earned.has(id) else 20, "stage": "Kindred" if earned.has(id) else "Acquainted",
			"kindred": {"postcard": "Postcard from %s" % Kindred.resident_name(id), "text": earned[id],
				"title": "%s's Best Friend" % Kindred.resident_name(id), "at": 1.0} if earned.has(id) else null}
	return {"residents": residents, "travel": {"home": "gn-5391959", "here": "gn-5391959", "today": "2026-10-14", "passes": {},
		"stamps": [], "visits": {}}, "energy": {"value": 120, "max": 200}, "coins": 50, "bag": {"capacity": 25, "slots": []}}

func _ui() -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	return ui

func test_the_arrival_cards_words() -> void:
	var c: Dictionary = Kindred.card({}, {"kind": "kindred", "resident": "res_pip", "postcard": "Postcard from Pip", "title": "Pip's Best Friend"})
	assert_array([c.resident, c.event, c.item_name, c.strip]).is_equal(["res_pip", "Kindred · Pip", "Postcard from Pip",
		"New title · Pip's Best Friend"])
	var old: Dictionary = Kindred.card({}, {"kind": "kindred", "resident": "res_old_kai"})   # an older server: the names from the resident's
	assert_array([old.item_name, old.strip]).is_equal(["Postcard from Old Kai", "New title · Old Kai's Best Friend"])

## Every open resident in the table's order (q(193) ④: a place in world_gen's placement rules or a hand-written
## outpost), the denominator how many they are; Mira (her weekly route is P2) and Ivo (until his Mine Hut is built,
## q(193) ②) are not on the page, no gap left; an unearned cell names no one.
func test_the_postcards_page_lists_the_open_residents_in_the_tables_order() -> void:
	var p: Dictionary = Kindred.postcards(_view())
	var table: Array = P0Logic.content().get("residents", {}).keys()
	var open: Array = table.filter(func(id): return not id in ["res_mira", "res_ivo"])
	assert_array(Kindred.open_residents()).is_equal(open)
	assert_bool(Kindred.open_residents().has("res_granny_wu")).is_true()   # the S-tier trading post's
	assert_str(str(p.count)).is_equal("Postcards · 1/10")
	assert_array(p.cells.map(func(c): return c.id)).is_equal(open)
	var pip: Dictionary = p.cells[table.find("res_pip")]
	assert_array([pip.earned, pip.name, pip.text]).is_equal([true, "Pip", "Best friend on the whole route. Don't tell the pigeons."])
	var kai: Dictionary = p.cells[table.find("res_old_kai")]
	assert_array([kai.earned, kai.name, kai.text]).is_equal([false, "", ""])

## Earned: the render card at its stamp crop where the card exists (上官婉儿 #405), else the initial (never the grey
## silhouette); unearned: grey, no initial.
func test_the_stamp_shows_a_face_an_initial_or_the_silhouette() -> void:
	var pip: Control = auto_free(Stamp.new("res_pip", true))
	var face := pip.get("face") as AtlasTexture
	assert_that([face.atlas.resource_path, face.region]).is_equal(["res://assets/p0/art/residents/pip_card.jpg", Rect2(65, 46, 175, 219)])
	assert_object(pip.find_child("Initial", false, false)).is_null()
	var hana: Control = auto_free(Stamp.new("res_hana", true))   # a resident without an illustration: their card
	assert_str((hana.get("face") as AtlasTexture).atlas.resource_path).is_equal("res://assets/p0/art/residents/hana_card.jpg")
	var wu: Control = auto_free(Stamp.new("res_granny_wu", true))   # no card yet
	assert_object(wu.get("face")).is_null()
	assert_str((wu.find_child("Initial", false, false) as Label).text).is_equal("G")
	var none: Control = auto_free(Stamp.new("res_hana", false))
	assert_object(none.find_child("Initial", false, false)).is_null()
	assert_vector(pip.custom_minimum_size).is_equal(Stamp.PASSPORT)
	var big: Control = auto_free(Stamp.new("res_pip", true, Stamp.CARD))
	assert_vector(big.custom_minimum_size).is_equal(Stamp.CARD)

## The `kindred` event: a Milestone with the stamp in the item's place, the postcard's name, the title on a heart strip.
func test_the_kindred_event_shows_its_card() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var v := _view()
	rt.session.view = v
	rt._on_state(v, [{"kind": "affinity", "resident": "res_pip", "delta": 2, "total": 150, "stage": "Kindred", "reason": "chat"},
		{"kind": "kindred", "resident": "res_pip", "postcard": "Postcard from Pip", "title": "Pip's Best Friend"}])
	for i in 3: await get_tree().process_frame
	var cards := rt.ui.root.find_children("*", "UiRewardMoment", true, false)
	assert_int(cards.size()).is_equal(1)
	var m := cards[0] as UiRewardMoment
	assert_array([m.tone, m.event, m.item_name, m.strip]).is_equal([UiRewardMoment.Tone.MILESTONE, "Kindred · Pip",
		"Postcard from Pip", "New title · Pip's Best Friend"])
	assert_object(m.strip_icon).is_same(UiFloatText.HEART)   # the affinity float's heart, 14 (不知火舞 on 284)
	assert_float(m.strip_icon_size).is_equal(14.0)
	assert_object(m.item_art).is_not_null()
	assert_bool(m._icon.visible).is_false()   # the stamp alone in the disc's place
	assert_array(m.rewards).is_empty()   # no pills
	rt.ui.close_modal()
	await get_tree().process_frame

## The Passport drawer: `Passport` / Close, the pills, Cities first; Postcards shows the grid, every cell as tall.
func test_the_passport_has_cities_and_postcards_pages() -> void:
	var ui := _ui()
	await get_tree().process_frame
	ui.set_view(_view())
	var d := ui.open_passport()
	assert_str(ui.modal_kind).is_equal("passport")
	var pills: Array = d.find_children("*", "UiFilterChip", true, false)
	assert_array(pills.map(func(p): return (p as Button).text)).is_equal(["Cities", "Postcards"])
	assert_bool((pills[0] as Button).button_pressed).is_true()
	assert_bool((d.find_child("Cities", true, false) as Control).visible).is_true()
	assert_bool((d.find_child("Postcards", true, false) as Control).visible).is_false()
	assert_object(d.find_child("Row_San_Francisco", true, false)).is_not_null()   # home's row, as before
	(pills[1] as Button).button_pressed = true
	for i in 3: await get_tree().process_frame
	var page := d.find_child("Postcards", true, false) as Control
	assert_bool(page.visible).is_true()
	assert_str((page.find_child("Count", true, false) as Label).text).is_equal("Postcards · 1/10")
	var cells: Array = page.find_child("Grid", true, false).get_children()
	assert_int(cells.size()).is_equal(10)
	for gone in ["Cell_res_mira", "Cell_res_ivo"]: assert_object(page.find_child(gone, true, false)).is_null()   # q(193)
	var heights := cells.map(func(c): return (c as Control).custom_minimum_size.y)
	assert_bool(heights.all(func(h): return is_equal_approx(h, heights[0]) and h > Stamp.PASSPORT.y)).is_true()
	# as tall as the longest Kindred line of the page's residents needs at the cells' own width: three lines in P1
	# (Mira's four-line one joins with her in P2; 不知火舞 on 284)
	var line := page.find_child("Cell_res_pip", true, false).find_child("Line", true, false) as Label
	assert_int(line.get_line_count()).is_less_equal(3)
	assert_float(heights[0]).is_less_equal(12 + Stamp.PASSPORT.y + 4 + 22 + 4 + 3 * 16 + 12)
	var pip := page.find_child("Cell_res_pip", true, false)
	assert_str((pip.find_child("Name", true, false) as Label).text).is_equal("Pip")
	assert_str((pip.find_child("Line", true, false) as Label).text).is_equal("“Best friend on the whole route. Don't tell the pigeons.”")
	assert_object((pip.find_child("Line", true, false) as Label).get_theme_font(&"font")).is_same(UiKit.bold_italic())   # C11 B italic
	assert_str((page.find_child("Cell_res_old_kai", true, false).find_child("Unknown", true, false) as Label).text).is_equal("Kindred · ?")

## Close goes back where it was opened from (the profile), else closes (the Stamp Desk); a city's Back returns here.
func test_close_goes_back_where_it_came_from() -> void:
	var ui := _ui()
	await get_tree().process_frame
	ui.set_view(_view())
	var back := [0]
	var d := ui.open_passport(func(): back[0] += 1)
	(d.find_child("Close", true, false) as BaseButton).pressed.emit()
	assert_int(back[0]).is_equal(1)   # the profile's way back
	var plain := ui.open_passport()
	(plain.find_child("Close", true, false) as BaseButton).pressed.emit()
	assert_str(ui.modal_kind).is_equal("")   # from the Stamp Desk: closed
	var postcards := ui.open_passport(Callable(), "postcards")
	assert_bool((postcards.find_child("Postcards", true, false) as Control).visible).is_true()
	ui.close_modal()
	await get_tree().process_frame

## A portrait without its face crop (300 × 660, as Pip's art) fills the stamp's picture without stretching: the
## top of it, centred across.
func test_a_whole_portrait_is_cropped_not_stretched() -> void:
	var r: Rect2 = Stamp.cover(Vector2(300, 660), Vector2(26, 34))
	assert_float(r.size.x / r.size.y).is_equal_approx(26.0 / 34.0, 0.001)
	assert_vector(r.position).is_equal(Vector2(0, 0))   # a tall picture: its top
	var wide: Rect2 = Stamp.cover(Vector2(340, 340), Vector2(26, 34))
	assert_float(wide.size.y).is_equal(340.0)
	assert_float(wide.position.x).is_equal_approx((340.0 - 340.0 * 26.0 / 34.0) * 0.5, 0.01)   # centred across

## Ivo joins once his Mine Hut is a room of the world (q(193) ②): the count follows the data, no number written.
func test_the_mine_hut_brings_ivo_onto_the_page() -> void:
	var rooms: Dictionary = P0Logic.content().world.room
	rooms["mine_hut"] = {"art": "", "anchors": "", "category": "Mine hut"}
	var with_hut := Kindred.open_residents()
	rooms.erase("mine_hut")
	assert_bool(with_hut.has("res_ivo")).is_true()
	assert_int(with_hut.size()).is_equal(11)
	assert_bool(Kindred.open_residents().has("res_ivo")).is_false()

## A postcard the player holds is on the page even when its resident has no home here yet (周瑜 on #400): it joins in
## the table's order and the count.
func test_a_held_postcard_is_never_hidden() -> void:
	var p: Dictionary = Kindred.postcards(_view({"res_pip": "Best friend on the whole route. Don't tell the pigeons.",
		"res_ivo": "Down here, a friend is worth more than ore."}))
	var ids: Array = p.cells.map(func(c): return c.id)
	assert_str(str(p.count)).is_equal("Postcards · 2/11")
	assert_bool(ids.has("res_ivo")).is_true()
	assert_bool(ids.has("res_mira")).is_false()
	var table: Array = P0Logic.content().get("residents", {}).keys()
	assert_array(ids).is_equal(table.filter(func(id): return ids.has(id)))   # still the table's order

## The dialogue bar and the request card: the illustration where a resident has one (Pip, Kai: 不知火舞 keeps them),
## else the render card; nobody's a vector placeholder once their card is in.
func test_the_dialogue_bar_keeps_the_illustrations_and_takes_the_cards() -> void:
	assert_str(P0Ui._portrait("pip").resource_path).is_equal("res://assets/p0/art/pip-portrait.jpg")
	assert_str(P0Ui._portrait("kai").resource_path).is_equal("res://assets/p0/art/kai-portrait.jpg")
	for key in ["hana", "sam", "lena", "rafa", "tomo", "theo", "nadia"]:
		assert_str(P0Ui._portrait(key).resource_path).is_equal("res://assets/p0/art/residents/%s_card.jpg" % key)
	assert_object(P0Ui._portrait("granny_wu")).is_null()
	assert_object(P0Ui._portrait("")).is_null()
	# every card has both crops, inside its 300 × 660
	var crops: Dictionary = P0RoomAnchors.read_json(P0Ui.CROPS_PATH)
	for key in ["pip", "kai", "hana", "sam", "lena", "rafa", "tomo", "theo", "nadia"]:
		for kind in ["stamp", "face"]:
			var r := (P0Ui.resident_crop(key, kind) as AtlasTexture).region
			assert_bool(Rect2(0, 0, 300, 660).encloses(r)).override_failure_message("%s %s %s" % [key, kind, r]).is_true()
	assert_int(crops.size()).is_greater_equal(9)
