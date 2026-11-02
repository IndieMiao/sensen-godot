extends GdUnitTestSuite
## Settings › Blocked players (SGODOT-384; q(28) §12.1.6; 不知火舞's spec 383, BP1–BP3 row 127): the Privacy group
## before Legal with `Blocked players` and how many, while anyone is blocked (or voice is offered here); the page lists
## them by name with `Unblock`, a tap takes the row away at once and lifts the block; none: `No one blocked`.

const P0VoiceRoom := preload("res://modules/p0/p0_voice_room.gd")
const STORE := "user://test_p0_blocked_players.json"
const TIPS := "user://test_p0_blocked_players_tips.json"

var blocks: Array = []
var asked: Array = []
var unblock_ok := true

func before_test() -> void:
	blocks = [{"handle": "5dd4a1b2c3d4e5f6"}, {"handle": "e57e0a1b2c3d4e5f"}]
	asked = []
	unblock_ok = true

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
			"status": return {"ok": true, "json": {"available": false, "age": "unknown"}}
			"blocks": return {"ok": true, "json": {"blocked": blocks.duplicate()}}
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
	assert_object(_page(ui).body.find_child("BlockedPlayers", true, false)).is_null()   # no voice here, nobody blocked
	assert_bool(_labels(_page(ui).body).has("Privacy")).is_false()

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
	assert_object(_page(ui).body.find_child("BlockedPlayers", true, false)).is_null()   # nobody left and no voice here: no group

func test_an_unblock_that_did_not_go_through_puts_the_row_back() -> void:
	var ui := await _ui()
	await ui._privacy_read(func(): pass)
	unblock_ok = false
	ui.open_blocked_players(func(): ui.open_settings())
	await await_idle_frame()
	(_page(ui).body.find_child("Blocked_5dd4a1b2c3d4e5f6", true, false).find_child("Unblock", true, false) as Button).pressed.emit()
	await await_millis(50)
	assert_array(_labels(_page(ui).body)).is_equal(["Traveller 5dd4", "Unblock", "Traveller e57e", "Unblock"])
