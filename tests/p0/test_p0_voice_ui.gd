extends GdUnitTestSuite
## The voice controls on P0Ui (SGODOT-383; q(274); 不知火舞's spec 383 6d206dfb): the mic key and people pill under the
## HUD on the right once the room offers voice; the 13+ card before the first mic; `Mic on · …` the first time only; the
## people drawer's rows and Block's card; nothing on a room without voice.

const P0VoiceRoom := preload("res://modules/p0/p0_voice_room.gd")
const FakeVoice := preload("res://tests/p0/test_p0_voice_room.gd").FakeVoice

static func _store() -> String: return "user://test_p0_voice_ui_bar_%d.json" % OS.get_process_id()

func before_test() -> void:
	if FileAccess.file_exists(P0VoiceRoom.MUTES): DirAccess.remove_absolute(ProjectSettings.globalize_path(P0VoiceRoom.MUTES))
	P0Ui._mic_toast_said = false

func after_test() -> void:
	for f in [P0VoiceRoom.MUTES, _store()]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _room() -> Array:
	var online: P0Online = auto_free(P0Online.new())
	online.transport = func(_m): pass
	online._message(JSON.stringify({"t": "joined", "outpost": "sh_tea_1", "room": 2, "capacity": 12, "rejoined": false, "self": 1, "epoch": 2}))
	online._message(JSON.stringify({"t": "roster", "count": 3, "members": [{"id": 1, "player": "me00me00"},
		{"id": 4, "player": "ab12cd34"}, {"id": 5, "player": "ef56gh78"}]}))
	var v: FakeVoice = auto_free(FakeVoice.new())
	var room: P0VoiceRoom = auto_free(P0VoiceRoom.new())
	room.voice = v
	var answers := {"status": {"available": true, "age": "unknown"}, "age": {"age": "ok"}, "report": {"result": "sent"}}
	room.request = func(_m: int, path: String, _b: Dictionary) -> Dictionary:
		return {"ok": true, "json": answers.get(path.get_file(), {})}
	room.setup(null, online, "tea")
	return [room, v, online]

func _ui() -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = _store()
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_surface("busy")
	return ui

func test_the_keys_come_with_voice_and_the_first_mic_asks_the_age_then_says_who_hears() -> void:
	var ui := await _ui()
	var f := _room()
	var room: P0VoiceRoom = f[0]
	ui.set_voice_room(room)
	assert_object(ui._voice_keys).is_null()   # the server not asked yet: nothing shown
	await room.fetch_status()
	assert_bool(ui._voice_keys.visible).is_true()
	assert_str(ui._voice_keys.people.text).is_equal("2")   # the others, not the player
	await await_idle_frame()
	var keys = ui._voice_keys   # on the Creel pill's line (V1 / V6), its top, shown or not; the mic on the pill's middle
	assert_float(keys.people.get_global_rect().position.y).is_equal_approx(ui._creel.position.y, 0.5)
	assert_float(keys.mic.get_global_rect().get_center().y).is_equal_approx(keys.people.get_global_rect().get_center().y, 0.5)
	assert_bool(ui._voice_keys.mic_on).is_false()          # the mic starts off
	ui._voice_keys.mic.pressed.emit()
	assert_str(ui.modal_kind).is_equal("age")              # the 13+ card first
	var card = ui._modal.get_child(1)
	assert_bool(card.go.disabled).is_true()                # no year picked: Continue grey
	card.pick(int(card.this_year) - 20)
	card.go.activated.emit()
	await await_idle_frame()
	f[1].changed.emit()   # the real Voice says so when the mic comes on
	assert_bool(ui._voice_keys.mic_on).is_true()
	assert_str(ui.toast_text()).starts_with("Mic on")
	assert_str(ui.toast_text()).ends_with("others here can hear you")   # q(274) 补记二; broken at its « · » when too long
	ui.clear_toast()
	ui._voice_keys.mic.pressed.emit()   # off
	f[1].changed.emit()
	ui._voice_keys.mic.pressed.emit()   # on again: no second toast
	f[1].changed.emit()
	assert_bool(ui._voice_keys.mic_on).is_true()
	assert_str(ui.toast_text()).is_empty()

func test_a_child_s_answer_hides_voice() -> void:
	assert_bool(P0Ui.AgeCard.ok_for(2012, 2026)).is_true()
	assert_bool(P0Ui.AgeCard.ok_for(2013, 2026)).is_false()   # 14 by the year: one born late in 2013 may still be 12 (user 11-02, way (a))
	var ui := await _ui()
	var f := _room()
	var room: P0VoiceRoom = f[0]
	room.request = func(_m: int, path: String, b: Dictionary) -> Dictionary:
		return {"ok": true, "json": {"available": true, "age": "unknown"} if path.get_file() == "status" else {"age": "ok" if b.get("ok") else "no"}}
	ui.set_voice_room(room)
	await room.fetch_status()
	ui._voice_keys.mic.pressed.emit()
	var card = ui._modal.get_child(1)
	card.pick(int(card.this_year) - 8)
	card.go.activated.emit()
	await await_idle_frame()
	assert_str(ui.toast_text()).is_equal("Voice chat isn't available")
	assert_bool(ui._voice_keys.visible).is_false()

func test_the_people_drawer_mutes_blocks_after_its_card_and_reports() -> void:
	var ui := await _ui()
	var f := _room()
	var room: P0VoiceRoom = f[0]
	ui.set_voice_room(room)
	await room.fetch_status()
	ui._voice_keys.people.pressed.emit()
	assert_str(ui.modal_kind).is_equal("people")
	var d = ui._people
	assert_str(d.title.text).ends_with("Layer 2")
	assert_int(d.list.get_children().filter(func(c): return c.name.begins_with("Person_")).size()).is_equal(2)
	assert_int(d.list.get_child_count()).is_equal(3)   # a line between the rows (V3)
	d.mute_pressed.emit(4, true)
	assert_bool(room.people().filter(func(r): return r.peer == 4)[0].muted).is_true()
	assert_str((d.list.find_child("Person_4", false, false).find_child("Mute", true, false) as Button).text).is_equal("Unmute")
	d.block_pressed.emit(5, true)
	assert_str(ui.modal_kind).is_equal("block_confirm")   # Block asks first (§5)
	var confirm := ui._modal.find_child("BlockConfirm", true, false)
	assert_str((confirm.card.find_child("Title", true, false) as Label).text).is_equal("Block Traveller ef56?")
	confirm.cancelled.emit()
	assert_str(ui.modal_kind).is_equal("people")
	d.report_pressed.emit(4)
	await await_idle_frame()
	assert_str(ui.toast_text()).is_equal("Report sent")
	d.close.pressed.emit()   # its own Close under the rows (V3)
	assert_str(ui.modal_kind).is_not_equal("people")

## §7 as V5 has it (383 50108c43): the wheel opens on this year with nothing picked; a tap on a year picks it, a drag
## the year it stops on.
func test_the_year_wheel_opens_on_this_year_and_picks_where_it_stops() -> void:
	var card = P0Ui.AgeCard.new(2026)
	card.animate = false
	card.size = Vector2(360, P0Ui.AgeCard.HEIGHT)
	add_child(auto_free(card))
	await await_idle_frame()
	assert_int(card.centred()).is_equal(2026)
	assert_int(card.year).is_equal(0)
	assert_bool(card.go.disabled).is_true()
	var mid: float = card.wheel.size.y * 0.5
	_click(card, mid - P0Ui.AgeCard.NEXT, mid - P0Ui.AgeCard.NEXT)   # a tap on the year over the band
	assert_int(card.year).is_equal(2025)
	assert_bool(card.go.disabled).is_false()
	_click(card, mid, mid + 3.0 * P0Ui.AgeCard.STEP)   # dragged three rows down: three years earlier
	assert_int(card.year).is_equal(2022)

func _click(card, from_y: float, to_y: float) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(180, from_y)
	card._wheel_input(down)
	if to_y != from_y:
		var move := InputEventMouseMotion.new()
		move.position = Vector2(180, to_y)
		card._wheel_input(move)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = Vector2(180, to_y)
	card._wheel_input(up)

class FakeCrowd extends Node:
	var speaking: Dictionary = {}

## §3: who speaks goes green over their head — the crowd's `speaking`, the drawer's dot; a muted speaker does not.
func test_a_speaker_s_name_tag_and_row_go_green() -> void:
	var ui := await _ui()
	var f := _room()
	var room: P0VoiceRoom = f[0]
	var crowd: FakeCrowd = auto_free(FakeCrowd.new())
	(f[2] as P0Online).crowd = crowd
	ui.set_voice_room(room)
	await room.fetch_status()
	f[1].participants = [{"id": "4", "speaking": true}, {"id": "5", "speaking": true}]
	room.set_muted(5, true)
	f[1].changed.emit()
	assert_dict(crowd.speaking).is_equal({4: true})
	ui._voice_keys.people.pressed.emit()
	assert_float((ui._people.list.find_child("Person_4", false, false).find_child("Speaking", true, false) as Control).modulate.a).is_equal(1.0)
	assert_float((ui._people.list.find_child("Person_5", false, false).find_child("Speaking", true, false) as Control).modulate.a).is_equal(0.0)
	# 384 (奕星 via 周瑜 on #650): lit only while their voice really reaches this phone. The blocker's phone has the
	# block in its voice_blocks (the server sends them to the blocker only, since #650) and lights nothing; the blocked
	# one's phone never hears of it, and stays dark because the plugin reports `speaking` only for a track it is
	# subscribed to (亚瑟 on #650), which a block takes away — so the blocked one cannot tell from it either
	(f[2] as P0Online)._message(JSON.stringify({"t": "voice_blocks", "blocked": [4]}))
	f[1].changed.emit()
	assert_dict(crowd.speaking).is_empty()
	await await_idle_frame()   # the drawer's rows it refreshed away are queue_free'd: gone a frame on, not orphans

func test_no_room_no_keys() -> void:
	var ui := await _ui()
	ui.set_voice_room(null)
	assert_object(ui._voice_keys).is_null()

## q(286) (Market Square's voice, SGODOT-415; 不知火舞's M1-b 476:195818): a long title breaks at its ` · ` into two lines,
## `Mute all` at the first, the drawer 173 over its rows (447 − 173 = 274 at most); the rows scroll as Today's — a fade
## at an edge with rows past it, a 3 px bar at the right while they overflow. A short one stays one line (154).
func test_a_long_title_breaks_at_its_dot_and_the_rows_scroll_as_todays() -> void:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	var rows := []
	for i in 12: rows.append({"peer": i + 2, "name": "Traveller %02d" % i})
	var d = load("res://scenes/p0/panels/p0_people_drawer.gd").new("Mission Market Square · Layer 1", rows)
	d.size = Vector2(360, 447)
	host.add_child(d)
	for i in 3: await get_tree().process_frame
	assert_str(d.title.text).is_equal("Mission Market Square\nLayer 1")
	assert_int(d.all_key.size_flags_vertical).is_equal(Control.SIZE_SHRINK_BEGIN)
	assert_float(d.height).is_equal(447.0)
	assert_float(d._held.custom_minimum_size.y).is_equal(274.0)
	assert_bool(d._bar.visible).is_true()
	assert_bool(d._fade_bottom.visible).is_true()
	assert_bool(d._fade_top.visible).is_false()
	d._scroll.scroll_vertical = 100
	for i in 2: await get_tree().process_frame
	assert_bool(d._fade_top.visible).is_true()
	var short = load("res://scenes/p0/panels/p0_people_drawer.gd").new("Fern Pond · Layer 1", rows.slice(0, 2))
	short.size = Vector2(360, 300)
	host.add_child(short)
	for i in 3: await get_tree().process_frame
	assert_str(short.title.text).is_equal("Fern Pond · Layer 1")
	assert_float(short.height).is_equal(154.0 + 2 * 45.0)
	assert_bool(short._bar.visible).is_false()
