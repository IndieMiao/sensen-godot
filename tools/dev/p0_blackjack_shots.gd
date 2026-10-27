extends SceneTree
## SGODOT-351 Blackjack page shots at 360 × 800 through P0BlackjackMock (no server, no world): each state of q(240)
## laid out as the frames name them (BJ-BET, BJ-BET-EMPTY, BJ-BET-CAP, BJ-DRAG, BJ-LOW, BJ-ACT…), saved as PNGs.
##   godot --path . --resolution 720x1600 -s tools/dev/p0_blackjack_shots.gd  (OUT=dir, ONLY=name,name, SCALE=2)
## MOVIE=1 keeps motion on (for frame strips); shots otherwise lay each state out at once.

var out := OS.get_environment("OUT") if OS.has_environment("OUT") else "user://bj_shots"
var only := OS.get_environment("ONLY").split(",", false) if OS.has_environment("ONLY") else PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

## Page + mock wired as P0Runtime does: a command goes to the mock, its reply's view then events come back.
class Rig:
	var page: P0BlackjackPage
	var mock: P0BlackjackMock
	func _init(p: P0BlackjackPage, m: P0BlackjackMock) -> void:
		page = p
		mock = m
		p.command.connect(send)
	func send(cmd: Dictionary) -> void:
		var r := mock.command(cmd, page.view)
		var v := mock.decorate(r.state)
		page.refresh(v)
		if bool(r.ok): page.on_events(r.events)
		else: page.refused(str(r.code), r.get("detail", {}))

func _rig(coins: int, intro := true, last_bet := 0) -> Rig:
	var m := P0BlackjackMock.new(11)
	m.intro = intro
	m.last_bet = last_bet
	var page := P0BlackjackPage.new(m.decorate({"coins": coins}), 0.0, 0.0)
	page.theme = UiKit.theme()
	page.animate = OS.get_environment("MOVIE") == "1"
	root.add_child(page)
	return Rig.new(page, m)

func _settle() -> void:
	for i in 6: await process_frame

func _shot(name: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out)
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name, " ", img.get_size())

func _want(name: String) -> bool: return only.is_empty() or name in only

func _run() -> void:
	await process_frame
	var states := ["bj-bet", "bj-bet-empty", "bj-bet-cap", "bj-drag", "bj-low", "bj-act", "bj-act-grey", "bj-split",
		"bj-result-blackjack", "bj-result-lose", "bj-result-bust", "bj-result-push", "bj-rules", "bj-intro", "bj-settled"]
	for s in states:
		if not _want(s): continue
		var rig: Rig = await call("_state_" + s.replace("-", "_"))
		await _shot(s)
		rig.page.queue_free()
		await _settle()
	quit()

func _bet(rig: Rig, values: Array) -> void:
	for v in values: rig.page.add_chip(v)

func _state_bj_bet() -> Rig:
	var r := _rig(300)
	_bet(r, [100, 10, 10])
	return r

func _state_bj_bet_empty() -> Rig:
	return _rig(300)

func _state_bj_bet_cap() -> Rig:
	var r := _rig(300)
	_bet(r, [100, 10, 10])   # 500 and 1K would leave under 40: grey
	return r

func _state_bj_drag() -> Rig:
	var r := _rig(300)
	_bet(r, [100, 10, 10])
	await _settle()
	var p := r.page
	p._press = {"index": 2, "start": Vector2.ZERO, "t0": 0, "touch": false, "id": -1}
	p._begin_drag()
	p._ghost.position = p.circle_center() - p._ghost.size * 0.5 + Vector2(22, 18)
	p.circle.lit = true
	return r

func _state_bj_low() -> Rig:
	return _rig(43)

func _deal(r: Rig, deck: Array, bet: int) -> void:
	r.mock.next_deck = deck
	r.page.stack = P0Blackjack.chips_for(bet)
	r.page.deal(bet)
	await _settle()

func _state_bj_act() -> Rig:
	var r := _rig(500)
	await _deal(r, ["AS", "KD", "6H", "7C", "5D", "8S"], 120)   # A·6 soft 17 against a K
	return r

func _state_bj_act_grey() -> Rig:
	var r := _rig(260)   # 140 after the deal: Double 120 would leave 20 → Need 20 more coins; Split: Pairs only
	await _deal(r, ["AS", "KD", "6H", "7C", "5D", "8S"], 120)
	return r

func _state_bj_split() -> Rig:
	var r := _rig(600)
	await _deal(r, ["8S", "6D", "8H", "TC", "3S", "2H", "TD", "9C"], 120)
	r.send({"type": "bj_act", "action": "split"})
	await _settle()
	return r

func _state_bj_result_blackjack() -> Rig:
	var r := _rig(500)
	await _deal(r, ["AS", "7D", "KH", "9C"], 120)
	return r

func _state_bj_result_lose() -> Rig:
	var r := _rig(500)
	await _deal(r, ["9S", "KD", "8H", "9C"], 120)
	r.send({"type": "bj_act", "action": "stand"})
	await _settle()
	return r

func _state_bj_result_bust() -> Rig:
	var r := _rig(500)
	await _deal(r, ["TS", "6D", "5H", "9C", "KH"], 120)
	r.send({"type": "bj_act", "action": "hit"})
	await _settle()
	return r

func _state_bj_result_push() -> Rig:
	var r := _rig(500)
	await _deal(r, ["TS", "TD", "QH", "QC"], 120)
	r.send({"type": "bj_act", "action": "stand"})
	await _settle()
	return r

func _state_bj_rules() -> Rig:
	var r := _rig(300)
	r.page.open_rules()
	return r

func _state_bj_intro() -> Rig:
	var r := _rig(300, false)
	r.page.opened()
	return r

func _state_bj_settled() -> Rig:
	var r := _rig(320)
	r.page.animate = true
	r.page.show_settled(P0Blackjack.settled_line({"net": 20}))
	return r
