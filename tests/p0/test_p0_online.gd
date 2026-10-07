extends GdUnitTestSuite
## P0Online (SGODOT-227): the outpost room client. Frame v1 decoding against bytes written by the P0
## server's encoder (tests/fixtures/p0/frame_v1.hex), the join / roster / seat messages, and inputs
## sent only when something changed.

class FakeCrowd extends Node:
	var rosters: Array = []
	var samples: Array = []
	func roster(members: Dictionary) -> void: rosters.append(members.duplicate())
	func sample(id: int, state: Dictionary) -> void: samples.append([id, state])

var online: P0Online
var crowd: FakeCrowd
var sent: Array

func before_test() -> void:
	online = auto_free(P0Online.new())
	crowd = auto_free(FakeCrowd.new())
	online.crowd = crowd
	sent = []
	online.transport = func(m: Dictionary): sent.append(m)

func _fixture() -> PackedByteArray:
	return FileAccess.get_file_as_string("res://tests/fixtures/p0/frame_v1.hex").strip_edges().hex_decode()

func _join(epoch := 3, self_id := 1, room := 1, rejoined := false) -> void:
	online._message(JSON.stringify({"t": "joined", "outpost": "sh_tea_1", "room": room, "capacity": 12, "rejoined": rejoined, "self": self_id, "epoch": epoch}))

func test_ws_url_follows_the_p0_server_url() -> void:
	assert_str(P0Online.ws_url("http://127.0.0.1:3110/v1")).is_equal("ws://127.0.0.1:3110/v1/p0/online")
	assert_str(P0Online.ws_url("https://p0.example.com/v1/")).is_equal("wss://p0.example.com/v1/p0/online")

func test_decodes_the_server_frame_bytes() -> void:
	var states := P0Online.decode_frame(_fixture(), 3)
	assert_int(states.size()).is_equal(2)
	assert_int(states[0].id).is_equal(1)
	assert_vector(states[0].position).is_equal_approx(Vector3(1.25, 0, -2.5), Vector3.ONE * 0.0001)
	assert_float(states[0].yaw).is_equal_approx(0.75, 0.0001)
	assert_str(P0Online.ACTIONS[states[0].action]).is_equal("walk")
	assert_int(states[0].seq).is_equal(7)
	assert_str(P0Online.ACTIONS[states[1].action]).is_equal("sit")
	assert_int(P0Online.frame_tick(_fixture())).is_equal(42)

func test_frames_for_another_epoch_or_truncated_are_ignored() -> void:
	assert_array(P0Online.decode_frame(_fixture(), 2)).is_empty()
	assert_array(P0Online.decode_frame(_fixture().slice(0, 30), 3)).is_empty()

func test_sit_matches_the_crowd_action_index() -> void:
	assert_int(P0Online.ACTIONS.find("sit")).is_equal(load("res://modules/net/online_crowd.gd").SIT_ACTION)
	assert_array(P0Online.ACTIONS.slice(0, OnlineSpace.ACTIONS.size())).is_equal(OnlineSpace.ACTIONS)

func test_roster_feeds_the_crowd_without_ourselves_and_frames_skip_us() -> void:
	_join(3, 1)
	online._message(JSON.stringify({"t": "roster", "count": 2, "members": [{"id": 1, "player": "me-000001", "seat": ""}, {"id": 4, "player": "them-00004", "seat": ""}]}))
	assert_array(crowd.rosters[-1].keys()).is_equal([4])
	online._frame(_fixture())
	assert_int(crowd.samples.size()).is_equal(1)
	assert_int(crowd.samples[0][0]).is_equal(4)
	online._frame(_fixture())   # same tick again: dropped
	assert_int(crowd.samples.size()).is_equal(1)
	online._message(JSON.stringify({"t": "left", "id": 4, "count": 1}))
	assert_bool(crowd.rosters[-1].is_empty()).is_true()

func test_joined_reports_room_and_rejoin() -> void:
	var got := []
	online.joined.connect(func(info): got.append(info))
	_join(5, 2, 2, true)
	assert_int(online.room).is_equal(2)
	assert_int(online.epoch).is_equal(5)
	assert_bool(got[0].rejoined).is_true()

func test_seat_messages_update_members() -> void:
	_join()
	online._message(JSON.stringify({"t": "roster", "count": 2, "members": [{"id": 1, "player": "me-000001", "seat": ""}, {"id": 4, "player": "them-00004", "seat": ""}]}))
	online._message(JSON.stringify({"t": "seat", "id": 4, "seat": "seat_table1_1"}))
	assert_str(online.seat_of(4)).is_equal("seat_table1_1")
	assert_int(online.sit("seat_table1_2")).is_equal(1)
	assert_dict(sent[-1]).is_equal({"t": "act", "seq": 1, "epoch": 3, "action": "sit", "node": "seat_table1_2"})

func test_inputs_are_sent_only_when_something_changed() -> void:
	var pos := {"position": Vector3(1, 0, -1), "yaw": 0.5, "action": "walk"}
	online.source = func(): return pos
	_join()
	online._tick(0.2)
	assert_int(sent.filter(func(m): return m.t == "input").size()).is_equal(1)
	online._tick(0.2)   # same position and action
	assert_int(sent.filter(func(m): return m.t == "input").size()).is_equal(1)
	pos.position = Vector3(1.5, 0, -1)   # lambdas capture by value: mutate, don't reassign
	online._tick(0.2)
	var inputs := sent.filter(func(m): return m.t == "input")
	assert_int(inputs.size()).is_equal(2)
	assert_dict(inputs[1]).contains_key_value("x", 1.5)
	assert_int(int(inputs[1].epoch)).is_equal(3)
