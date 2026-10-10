extends GdUnitTestSuite
## LOOK-PICK (SGODOT-282; 不知火舞 49498df6 / e2d76a7c, q(112) / q(115)): Homestead looks a (timber) / b (stone) at
## Lv3 / 5 / 8 / 10 — HOME-1's Looks rows, the card, and the parts on the farm.

const Looks = preload("res://scenes/p0/p0_looks.gd")
const Fence = preload("res://scenes/p0/p0_fence.gd")
const FarmProps = preload("res://modules/farm/farm_props.gd")
const FarmArt = preload("res://modules/farm/farm_art.gd")

func _view(level: int, looks := {}) -> Dictionary:
	var rows: Array = []
	for l in P0Logic.look_stages():
		var reached := level >= int(l.level)
		rows.append({"id": l.id, "level": l.level, "name": l.name, "a": l.a, "b": l.b,
			"look": str(looks.get(str(l.id), "a")) if reached else null})
	return {"homestead": {"level": level, "looks": rows, "next": null, "unlocks": {"fence": level >= 3}},
		"energy": {"max": 240}, "bag": {"capacity": 30}}

func _ui(v: Dictionary) -> P0Ui:
	var ui: P0Ui = auto_free(P0Ui.new())
	add_child(ui)
	ui.set_view(v)
	return ui

# ---------------------------------------------------------------- HOME-1 Looks (e2d76a7c, Figma 2201:33545)
func test_looks_rows_name_the_look_on_reached_stages_and_grey_the_rest() -> void:
	var rows := P0Logic.look_rows(_view(4))
	assert_array(rows.map(func(r): return "%s … %s" % [r.name, r.value])).is_equal(
		["Fence & Mailbox … Timber Fence ›", "Porch … Homestead Lv5", "Kitchen Wing … Homestead Lv8", "Master Farmhouse … Homestead Lv10"])
	assert_array(rows.map(func(r): return [r.reached, r.open])).is_equal([[true, true], [false, false], [false, false], [false, false]])
	assert_array(rows.map(func(r): return str(r.icon))).is_equal(["mailbox", "door", "kitchen", "home"])
	assert_array(P0Logic.look_rows(_view(2))).is_empty()   # no stage yet: no Looks section
	var away := P0Logic.look_rows(_view(5, {"porch": "b"}), false)   # away from home: read only, no ›
	assert_str(str(away[1].value)).is_equal("Stone Porch")
	assert_bool(bool(away[1].open)).is_false()

func test_the_next_look_level_lists_its_stage_timber_or_stone() -> void:
	var v := _view(4)
	v.homestead.next = {"level": 5, "coins": {"need": 840, "have": 0}, "skills": {"need": 9, "have": 9},
		"materials": [], "energy": 240, "meals": 240, "unlocks": ["notice_board", "trip_7", "porch", "standard_room"]}
	var p := P0Logic.home_panel(v)
	assert_str(str(p.look)).is_equal("Lv5 look · Porch")
	var row: Dictionary = p.changes.filter(func(c): return str(c.text).ends_with("Timber or Stone"))[0]
	assert_str("%s · %s" % [row.text, row.note]).is_equal("Porch · Timber or Stone · pick one")
	assert_str(str(row.icon)).is_equal("door")

func test_a_reached_looks_row_opens_the_card_with_the_current_look() -> void:
	var ui := _ui(_view(5, {"porch": "b"}))
	ui.space = "home"
	load("res://scenes/p0/home/p0_home_panel.gd").open(ui, true)
	var row: Control = ui.find_children("Look_porch", "", true, false)[0]
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	row.gui_input.emit(up)
	var card: P0LookPick = ui.find_children("*", "P0LookPick", true, false)[0]
	assert_bool(card.first).is_false()
	assert_str(card.choice).is_equal("b")
	assert_str(card.use_button.label).is_equal("Use Stone Porch")
	card.dismiss()   # from HOME-1: no change, back to HOME-1
	assert_str(ui.modal_kind).is_equal("homestead")

# ---------------------------------------------------------------- LOOK-PICK (49498df6, Figma 2199:32862)
func test_the_card_after_the_upgrade_previews_writes_and_closes_to_a() -> void:
	var ui := _ui(_view(5))
	var previews: Array = []
	var sent: Array = []
	ui.look_previewed.connect(func(st, lk): previews.append([st, lk]))
	ui.command.connect(func(c): sent.append(c))
	var card := P0LookPick.open(ui, "porch", true)
	await get_tree().process_frame
	assert_str((card.find_child("Title", true, false) as Label).text).is_equal("Lv5 look · Porch")
	assert_str((card.find_child("Subtitle", true, false) as Label).text).is_equal("Pick one · free to change later")
	assert_str(card.choice).is_equal("a")   # default a
	assert_bool((card.options.a as UiLookOption).selected).is_true()
	assert_str(card.use_button.label).is_equal("Use Timber Porch")
	(card.options.b as UiLookOption).picked.emit()
	assert_str(card.use_button.label).is_equal("Use Stone Porch")
	assert_bool((card.options.b as UiLookOption).selected).is_true()
	assert_array(previews).is_equal([["porch", "b"]])   # the farmhouse shows it at once
	assert_array(sent).is_empty()                         # only Use writes it
	card.use()
	assert_array(sent).is_equal([{"type": "set_look", "stage": "porch", "look": "b"}])
	assert_bool(ui.has_modal()).is_false()
	# closing the next one after an upgrade = a: the preview ends, nothing is sent
	var again := P0LookPick.open(ui, "porch", true)
	again.pick("b")
	again.dismiss()
	assert_array(previews.back()).is_equal(["porch", ""])
	assert_int(sent.size()).is_equal(1)

func test_two_cards_are_as_tall_as_the_taller() -> void:
	var a := UiLookOption.new("Timber Porch")
	var b := UiLookOption.new("Stone Porch")
	a.theme = UiKit.theme()
	b.theme = UiKit.theme()
	add_child(auto_free(a))
	add_child(auto_free(b))
	UiLookOption.pair(a, b)
	assert_float(a.custom_minimum_size.y).is_equal(b.custom_minimum_size.y)
	assert_float(a.custom_minimum_size.x).is_equal(158.0)
	var wing_a := UiLookOption.new("Timber Kitchen Wing")
	var wing_b := UiLookOption.new("Stone Kitchen Wing")
	for o in [wing_a, wing_b]:
		o.theme = UiKit.theme()
		add_child(auto_free(o))
	await get_tree().process_frame
	UiLookOption.pair(wing_a, wing_b)
	assert_float(wing_a.custom_minimum_size.y).is_greater(a.custom_minimum_size.y)   # two lines: taller, same font size
	assert_float(wing_a.custom_minimum_size.y).is_equal(wing_b.custom_minimum_size.y)

# ---------------------------------------------------------------- the farm's parts (上官婉儿 e4d03424)
func test_stone_wall_follows_the_fence_run_three_rocks_a_segment() -> void:
	var bp := P0Garden.blueprint()
	var segs := P0Garden.fence_front(bp) + P0Garden.fence_ring(bp)
	var wall := P0Garden.stone_wall(segs)
	assert_int(wall.size()).is_equal(segs.size() * P0Garden.STONE_PER_SEG)
	for i in segs.size():   # each segment's rocks sit on it, within its length
		var seg: Dictionary = segs[i]
		for k in P0Garden.STONE_PER_SEG:
			var p: Vector3 = wall[i * P0Garden.STONE_PER_SEG + k].pos
			assert_float(p.distance_to(seg.pos)).is_less(P0Garden.FENCE_SEG * float(seg.stretch) * 0.5)

func test_porch_and_kitchen_parts_keep_off_the_door_path() -> void:
	var bp := P0Garden.blueprint()
	var door := bp.cell_to_world(P0Garden.ANCHORS.house + Vector2i(0, -2))
	for stage in ["porch", "kitchen_extension"]:
		for look in ["a", "b"]:
			var parts := P0Garden.look_parts(bp, stage, look)
			assert_array(parts).is_not_empty()
			for p in parts:
				if str(p.asset) == "path_tile": continue   # the landing is the door path itself
				assert_float(absf((p.pos as Vector3).x - door.x)).override_failure_message("%s %s %s" % [stage, look, p.asset]).is_greater(0.6)
	assert_str(P0Garden.look_house("a")).is_equal("house_barn")
	assert_str(P0Garden.look_house("b")).is_equal("house_dome")
	assert_str(P0Garden.look_house("")).is_equal("house_cottage")

func test_the_farm_shows_the_views_looks_and_the_cards_preview() -> void:
	var bp := P0Garden.blueprint()
	var house := FarmProps.build("house", bp.cell_to_world(P0Garden.ANCHORS.house), 1.0, "cottage")
	add_child(auto_free(house))
	var fence: Node3D = auto_free(Fence.new())
	add_child(fence)
	fence.build(bp)
	var looks: Node3D = auto_free(Looks.new())
	add_child(looks)
	looks.build(bp, house, "cottage", fence)
	var cottage := house.mesh
	var v := _view(5)
	looks.sync(v)
	fence.sync(v)
	assert_str(looks.shown("porch")).is_equal("a")
	assert_str(looks.shown("kitchen_extension")).is_equal("")   # Lv8 not reached: nothing there
	assert_int(looks.parts("porch").size()).is_equal(2)          # two timber railings
	assert_str(fence.look).is_equal("a")
	looks.preview("porch", "b")   # LOOK-PICK's preview
	looks.sync(v)
	assert_str(looks.shown("porch")).is_equal("b")
	assert_int(looks.parts("porch").size()).is_equal(3)          # a landing and two rocks
	var used := _view(5, {"porch": "b"})   # Use landed: the preview lets go, the view keeps b
	looks.sync(used)
	assert_bool(looks.previews.has("porch")).is_false()
	assert_str(looks.shown("porch")).is_equal("b")
	fence.preview = "b"
	fence.sync(used)
	assert_str(fence.look).is_equal("b")   # Stone Wall
	var lv10 := _view(10, {"master_farmhouse": "b"})
	looks.sync(lv10)
	assert_object(house.mesh).is_not_same(cottage)
	assert_object(house.mesh).is_same(FarmArt.mesh_for("house_dome"))
