extends SceneTree
## SGODOT-351 Blackjack page shots at 360 × 800 through P0BlackjackMock (no server, no world): each state of q(240)
## laid out as the frames name them (BJ-BET, BJ-BET-EMPTY, BJ-BET-CAP, BJ-DRAG, BJ-LOW, BJ-ACT…), saved as PNGs.
##   godot --path . --resolution 720x1600 -s tools/dev/p0_blackjack_shots.gd  (OUT=dir, ONLY=name,name, SCALE=2)
## MOVIE=1 keeps motion on (for frame strips); shots otherwise lay each state out at once.
## VIDEO=dir records the gesture walkthrough instead (run with --fixed-fps 30): real mouse events through the viewport,
## a finger marker, every frame saved — tap adds, drag in adds, drag out flies back, a grey chip takes neither, Clear,
## Deal, Stand, Deal again. ffmpeg -framerate 30 -i dir/f_%05d.png makes the video.

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
	if OS.has_environment("VIDEO"):
		await _video(OS.get_environment("VIDEO"))
		quit()
		return
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

# ---------------------------------------------------------------- the gesture video

var _frames_dir := ""
var _frame := 0
var _finger: Control
var _rec := false

class Finger extends Control:
	var down := false
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 20.0 if down else 14.0, Color(1, 1, 1, 0.45 if down else 0.25))
		draw_arc(Vector2.ZERO, 20.0 if down else 14.0, 0.0, TAU, 32, Color(0.18, 0.23, 0.2, 0.6), 2.0, true)

func _record_loop() -> void:
	while _rec:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_frames_dir.path_join("f_%05d.png" % _frame))
		_frame += 1

func _wait(sec: float) -> void:
	var n := int(sec * 30.0)
	for i in n: await process_frame

## A logical (360-wide) point to the window's pixels for Input.parse_input_event.
func _win(p: Vector2) -> Vector2:
	var k := Vector2(DisplayServer.window_get_size()) / root.get_visible_rect().size
	return p * k

func _mouse(p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = _win(p)
	e.global_position = e.position
	Input.parse_input_event(e)
	_finger.down = pressed
	_finger.position = p
	_finger.queue_redraw()

func _move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _win(p)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _finger.down else 0
	Input.parse_input_event(e)
	_finger.position = p

func _tap(p: Vector2) -> void:
	_move(p)
	await _wait(0.15)
	_mouse(p, true)
	await _wait(0.1)
	_mouse(p, false)

func _drag(from: Vector2, to: Vector2, sec := 0.7, hold := 0.35) -> void:
	_move(from)
	await _wait(0.15)
	_mouse(from, true)
	await _wait(0.12)
	var n := int(sec * 30.0)
	for i in n:
		_move(from.lerp(to, ease(float(i + 1) / n, 0.6)))
		await process_frame
	await _wait(hold)
	_mouse(to, false)

func _chip(page: P0BlackjackPage, i: int) -> Vector2:
	return page.tray.position + (page.chips[i] as Control).position + Vector2.ONE * UiChipToken.SIZE * 0.5

func _centre(c: Control) -> Vector2: return c.get_global_rect().get_center()

func _video(dir: String) -> void:
	_frames_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)
	var r := _rig(300)
	r.page.animate = true
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	_finger = Finger.new()
	_finger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finger.position = Vector2(180, 760)
	layer.add_child(_finger)
	await _settle()
	_rec = true
	_record_loop()
	var p := r.page
	await _wait(0.8)
	await _tap(_chip(p, 3))            # tap: 100 flies in
	await _wait(0.6)
	await _tap(_chip(p, 1))            # 10
	await _wait(0.4)
	await _tap(_chip(p, 1))            # 10 → 120
	await _wait(0.7)
	await _drag(_chip(p, 2), p.circle_center() + Vector2(0, 30))   # drag 50 in: the ring lights, it adds → 170
	await _wait(0.8)
	await _drag(_chip(p, 1), Vector2(70, 330), 0.6, 0.3)          # drag 10 out: flies back, nothing added
	await _wait(0.9)
	await _tap(_chip(p, 4))            # 500 is grey (170 + 500 > 300 − 40): nothing
	await _wait(0.5)
	await _drag(_chip(p, 5), p.circle_center(), 0.5, 0.2)          # 1K grey: no drag either
	await _wait(0.8)
	await _tap(_centre(p.clear_key))   # Clear: 0
	await _wait(0.7)
	await _tap(_chip(p, 3))
	await _wait(0.3)
	await _tap(_chip(p, 1))
	await _wait(0.3)
	await _tap(_chip(p, 1))            # 120 again
	await _wait(0.7)
	r.mock.next_deck = ["9S", "6D", "8H", "TC", "4C"]
	await _tap(_centre(p.deal_key))    # Deal · 120
	await _wait(1.6)
	await _tap(_centre(p.stand_key))   # Stand: the hole card turns over, the dealer draws, the result
	await _wait(2.6)
	r.mock.next_deck = ["TS", "7D", "QH", "9C"]
	await _tap(_centre(p.again_key))   # Deal again · 120
	await _wait(1.8)
	_rec = false
	await _settle()
	print("video frames ", _frame)
