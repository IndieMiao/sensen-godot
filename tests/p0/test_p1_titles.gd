extends GdUnitTestSuite
## q(180) (§10.6.2): titles named from view.titles' stable ids, the name row's fitting rule, the Titles drawer and
## wearing one from the profile.

const P0Titles := preload("res://modules/p0/p0_titles.gd")
const TitlesDrawer := preload("res://scenes/p0/panels/p0_titles_drawer.gd")
const STORE := "user://test_p1_titles.json"
const TIPS := "user://test_p1_titles_tips.json"

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _view(list: Array, wearing = null, seq := 7) -> Dictionary:
	return {"seq": seq, "titles": {"list": list, "wearing": wearing}, "cooking": {"pages_total": 48}, "skills": {},
		"energy": {"value": 150, "max": 200}, "coins": 40, "bag": {"capacity": 25, "slots": []}, "profile": {"name": "Lin"}}

func test_every_title_has_its_name_and_where_it_came_from() -> void:
	var ids := ["homestead", "level:farming", "level:fishing", "level:cooking", "milestone:master_chef", "milestone:head_chef",
		"milestone:line_cook", "milestone:home_cook", "milestone:muscle_memory", "explorer:100", "explorer:3",
		"kindred:res_pip", "req:req_res_pip_5", "req:req_res_kai_3"]
	var v := _view(ids)
	assert_array(ids.map(func(id): var t := P0Titles.info(v, id); return "%s (%s)" % [t.name, t.source])).is_equal([
		"Homestead Master (Homestead Lv10)", "Master Gardener (Farming Lv10)", "Master Angler (Fishing Lv10)", "Chef (Cooking Lv10)",
		"Master Chef (Cookbook 48/48)", "Head Chef (Cookbook 36/48)", "Line Cook (Cookbook 20/48)", "Home Cook (Cookbook 8/48)",
		"Muscle Memory (Mastered 10)", "Globetrotter (Explorer Platinum)", "Wanderer (Explorer Bronze)",
		"Pip's Best Friend (Kindred · Pip)", "Route Buddy (Request · Pip's Big Route)", "Harbor Hand (Request · The Smoker's Secret)"])
	assert_dict(P0Titles.info(v, "req:req_gone")).is_empty()   # a newer server's id this client can't name
	assert_dict(P0Titles.info(v, "kindred:res_nobody")).is_empty()

func test_rows_keep_the_server_order_and_mark_the_worn_one() -> void:
	var v := _view(["milestone:home_cook", "kindred:res_pip", "req:req_gone", "req:req_res_pip_5"], "kindred:res_pip")
	var rows := P0Titles.rows(v)
	assert_array(rows.map(func(r): return [r.name, r.worn])).is_equal([["Home Cook", false], ["Pip's Best Friend", true], ["Route Buddy", false]])
	assert_str(P0Titles.worn_name(v)).is_equal("Pip's Best Friend")
	assert_str(P0Titles.worn_name(_view([]))).is_equal("")

func test_a_pick_shows_until_the_servers_answer_lands() -> void:
	var pending := {id = "milestone:home_cook", seq = 7}
	var v := _view(["milestone:home_cook", "kindred:res_pip"], "kindred:res_pip", 7)
	assert_str(P0Titles.worn(v, pending)).is_equal("milestone:home_cook")   # sent, not answered yet
	v.seq = 8
	v.titles.wearing = "milestone:home_cook"
	assert_str(P0Titles.worn(v, pending)).is_equal("milestone:home_cook")   # answered
	v.titles.wearing = "kindred:res_pip"
	assert_str(P0Titles.worn(v, pending)).is_equal("kindred:res_pip")   # a later state: the server's word

## q(180) ④ with a fixed 7 px a letter: the title gives way first, down to its first letter and `…`; only then the name.
func test_the_title_gives_way_before_the_name() -> void:
	var w := func(t: String) -> float: return 7.0 * t.length()
	var fit := func(n: String, t: String, width: float) -> Array:
		var f := P0Titles.fit(n, t, width, 8.0, 10.0, w, w)
		return [f.name, f.title]
	assert_array(fit.call("Lin", "Home Cook", 200.0)).is_equal(["Lin", "Home Cook"])
	# 10 letters 70 + 8 + 10: 112 left of 200 → 16 letters with the `…`
	assert_array(fit.call("Maximilian", "Granny Wu's Best Friend", 200.0)).is_equal(["Maximilian", "Granny Wu's Bes…"])
	assert_array(fit.call("Maximilian", "Granny Wu's Best Friend", 102.0)).is_equal(["Maximilian", "G…"])   # just room for G…
	assert_array(fit.call("WWWWWWWWWWWWWWWW", "Granny Wu's Best Friend", 120.0)).is_equal(["WWWWWWWWWWW…", "G…"])   # 120−8−10−14 = 88: 11 W and `…`
	assert_array(fit.call("WWWWWWWWWWWWWWWW", "", 70.0)).is_equal(["WWWWWWWWW…", ""])
	assert_array(fit.call("Lin", "", 70.0)).is_equal(["Lin", ""])
	assert_str(P0Titles.cut("Best Friend", 42.0, w)).is_equal("Best…")   # the space before `…` is dropped

func _row(who: String, title: String, width := 264.0) -> P0ProfilePage._NameRow:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(width, 40)
	add_child(auto_free(host))
	var row := P0ProfilePage._NameRow.new(who, title)
	host.add_child(row)
	row.size = Vector2(width, row.get_combined_minimum_size().y)
	return row

## The frames' two longest cases in the theme's own fonts (安其拉 769e4881: 264 px for the name and the title):
## PROFILE-1-TITLE-LONG fits whole, PROFILE-1-TITLE-CUT cuts the title to `Granny Wu's Best F…`, › always there.
func test_the_frames_longest_name_and_title() -> void:
	var long := _row("Maximilian Woods", "Granny Wu's Best Friend")
	await get_tree().process_frame
	assert_str(long.name_label.text).is_equal("Maximilian Woods")
	assert_str(long.title_label.text).is_equal("Granny Wu's Best Friend")
	assert_float(long.chevron.position.x + long.chevron.size.x).is_less_equal(264.0)
	var cut := _row("MAXIMILIAN WOODS", "Granny Wu's Best Friend")
	await get_tree().process_frame
	assert_str(cut.name_label.text).is_equal("MAXIMILIAN WOODS")
	assert_str(cut.title_label.text).is_equal("Granny Wu's Best F…")
	assert_bool(cut.chevron.visible).is_true()
	assert_float(cut.chevron.position.x + cut.chevron.size.x).is_less_equal(264.0)

## The title and its › tap as one, 44 high, centred on the name's line, which keeps the name's own height.
func test_the_title_taps_44_high_and_the_line_keeps_its_height() -> void:
	var row := _row("Lin", "Home Cook")
	await get_tree().process_frame
	assert_float(row.size.y).is_equal(row.name_label.get_minimum_size().y)
	assert_float(row.hit.size.y).is_equal(44.0)
	assert_float(row.hit.position.y + row.hit.size.y * 0.5).is_equal_approx(row.size.y * 0.5, 0.01)
	assert_float(row.hit.position.x).is_equal(row.title_label.position.x)
	assert_float(row.hit.position.x + row.hit.size.x).is_greater_equal(row.chevron.position.x + row.chevron.size.x)
	assert_float(row.title_label.position.x - (row.name_label.position.x + row.name_label.size.x)).is_equal(8.0)
	assert_float(row.chevron.position.x - (row.title_label.position.x + row.title_label.size.x)).is_equal(4.0)
	var bare := _row("Lin", "")
	await get_tree().process_frame
	assert_bool(bare.title_label.visible or bare.chevron.visible or bare.hit.visible).is_false()   # no title: no ›, nothing to tap

func test_the_drawer_lists_the_titles_and_a_row_wears_one() -> void:
	assert_float(TitlesDrawer.height_for(5)).is_equal(388.0)   # TITLES 2595:153099: five rows
	assert_float(TitlesDrawer.height_for(6)).is_equal(446.0)
	assert_float(TitlesDrawer.height_for(12)).is_equal(447.0)   # MAP-8's at most, scrolling past it
	var v := _view(["milestone:home_cook", "kindred:res_pip", "req:req_res_pip_5"], "milestone:home_cook")
	var d: UiDrawer = auto_free(TitlesDrawer.new(P0Titles.rows(v)))
	var labels := d.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	assert_array(labels).is_equal(["Titles", "Tap a title to wear it", "Home Cook", "Cookbook 8/48", "Pip's Best Friend",
		"Kindred · Pip", "Route Buddy", "Request · Pip's Big Route"])
	var rows: Array = d.list.get_children()
	assert_array(rows.map(func(r): return (r as Control).custom_minimum_size.y)).is_equal([58.0, 58.0, 58.0])
	assert_array(rows.map(func(r): return r.find_child("Worn", true, false) != null)).is_equal([true, false, false])
	var got := []
	d.connect(&"title_picked", func(id: String): got.append(id))
	d.close_requested.connect(func(): got.append("close"))
	(rows[1] as Button).pressed.emit()
	(rows[0] as Button).pressed.emit()   # the worn one only closes
	assert_array(got).is_equal(["kindred:res_pip", "close"])

func _ui(v: Dictionary) -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(v)
	return ui

## Profile › title › Titles › a row: wear_title goes out, the profile is back with the new title at once.
func test_wearing_a_title_from_the_profile() -> void:
	var v := _view(["milestone:home_cook", "kindred:res_pip"], "milestone:home_cook")
	var ui: P0Ui = await _ui(v)
	var sent := []
	ui.command.connect(func(cmd: Dictionary): sent.append(cmd))
	ui.open_profile()
	await await_idle_frame()
	assert_str(ui._profile.name_row.title_label.text).is_equal("Home Cook")
	ui._profile.name_row.hit.pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("titles")
	var d: UiDrawer = ui._modal.find_children("*", "UiDrawer", true, false)[0]
	(d.list.get_child(1) as Button).pressed.emit()
	await await_idle_frame()
	assert_array(sent).is_equal([{"type": "wear_title", "id": "kindred:res_pip"}])
	assert_str(ui.modal_kind).is_equal("profile")
	assert_str(ui._profile.name_row.title_label.text).is_equal("Pip's Best Friend")   # before the answer lands
	var answered := _view(["milestone:home_cook", "kindred:res_pip"], "kindred:res_pip", 8)
	ui.set_view(answered)
	ui._profile.refresh(answered)
	await await_idle_frame()   # the rows refresh replaced are freed
	assert_str(ui._profile.name_row.title_label.text).is_equal("Pip's Best Friend")

## Close above the Titles drawer, and a tap on the scrim, go back to the profile, not out to the world.
func test_closing_titles_goes_back_to_the_profile() -> void:
	var ui: P0Ui = await _ui(_view(["milestone:home_cook"], "milestone:home_cook"))
	ui.open_profile()
	await await_idle_frame()
	ui._profile.name_row.hit.pressed.emit()
	await await_idle_frame()
	(ui._modal.find_children("*", "UiCloseButton", true, false)[0] as Button).pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("profile")
	ui._profile.name_row.hit.pressed.emit()
	await await_idle_frame()
	ui.back_modal()   # the scrim's tap
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("profile")
