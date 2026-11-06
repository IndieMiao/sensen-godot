extends GdUnitTestSuite
## A 包反馈 3 (不知火舞's spec ③, q(284)): requests tracked at once stop at 25 (content requests.track_max). Every way to
## take another greys its key with its own name and `Requests 25/25` (LOCK-10, T4; 不知火舞 on #738) — a board's
## `Track · Requests 25/25`, a resident's `Request · …` (and the card's `Accept · …`), a keeper's `Accept · …` — and a tap, or the server's track_limit, says `Finish or drop a request first`.

const TIPS := "user://test_p0_track_full_tips.json"
const STORE := "user://test_p0_track_full_bar.json"

func after_test() -> void:
	for f in [TIPS, STORE]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

## `n` Stall Board requests taken, and one more open to take.
static func _view(n: int) -> Dictionary:
	var slots: Array = []
	for i in n: slots.append({"id": "t%d" % i, "title": "Crate %d" % i, "kind": "crop", "items": ["crop_radish"], "have": 0, "qty": 2,
		"status": "accepted"})
	slots.append({"id": "open", "title": "Crate", "kind": "crop", "items": ["crop_radish"], "have": 0, "qty": 2, "status": "open"})
	return {"coins": 120, "energy": {"value": 150, "max": 200}, "bag": {"capacity": 25, "slots": []},
		"names": {"crop_radish": "Radish"}, "boards": {"stall": {"slots": slots}},
		"residents": {"res_pip": {"request": {"id": "req_res_pip_2", "kind": "sow", "have": 0, "qty": 5, "ready": false},
			"request_state": "open", "affinity": 0}}}

func test_the_content_tracks_25() -> void:
	assert_int(int(P0Logic.content().requests.track_max)).is_equal(25)

func test_below_25_every_key_takes_a_request() -> void:
	var v := _view(24)
	assert_str(P0Logic.track_full_reason(v)).is_empty()
	var card := P0Board.card(v, v.boards.stall.slots[24])
	assert_that([card.command, card.reason, card.cmd]).is_equal(["Track", "", {"type": "accept", "request": "open"}])
	var bar := P0Logic.resident_bar(v, "res_pip")
	assert_that([bar.request_reason, bar.request_cmd.type]).is_equal(["", "accept"])

func test_at_25_every_key_greys_with_its_reason_and_sends_nothing() -> void:
	var v := _view(25)
	assert_str(P0Logic.track_full_reason(v)).is_equal("Requests 25/25")
	assert_str(P0Logic.track_full_reason(v, "Accept")).is_equal("Accept · Requests 25/25")
	var card := P0Board.card(v, v.boards.stall.slots[25])
	assert_that([card.command, card.reason]).is_equal(["Track", "Track · Requests 25/25"])
	assert_bool(card.has("cmd") and not (card.cmd as Dictionary).is_empty()).is_false()
	var bar := P0Logic.resident_bar(v, "res_pip")
	assert_that([bar.request_label, bar.request_reason, bar.request_cmd]).is_equal(["Request", "Request · Requests 25/25", {}])
	assert_str(P0Logic.blocked_toast("Requests 25/25")).is_equal("Finish or drop a request first")
	assert_str(P0Logic.blocked_toast("Track · Requests 25/25")).is_equal("Finish or drop a request first")
	assert_str(P0Logic.blocked_toast("Need 2 more Radish")).is_equal("Need 2 more Radish")   # any other reason: itself

func test_a_tap_on_the_greyed_request_card_and_the_servers_refusal_say_what_to_do() -> void:
	var ui := P0Ui.new()
	ui.tips_path = TIPS
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view(25))
	ui.open_resident_request("res_pip")
	var card: UiRequestCard = ui.find_children("*", "UiRequestCard", true, false)[0]
	assert_str(card.action_button().reason).is_equal("Accept · Requests 25/25")   # the bar said Request
	card.action_button().unavailable_pressed.emit(card.action_button().reason)
	await await_idle_frame()
	assert_array(_toast_texts(ui)).contains(["Finish or drop a request first"])

static func _toast_texts(ui: P0Ui) -> Array:
	return ui.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
