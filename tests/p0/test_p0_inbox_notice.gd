extends GdUnitTestSuite
## The Sent to Inbox card (InboxNotice 1860:104768; BAG-5-2 482:146 / FARM-LV2-2 1368:91701; LOCK-14, q(87);
## SGODOT-234): under the bell for 2 s, a tap opens the Inbox on Parcels, held while a card or drawer is up.

const STORE := "user://test_p0_inbox_notice.json"
const TIPS := "user://test_p0_inbox_notice_tips.json"
const SPEC := {title = "Sent to Inbox", item = "Perch", quantity = "×7", line = "Expires in 24h"}

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _ui() -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view({"energy": {"value": 150, "max": 200}, "coins": 40, "bag": {"capacity": 25, "slots": []},
		"inbox": {"badge": 1, "parcels": [{"key": "request:1:0", "id": "fish_perch", "qty": 7, "left": 86400000}]}})
	ui.set_surface("farm")
	return ui

func test_the_card_hangs_under_the_bell_for_two_seconds() -> void:
	var ui: P0Ui = await _ui()
	ui.inbox_notice_when_clear(SPEC)
	await await_idle_frame()
	await await_idle_frame()
	assert_dict(ui.inbox_notice_shown()).is_equal(SPEC)
	var card := ui.inbox_notice_card()
	# BAG-5-2: x 68 y 110 of 360 × 800 — the right edge on the bell's, 12 under the HUD's two rows.
	assert_float(card.get_global_rect().end.x).is_equal_approx(ui.hud.balances_rect().end.x, 0.5)
	assert_float(card.position.y).is_equal(float(UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H) + 12.0 + ui.safe_top())
	assert_vector(card.size).is_equal(Vector2(UiInboxNotice.WIDTH, UiInboxNotice.HEIGHT))
	assert_object(card.icon_texture()).is_same(P0Logic.icon("parcel"))
	ui._process(UiTokens.MOTION_TOAST_BASE_MS / 1000.0 - 0.1)
	assert_dict(ui.inbox_notice_shown()).is_not_empty()
	ui._process(0.2)
	assert_dict(ui.inbox_notice_shown()).is_empty()

func test_a_tap_opens_the_inbox_on_parcels() -> void:
	var ui: P0Ui = await _ui()
	ui.inbox_notice_when_clear(SPEC)
	await await_idle_frame()
	ui.inbox_notice_card().tapped.emit()
	assert_str(ui.modal_kind).is_equal("inbox")
	assert_str(ui.inbox().tab).is_equal("parcels")
	assert_dict(ui.inbox_notice_shown()).is_empty()

func test_it_waits_for_a_card_or_drawer_and_a_new_one_replaces_it() -> void:
	var ui: P0Ui = await _ui()
	ui.open_inbox()
	ui.inbox_notice_when_clear(SPEC)
	await await_idle_frame()
	assert_dict(ui.inbox_notice_shown()).is_empty()   # held under the drawer
	ui.close_modal()
	await await_idle_frame()
	assert_dict(ui.inbox_notice_shown()).is_equal(SPEC)
	var next := {title = "Inbox full · waiting", item = "Carrot Seeds", quantity = "×5", line = "+1 more · Claim a parcel first"}
	ui.inbox_notice_when_clear(next)
	assert_dict(ui.inbox_notice_shown()).is_equal(next)
	assert_int(ui.root.find_children("*", "UiInboxNotice", true, false).size()).is_equal(1)
	ui.inbox_notice_when_clear({})   # nothing to say
	assert_dict(ui.inbox_notice_shown()).is_equal(next)
