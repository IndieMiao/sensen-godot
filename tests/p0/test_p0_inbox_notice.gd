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
	# C-50: frames are stepped by hand below. Real frames spent the 2 s too: a slow setup frame (≥ 0.1 s, as on a
	# loaded Linux runner) hid the card before the check at 1.9 s.
	ui.set_process(false)
	ui.inbox_notice_when_clear(SPEC)
	await await_idle_frame()
	await await_idle_frame()
	ui._process(0.0)   # the per-frame placement, after the HUD has laid out
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

## 不知火舞 on 234 (after 刘邦 on #116): the card's top is 8 under the lowest thing showing under the HUD — the system line,
## then the creel badge at the pond —, else 12 under the HUD; it moves down when one comes and never jumps back up.
func _bottom(ui: P0Ui, c: Control) -> float: return c.get_global_rect().end.y - ui.root.global_position.y

func test_it_sits_under_the_system_line_and_does_not_jump_back() -> void:
	var ui: P0Ui = await _ui()
	ui.inbox_notice_when_clear(SPEC)
	await await_idle_frame()
	var card := ui.inbox_notice_card()
	var base := float(UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H) + 12.0 + ui.safe_top()
	assert_float(card.position.y).is_equal(base)
	ui.show_sys(UiSysBanner.Kind.OFFLINE, "Offline")   # comes while the card shows: the card moves down
	await await_idle_frame()
	ui._process(0.0)
	var under := roundf(_bottom(ui, ui._sys) + 8.0)
	assert_float(card.position.y).is_equal(under)
	assert_bool(card.get_global_rect().intersects(ui._sys.get_global_rect())).is_false()
	ui.hide_sys()   # goes: the card stays put for the rest of its 2 s
	ui._process(0.0)
	assert_float(card.position.y).is_equal(under)
	# The next card comes up at the spot of the moment.
	ui.inbox_notice_when_clear({title = "Sent to Inbox", item = "Worm Bait", quantity = "×3", line = "Expires in 24h"})
	assert_float(card.position.y).is_equal(base)

func test_at_the_pond_it_sits_under_the_creel_badge_and_under_both_with_a_system_line() -> void:
	var ui: P0Ui = await _ui()
	var v := ui.view.duplicate(true)
	v.bag["free"] = 0
	ui.set_surface("pond")
	ui.set_mode("fish")
	ui.set_view(v)
	ui.set_action(P0Logic.fish_action(v, ""))
	await await_idle_frame()
	assert_bool(ui._creel.visible).is_true()
	ui.inbox_notice_when_clear(SPEC)
	await await_idle_frame()
	var card := ui.inbox_notice_card()
	assert_float(card.position.y).is_equal(roundf(_bottom(ui, ui._creel) + 8.0))   # Creel full is not covered
	assert_bool(card.get_global_rect().intersects(ui._creel.get_global_rect())).is_false()
	ui._hide_notice()
	ui.show_sys(UiSysBanner.Kind.CMD_FAIL, "Didn't go through")   # the badge moves under the line, the card under both
	ui.inbox_notice_when_clear(SPEC)
	await await_idle_frame()
	assert_float(_bottom(ui, ui._creel)).is_greater(_bottom(ui, ui._sys))
	assert_float(card.position.y).is_equal(roundf(_bottom(ui, ui._creel) + 8.0))
