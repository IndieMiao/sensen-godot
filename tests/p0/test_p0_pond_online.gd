extends GdUnitTestSuite
## Pond multiplayer (the user, 11-02 via 奕星; SGODOT-383): the pond is an online room of 8, `pond:<id>`. Our line goes to
## the room as the fishing panel moves (its landing, the reel's hold and fish at most every LINE_SEND_S, the fish landed,
## `none` once in); the others' lines come back as `fishing` and pose their rigs (OnlineCrowd.fishing_snapshot).

const P0Pond := preload("res://scenes/p0/p0_pond.gd")
const PHONE := Vector2(360, 800)

class FakeCrowd extends Node3D:
	var rosters: Array = []
	var lines: Array = []
	func roster(members: Dictionary) -> void: rosters.append(members.duplicate())
	func sample(_id: int, _state: Dictionary) -> void: pass
	func fishing_snapshot(states: Array) -> void: lines.append(states)

var sent: Array

func _pond() -> Node3D:
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_pond.gd\"\nfunc _ready() -> void: pass\n"
	stub.reload()
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	add_child(auto_free(vp))
	var pond: Node3D = Node3D.new()
	pond.set_script(stub)
	vp.add_child(pond)
	pond.entry = preload("res://modules/p0/p0_ponds.gd").location("pond_san_francisco_03")   # Fern Pond
	pond.bp = SystemPonds.blueprint(pond.entry)
	pond.grid = BlueprintGrid.new(pond.bp)
	pond.cam = Camera3D.new()
	pond.add_child(pond.cam)
	pond.actor = P0Actor.new()
	pond.add_child(pond.actor)
	pond.actor.setup(pond.bp, pond.grid, pond.cam)
	pond.panel = P0FishingPanel.new()
	pond.add_child(pond.panel)
	pond.panel.hide()
	return pond

func _online(pond: Node3D) -> P0Online:
	sent = []
	pond.crowd = auto_free(FakeCrowd.new())
	var o := P0Online.new()
	o.transport = func(m: Dictionary): sent.append(m)
	pond.attach_online(o)
	o._message(JSON.stringify({"t": "joined", "outpost": "pond:pond_san_francisco_03", "room": 1, "capacity": 8, "rejoined": false, "self": 2, "epoch": 4}))
	return o

func _lines() -> Array: return sent.filter(func(m): return str(m.get("t", "")) == "fish")

func test_the_ponds_room_is_pond_and_its_id() -> void:
	var pond := _pond()
	assert_str(pond.room_id()).is_equal("pond:pond_san_francisco_03")

func test_our_line_goes_to_the_room_as_the_panel_moves() -> void:
	var pond := _pond()
	var o := _online(pond)
	pond._tell_line(0.016)
	assert_array(_lines()).is_empty()   # no panel up: nothing new to say ("none" was never sent as a line)
	pond.panel.show()
	pond.panel.phase = "casting"
	pond.panel.landing = Vector3(5.123, 0, -3.456)
	pond._tell_line(0.016)
	assert_dict(_lines()[-1]).is_equal({"t": "fish", "epoch": 4, "phase": "casting", "target": [5.12, -3.46]})
	pond.panel.phase = "waiting"
	pond._tell_line(0.016)
	assert_str(str(_lines()[-1].phase)).is_equal("waiting")   # a phase change goes at once
	pond.panel.phase = "playing"
	pond.panel.model = {"fish": 0.42}
	pond.panel.held = true
	pond._tell_line(0.016)
	assert_dict(_lines()[-1]).contains_key_value("held", true).contains_key_value("fish", 0.4)
	var n := _lines().size()
	pond.panel.held = false
	pond._tell_line(0.016)
	assert_int(_lines().size()).is_equal(n)   # the hold moves within LINE_SEND_S: it waits
	pond._tell_line(P0Pond.LINE_SEND_S)
	assert_bool(bool(_lines()[-1].held)).is_false()
	pond.panel.phase = "result"
	pond.panel._last = {"outcome": "caught", "fish_id": "fish_crucian", "tier": 1}
	pond._tell_line(0.016)
	assert_dict(_lines()[-1]).contains_key_value("outcome", "caught").contains_key_value("fish_id", "fish_crucian")
	pond.panel.hide()
	pond._tell_line(0.016)
	assert_dict(_lines()[-1]).is_equal({"t": "fish", "epoch": 4, "phase": "none"})
	assert_object(o).is_not_null()

func test_the_rig_is_posed_by_the_line_and_the_others_lines_reach_the_crowd() -> void:
	var pond := _pond()
	var o := _online(pond)
	assert_str(pond._online_action()).is_equal("idle")
	pond.panel.show()
	pond.panel.phase = "waiting"
	assert_str(pond._online_action()).is_equal("fishing_wait")
	pond.panel.phase = "playing"
	assert_str(pond._online_action()).is_equal("fishing_reel")
	var line := {"id": 5, "sequence": 1, "target": [6, -3], "phase": "waiting", "age": 0.2, "cast_age": 1.1, "held": false, "fish": 0.5}
	o._message(JSON.stringify({"t": "fishing", "epoch": 4, "members": [line]}))
	o._message(JSON.stringify({"t": "fishing", "epoch": 3, "members": [line]}))   # an older join's: dropped
	assert_int(pond.crowd.lines.size()).is_equal(1)
	assert_int(int(pond.crowd.lines[0][0].id)).is_equal(5)

func test_a_line_before_the_join_is_not_sent() -> void:
	var o := P0Online.new()
	auto_free(o)
	sent = []
	o.transport = func(m: Dictionary): sent.append(m)
	o.fish({"phase": "casting", "target": [1, 1]})
	assert_array(sent).is_empty()

## 奕星 on #646: Layer 2 and later say so once, as an outpost's do; Layer 1 and a reconnect say nothing. The user, 11-02:
## the player reads a room as a "Layer".
func test_layer_2_says_so_once() -> void:
	assert_str(P0Online.layer_notice({"room": 2, "rejoined": false})).is_equal("Layer 1 is full · you're in Layer 2")
	assert_str(P0Online.layer_notice({"room": 3, "rejoined": false})).is_equal("Layer 2 is full · you're in Layer 3")
	assert_str(P0Online.layer_notice({"room": 2, "rejoined": true})).is_empty()   # back in the layer just left
	assert_str(P0Online.layer_notice({"room": 1, "rejoined": false})).is_empty()
	var pond := _pond()
	var o := _online(pond)
	assert_bool(o.joined.is_connected(pond._on_joined)).is_true()
