extends GdUnitTestSuite
## 上官婉儿 on 475 (3bee65ba / 8804d489; 奕星: by the piece): the marked point's piece (the slot's 1.5 m footprint to its
## height) KEY_GAP_PX off the action keys on the reference screen (360 × 800, REF_COLUMN), the camera moved for it the
## least, the player first; its 28 px icon's gap listed (one still under 8 lifts itself over the keys, P0Ui.world_icon). Every slot of the three pond shapes (server/data/pond_slots.json), the player at
## its stand, the tallest piece it may hold: before (the clamp as it was) and after, printed for the review, after ≥ 8.

const POND := preload("res://scenes/p0/p0_pond.gd")
const PondGather := preload("res://scenes/p0/p0_pond_gather.gd")

## The least gap (px) between any of `rects` and `keys`: negative when one overlaps them.
static func _gap(rects: Array, keys: Rect2) -> float:
	var g := INF
	for r: Rect2 in rects:
		g = minf(g, maxf(maxf(keys.position.x - r.end.x, r.position.x - keys.end.x), maxf(keys.position.y - r.end.y, r.position.y - keys.end.y)))
	return g

## The camera with the player at `at` on the reference screen (the inverse of P0Pond.project for a point on the ground).
static func _focus_with(player: Vector3, at: Vector2, size: float) -> Vector3:
	var px := POND.REF_VIEW.x / size
	var sx := at.x - POND.REF_VIEW.x * 0.5
	var sy := at.y - POND.REF_VIEW.y * 0.5
	return player - POND.right_axis() * (sx / px) + POND.ahead_axis() * (sy / px / sin(deg_to_rad(POND.PITCH_DEG)))

## Two framings: settled (P0Follow centres the player 0.6 s after a stop) and still walking at the safe box's bottom-right
## corner (P0Follow.BOX 40 % × 45 %), where the piece comes nearest the keys.
func test_every_slot_at_its_stand_keeps_its_piece_and_icon_off_the_keys() -> void:
	var slots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://server/data/pond_slots.json")).shapes
	var size: float = POND.view_size(POND.REF_VIEW, 1.0)
	var lines := PackedStringArray(["shape slot kind framing piece_before piece_after moved_px icon_after (an icon still under 8 lifts itself over the keys)"])
	var short := PackedStringArray()
	for shape in slots:
		for id in slots[shape]:
			var s: Dictionary = slots[shape][id]
			var pieces: Array = s.get("pieces", [])
			var tall := not bool(s.get("low_only", false)) and (pieces.is_empty() or pieces.has("wood") or pieces.has("hardwood"))
			var p := {"x": float(s.x), "z": float(s.z), "kind": "wood" if tall else "stone"}
			var player := Vector3(float(s.stand[0]), 0, float(s.stand[1]))
			var box := PondGather.piece_box(p)
			var icon := PondGather.icon_at(p)
			var corner := POND.REF_VIEW * 0.5 + Vector2(POND.REF_VIEW.x * 0.2, POND.REF_VIEW.y * 0.225)   # the safe box's bottom right
			for frame in [["settled", player], ["walking", _focus_with(player, corner, size)]]:
				var before: Vector3 = POND.clamp_focus(frame[1], size, POND.REF_VIEW, POND.REF_BAND, PondScenery.MEADOW, player, POND.REF_COLUMN)
				var moved: float = POND.piece_need(before, player, box, size, POND.REF_VIEW, POND.REF_COLUMN)
				var after: Vector3 = before + POND.right_axis() * (moved / (POND.REF_VIEW.x / size))
				var g0 := _gap([POND.piece_rects(before, box, icon, size, POND.REF_VIEW)[0]], POND.REF_COLUMN)
				var g1 := _gap([POND.piece_rects(after, box, icon, size, POND.REF_VIEW)[0]], POND.REF_COLUMN)
				var i1 := _gap([POND.piece_rects(after, box, icon, size, POND.REF_VIEW)[1]], POND.REF_COLUMN)
				lines.append("%s %s %s %s %.1f %.1f %.1f %.1f" % [shape, id, p.kind, frame[0], g0, g1, moved, i1])
				if g1 < POND.KEY_GAP_PX - 0.01: short.append("%s %s %s %.1f" % [shape, id, frame[0], g1])
				# the player stays on the screen, PLAYER_SAFE_PX in
				var at: Vector2 = POND.project(player, after, size, POND.REF_VIEW)
				assert_float(at.x - POND.PLAYER_HALF_M * POND.REF_VIEW.x / size).is_greater_equal(POND.PLAYER_SAFE_PX - 0.01)
	print("PIECE_KEYS\n" + "\n".join(lines))
	assert_array(Array(short)).override_failure_message("short of KEY_GAP_PX: " + ", ".join(short)).is_empty()

## 8804d489 ②: it starts only once the piece comes within KEY_GAP_PX, and lets go only once it would be PIECE_HYST_PX
## further clear — no back and forth along the bank.
func test_the_shift_holds_until_the_piece_is_clear_by_the_hysteresis() -> void:
	var size: float = POND.view_size(POND.REF_VIEW, 1.0)
	var px: float = POND.REF_VIEW.x / size
	var p := {"x": 12.0, "z": -7.6, "kind": "clay"}
	var box := PondGather.piece_box(p)
	var player := Vector3(11.12, 0, -7.62)
	var corner := POND.REF_VIEW * 0.5 + Vector2(POND.REF_VIEW.x * 0.2, POND.REF_VIEW.y * 0.225)
	var focus: Vector3 = POND.clamp_focus(_focus_with(player, corner, size), size, POND.REF_VIEW, POND.REF_BAND, PondScenery.MEADOW, player, POND.REF_COLUMN)
	var need: float = POND.piece_want(focus, player, box, size, POND.REF_VIEW, POND.REF_COLUMN, 0.0)
	assert_float(need).is_greater(0.0)
	# the camera's own focus moved so the piece now sits 2 px clear past KEY_GAP_PX unshifted: within the hysteresis, held
	var nearly: Vector3 = focus + POND.right_axis() * ((need + 2.0) / px)
	assert_float(POND.piece_need(nearly, player, box, size, POND.REF_VIEW, POND.REF_COLUMN)).is_equal(0.0)
	assert_float(POND.piece_want(nearly, player, box, size, POND.REF_VIEW, POND.REF_COLUMN, need)).is_greater(0.0)
	# clear by more than the hysteresis: let go
	var clear: Vector3 = focus + POND.right_axis() * ((need + POND.PIECE_HYST_PX + 1.0) / px)
	assert_float(POND.piece_want(clear, player, box, size, POND.REF_VIEW, POND.REF_COLUMN, need)).is_equal(0.0)
