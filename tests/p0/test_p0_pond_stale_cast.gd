extends GdUnitTestSuite
## SGODOT-463 (Pixel, Fern Pond: 「无法钓鱼…可能点太快了…重启也不能用」): a line the client stopped watching stayed on the
## server, the view's cast greyed the key at `Fishing…`, and only a new cast would have settled it. A cast whose reply
## comes with no panel open is reeled straight in; while the panel casts, the old line's catch (settled by the new cast)
## is left to the runtime, so the panel keeps the new line.

const P0Pond := preload("res://scenes/p0/p0_pond.gd")

var sent: Array

func _pond() -> Node3D:
	var session: P0Session = auto_free(P0Session.new())   # not in the tree: no refresh, no files
	session.transport = func(_method: int, _path: String, _body: Dictionary, cmd: Dictionary): sent.append(cmd)
	session.view = {"seq": 3}
	var rt: P0Runtime = auto_free(P0Runtime.new())
	rt.session = session
	var pond = auto_free(P0Pond.new())   # not in the tree: no _ready, only its event handling
	pond.rt = rt
	pond.panel = auto_free(P0FishingPanel.new())
	return pond

func before_test() -> void:
	sent = []

func test_a_cast_answered_with_no_panel_open_is_reeled_straight_in() -> void:
	var pond := _pond()
	pond.panel.visible = false
	pond.p0_event({"kind": "cast", "bite_in": 2000, "rarity": 1, "breaks": null}, {})
	assert_int(sent.size()).is_equal(1)
	assert_dict(sent[0]).is_equal({"type": "reel", "outcome": "cancel"})

func test_a_cast_answered_to_the_open_panel_is_watched_not_reeled() -> void:
	var pond := _pond()
	add_child(pond.panel)   # its gauge and card are built in _ready
	pond.panel.visible = true
	pond.panel.rt = pond.rt
	pond.panel.phase = "casting"
	pond.p0_event({"kind": "cast", "bite_in": 2000, "rarity": 1, "breaks": null}, {})
	assert_array(sent).is_empty()
	assert_str(pond.panel.phase).is_equal("waiting")

func test_while_casting_the_old_lines_catch_is_left_to_the_runtime() -> void:
	var pond := _pond()
	pond.panel.visible = true
	pond.panel.phase = "casting"
	var shown = pond.p0_event({"kind": "catch", "fish": "", "rarity": 1, "result": "escaped", "refund": 3}, {})
	assert_bool(shown == true).is_false()   # the runtime says `Got away` for the old line
	assert_str(pond.panel.phase).is_equal("casting")   # the panel still waits for the new line's cast
	assert_array(sent).is_empty()
