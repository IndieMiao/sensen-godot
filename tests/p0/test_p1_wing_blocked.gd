extends GdUnitTestSuite
## Homestead Lv8's Kitchen Wing and what stands on its cells (q(303), SGODOT-450; 不知火舞 450 v1.2, 后裔's interface):
## the cells come from content decor.yard.wing, as the server reads them; from Lv8 they are the house's (`Space taken`).
## Before the upgrade into it, pieces or facilities on them are its last gap (homestead.next.blocked): HOME-1's key grey
## with `Space taken`, a tap `Space taken · clear it first`, Today's `Homestead Lv8 · Space taken` to do now with no red
## dot and a Show into Decorate. A save already past Lv8 with them held (homestead.wing_blocked): `Kitchen Wing · Space
## taken` (the Master Farmhouse's name from Lv15), the same Show, no dot.

const WING := [Vector2i(5, 17), Vector2i(5, 18), Vector2i(6, 18), Vector2i(7, 16), Vector2i(7, 17), Vector2i(7, 18), Vector2i(8, 18)]

static func _held() -> Dictionary:
	return {"cells": [[7, 16], [6, 18]], "pieces": [{"uid": 3, "item": "deco_planter", "x": 7, "y": 16, "rot": 0}],
		"facilities": [{"id": 1, "kind": "compost_bin", "x": 6, "y": 18}]}

## Lv7 with everything for Lv8 had: only the wing's cells can stop it.
static func _lv7() -> Dictionary:
	return {
		"coins": 900, "energy": {"value": 150, "max": 200},
		"skills": {"farming": {"level": 6, "xp": 0}, "fishing": {"level": 5, "xp": 0}, "cooking": {"level": 5, "xp": 0}},
		"bag": {"capacity": 25, "slots": []}, "firsts": ["harvest:crop_radish"],
		"homestead": {"level": 7, "next": {"level": 8, "coins": {"need": 600, "have": 900}, "skills": [], "materials": [],
			"energy": 260, "meals": 4, "unlocks": ["kitchen_extension"], "can_upgrade": true}},
		"decor": {"placed": [{"uid": 3, "id": "deco_planter", "x": 7, "y": 16, "rot": 0}], "cap": 48, "used": 1, "stored": {}},
		"mine": {"at": null, "records": {}},
	}

static func _home_row(v: Dictionary) -> Dictionary:
	for r in P0Logic.today_rows(v):
		if str(r.line).begins_with("Homestead") or str(r.line).begins_with("Upgrade to Homestead"): return r
	return {}

func test_the_wing_cells_are_the_contents_and_the_houses_from_lv8() -> void:
	assert_array(P0Decor.wing_cells()).contains_exactly_in_any_order(WING)
	assert_int(int(P0Decor.wing().homestead)).is_equal(8)
	var v := {"homestead": {"level": 7}, "decor": {"placed": [], "cap": 48, "stored": {}}}
	for c in WING: assert_str(P0Decor.reason(v, "deco_planter", c)).override_failure_message(str(c)).is_equal("")
	v.homestead.level = 8
	for c in WING: assert_str(P0Decor.reason(v, "deco_planter", c)).override_failure_message(str(c)).is_equal("Space taken")
	assert_str(P0Decor.reason(v, "deco_planter", Vector2i(4, 17))).is_equal("")   # beside the wing: free as before
	assert_str(P0Decor.reason(v, "deco_bench", Vector2i(4, 17))).is_equal("Space taken")   # a 2×1 reaching (5, 17)
	v.homestead.level = 15   # the Master Farmhouse keeps them
	assert_str(P0Decor.reason(v, "deco_planter", Vector2i(8, 18))).is_equal("Space taken")
	assert_bool(P0Decor.wing_cells().any(func(c): return P0Decor.nearest_spot(v, "deco_planter", 0, Vector2i(6, 17)) == c)).is_false()

func test_held_reads_the_servers_shape_and_nothing_held_is_none() -> void:
	var v := _lv7()
	assert_dict(P0Decor.next_blocked(v)).is_empty()   # an older server, or nothing on the cells: no key
	v.homestead.next.blocked = _held()
	assert_array(P0Decor.held_cells(P0Decor.next_blocked(v))).is_equal([Vector2i(7, 16), Vector2i(6, 18)])
	assert_int(int(P0Decor.next_blocked(v).pieces[0].uid)).is_equal(3)
	v.homestead.next.blocked = {"cells": [], "pieces": [], "facilities": []}
	assert_dict(P0Decor.next_blocked(v)).is_empty()
	v.homestead.next = null   # the top level
	assert_dict(P0Decor.next_blocked(v)).is_empty()
	v.homestead.wing_blocked = _held()
	assert_dict(P0Decor.wing_blocked(v)).is_not_empty()

func test_home1_greys_upgrade_with_space_taken_as_the_last_gap() -> void:
	var v := _lv7()
	var p := P0Logic.home_panel(v)
	assert_str(str(p.reason)).is_empty()   # nothing held: Upgrade
	v.homestead.next.blocked = _held()
	p = P0Logic.home_panel(v)
	assert_str(str(p.reason)).is_equal("Space taken")
	assert_str(str(p.tap)).is_equal("Space taken · clear it first")
	assert_bool(bool(p.get("blocked", false))).is_true()
	v.homestead.next.coins.have = 500   # a gap before it says itself first
	p = P0Logic.home_panel(v)
	assert_str(str(p.reason)).is_equal("Need 100 more coins")
	assert_bool(bool(p.get("blocked", false))).is_false()
	assert_str(str(P0Logic.home_panel(v, false).reason)).is_equal("At home")   # away: as before

func test_today_says_space_taken_to_do_now_without_a_dot() -> void:
	var v := _lv7()
	assert_str(str(_home_row(v).line)).is_equal("Upgrade to Homestead Lv8")
	v.homestead.next.blocked = _held()
	var row := _home_row(v)
	assert_str(str(row.line)).is_equal("Homestead Lv8 · Space taken")
	assert_str(str(row.icon)).is_equal("deco_planter")
	assert_str(str(row.go)).is_equal(P0Logic.DECORATE_GO)
	assert_str(str(row.dot)).is_empty()
	assert_bool(bool(row.get("home_request", false))).is_true()   # a tap off its Show opens HOME-1
	assert_bool(bool(P0Logic.homestead_row(v).now)).is_true()
	assert_array(P0Logic.today_dots(P0Logic.today_rows(v))).is_empty()
	v.homestead.next.coins.have = 500   # coins first, as on HOME-1
	assert_str(str(_home_row(v).line)).is_equal("Homestead Lv8 · 100 coins to go")

func test_a_save_past_lv8_says_its_look_waits_on_the_cells() -> void:
	var v := _lv7()
	v.homestead = {"level": 9, "next": null, "wing_blocked": _held()}
	var rows := P0Logic.today_rows(v)
	var wing: Array = rows.filter(func(r): return str(r.line).ends_with("· Space taken"))
	assert_int(wing.size()).is_equal(1)
	assert_str(str(wing[0].line)).is_equal("Kitchen Wing · Space taken")
	assert_str(str(wing[0].go)).is_equal(P0Logic.DECORATE_GO)
	assert_str(str(wing[0].dot)).is_empty()
	assert_array(P0Logic.today_dots(rows)).is_empty()
	v.homestead.level = 15
	assert_str(str(P0Logic.wing_row(v).line)).is_equal("Master Farmhouse · Space taken")
	v.homestead.erase("wing_blocked")
	assert_dict(P0Logic.wing_row(v)).is_empty()

func test_decorate_is_a_farm_target() -> void:
	assert_bool(P0Ui.home_target(P0Logic.DECORATE_GO)).is_true()
	assert_str(P0Ui.show_label(P0Logic.DECORATE_GO, "home", true)).is_equal("Show")
	assert_str(P0Ui.show_label(P0Logic.DECORATE_GO, "map", true)).is_equal("Show")

# ---------------------------------------------------------------- the screens (frames B1, B5, B6)
const HomePanel = preload("res://scenes/p0/home/p0_home_panel.gd")
const Looks = preload("res://scenes/p0/p0_looks.gd")
const Fence = preload("res://scenes/p0/p0_fence.gd")
const FarmProps = preload("res://modules/farm/farm_props.gd")
const FarmArt = preload("res://modules/farm/farm_art.gd")
const GardenScenery = preload("res://scenes/p0/p0_garden_scenery.gd")

func _ui(v: Dictionary) -> P0Ui:
	var ui: P0Ui = auto_free(P0Ui.new())
	add_child(ui)
	ui.set_view(v)
	return ui

## B1: the grey key says `Space taken`; a tap is an Error `Space taken · clear it first` with Decorate ›, which goes
## into Decorate on the held cells (P0Farm.p0_show_spot) — out of the farmhouse first when there.
func test_home1s_grey_key_offers_decorate() -> void:
	var v := _lv7()
	v.homestead.next.blocked = _held()
	var ui := _ui(v)
	ui.space = "home"
	HomePanel.open(ui)
	var button: UiCommandButton = ui.find_children("*", "UiCommandButton", true, false)[0]
	assert_str(button.reason).is_equal("Space taken")
	button.unavailable_pressed.emit(button.reason)
	assert_str(ui.toast_text().replace("\n", " ").replace(" · ", " ")).is_equal("Space taken clear it first")   # its lines: the frame's width
	var went: Array = []
	ui.show_spot.connect(func(w): went.append(w))
	ui._on_toast_action(P0Ui.DECORATE_ACTION)
	assert_array(went).is_equal([P0Logic.DECORATE_GO])
	assert_str(ui.modal_kind).is_empty()   # HOME-1 closed
	ui.space = "pond"   # nowhere else to decorate
	ui._on_toast_action(P0Ui.DECORATE_ACTION)
	assert_int(went.size()).is_equal(1)

## The server's homestead_blocked (a view not caught up): the same words, and its detail kept for Decorate's marks.
func test_a_blocked_upgrade_says_it_and_keeps_what_holds_the_cells() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.view = _lv7()
	rt._on_refused("homestead_blocked", _held(), {"type": "homestead_upgrade"})
	assert_str(rt.ui.toast_text().replace("\n", " ").replace(" · ", " ")).is_equal("Space taken clear it first")
	assert_array(P0Decor.held_cells(rt.held_detail)).is_equal([Vector2i(7, 16), Vector2i(6, 18)])

func _farm_looks() -> Array:
	var bp := P0Garden.blueprint()
	var house := FarmProps.build("house", bp.cell_to_world(P0Garden.ANCHORS.house), 1.0, "cottage")
	add_child(auto_free(house))
	var fence: Node3D = auto_free(Fence.new())
	add_child(fence)
	fence.build(bp)
	var looks: Node3D = auto_free(Looks.new())
	add_child(looks)
	looks.build(bp, house, "cottage", fence)
	return [looks, house]

static func _looks_view(level: int) -> Dictionary:
	var rows: Array = []
	for l in P0Logic.look_stages():
		rows.append({"id": l.id, "level": l.level, "name": l.name, "a": l.a, "b": l.b, "look": "a" if level >= int(l.level) else null})
	return {"homestead": {"level": level, "looks": rows, "next": null}}

## B5 / B6: a save past Lv8 with the wing's cells held shows no wing, old or new, and the old house; cleared between two
## views, the wing pops in and says `Lv8 look · Kitchen Wing`; a save that opens already clear says nothing.
func test_a_held_wing_is_not_drawn_until_its_cells_clear() -> void:
	var made := _farm_looks()
	var looks: Node3D = made[0]
	var said: Array = []
	looks.wing_cleared.connect(func(stage): said.append("Lv%d look · %s" % [int(stage.level), str(stage.name)]))
	var v := _looks_view(9)
	v.homestead.wing_blocked = _held()
	looks.sync(v)
	assert_str(looks.shown("kitchen_extension")).is_empty()
	assert_array(looks.parts("kitchen_extension")).is_empty()
	assert_bool(looks.waits()).is_true()
	assert_bool(looks.wing_model_shown()).is_false()
	v.homestead.erase("wing_blocked")
	looks.sync(v)
	assert_str(looks.shown("kitchen_extension")).is_equal("a")
	assert_array(said).is_equal(["Lv8 look · Kitchen Wing"])
	assert_bool(looks.waits()).is_equal(P0Garden.WING_WAITS)
	var fresh: Node3D = _farm_looks()[0]   # a launch on a save already clear: no toast
	var quiet: Array = []
	fresh.wing_cleared.connect(func(s): quiet.append(s))
	fresh.sync(v)
	assert_array(quiet).is_empty()
	var lv15: Array = _farm_looks()   # the Master Farmhouse: the old house while held
	var house: MeshInstance3D = lv15[1]
	var w15 := _looks_view(15)
	w15.homestead.wing_blocked = _held()
	(lv15[0] as Node3D).sync(w15)
	assert_object(house.mesh).is_same(FarmArt.mesh_for(P0Garden.look_house("a", "cottage", true)))
	assert_array((lv15[0] as Node3D).parts("kitchen_extension")).is_empty()

## The grass, flowers and the bush on the wing's cells and (6, 17) are their own draw, hidden while the wing's model
## stands there; every other point of the dressing is where it was (the scatter's draws unchanged).
func test_the_dressing_on_the_wings_cells_hides_with_the_wing() -> void:
	var bp := P0Garden.blueprint()
	var scenery: Node3D = auto_free(GardenScenery.new())
	add_child(scenery)
	scenery.build(bp, "cottage")
	var dress: Node3D = scenery.find_child("WingDressing", false, false)
	var cells := GardenScenery.wing_dress_cells()
	var inside := 0
	for mm in dress.get_children():
		var m := (mm as MultiMeshInstance3D).multimesh
		for i in m.instance_count:
			assert_bool(cells.has(bp.world_to_cell(m.get_instance_transform(i).origin))).is_true()
			inside += 1
	assert_int(inside).is_greater(0)   # the bush at (6, 17) at least
	for mm in scenery.get_children():
		if not mm is MultiMeshInstance3D: continue
		var m := (mm as MultiMeshInstance3D).multimesh
		if str(mm.name) in ["TreeN0", "Tree0", "SteppingStone"]: continue
		for i in m.instance_count:
			assert_bool(cells.has(bp.world_to_cell(m.get_instance_transform(i).origin))).override_failure_message(str(mm.name)).is_false()
	scenery.show_wing(true)
	assert_bool(dress.visible).is_false()
	scenery.show_wing(false)
	assert_bool(dress.visible).is_true()

## Below Lv15 the house is the farm's own whether the wing is held or not: its porch stays as it stands when the wing
## clears or is held again — not rebuilt nor popped in again (周瑜 on #916).
func test_the_porch_stays_as_the_wing_is_held_or_cleared() -> void:
	var looks: Node3D = _farm_looks()[0]
	var v := _looks_view(9)
	v.homestead.wing_blocked = _held()
	looks.sync(v)
	var porch: Node3D = looks.parts("porch")[0]
	v.homestead.erase("wing_blocked")
	looks.sync(v)
	assert_object(looks.parts("porch")[0]).is_same(porch)
	assert_vector(porch.scale).is_equal(Vector3.ONE)
	v.homestead.wing_blocked = _held()
	looks.sync(v)
	assert_object(looks.parts("porch")[0]).is_same(porch)

## B5a: a save past Lv8 with the wing held is told on the launch's first farm view — after the launch cover is gone,
## an Error with Decorate ›; under the cover it ran out unseen (不知火舞 on #916).
func test_the_held_wing_is_said_once_the_launch_cover_is_gone() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt._launch_s = 0.5   # the launch cover is up
	rt.toast_on_arrival(P0Logic.HOME_BLOCKED_TAP, P0Ui.DECORATE_ACTION)
	for i in 3: await get_tree().process_frame
	assert_str(rt.ui.toast_text()).is_empty()
	rt._launch_s = -1.0
	rt._flush_arrival_toast()
	assert_str(rt.ui.toast_text().replace("\n", " ").replace(" · ", " ")).is_equal("Space taken clear it first")
	assert_int(rt.ui._toasts.current_severity()).is_equal(ToastLayer.Severity.ERROR)
	assert_str(rt.ui._toasts.current_action()).is_equal(P0Ui.DECORATE_ACTION)
