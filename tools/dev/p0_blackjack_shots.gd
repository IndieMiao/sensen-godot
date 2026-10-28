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

func _rig(coins: int, intro := true, last_bet := 0, safe_top := 0.0) -> Rig:
	var m := P0BlackjackMock.new(11)
	m.intro = intro
	m.last_bet = last_bet
	var page := P0BlackjackPage.new(m.decorate({"coins": coins}), safe_top, 0.0)
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
		if OS.get_environment("VIDEO_KIND") == "settle": await _video_settle(OS.get_environment("VIDEO"))
		elif OS.get_environment("VIDEO_KIND") == "settle-low": await _video_settle(OS.get_environment("VIDEO"), true)
		else: await _video(OS.get_environment("VIDEO"))
		quit()
		return
	var states := ["bj-bet", "bj-bet-empty", "bj-bet-cap", "bj-drag", "bj-low", "bj-act", "bj-act-grey", "bj-split",
		"bj-result-blackjack", "bj-result-lose", "bj-result-bust", "bj-result-push", "bj-rules", "bj-intro", "bj-settled",
		"bj-tall", "bj-short", "bj-result-win", "bj-result-dealer-busts", "bj-result-win-float", "bj-result-blackjack-float",
		"bj-safe-top"]
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
	p._ghost.position = p.circle_center() - p._ghost.size * 0.5 + Vector2(22, -18)
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

func _state_bj_result_win() -> Rig:
	var r := _rig(500)
	await _deal(r, ["TS", "TD", "9H", "7C"], 120)   # 19 against 17
	r.send({"type": "bj_act", "action": "stand"})
	await _settle()
	return r

func _state_bj_result_dealer_busts() -> Rig:
	var r := _rig(500)
	await _deal(r, ["TS", "TD", "8H", "6C", "KH"], 120)   # 18 stands; the dealer's 16 draws a K
	r.send({"type": "bj_act", "action": "stand"})
	await _settle()
	return r

## Motion on, caught while the winnings slide in and `+120 coins` floats (RESULT-T 191:169661 / 192:171017).
func _state_bj_result_win_float() -> Rig:
	var r := _rig(500)
	await _deal(r, ["TS", "TD", "9H", "7C"], 120)
	r.page.animate = true
	r.send({"type": "bj_act", "action": "stand"})
	await create_timer(float(OS.get_environment("FLOAT_AT")) if OS.has_environment("FLOAT_AT") else 1.1).timeout
	return r

func _state_bj_result_blackjack_float() -> Rig:
	var r := _rig(500)
	r.page.animate = true
	await _deal(r, ["AS", "7D", "KH", "9C"], 120)
	await create_timer(float(OS.get_environment("FLOAT_AT")) if OS.has_environment("FLOAT_AT") else 1.6).timeout
	return r

## A phone's safe area (44 at the top): back, Rules and coins on one row under it (不知火舞 351 ed79b57c ①); a Push.
func _state_bj_safe_top() -> Rig:
	var r := _rig(500, true, 0, 44.0)
	await _deal(r, ["TS", "TD", "QH", "QC"], 120)
	r.send({"type": "bj_act", "action": "stand"})
	await _settle()
	return r

func _state_bj_rules() -> Rig:
	var r := _rig(300)
	_bet(r, [100, 10, 10])
	await _settle()   # a tap comes after the page is laid out: the rules wrap to its width
	r.page.open_rules()
	return r

func _state_bj_intro() -> Rig:
	var r := _rig(300, false)
	r.page.opened()
	return r

## Other screen proportions: the picture stays on the bottom edge (cropped from the top / sides).
func _state_bj_tall() -> Rig:
	var r := _rig(300)
	_bet(r, [100, 10, 10])
	r.page.set_anchors_preset(Control.PRESET_TOP_LEFT)
	r.page.size = Vector2(360, 860)
	r.page.position = Vector2(0, -60)
	return r

func _state_bj_short() -> Rig:
	var r := _rig(300)
	_bet(r, [100, 10, 10])
	r.page.set_anchors_preset(Control.PRESET_TOP_LEFT)
	r.page.size = Vector2(360, 720)
	r.page.position = Vector2(0, 80)
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

## Press and release in one frame: frames saved to disk run far slower than real time, so a press held across frames
## would outlast GestureArbiter.TAP_MAX_MS in wall-clock time and not count as a tap. The marker stays down a moment.
func _tap(p: Vector2) -> void:
	_move(p)
	await _wait(0.15)
	_mouse(p, true)
	_mouse(p, false)
	_finger.down = true
	_finger.queue_redraw()
	await _wait(0.1)
	_finger.down = false
	_finger.queue_redraw()

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
	return page.stack_top(i)

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
	await _tap(p.circle_center())      # tap the stake: it all goes back (no Clear)
	await _wait(0.7)
	await _tap(_chip(p, 3))
	await _wait(0.3)
	await _tap(_chip(p, 1))
	await _wait(0.3)
	await _tap(_chip(p, 1))            # 120 again
	await _wait(0.7)
	r.mock.next_deck = ["9S", "6D", "8H", "TC", "4C"]
	await _tap(_centre(p.deal_key))    # Deal
	await _wait(1.6)
	await _tap(_centre(p.stand_key))   # Stand: the hole card turns over, the dealer draws, the result
	await _wait(2.6)
	r.mock.next_deck = ["TS", "7D", "QH", "9C"]
	await _tap(_centre(p.deal_key))    # the stake set itself again: Deal
	await _wait(1.8)
	_rec = false
	await _settle()
	print("video frames ", _frame)

## VIDEO_KIND=settle (不知火舞 351 d1969a60): each hand's settling as it plays — opening on last hand's bet, a win, a loss,
## a push on one hand, a doubled push, a split won and lost, and a loss the wallet steps the next bet down for. A caption
## names each hand; "mark <name> <frame>" lines in the log say where each result begins.
var _caption: Label

func _say(text: String) -> void:
	_caption.text = text
	_caption.size = Vector2(360, 24)

func _hand(r: Rig, name: String, deck: Array, moves: Array, after := 3.2) -> void:
	_say(name)
	r.mock.next_deck = deck
	await _tap(_centre(r.page.deal_key))
	await _wait(1.6)
	for m in moves:
		print("mark ", name, " ", _frame)
		var key: UiFeltAction = r.page.get(m + "_key")
		await _tap(_centre(key))
		await _wait(1.4)
	await _wait(after)

func _video_settle(dir: String, low := false) -> void:
	_frames_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)
	var r := _rig(90 if low else 500, true, 50)
	r.page.animate = true
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.position = Vector2(0, 92)
	_caption.add_theme_font_size_override(&"font_size", 13)
	_caption.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.9))
	_caption.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.7))
	_caption.add_theme_constant_override(&"outline_size", 4)
	layer.add_child(_caption)
	_finger = Finger.new()
	_finger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finger.position = Vector2(180, 760)
	layer.add_child(_finger)
	_say("Open with last bet 50")
	await _settle()
	_rec = true
	_record_loop()
	var p := r.page
	print("mark open ", _frame)
	await _wait(1.6)
	if low:   # 90 coins, bet 50, lose: 40 left, not even 5 above the floor
		await _hand(r, "7 Bet 50 of 90, lose: Low on coins", ["9S", "KD", "8H", "TC"], ["stand"])
		_rec = false
		await _settle()
		print("video frames ", _frame)
		return
	await _hand(r, "1 Win (20 vs 17)", ["TS", "7D", "KH", "TC"], ["stand"])
	await _hand(r, "2 Lose (17 vs 20)", ["9S", "KD", "8H", "TC"], ["stand"])
	await _hand(r, "3 Push, one hand (17 vs 17)", ["9S", "7D", "8H", "TC"], ["stand"], 2.0)
	await _hand(r, "4 Push after Double (17 vs 17)", ["6S", "7D", "5H", "TC", "6C"], ["double"])
	await _hand(r, "5 Split: win 18 / lose 15 vs 17", ["8S", "9D", "8H", "8C", "TS", "7H"], ["split", "stand", "stand"])
	_say("6 Bet 300, lose: 200 left, next bet 160")
	await _tap(p.circle_center())      # take the 50 back
	await _wait(0.5)
	for i in 3:
		await _tap(_chip(p, 3))
		await _wait(0.35)
	await _wait(0.4)
	await _hand(r, "6 Bet 300, lose: 200 left, next bet 160", ["9S", "KD", "8H", "TC"], ["stand"])
	_rec = false
	await _settle()
	print("video frames ", _frame)
