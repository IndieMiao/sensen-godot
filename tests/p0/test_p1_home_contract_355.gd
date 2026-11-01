extends GdUnitTestSuite
## 355 A client-only fixtures. Values deliberately vary from r9: views/content own all calibrated numbers.

const HomePanel = preload("res://scenes/p0/home/p0_home_panel.gd")
var _content: Dictionary

func before_test() -> void:
	_content = P0Logic.content()
	P0Logic._content = _content.duplicate(true)
	P0Logic._content.homestead.max_level = 17
	P0Logic._content.bag_upgrades = [
		{id="bag_upgrade_1", name="Bag Upgrade I", price=60, capacity=30},
		{id="bag_upgrade_2", name="Bag Upgrade II", price=150, capacity=35, requires="bag_upgrade_1"},
		{id="bag_upgrade_3", name="Bag Upgrade III", price=300, capacity=40, requires="bag_upgrade_2"},
		{id="bag_upgrade_4", name="Bag Upgrade IV", price=600, capacity=45, requires="bag_upgrade_3"}]

func after_test() -> void:
	P0Logic._content = _content
	for p in ["user://test_355_home_bar.json", "user://test_355_home_tips.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

static func view(level := 5) -> Dictionary:
	var next = null if level == 17 else {level=level+1, coins={need=120, have=300},
		skills=[{skill="farming",need=3,have=3},{skill="fishing",need=3,have=2},{skill="cooking",need=2,have=1}],
		travel=null, materials=[{id="wood",name="Timber",need=6,have=6}], energy=250, meals=250,
		energy_gain=50, plots=18, unlocks=["big_pot"], can_upgrade=false}
	if level >= 15 and next != null:
		next.energy_gain=0
		next.travel={stamps={need=6,have=4},climates={need=1,have=0}}
	return {homestead={level=level,max=17,plots={now=16,max=41},next=next,unlocks={}},
		energy={value=180,max=240},bag={capacity=25,slots=[]},
		skills={farming={level=3,xp=100},fishing={level=2,xp=50},cooking={level=1,xp=0}},firsts=["harvest:crop_radish"]}

func test_separate_skill_and_travel_tiles_and_first_gap_follow_contract_order() -> void:
	var v := view(16)
	var p := P0Logic.home_panel(v)
	assert_array(p.tiles.map(func(t): return t.id)).is_equal(["wood","coins","skill_farming","skill_fishing","skill_cooking","stamps","climates"])
	assert_array(p.tiles.slice(2,5).map(func(t): return t.icon)).is_equal(["hoe","rod","pot"])
	assert_str(p.reason).is_equal("Fishing Lv3 needed · now 2")
	v.homestead.next.materials[0].have=2
	assert_str(P0Logic.home_panel(v).reason).is_equal("Need 4 more Timber")
	v.homestead.next.materials[0].have=6
	v.homestead.next.coins.have=100
	assert_str(P0Logic.home_panel(v).reason).is_equal("Need 20 more coins")
	v.homestead.next.coins.have=300
	v.homestead.next.skills[1].have=3
	assert_str(P0Logic.home_panel(v).reason).is_equal("Cooking Lv2 needed · now 1")
	v.homestead.next.skills[2].have=2
	assert_str(P0Logic.home_panel(v).reason).is_equal("6 stamps needed · now 4")
	v.homestead.next.travel.stamps.have=6
	assert_str(P0Logic.home_panel(v).reason).is_equal("Visit 1 more climate")
	v.homestead.next.travel.climates.need=3
	assert_str(P0Logic.home_panel(v).reason).is_equal("Visit 3 more climates")
	v.homestead.next.travel.climates.have=3
	assert_str(P0Logic.home_panel(v).reason).is_empty()
	assert_str(P0Logic.home_panel(v,false).reason).is_equal("At home")

func test_optional_gates_absent_and_fields_and_footer_read_view_values() -> void:
	var v := view()
	v.homestead.next.skills.resize(2)
	v.homestead.next.energy_gain=37
	v.homestead.plots.now=31
	v.homestead.next.plots=36
	var p := P0Logic.home_panel(v)
	assert_array(p.tiles.map(func(t): return t.id)).is_equal(["wood","coins","skill_farming","skill_fishing"])
	assert_str(p.footer).is_equal("Upgrading is free of Energy · +37 Energy")
	assert_dict(p.changes[1]).is_equal({icon="field",text="Fields 36",note="+5 to till"})
	v.homestead.next.plots=31
	v.homestead.next.energy_gain=0
	v.homestead.next.skills=[]
	assert_bool(P0Logic.home_panel(v).changes.any(func(c):return c.icon=="field")).is_false()
	assert_str(P0Logic.home_panel(v).footer).is_equal("Upgrading is free of Energy")
	assert_array(P0Logic.home_panel(v).tiles.map(func(t):return t.id)).is_equal(["wood","coins"])

func test_max_and_decor_cap_follow_authoritative_cap_not_level_ten_or_seventeen() -> void:
	var v := view(17)
	var p := P0Logic.home_panel(v)
	assert_str(p.subtitle).is_equal("Max level for now")
	assert_bool(p.button).is_false()
	assert_array(p.tiles).is_empty()
	v.homestead.max=19
	assert_str(P0Logic.home_panel(v).subtitle).is_empty()
	assert_str(P0Decor.cap_line(v)).contains("Homestead Lv18")
	v.homestead.level=19
	assert_str(P0Decor.cap_line(v)).contains("Store one to place this")
	assert_bool(P0Logic.home_panel(v).button).is_false()

func test_upgrade_event_gain_is_actual_at_any_level_and_bag_prices_are_content_driven() -> void:
	var v := view()
	for level in [5,15,16,17]:
		for gain in [50,17,0]:
			assert_str(P0Logic.home_moment(v,{level=level,energy=gain}).subtitle).is_equal("Max Energy 240"+(" · +%d Energy"%gain if gain>0 else ""))
	for i in 4:
		var tier: Dictionary=P0Logic._content.bag_upgrades[i]
		tier.price=63+i*137
		v.homestead.next.unlocks=[tier.id]
		var line: String="%s · %d coins"%[tier.name,tier.price]
		assert_str(P0Logic.home_panel(v).changes[-1].text).is_equal(line)
		assert_str(P0Logic.home_moment(v,{level=16,unlocks=[tier.id]}).detail).is_equal(line)
	v.bag.capacity=40
	assert_str(P0Logic.bag_tier_note(v,"bag_upgrade_4")).is_equal("Bag 40 → 45")

func test_unlock_ids_use_existing_icons_and_removed_or_no_row_ids_stay_hidden() -> void:
	var v := view()
	var ids := ["healing_potion","vein_mines","iron_sword","decor_set_1","decor_set_2","orchard_10","sprinklers_12","fourth_stove"]
	v.homestead.next.unlocks=ids
	var p := P0Logic.home_panel(v)
	assert_int(p.changes.size()).is_equal(2+ids.size())
	for row in p.changes:
		assert_bool(ResourceLoader.exists("res://assets/p0/icons/%s.svg"%row.icon)).is_true()
	v.homestead.next.unlocks=["city_gather","pip_first_dive","stall_upgrade","travel_gates","old_tree","clay_bank","plots_40","plots_48","long_haul_ticket","trip_7"]
	assert_int(P0Logic.home_panel(v).changes.size()).is_equal(2)
	assert_str(P0Logic.home_moment(v,{level=16,unlocks=v.homestead.next.unlocks}).detail).is_empty()

func test_today_remains_early_only_and_requires_every_listed_skill() -> void:
	var v := view(1)
	v.homestead.next.materials=[]
	assert_dict(P0Logic.homestead_row(v)).is_empty()
	for s in v.homestead.next.skills:s.have=s.need
	assert_str(P0Logic.homestead_row(v).row.go).is_equal("sign")
	v.homestead.level=3
	assert_dict(P0Logic.homestead_row(v)).is_empty()

func _ui(v: Dictionary) -> P0Ui:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.quick_store="user://test_355_home_bar.json"
	ui.tips_path="user://test_355_home_tips.json"
	add_child(ui)
	ui.set_view(v)
	ui.set_place("San Francisco · Homestead")
	ui.set_surface("farm")
	return ui

func test_all_gate_tiles_wrap_and_skill_source_navigation_returns_to_home() -> void:
	var v := view(16)
	for id in ["stone","fiber","clay","copper_ore","quartz","hardwood","rock_salt","iron_ore","coal"]:
		v.homestead.next.materials.append({id=id,name=P0Logic.item_name(v,id),need=8,have=2})
	var ui := _ui(v)
	HomePanel.open(ui)
	await await_idle_frame()
	var tiles := ui.find_children("*","UiNeedTile",true,false)
	assert_int(tiles.size()).is_equal(16)
	for tile in tiles:
		assert_float(tile.get_global_rect().end.x).is_less_equal(ui.root.get_global_rect().end.x)
		assert_float(tile.size.x).is_greater_equal(tile.get_minimum_size().x)
	var fishing = tiles.filter(func(t):return t.item_name=="Fishing")[0]
	fishing.pressed.emit()
	await await_idle_frame()
	var source: UiNeedSource=ui.root.find_children("*","UiNeedSource",true,false)[0]
	assert_str(source.text).is_equal("Fishing Lv3 · now 2")
	source.show_pressed.emit()
	assert_str(ui.modal_kind).is_equal("skills")
	ui.back_modal()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("homestead")
	var maps := []
	ui.show_on_map.connect(func(target): maps.append(target))
	var stamps = ui.find_children("*","UiNeedTile",true,false).filter(func(t):return t.item_name=="Stamps" and not t.is_queued_for_deletion())[-1]
	stamps.pressed.emit()
	await await_idle_frame()
	source=ui.root.find_children("*","UiNeedSource",true,false)[0]
	source.show_pressed.emit()
	assert_array(maps).is_equal(["map"])

func test_skills_back_keeps_home_panels_original_return_destination() -> void:
	var ui := _ui(view())
	var returned := []
	ui.open_home_panel(func(): returned.append("profile"))
	await await_idle_frame()
	var fishing = ui.find_children("*","UiNeedTile",true,false).filter(func(t):return t.item_name=="Fishing")[0]
	fishing.pressed.emit()
	await await_idle_frame()
	var source: UiNeedSource=ui.root.find_children("*","UiNeedSource",true,false)[0]
	source.show_pressed.emit()
	assert_str(ui.modal_kind).is_equal("skills")
	ui.back_modal()
	assert_str(ui.modal_kind).is_equal("homestead")
	assert_array(returned).is_empty()
	ui.back_modal()
	assert_array(returned).is_equal(["profile"])

func test_travel_sources_show_map_and_refusal_details_have_readable_copy() -> void:
	var v := view(16)
	assert_dict(P0Logic.home_source(v,"stamps")).is_equal({text="Stamps · visit new cities",go="map"})
	assert_str(P0Logic.home_source(v,"climates").go).is_equal("map")
	var rt: P0Runtime=auto_free(P0Runtime.new())
	rt.ui.quick_store="user://test_355_home_bar.json"
	rt.ui.tips_path="user://test_355_home_tips.json"
	rt.session.transport=func(_m,_p,_b,_c):pass
	add_child(rt)
	rt.set_process(false)
	rt.session.set_process(false)
	for s in v.homestead.next.skills:s.have=s.need
	v.homestead.next.travel.stamps.have=6
	v.homestead.next.travel.climates.have=1
	rt.session.view=v
	rt._on_refused("travel_short",{kind="stamps",need=8,have=5},{type="homestead_upgrade"})
	assert_str(rt.ui.toast_text()).is_equal("8 stamps needed · now 5")
	rt._on_refused("travel_short",{kind="climates",need=3,have=1},{type="homestead_upgrade"})
	assert_str(rt.ui.toast_text()).is_equal("Visit 2 more climates")
	rt._on_refused("skills_short",{skill="cooking",need=8,have=6},{type="homestead_upgrade"})
	assert_str(rt.ui.toast_text()).is_equal("Cooking Lv8 needed · now 6")
