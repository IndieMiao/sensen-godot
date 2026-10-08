extends GdUnitTestSuite
## The P0 Inbox (SGODOT-234; §12.5.2, q(50) / q(79), LOCK-14; INBOX-* / PARCEL-1…5): three tabs, parcels with Claim
## and Claim all, Updates for what expired or went back while the player was away, the bell's number.

const STORE := "user://test_p0_inbox.json"
const NOW := 1_800_000_000_000.0

func _view(free := 6, parcels := 3, updates: Array = [], waiting := 0) -> Dictionary:
	var ps: Array = []
	var items := [["seed_pumpkin", 2, "Welcome gift", 3_900_000.0], ["dish_herb_grilled_fish", 1, "Mia's gift meal", 18_720_000.0],
		["fish_perch", 7, "Request reward · Stall Board", 85_200_000.0]]
	for i in parcels:
		var it: Array = items[i % items.size()]
		ps.append({"key": "p%d" % i, "id": it[0], "qty": it[1], "source": it[2], "left": it[3], "can_claim": free > 0})
	var unread := updates.filter(func(u): return SHOWN.has(u.status) and not u.read).size()
	return {"coins": 230, "energy": {"value": 142, "max": 210},
		"names": {"seed_pumpkin": "Pumpkin Seeds", "dish_herb_grilled_fish": "Herb Grilled Fish", "fish_perch": "Perch", "bait_worm": "Worm Bait"},
		"bag": {"capacity": 25, "free": free, "slots": []},
		"inbox": {"limit": 8, "badge": ps.size() + unread, "waiting": waiting, "claim_slots": mini(free, ps.size()), "parcels": ps, "updates": updates}}

const SHOWN := ["expired", "returned"]

func before_test() -> void:
	UiCommandButton.offline = false   # a runtime left by an earlier suite may have gone offline (no server in tests)

func _upd(key: String, status: String, coins := 0, read := false, at := NOW - 7_200_000.0, id := "fish_perch", qty := 7, gift = null) -> Dictionary:
	var u := {"key": key, "id": id, "qty": qty, "source": "Fishing Lv2 reward", "at": at, "status": status, "coins": coins, "read": read}
	if gift != null: u["gift"] = gift
	return u

# ---------------------------------------------------------------- words (P0Inbox)
func test_the_page_that_opens_and_the_line_under_the_title() -> void:
	assert_str(P0Inbox.default_tab(_view(6, 3))).is_equal("parcels")
	assert_str(P0Inbox.default_tab(_view(6, 0, [], 2))).is_equal("parcels")   # only queued ones still open Parcels
	assert_str(P0Inbox.default_tab(_view(6, 0))).is_equal("updates")
	assert_str(P0Inbox.new_line(_view(6, 3))).is_equal("3 new")
	assert_str(P0Inbox.new_line(_view(6, 0, [_upd("u1", "expired", 18)]))).is_equal("1 new")
	assert_str(P0Inbox.new_line(_view(6, 0))).is_equal("Nothing new")

func test_the_parcels_page_head_rule_and_note() -> void:
	assert_str(P0Inbox.capacity_line(_view(6, 3))).is_equal("Bag 19/25 · 6 slots free")
	assert_str(P0Inbox.capacity_line(_view(1, 3))).is_equal("Bag 24/25 · 1 slot free")
	assert_str(P0Inbox.capacity_line(_view(0, 2))).is_equal("Bag 25/25 · Bag full")
	assert_str(P0Inbox.rule_line(_view(6, 3))).is_equal("Parcels 3/8 · Kept 24h · Claim needs a free slot")
	assert_str(P0Inbox.rule_line(_view(10, 3, [], 2))).is_equal("Parcels 3/8 · 2 more waiting · Kept 24h · Claim needs a free slot")
	assert_str(P0Inbox.left_text(2_520_000.0)).is_equal("42m left")
	assert_str(P0Inbox.left_text(85_200_000.0)).is_equal("23h 40m left")
	assert_str(P0Inbox.left_text(79_200_000.0)).is_equal("22h left")

func test_rows_go_soonest_first_with_name_source_and_time() -> void:
	var rows := P0Inbox.parcel_rows(_view(6, 3))
	assert_that(rows.map(func(r): return r.title)).is_equal(["Pumpkin Seeds ×2", "Herb Grilled Fish ×1", "Perch ×7"])
	assert_that([rows[2].sub, rows[2].left, rows[2].can_claim]).is_equal(["Request reward · Stall Board", "23h 40m left", true])

func test_claim_all_takes_what_fits_and_with_the_bag_full_says_make_room() -> void:
	assert_that(P0Inbox.claim_all(_view(6, 3)).label).is_equal("Claim all · 3 slots")
	assert_that(P0Inbox.claim_all(_view(2, 3)).label).is_equal("Claim all · 2 slots")
	var full := P0Inbox.claim_all(_view(0, 2))
	assert_that([full.label, full.reason, full.keys]).is_equal(["", "Make room · 2 slots", []])
	assert_that(P0Inbox.claim_all(_view(6, 0))).is_equal({})

## q(79): only what happened while the player was away; claims stay on the server and are not listed.
func test_updates_list_expired_and_returned_parcels_only() -> void:
	var v := _view(6, 0, [_upd("u3", "returned", 0, false, NOW - 86_400_000.0 * 1.5, "dish_herb_grilled_fish", 1, {"from": "Pip"}),
		_upd("u2", "expired", 0, true, NOW - 3_600_000.0 * 5, "bait_worm", 3), _upd("u1", "expired", 18, false, NOW - 30_000.0),
		_upd("c1", "claimed", 0, true)])
	var rows := P0Inbox.update_rows(v, NOW)
	assert_that(rows.map(func(r): return r.title)).is_equal(
		["Pip's gift meal went back · unclaimed", "Parcel expired · Worm Bait ×3 lost", "Parcel expired · +18 coins"])
	assert_that(rows.map(func(r): return r.time)).is_equal(["1d ago", "5h ago", "Just now"])
	assert_that([rows[2].sub, rows[1].sub, rows[0].sub]).is_equal(["Perch ×7 · turned into coins at 80%", "Fishing Lv2 reward", "Herb Grilled Fish ×1"])
	assert_that(rows.map(func(r): return r.unread)).is_equal([true, false, true])

func test_the_bell_reads_the_servers_badge() -> void:
	var v := _view(0, 2, [_upd("u1", "expired", 18)])
	v.inbox.badge = 3
	assert_int(P0Inbox.badge(v)).is_equal(3)
	assert_int(int(P0Logic.hud_state(v).unread)).is_equal(3)

# ---------------------------------------------------------------- the drawer
func _drawer(v: Dictionary, tab := "") -> P0InboxDrawer:
	var d := P0InboxDrawer.new(v, tab)
	d.animate = false
	d.now_ms = func() -> float: return NOW
	add_child(auto_free(d))
	return d

func test_parcels_page_draws_rows_and_claims() -> void:
	var d := _drawer(_view(6, 3))
	await get_tree().process_frame
	assert_str(d.tab).is_equal("parcels")
	assert_int(d.rows.size()).is_equal(3)
	var badge := d.tabs.tabs()[1].get_child(0).get_node("Badge") as Control
	assert_that([badge.visible, (badge.get_node("Number") as Label).text]).is_equal([true, "3"])
	var sent: Array = []
	d.claim_requested.connect(func(cmd, _from): sent.append(cmd))
	d.rows[1].claim.pressed.emit()
	d.claim_all.pressed.emit()
	assert_that(sent).is_equal([{"type": "claim_parcel", "key": "p1"}, {"type": "claim_parcels", "keys": ["p0", "p1", "p2"]}])
	assert_object(d.action_area()).is_same(d.claim_all)   # q(16): a toast sits above Claim all

func test_a_full_bag_greys_every_claim_and_says_make_room() -> void:
	var d := _drawer(_view(0, 2))
	await get_tree().process_frame
	assert_that(d.rows.map(func(r): return [r.claim.text, r.claim.is_unavailable()])).is_equal([["Claim", true], ["Claim", true]])
	assert_that([d.claim_all.text, d.claim_all.is_unavailable()]).is_equal(["Make room · 2 slots", true])

func test_updates_opened_read_them_and_the_dots_stay_for_the_visit() -> void:
	var v := _view(6, 0, [_upd("u1", "expired", 18)])
	var asked: Array = []
	var d := P0InboxDrawer.new(v)
	d.animate = false
	d.now_ms = func() -> float: return NOW
	d.read_requested.connect(func(keys): asked.append(keys))
	add_child(auto_free(d))
	await get_tree().process_frame
	assert_str(d.tab).is_equal("updates")
	assert_that(asked).is_equal([["u1"]])
	v.inbox.updates[0].read = true   # the server's answer
	v.inbox.badge = 0
	d.refresh(v)
	assert_bool(d.rows[0].unread()).is_true()   # still marked for this visit
	assert_bool((d.tabs.tabs()[2].get_child(0).get_node("Dot") as Control).visible).is_false()

func test_empty_pages_say_so() -> void:
	var d := _drawer(_view(6, 0), "todo")
	await get_tree().process_frame
	assert_int(d.find_children("*", "UiEmptyState", true, false).size()).is_equal(1)
	assert_bool(d.claim_all.visible).is_false()
	d.set_tab("parcels")
	await get_tree().process_frame
	assert_object(d.action_area()).is_null()   # no Claim all: the toast sits at the drawer's foot

# ---------------------------------------------------------------- the UI and the runtime
func test_the_bell_opens_the_inbox_and_the_ui_sends_its_commands() -> void:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await get_tree().process_frame
	ui.set_view(_view(6, 3))
	var sent: Array = []
	ui.command.connect(func(cmd): sent.append(cmd))
	ui.hud.inbox_pressed.emit()
	await get_tree().process_frame
	assert_str(ui.modal_kind).is_equal("inbox")
	ui.inbox().rows[0].claim.pressed.emit()
	assert_that(sent).is_equal([{"type": "claim_parcel", "key": "p0"}])
	assert_bool(ui.inbox_float_at().is_finite()).is_true()
	ui.inbox().set_tab("updates")
	ui.close_modal()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func test_a_claimed_parcel_floats_from_its_button_even_for_fish() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	add_child(rt)
	await get_tree().process_frame
	rt.ui.set_view(_view(6, 3))
	rt.ui.open_inbox()
	await get_tree().process_frame
	rt.ui.inbox().rows[2].claim.pressed.emit()
	var at := rt.ui.inbox_float_at()
	rt._on_state(_view(5, 2), [{"kind": "item", "id": "fish_perch", "delta": 7}])
	await get_tree().process_frame
	await get_tree().process_frame
	var f := rt.ui.root.get_children().filter(func(c): return c is UiFloatText and str(c.text).contains("Perch"))
	assert_int(f.size()).is_equal(1)
	assert_float((f[0] as Control).position.x).is_less(at.x + 200.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
