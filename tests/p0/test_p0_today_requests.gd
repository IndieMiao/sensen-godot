extends GdUnitTestSuite
## q(104) (李白 42d3f56c, 奕星 A): every taken request goes to Today — the Stall Board's, the Market Board's and the
## residents' — and untaken ones stay on their boards. A request ready to hand in leads (`… · Deliver to Old Kai`,
## Show on map at the place it is handed in); one still short follows what else can be done now, before the countdowns
## (`An Old Man's Catch · Rare fish 0/1`); a fish one points at the pond its ! hangs on. One whose fish the player cannot
## land yet has no Show, a small line `Fishing Lv4 needed`, and the whole row opens that fish's gate card — the
## Fish-dex silhouette's, the lowest-level fish of its rarity (Old Kai's Rare fish: Golden Koi). The first session keeps
## its tutorial request alone.

const STORE := "user://test_p0_today_requests.json"
const TIPS := "user://test_p0_today_requests_tips.json"
const KAI := "req_res_kai_1"

func _view(fishing := 2) -> Dictionary:
	return {
		"coins": 120, "energy": {"value": 150, "max": 200},
		"skills": {"farming": {"level": 2, "xp": 60}, "fishing": {"level": fishing, "xp": 70}, "cooking": {"level": 2, "xp": 40}},
		"names": {"fish_koi": "Golden Koi", "fish_crucian": "Pond Crucian", "fish_perch": "River Perch", "crop_radish": "Radish"},
		"bag": {"capacity": 25, "slots": []},
		# Joey's save (q(104)): Old Kai's Rare fish taken at Fishing Lv2.
		"residents": {"res_old_kai": {"request": {"id": KAI, "kind": "fish", "rarity": 3, "have": 0, "qty": 1, "ready": false},
			"request_state": "accepted"}},
	}

static func _lines(v: Dictionary) -> Array: return P0Logic.today_rows(v).map(func(r): return r.line)
static func _row(v: Dictionary, line: String) -> Dictionary:
	var found := P0Logic.today_rows(v).filter(func(r): return r.line == line)
	return found[0] if not found.is_empty() else {}

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

## Joey: the request is in Today, said as its pin's reason line says it, with no Show and `Fishing Lv4 needed` under it.
func test_a_fish_the_player_cannot_land_yet_says_the_level_it_needs() -> void:
	var r := _row(_view(), "An Old Man's Catch · Rare fish 0/1")
	assert_dict(r).is_not_empty()
	assert_that([r.state, r.tail, r.go, r.gate]).is_equal(["short", "Fishing Lv4 needed", "", "fish_koi"])

## At Fishing Lv4 it reads as before: no small line, and Show on map points at the pond its ! hangs on.
func test_at_the_level_the_row_points_at_the_marked_pond() -> void:
	var v := _view(4)
	v["map_markers"] = [{"place": "pond_san_francisco_03", "kind": "request", "why": {"request": KAI, "tracked": true}}]
	var r := _row(v, "An Old Man's Catch · Rare fish 0/1")
	assert_that([r.state, r.tail, r.go, r.has("gate")]).is_equal(["default", "", "pond:pond_san_francisco_03", false])

## Ready to hand in, it leads, Show on map at the outpost where its resident is (Old Kai at the Tackle Shop).
func test_a_request_ready_to_hand_in_leads() -> void:
	var v := _view(4)
	v.residents.res_old_kai.request.merge({"have": 1, "ready": true}, true)
	v["plots"] = [{"state": "sown", "crop": "crop_radish"}]
	var rows := P0Logic.today_rows(v)
	assert_that([rows[0].line, rows[0].go]).is_equal(["An Old Man's Catch · Deliver to Old Kai", "outpost:tackle"])
	assert_str(rows[1].line).is_equal("Water 1 sown plot · Free")

## The Market Board's taken requests too (a rarity: `Fine fish`), handed in at the market square; the Stall Board's at
## the stall; untaken ones are not in Today.
func test_market_and_stall_requests_taken_and_untaken() -> void:
	var v := _view(4)
	v.erase("residents")
	v["boards"] = {
		"stall": {"slots": [{"id": "req_stall_a", "title": "Crate of Radishes", "kind": "crop", "items": ["crop_radish"], "have": 2, "qty": 10, "status": "open"}]},
		"market": {"slots": [{"id": "req_dusk", "title": "Dusk Haul", "kind": "fish", "rarity": 2, "items": [], "have": 1, "qty": 4, "status": "accepted"}]}}
	assert_array(_lines(v)).contains(["Dusk Haul · Fine fish 1/4"]).not_contains(["Crate of Radishes · Radish 2/10"])
	v.boards.market.slots[0].merge({"have": 4, "ready": true}, true)
	var rows := P0Logic.today_rows(v)
	assert_that([rows[0].line, rows[0].go]).is_equal(["Dusk Haul · Deliver at %s" % P0Outposts.by_role("market").name, "outpost:market"])
	v.boards.stall.slots[0].status = "accepted"
	v.boards.stall.slots[0].merge({"have": 10, "ready": true}, true)
	assert_array(_lines(v)).contains(["Crate of Radishes · Deliver at the Stall"])

## A request still short comes after what else can be done now and before the countdowns; a plot request reads `Plots`.
func test_a_short_request_follows_the_now_rows_and_precedes_the_countdowns() -> void:
	var v := _view(4)
	v.residents["res_pip"] = {"request": {"id": "req_res_pip_2", "kind": "sow", "have": 3, "qty": 5, "ready": false}, "request_state": "accepted"}
	v.residents.erase("res_old_kai")
	v["plots"] = [{"state": "sown", "crop": "crop_radish"}, {"state": "growing", "crop": "crop_radish", "ready_in": 3600000}]
	assert_array(_lines(v)).is_equal(["Water 1 sown plot · Free", "Five Little Plots · Plots 3/5", "Radishes ready in 1h"])

## The first session shows its tutorial request alone (the guide's own row).
func test_the_first_session_keeps_its_tutorial_request_alone() -> void:
	var v := _view()
	v["stall"] = {"board": {"requests": [{"id": P0Guide.TUTORIAL, "title": "Pond Catch", "item": "fish_crucian", "qty": 2, "have": 0, "status": "accepted"}]}}
	assert_array(_lines(v).filter(func(l): return l.begins_with("An Old Man's Catch"))).is_empty()

## On screen: the small line shows under the row, there is no Show, and a tap on the row opens Golden Koi's gate card —
## the Fish-dex silhouette's — whose Back returns to Today.
func test_the_row_opens_the_fishs_gate_card_and_back_returns_to_today() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_surface("farm")
	ui.open_today()
	await await_idle_frame()
	var panel: UiTodayPanel = ui.find_children("*", "UiTodayPanel", true, false)[0]
	var labels: Array = panel.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	assert_array(labels).contains(["An Old Man's Catch · Rare fish 0/1", "Fishing Lv4 needed"])
	assert_int(panel.find_children("*", "UiShowPill", true, false).size()).is_equal(0)
	var i := P0Logic.today_rows(ui.view).map(func(r): return r.line).find("An Old Man's Catch · Rare fish 0/1")
	panel.row_pressed.emit(i)
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("gate")
	var sheet: UiInfoSheet = ui.find_children("*", "UiInfoSheet", true, false)[0]
	var dex := P0Logic.gate_spec(ui.view, P0Logic.fish_gate(ui.view, "fish_koi"))   # the Fish-dex silhouette's card
	assert_that([sheet.spec().title, sheet.spec().lead]).is_equal([dex.title, dex.lead])
	assert_str(sheet.spec().lead).is_equal("Fishing Lv4 keeps Golden Koi on the hook")
	ui.close_top_layer()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("today")

## A real tap on the row (press and release in place) asks for its card; a drag does not.
func test_a_tap_on_a_tap_row_presses_it() -> void:
	var panel := UiTodayPanel.new([{"line": "An Old Man's Catch · Rare fish 0/1", "state": "short", "tail": "Fishing Lv4 needed", "tap": true}])
	add_child(auto_free(panel))
	await await_idle_frame()
	var got := []
	panel.row_pressed.connect(func(i): got.append(i))
	var row: HBoxContainer = panel.find_children("*", "HBoxContainer", true, false)[0]
	for at in [[Vector2(20, 10), Vector2(22, 11)], [Vector2(20, 10), Vector2(120, 10)]]:
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = down
			e.position = at[0] if down else at[1]
			row.gui_input.emit(e)
	assert_array(got).is_equal([0])
