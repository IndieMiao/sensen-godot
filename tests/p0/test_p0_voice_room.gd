extends GdUnitTestSuite
## P0VoiceRoom (SGODOT-383; the user, 11-02 via 奕星, q(274)): the online room's voice. Nothing goes to the server before
## the player wants voice; the 13+ gate comes first; the mic starts off and toggles; Mute is this phone's own, by the
## person's public handle, put back on their peer id in every layer; Block and Report go to the server; Market Square
## has it too since q(286) (SGODOT-415).

const P0VoiceRoom := preload("res://modules/p0/p0_voice_room.gd")

class FakeVoice extends Node:
	signal changed
	var calls: Array = []
	var is_active := false
	var microphone := false
	var participants: Array = []
	var blocked: Array = []
	func supported() -> bool: return true
	func active() -> bool: return is_active
	func join_with(_r: Callable) -> void:
		calls.append(["join_with"])
		is_active = true
	func set_microphone(on: bool) -> void:
		microphone = on
		calls.append(["mic", on])
	func set_muted(id: String, on: bool) -> void: calls.append(["muted", id, on])
	func set_blocked(ids: Array) -> void:
		blocked = ids
		calls.append(["blocked", ids])
	func invalidate_membership() -> void: calls.append(["invalidate"])
	func leave() -> void:
		is_active = false
		calls.append(["leave"])

var asked: Array
var answers: Dictionary

func before_test() -> void:
	if FileAccess.file_exists(P0VoiceRoom.MUTES): DirAccess.remove_absolute(ProjectSettings.globalize_path(P0VoiceRoom.MUTES))

func after_test() -> void:
	if FileAccess.file_exists(P0VoiceRoom.MUTES): DirAccess.remove_absolute(ProjectSettings.globalize_path(P0VoiceRoom.MUTES))

func _room(role := "tea") -> Array:
	asked = []
	answers = {"status": {"ok": true, "available": true, "age": "unknown"}, "age": {"ok": true, "available": true, "age": "ok"}}
	var online: P0Online = auto_free(P0Online.new())
	online.transport = func(_m): pass
	online._message(JSON.stringify({"t": "joined", "outpost": "sh_tea_1", "room": 1, "capacity": 12, "rejoined": false, "self": 1, "epoch": 2}))
	var v: FakeVoice = auto_free(FakeVoice.new())
	var room: P0VoiceRoom = auto_free(P0VoiceRoom.new())
	room.voice = v
	room.request = func(method: int, path: String, body: Dictionary) -> Dictionary:
		asked.append([method, path, body])
		var action := path.get_file()
		return {"ok": true, "json": answers.get(action, {"ok": true})}
	room.setup(null, online, role)
	return [room, v, online]

func test_nothing_goes_out_before_the_player_wants_voice_and_the_gate_comes_first() -> void:
	var f := _room()
	var room: P0VoiceRoom = f[0]
	assert_array(asked).is_empty()
	assert_bool(room.offered()).is_false()   # the server not asked yet
	await room.fetch_status()
	assert_bool(room.offered()).is_true()
	var gate := [0]
	room.age_needed.connect(func(): gate[0] += 1)
	room.toggle_mic()
	assert_int(gate[0]).is_equal(1)   # unknown: the 13+ card first, no join
	assert_bool(f[1].calls.any(func(c): return c[0] == "join_with")).is_false()
	await room.answer_age(true)
	assert_array(asked.map(func(a): return a[1])).is_equal(["/p0/voice/status", "/p0/voice/age"])
	assert_dict(asked[1][2]).is_equal({"ok": true})   # yes / no only: no birth year leaves the phone
	assert_array(f[1].calls).is_equal([["join_with"], ["mic", true]])   # on once answered
	room.toggle_mic()
	assert_array(f[1].calls[-1]).is_equal(["mic", false])   # the key again: off, still in the room's voice

func test_a_no_hides_voice_and_market_square_has_it_since_q286() -> void:
	var f := _room()
	var room: P0VoiceRoom = f[0]
	await room.fetch_status()
	answers["age"] = {"ok": true, "available": true, "age": "no"}
	await room.answer_age(false)
	assert_bool(room.offered()).is_false()
	var m := _room("market")
	answers["status"] = {"ok": true, "available": true, "age": "ok"}
	await m[0].fetch_status()
	assert_bool(m[0].offered()).is_true()   # q(286): Market Square's whole layer has voice (SGODOT-415)

## Grace Cathedral has no voice (奕星 11-06; 后裔's #800 NO_VOICE_ROLES ['church']): no mic key, no count, the server
## answering yes or not.
func test_the_cathedral_has_no_voice() -> void:
	var c := _room("church")
	answers["status"] = {"ok": true, "available": true, "age": "ok"}
	await c[0].fetch_status()
	assert_bool(c[0].here).is_false()
	assert_bool(c[0].offered()).is_false()

func test_mute_is_kept_by_handle_and_put_on_the_new_peer_in_another_layer() -> void:
	var f := _room()
	var room: P0VoiceRoom = f[0]
	var online: P0Online = f[2]
	online._message(JSON.stringify({"t": "roster", "count": 2, "members": [{"id": 1, "player": "aaaa1111aaaa1111"}, {"id": 4, "player": "bbbb2222bbbb2222"}]}))
	room.set_muted(4, true)
	assert_array(f[1].calls[-1]).is_equal(["muted", "4", true])
	assert_array(JSON.parse_string(FileAccess.get_file_as_string(P0VoiceRoom.MUTES))).is_equal(["bbbb2222bbbb2222"])
	var rows: Array = room.people()
	assert_int(rows.size()).is_equal(2)   # the player first (q(289)), then the others
	assert_dict(rows[0]).contains_key_value("self", true).contains_key_value("name", "Traveller aaaa").contains_key_value("muted", false)
	assert_dict(rows[1]).contains_key_value("peer", 4).contains_key_value("muted", true).contains_key_value("name", "Traveller bbbb")
	# Layer 2: the same person is peer 2 now
	online._message(JSON.stringify({"t": "joined", "outpost": "sh_tea_1", "room": 2, "capacity": 12, "rejoined": false, "self": 3, "epoch": 3}))
	online._message(JSON.stringify({"t": "roster", "count": 2, "members": [{"id": 3, "player": "aaaa1111aaaa1111"}, {"id": 2, "player": "bbbb2222bbbb2222"}]}))
	assert_bool(f[1].calls.has(["muted", "2", true])).is_true()

func test_blocks_from_the_hub_reach_voice_and_block_report_go_to_the_server() -> void:
	var f := _room()
	var room: P0VoiceRoom = f[0]
	var online: P0Online = f[2]
	online._message(JSON.stringify({"t": "voice_blocks", "blocked": [4]}))
	assert_array(f[1].calls[-1]).is_equal(["blocked", ["4"]])
	await room.set_blocked(4, true)
	assert_array(asked[-1]).is_equal([HTTPClient.METHOD_POST, "/p0/voice/block", {"peer": 4, "on": true}])
	assert_str(await room.report(4, "shouting")).is_equal("sent")
	assert_array(asked[-1]).is_equal([HTTPClient.METHOD_POST, "/p0/voice/report", {"peer": 4, "reason": "shouting"}])
	answers["report"] = {"ok": true, "already": true}
	assert_str(await room.report(4)).is_equal("already")   # You already reported this (不知火舞's spec §6)

## The blocked are out of sight from the Block on: the Blocked list (handles) and Unblock by handle (q(28)).
func test_the_blocked_list_and_unblock_by_handle() -> void:
	var f := _room()
	var room: P0VoiceRoom = f[0]
	answers["blocks"] = {"ok": true, "blocked": [{"handle": "bbbb2222bbbb2222"}]}
	var rows: Array = await room.blocked_list()
	assert_array(rows).is_equal([{"handle": "bbbb2222bbbb2222", "name": "Traveller bbbb"}])
	assert_array(asked[-1]).is_equal([HTTPClient.METHOD_GET, "/p0/voice/blocks", {}])
	assert_bool(await room.unblock("bbbb2222bbbb2222")).is_true()
	assert_array(asked[-1]).is_equal([HTTPClient.METHOD_POST, "/p0/voice/unblock", {"handle": "bbbb2222bbbb2222"}])
	answers["blocks"] = {"ok": true, "blocked": []}
	assert_array(await room.blocked_list()).is_empty()   # none blocked: `No one blocked`

## The Blocked list not reached is null, never [] (奕星): the page must not say `No one blocked` for a failed read.
func test_the_blocked_list_not_reached_is_null_not_empty() -> void:
	var f := _room()
	var room: P0VoiceRoom = f[0]
	room.request = func(_m: int, _p: String, _b: Dictionary) -> Dictionary: return {"ok": false, "json": {}}
	assert_that(await room.blocked_list()).is_null()
	room.request = func(_m: int, _p: String, _b: Dictionary) -> Dictionary: return {"ok": true, "json": {"code": "x"}}
	assert_that(await room.blocked_list()).is_null()   # an answer without the list

func test_a_new_layer_with_voice_on_asks_again() -> void:
	var f := _room()
	f[1].is_active = true
	f[2]._message(JSON.stringify({"t": "joined", "outpost": "sh_tea_1", "room": 2, "capacity": 12, "rejoined": false, "self": 1, "epoch": 3}))
	assert_bool(f[1].calls.has(["invalidate"])).is_true()

## 李元芳 on 415 (232 f8ecefed): the first in a layer sees the count go up when the next comes in, and down when they go —
## the room's `changed` on every roster change, not only on the voice's own.
func test_the_room_says_changed_when_someone_comes_in_or_goes() -> void:
	var f := _room()
	var room: P0VoiceRoom = f[0]
	var online: P0Online = f[2]
	var said := []
	room.changed.connect(func(): said.append(room.people().size()))
	online._message(JSON.stringify({"t": "peer", "member": {"id": 4, "player": "bbbb2222bbbb2222"}}))
	assert_array(said).is_equal([1])
	online._message(JSON.stringify({"t": "left", "id": 4}))
	assert_array(said).is_equal([1, 0])
