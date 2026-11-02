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
	assert_str(ui.toast_text()).ends_with("everyone in this layer can hear you")   # broken at its « · » when too long
	ui.clear_toast()
	ui._voice_keys.mic.pressed.emit()   # off
	f[1].changed.emit()
	ui._voice_keys.mic.pressed.emit()   # on again: no second toast
	f[1].changed.emit()
	assert_bool(ui._voice_keys.mic_on).is_true()
	assert_str(ui.toast_text()).is_empty()

func test_a_child_s_answer_hides_voice() -> void:
	assert_bool(P0Ui.AgeCard.ok_for(2013, 2026)).is_true()
	assert_bool(P0Ui.AgeCard.ok_for(2014, 2026)).is_false()
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
	assert_int(d.list.get_child_count()).is_equal(2)
	d.mute_pressed.emit(4, true)
	assert_bool(room.people().filter(func(r): return r.peer == 4)[0].muted).is_true()
	assert_str((d.list.get_child(0).find_child("Mute", true, false) as Button).text).is_equal("Unmute")
	d.block_pressed.emit(5, true)
	assert_str(ui.modal_kind).is_equal("block_confirm")   # Block asks first (§5)
	var confirm := ui._modal.find_child("BlockConfirm", true, false)
	assert_str((confirm.card.find_child("Title", true, false) as Label).text).is_equal("Block Traveller ef56?")
	confirm.cancelled.emit()
	assert_str(ui.modal_kind).is_equal("people")
	d.report_pressed.emit(4)
	await await_idle_frame()
	assert_str(ui.toast_text()).is_equal("Report sent")

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
	assert_float((ui._people.list.get_child(0).find_child("Speaking", true, false) as Control).modulate.a).is_equal(1.0)
	assert_float((ui._people.list.get_child(1).find_child("Speaking", true, false) as Control).modulate.a).is_equal(0.0)
	# 384 (奕星 via 周瑜 on #650): lit only while their voice really reaches this phone — a block either way (the server
	# sends voice_blocks to both phones) leaves no light, so the blocked one cannot tell from it
	(f[2] as P0Online)._message(JSON.stringify({"t": "voice_blocks", "blocked": [4]}))
	f[1].changed.emit()
	assert_dict(crowd.speaking).is_empty()

func test_no_room_no_keys() -> void:
	var ui := await _ui()
	ui.set_voice_room(null)
	assert_object(ui._voice_keys).is_null()
