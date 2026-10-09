extends GdUnitTestSuite
## FISH-6 Fish-dex (SGODOT-233; 482:171 R1): Kinds NeedTile and the next reward, rarity sections of six-column fish
## cells (caught ×N / UNCOLLECTED silhouette), new catches ring once; a gated silhouette opens the gate card (q(57)),
## any other cell the fish card, and both come back to the dex.

const STORE := "user://test_p0_fish_dex.json"
const TIPS := "user://test_p0_fish_dex_tips.json"

var ui: P0Ui

func _view(fishing_xp := 100) -> Dictionary:
	return {
		"coins": 40, "energy": {"value": 150, "max": 200},
		"skills": {"fishing": {"level": 2, "xp": fishing_xp}, "farming": {"level": 1, "xp": 0}, "cooking": {"level": 1, "xp": 0}},
		"names": {"fish_crucian": "Pond Crucian", "fish_carp": "Common Carp", "fish_perch": "River Perch", "fish_koi": "Golden Koi"},
		"fishing": {"rod": "Starter Rod", "rod_reach": 2, "dex": [
			{"id": "fish_crucian", "rarity": 1, "level": 1, "where": ["pond", "river"], "caught": 23},
			{"id": "fish_carp", "rarity": 1, "level": 1, "where": ["pond", "river"], "caught": 0},
			{"id": "fish_perch", "rarity": 2, "level": 2, "where": ["river", "pond"], "caught": 2},
			{"id": "fish_koi", "rarity": 3, "level": 4, "where": ["pond"], "caught": 0, "seen": true}]},
		"gear": {"rods": [{"id": "rod_reed", "name": "Reed Rod", "reach": 3, "level": 3, "price": 80, "owned": false}]},
		"bag": {"capacity": 25, "slots": []},
		"profile": {"name": "Mia"},
	}

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TIPS))
	ui = P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_surface("farm")

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TIPS))

func _dex() -> P0FishDex:
	var found := ui.find_children("*", "P0FishDex", true, false).filter(func(d): return not d.is_queued_for_deletion())
	return found[0] if not found.is_empty() else null

func test_the_dex_reads_sections_kinds_and_what_is_next() -> void:
	var d := P0FishDex.dex_data(_view())
	assert_that([d.got, d.total]).is_equal([2, 4])
	assert_array(d.sections.map(func(s): return s.name)).is_equal(["Common", "Fine", "Rare"])
	assert_array(d.sections[0].fish.map(func(f): return [f.id, f.caught, f.icon])).is_equal(
		[["fish_crucian", 23, "fish_crucian"], ["fish_carp", 0, "fish_unknown"]])
	# This season's four fish can't reach the 10-kinds reward: only the rod's reach, what holds the rest back.
	assert_array(d.next).is_equal(["Starter Rod lands up to Fine fish", ""])
	var v := _view()
	for i in 16: v.fishing.dex.append({"id": "fish_x%d" % i, "rarity": 1, "level": 1, "caught": 1 if i < 7 else 0})
	assert_array(P0FishDex.dex_data(v).next).is_equal(["Next at 10 kinds", "+%d Energy" % int(P0Logic.content().rewards.fishdex[0][1])])

func test_caught_cells_count_and_the_rest_are_silhouettes() -> void:
	ui.open_fishdex()
	await await_idle_frame()
	var dex := _dex()
	assert_str(ui.modal_kind).is_equal("fishdex")
	var crucian: UiItemCell = dex.cells["fish_crucian"]
	assert_that([crucian.quantity, crucian.state]).is_equal(["×23", UiItemCell.State.DEFAULT])
	var carp: UiItemCell = dex.cells["fish_carp"]
	assert_that([carp.quantity, carp.state]).is_equal(["", UiItemCell.State.UNCOLLECTED])
	assert_float(carp._icon.modulate.a).is_equal_approx(UiTokens.OPACITY_ZERO_ICON, 0.001)

func test_new_catches_ring_once_after_the_drawer_is_up() -> void:
	ui.open_fishdex()
	await get_tree().create_timer(UiTokens.MOTION_DRAWER_MS / 1000.0 + 0.05).timeout
	assert_bool((_dex().cells["fish_crucian"] as UiItemCell).is_flashing()).is_true()
	ui.close_modal()
	await await_idle_frame()
	ui.open_fishdex()   # seen now: nothing rings
	await get_tree().create_timer(UiTokens.MOTION_DRAWER_MS / 1000.0 + 0.05).timeout
	assert_bool((_dex().cells["fish_crucian"] as UiItemCell).is_flashing()).is_false()

func test_a_gated_silhouette_opens_the_gate_card_and_back_returns_to_the_dex() -> void:
	ui.open_fishdex()
	await await_idle_frame()
	_dex().cell_pressed.emit("fish_koi")   # Golden Koi is Fishing Lv4, the player Lv2
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("gate")
	var sheet: UiInfoSheet = ui.find_children("*", "UiInfoSheet", true, false)[0]
	assert_str(sheet.spec().lead).is_equal("Fishing Lv4 keeps Golden Koi on the hook")
	ui.close_top_layer()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("fishdex")   # one layer at a time
	assert_bool(_dex().animate).is_false()

func test_other_cells_open_the_fish_card() -> void:
	ui.open_fishdex()
	await await_idle_frame()
	_dex().cell_pressed.emit("fish_crucian")
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("fish")
	var s := P0Logic.fish_card_spec(_view(), "fish_crucian")
	assert_array(s.facts).is_equal(["Caught ×23 · Pond · River", "Full XP"])
	assert_array(P0Logic.fish_card_spec(_view(), "fish_carp").facts).is_equal(["Not caught yet · Pond · River"])
	assert_that([P0Logic.xp_percent(3, 1), P0Logic.xp_percent(4, 1), P0Logic.xp_percent(9, 1)]).is_equal([75, 50, -1])

func test_no_tab_row_and_the_profile_tile_opens_the_dex() -> void:
	ui.open_fishdex()
	await await_idle_frame()
	assert_int(_dex().find_children("*", "UiFilterChip", true, false).size()).is_equal(0)   # Fish-dex only in P0
	ui.close_modal()
	ui.open_profile()
	await await_idle_frame()
	var page := ui._profile
	ui._profile.collection_pressed.emit("fish")
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("fishdex")
	assert_object(ui._modal.get_child(0)).is_same(page)   # 256 ⑧: the profile stays behind the dex …
	_dex().cell_pressed.emit("fish_crucian")
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("fish")
	assert_object(ui._modal.get_child(0)).is_same(page)   # … and behind the card the dex opens
	ui.close_top_layer()   # the card: back to the dex
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("fishdex")
	ui.close_top_layer()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("profile")
	ui._profile.collection_pressed.emit("pages")   # no read-only Cookbook yet: nothing opens, no placeholder
	assert_str(ui.modal_kind).is_equal("profile")
	assert_str(ui.toast_text()).is_empty()

func test_a_cookbook_guide_shows_only_when_a_host_opens_it() -> void:
	var gate := {"skill": "cooking", "level": 4, "what": "3rd slot"}
	ui.open_gate_card(gate)
	assert_bool(ui.find_children("*", "UiInfoSheet", true, false)[0].spec().buttons.is_empty()).is_true()
	var asked := []
	ui.panel_requested.connect(func(p): asked.append(p))
	var sheet := ui.open_gate_card(gate)
	assert_array(sheet.spec().buttons.map(func(b): return b.label)).is_equal(["Cookbook"])
	sheet.action_requested.emit(&"guide", "gate", {"go": "cookbook"})
	assert_array(asked).is_equal(["cookbook"])
