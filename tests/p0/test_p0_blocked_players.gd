extends GdUnitTestSuite
## Settings › Blocked players (SGODOT-384; q(28) §12.1.6; 不知火舞's spec 383, BP1–BP3 row 127): the Privacy group
## before Legal with `Blocked players` and how many, always — a Block is made in any room, voice or not (q(309): an
## iPhone too); the page lists
## them by name with `Unblock`, a tap takes the row away at once and lifts the block; none: `No one blocked`.

const P0VoiceRoom := preload("res://modules/p0/p0_voice_room.gd")
const STORE := "user://test_p0_blocked_players.json"
const TIPS := "user://test_p0_blocked_players_tips.json"

var blocks: Array = []
var asked: Array = []
var unblock_ok := true
var blocks_ok := true
var status_ok := true
var during_blocks := Callable()

func before_test() -> void:
	blocks = [{"handle": "5dd4a1b2c3d4e5f6"}, {"handle": "e57e0a1b2c3d4e5f"}]
	asked = []
	unblock_ok = true
	blocks_ok = true
	status_ok = true
	during_blocks = Callable()

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

## Every visible word, the text keys' too.
func _labels(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "Control", true, false):
		if (c is Label or c is Button) and c.is_visible_in_tree() and str(c.text) != "": out.append(str(c.text))
	return out

## A P0Ui with the account's voice answered here: no voice on this server, `blocks` as the block list.
func _ui() -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	var acc: P0VoiceRoom = auto_free(P0VoiceRoom.new())
	acc.request = func(_m: int, path: String, body: Dictionary) -> Dictionary:
		asked.append([path.get_file(), body])
		match path.get_file():
			"status": return {"ok": true, "json": {"available": false, "age": "unknown"}} if status_ok else {"ok": false, "json": {}}
			"blocks":
				if during_blocks.is_valid(): during_blocks.call()
				return {"ok": true, "json": {"blocked": blocks.duplicate()}} if blocks_ok else {"ok": false, "json": {}}
			"unblock":
				if unblock_ok: blocks = blocks.filter(func(b): return b.handle != body.handle)
				return {"ok": unblock_ok, "json": {}}
		return {"ok": true, "json": {}}
	ui.voice_account = acc
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view({"energy": {"value": 150, "max": 200}, "coins": 40, "skills": {}, "bag": {"capacity": 25, "slots": []}})
	return ui

func _page(ui: P0Ui) -> P0SettingsPage:
	return ui._modal.find_children("*", "P0SettingsPage", true, false)[0]

func test_the_privacy_group_comes_before_legal_while_anyone_is_blocked() -> void:
	var ui := await _ui()
	ui.open_settings()
	await await_millis(50)   # the server read, then the page again
	var page := _page(ui)
	var texts := _labels(page.body)
	assert_int(texts.find("Privacy")).is_less(texts.find("Legal"))
	var row: UiSettingRow = page.body.find_child("BlockedPlayers", true, false)
	assert_array(_labels(row)).is_equal(["Blocked players", "2", "›"])
	assert_bool(row.get_parent().get_child_count() == 1).is_true()   # its own card
	blocks = []
	ui.open_settings()
	await await_millis(50)
	# no voice here, nobody blocked: still there, 0 (q(309) ⑤: an iPhone blocks from the drawer and lifts it here)
	assert_array(_labels(_page(ui).body.find_child("BlockedPlayers", true, false))).is_equal(["Blocked players", "0", "›"])
	assert_bool(_labels(_page(ui).body).has("Privacy")).is_true()

func test_the_list_unblocks_at_a_tap_with_no_card_and_ends_on_no_one_blocked() -> void:
	var ui := await _ui()
	ui.open_settings()
	await await_millis(50)
	(_page(ui).body.find_child("BlockedPlayers", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	await await_millis(50)
	assert_str(ui.modal_kind).is_equal("blocked_players")
	var page := _page(ui)
	assert_str(page.header.title).is_equal("Blocked players")
	assert_array(_labels(page.body)).is_equal(["Traveller 5dd4", "Unblock", "Traveller e57e", "Unblock"])
	(page.body.find_child("Blocked_5dd4a1b2c3d4e5f6", true, false).find_child("Unblock", true, false) as Button).pressed.emit()
	assert_array(_labels(page.body)).is_equal(["Traveller e57e", "Unblock"])   # gone at once, before the server answers
	await await_millis(50)
	assert_array(asked.filter(func(a): return a[0] == "unblock")).is_equal([["unblock", {"handle": "5dd4a1b2c3d4e5f6"}]])
	assert_str(ui.modal_kind).is_equal("blocked_players")   # no card
	assert_str(ui.toast_text()).is_empty()                  # no toast
	(page.body.find_child("Blocked_e57e0a1b2c3d4e5f", true, false).find_child("Unblock", true, false) as Button).pressed.emit()
	await await_millis(50)
	assert_array(_labels(_page(ui).body)).is_equal(["No one blocked"])
	_page(ui).back_pressed.emit()
	await await_millis(50)
	assert_str(ui.modal_kind).is_equal("settings")
	assert_array(_labels(_page(ui).body.find_child("BlockedPlayers", true, false))).is_equal(["Blocked players", "0", "›"])   # nobody left: 0 (q(309))

func test_an_unblock_that_did_not_go_through_puts_the_row_back() -> void:
	var ui := await _ui()
	await ui._privacy_read(func(): pass)
	unblock_ok = false
	ui.open_blocked_players(func(): ui.open_settings())
	await await_idle_frame()
	(_page(ui).body.find_child("Blocked_5dd4a1b2c3d4e5f6", true, false).find_child("Unblock", true, false) as Button).pressed.emit()
	await await_millis(50)
	assert_array(_labels(_page(ui).body)).is_equal(["Traveller 5dd4", "Unblock", "Traveller e57e", "Unblock"])

## A list not read (blocked_list null, 后裔 ed9c83b2) is never `No one blocked` (不知火舞 384 6e014af3): none read this
## launch, the page shows the empty state and Retry, which reads again only when tapped; once one is read, a failed read
## leaves it as it was.
func test_a_list_never_read_shows_retry_and_a_read_one_stays() -> void:
	var ui := await _ui()
	blocks_ok = false
	ui.open_blocked_players(func(): ui.open_settings())
	await await_millis(50)
	var page := _page(ui)
	assert_int(asked.filter(func(a): return a[0] == "blocks").size()).is_equal(1)   # drawn again after it, not read again
	assert_array(_labels(page.body)).is_equal(["Check your connection and try again.", "Retry"])
	assert_bool(_labels(page.body).has("No one blocked")).is_false()
	var reads := asked.filter(func(a): return a[0] == "blocks").size()
	await await_millis(100)
	assert_int(asked.filter(func(a): return a[0] == "blocks").size()).is_equal(reads)   # no retry by itself
	blocks_ok = true
	(page.body.find_child("Retry", true, false) as UiCommandButton).activated.emit()
	await await_millis(50)
	assert_array(_labels(_page(ui).body)).is_equal(["Traveller 5dd4", "Unblock", "Traveller e57e", "Unblock"])
	blocks_ok = false
	ui.open_blocked_players(func(): ui.open_settings())
	await await_millis(50)
	assert_array(_labels(_page(ui).body)).is_equal(["Traveller 5dd4", "Unblock", "Traveller e57e", "Unblock"])

## Settings while the list was never read: the row without a number (不知火舞 384 6e014af3), voice or not and with the
## status not read either (q(309): always there).
func test_settings_without_a_read_list() -> void:
	var page := P0SettingsPage.settings("dev", 0.0, 0.0, {}, "", P0SettingsPage.BLOCKED_UNREAD)
	add_child(auto_free(page))
	assert_array(_labels(page.body.find_child("BlockedPlayers", true, false))).is_equal(["Blocked players", "›"])
	var ui := await _ui()
	blocks_ok = false
	status_ok = false
	ui.open_settings()
	await await_millis(50)
	assert_array(_labels(_page(ui).body.find_child("BlockedPlayers", true, false))).is_equal(["Blocked players", "›"])
	assert_bool(_labels(_page(ui).body).has("Voice chat")).is_false()

## A list read before an Unblock answers after it: dropped, the row does not come back (周瑜 on #667).
func test_a_list_read_before_an_unblock_is_dropped() -> void:
	var ui := await _ui()
	await ui._privacy_read(func(): pass)
	var reopened := [false]
	during_blocks = func():   # an Unblock goes out while this read is out
		ui._unblocks += 1
		during_blocks = Callable()
	await ui._privacy_read(func(): reopened[0] = true)
	assert_bool(reopened[0]).is_false()
	assert_int(ui._blocked.size()).is_equal(2)   # left as it was: the Unblock's own answer takes the row out

## q(277): `Voice chat ›` under `Blocked players` in the Privacy card, only while this phone is offered voice (不知火舞);
## alone when nobody is blocked here; neither row, no group. Its page: the PageHeader and P0Legal's words.
func test_voice_chat_rides_with_the_voice_entry() -> void:
	var both := P0SettingsPage.settings("dev", 0.0, 0.0, {}, "", 2, true)
	add_child(auto_free(both))
	var vc: UiSettingRow = both.body.find_child("VoiceChat", true, false)
	assert_array(_labels(vc)).is_equal(["Voice chat", "›"])
	assert_object(vc.get_parent()).is_same(both.body.find_child("BlockedPlayers", true, false).get_parent())   # one card
	var texts := _labels(both.body)
	assert_int(texts.find("Voice chat")).is_greater(texts.find("Blocked players"))
	assert_int(texts.find("Voice chat")).is_less(texts.find("Legal"))
	var alone := P0SettingsPage.settings("dev", 0.0, 0.0, {}, "", P0SettingsPage.BLOCKED_NONE, true)
	add_child(auto_free(alone))
	assert_bool(_labels(alone.body).has("Privacy")).is_true()
	assert_object(alone.body.find_child("BlockedPlayers", true, false)).is_null()
	var none := P0SettingsPage.settings("dev", 0.0, 0.0, {}, "", P0SettingsPage.BLOCKED_NONE, false)
	add_child(auto_free(none))
	assert_bool(_labels(none.body).has("Privacy")).is_false()
	# here no voice is offered (the server's off): only Blocked players, for the two blocked
	var ui := await _ui()
	ui.open_settings()
	await await_millis(50)
	assert_object(_page(ui).body.find_child("BlockedPlayers", true, false)).is_not_null()
	assert_object(_page(ui).body.find_child("VoiceChat", true, false)).is_null()
	ui.open_voice_chat_info(func(): ui.open_settings())
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("voice_chat")
	assert_str(_page(ui).header.title).is_equal("Voice chat")
	assert_array(_labels(_page(ui).body)).is_equal([P0Legal.VOICE_CHAT])
	_page(ui).back_pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("settings")
