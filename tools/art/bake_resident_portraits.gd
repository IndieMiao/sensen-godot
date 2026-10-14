extends SceneTree
## Kindred postcard stamps (q(171), SGODOT-284; 上官婉儿): bakes each resident's card portrait — 300 × 660, the format of
## pip-portrait.jpg — from the look their 3D figure wears, on P0KeeperPortraits' own stage (#339: the same light, sky and
## three-quarter turn as the generated keepers), so the twelve stamps read as one set. Residents and their portrait keys
## come from the content (residents), their looks from assets/p0/outpost_npcs.json; --looks=<json> adds or overrides
## looks ({"res_x": {"slots": {...}}}) for residents that have none yet. Writes, under --out:
##   <portrait>_card.jpg       one card per resident with a look (the game's assets/p0/art/residents/, 苏烈)
##   cards.png                 every card side by side at half size, in the residents' table order
##   stamps.png                each head as the stamp shows it: 32 × 40 (top row) and 3× (bottom row)
##   crops.json                per portrait key, the head box on the card: stamp (32:40) and face (square) rects
##   portrait_crops.json       the same two boxes only, {key: {stamp, face}}, as the game reads them
##                             (assets/p0/art/residents/portrait_crops.json: the stamp and the profile face crop from it)
## Needs a window (no --headless):
##   godot --path . --script res://tools/art/bake_resident_portraits.gd -- [--looks=<json>] [--out=<dir>] [--ids=res_a,res_b]

const NPCS_PATH := "res://assets/p0/outpost_npcs.json"
const STAMP := Vector2i(32, 40)
const STAMP_ZOOM := 3
const WAIT_FRAMES := 900
const WATCHDOG_S := 600.0   # never left hanging (an error in _run stops it, not the window)
var KP: GDScript   # P0KeeperPortraits, loaded once the autoloads (Avatar …) are up: a preload compiles too early
var OA: GDScript   # OnlineAppearance, likewise
var _elapsed := 0.0
var _out := "output/resident-portraits"
var _looks_path := ""
var _only: PackedStringArray = []
var _cols := 0   # stamps.png / cards.png wrap after this many (0: one row)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.trim_prefix("--out=")
		elif a.begins_with("--looks="): _looks_path = a.trim_prefix("--looks=")
		elif a.begins_with("--ids="): _only = a.trim_prefix("--ids=").split(",", false)
		elif a.begins_with("--cols="): _cols = int(a.trim_prefix("--cols="))
	if DisplayServer.get_name() == "headless":
		printerr("needs a window: drop --headless")
		quit(2)
		return
	_run.call_deferred()

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > WATCHDOG_S:
		printerr("watchdog: %d s, giving up" % WATCHDOG_S)
		return true
	return false

func _run() -> void:
	KP = load("res://modules/p0/p0_keeper_portraits.gd")
	OA = load("res://modules/net/online_appearance.gd")
	var avatar := root.get_node_or_null("/root/Avatar")
	if KP == null or OA == null or avatar == null:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var looks := _looks()
	var content := P0Logic.content()
	var kp: Node = KP.new()   # its stage: the same viewport, light, sky, turn and card framing as the keepers
	root.add_child(kp)
	await process_frame
	var cards: Array[Image] = []
	var keys: Array[String] = []
	var crops := {}
	var residents: Dictionary = content.get("residents", {})
	var ids: Array = residents.keys() + looks.keys().filter(func(k): return not residents.has(k))   # then option looks (--looks)
	for id in ids:
		if not _only.is_empty() and not _only.has(id): continue
		if not looks.has(id):
			print("skip %s: no look" % id)
			continue
		var key := str(residents[id].get("portrait", "")) if residents.has(id) else str(id)
		var shot: Dictionary = await _shoot(kp, avatar, looks[id])
		if shot.is_empty():
			printerr("%s: nothing drawn" % id)
			continue
		var card: Image = shot.card
		card.convert(Image.FORMAT_RGB8)
		card.save_jpg("%s/%s_card.jpg" % [_out, key], 0.92)
		cards.append(card)
		keys.append(key)
		crops[key] = _head_crops(card, shot.neck)
		print("baked %s → %s_card.jpg  stamp %s  face %s" % [id, key, crops[key].stamp, crops[key].face])
	if cards.is_empty():
		quit(1)
		return
	_sheet_cards(cards, _cols).save_png(_out + "/cards.png")
	_sheet_stamps(cards, keys, crops, _cols).save_png(_out + "/stamps.png")
	var f := FileAccess.open(_out + "/crops.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"order": keys, "crops": crops}, "  "))
	f.close()
	var game := {}
	for k in keys: game[k] = {"stamp": crops[k].stamp, "face": crops[k].face}
	f = FileAccess.open(_out + "/portrait_crops.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(game, "  ", false))
	f.close()
	print("done: %d cards in %s" % [cards.size(), _out])
	quit(0)

## P0KeeperPortraits._draw's card, step for step, on its own stage — plus where the head bone (Head_M, at the jaw)
## lands on the card, which the head crop is measured from: {card: Image, neck: Vector2} or {} when nothing is drawn.
func _shoot(kp: Node, avatar: Node, slots: Dictionary) -> Dictionary:
	kp._stage(KP.CARD)
	var rig: Node3D = avatar.create_rig()
	for child in rig.get_children():   # a still picture: no distance polling
		if child is RigActivity:
			rig.remove_child(child)
			child.free()
	rig.rotation.y = KP.TURN
	kp._viewport.add_child(rig)
	rig.apply_config(OA.config({"version": 1, "slots": slots}, true))
	var frames := 0
	while rig.is_busy() and frames < KP.BUSY_FRAMES:
		frames += 1
		await process_frame
	rig.play_motion("idle")
	var animation := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation: animation.pause()
	await process_frame
	var bounds := DressingCamera.merged_aabb(rig)
	var card: Image = await kp._card(bounds)
	var neck := Vector2(-1, -1)
	if rig.skeleton:
		var bone: int = rig.skeleton.find_bone("Head_M")
		if bone >= 0: neck = kp._camera.unproject_position(rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(bone).origin)
	kp._viewport.remove_child(rig)
	rig.free()
	if card == null or card.is_empty(): return {}
	return {"card": card, "neck": neck}

## res_* looks from outpost_npcs.json, then --looks on top.
func _looks() -> Dictionary:
	var out := {}
	var npcs = JSON.parse_string(FileAccess.get_file_as_string(NPCS_PATH))
	for id in (npcs.get("npcs", {}) as Dictionary):
		if str(id).begins_with("res_") and npcs.npcs[id].has("slots"): out[id] = npcs.npcs[id].slots
	if _looks_path != "":
		var extra = JSON.parse_string(FileAccess.get_file_as_string(_looks_path))
		for id in (extra as Dictionary): out[id] = extra[id].get("slots", extra[id])
	return out

## The head on a card: from the figure's top (the first row off the sky, the corner pixel) down to the head bone (Head_M,
## at the jaw), centred on the bone. stamp: a 32:40 box from just above the top to past the jaw (a little of the
## shoulders); face: a square on the head for the profile's round face (FACE_CROPS).
static func _head_crops(card: Image, neck: Vector2) -> Dictionary:
	var sky := card.get_pixel(2, 2)
	var w := card.get_width()
	var h := card.get_height()
	var top := -1
	for y in h:
		for x in range(0, w, 2):
			var c := card.get_pixel(x, y)
			if absf(c.r - sky.r) + absf(c.g - sky.g) + absf(c.b - sky.b) > 0.12:
				top = y
				break
		if top >= 0: break
	if top < 0 or neck.x < 0: return {"stamp": [0, 0, w, int(w * float(STAMP.y) / STAMP.x)], "face": [0, 0, w, w]}
	var head := neck.y - top
	var sh := int(head * 1.45)
	var sw := int(sh * float(STAMP.x) / STAMP.y)
	var sx := clampi(int(neck.x - sw * 0.5), 0, w - sw)
	var sy := clampi(top - int(sh * 0.05), 0, h - sh)
	var side := int(head * 1.12)
	var fx := clampi(int(neck.x - side * 0.5), 0, w - side)
	var fy := clampi(top - int(side * 0.04), 0, h - side)
	return {"stamp": [sx, sy, sw, sh], "face": [fx, fy, side, side], "head_top": top, "jaw": [int(neck.x), int(neck.y)]}

static func _sheet_cards(cards: Array[Image], cols := 0) -> Image:
	var cw := 150
	var ch := 330
	var gap := 8
	var n := cards.size()
	var per := cols if cols > 0 else n
	var rows := ceili(float(n) / per)
	var sheet := Image.create(gap + per * (cw + gap), gap + rows * (ch + gap), false, Image.FORMAT_RGB8)
	sheet.fill(Color.WHITE)
	for i in n:
		var c := cards[i].duplicate() as Image
		c.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(gap + (i % per) * (cw + gap), gap + (i / per) * (ch + gap)))
	return sheet

## Each head as the stamp crops it: 32 × 40 above, 3× below; rows of `cols` (0: one row).
static func _sheet_stamps(cards: Array[Image], keys: Array[String], crops: Dictionary, cols := 0) -> Image:
	var big := STAMP * STAMP_ZOOM
	var gap := 12
	var n := cards.size()
	var per := cols if cols > 0 else n
	var rows := ceili(float(n) / per)
	var cell_h := gap * 2 + STAMP.y + big.y
	var sheet := Image.create(gap + per * (big.x + gap), gap + rows * cell_h, false, Image.FORMAT_RGB8)
	sheet.fill(Color.WHITE)
	for i in n:
		var r: Array = crops[keys[i]].stamp
		var head := cards[i].get_region(Rect2i(r[0], r[1], r[2], r[3]))
		var small := head.duplicate() as Image
		small.resize(STAMP.x, STAMP.y, Image.INTERPOLATE_LANCZOS)
		var x := gap + (i % per) * (big.x + gap)
		var y := gap + (i / per) * cell_h
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, STAMP), Vector2i(x + (big.x - STAMP.x) / 2, y))
		head.resize(big.x, big.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(head, Rect2i(Vector2i.ZERO, big), Vector2i(x, y + gap + STAMP.y))
	return sheet
