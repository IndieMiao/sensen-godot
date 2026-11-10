extends RefCounted
## The wild pond's shore foam (SGODOT-422, 盘古, the user's 0.3.5 11-09: "新版野外的水花，其实是上一版石头的水花"): the
## water's foam_contact made as the pond is entered, from the bank as v7 lays it — the waterline, its rock groups and
## its cattails — in place of the mask baked from the old round stones (assets/ponds/p0/foam/, kept for scenes/pond).
##
## What pond_water.gdshader reads: foam_contact.r is a DISTANCE in metres (0–1, 1 m a unit, as the old bake's), not a
## strength: the contact froth fills where it is under foam_width (0.14, broken by the foam pattern), sparse surface
## filaments between foam_width × 2 and ~0.95, nothing past. So one 8-bit channel (FORMAT_R8, filterable everywhere,
## never a 32-bit float) holds the base and the contacts both: each is a distance squeezed so its own froth width maps
## onto the shader's 0.14, and a texel keeps the nearer (min) — the stronger. 0.125 m a texel over the template's
## extent (12 × 16 m → 96 × 128, 12 KB), half the ground's water distance grid (PondWildGround.SDF_PX), which it reads.
## - base: the whole waterline, 0.2–0.85 m of froth, the width from a slow noise along the bank (WEAK_SHARE of it the
##   narrow, broken end), wider on the bank's headlands and narrower in its bays;
## - contacts: each bank rock a ring out to its radius × 1.6–2.0 (the bigger, the wider), a tail on its lee side (the
##   way the foam pattern drifts); each cattail a small ring at its foot; the lily pads none. Past them the distance
##   climbs fast, so the open water keeps none (no white island off the bank).

const G := preload("res://modules/ponds/pond_wild_ground.gd")
const PX := 0.125
const FOAM_W := 0.14          # pond_water.gdshader's foam_width: the contact froth's own width in its distance
const BASE_W := Vector2(0.2, 0.85)   # the wide end 0.6 → 0.85: it read as nothing on Pebble's bank (上官婉儿 11-10: one notch up)
const WEAK_SHARE := 0.38      # the waterline's share on the narrow, broken end (0.35 before the rocks' rings grew)
const WEAK_GAP := 0.04        # how far a weak stretch's waterline is pushed off the froth (broken, not gone; 0.075 left Pebble's weak bank bare)
const NOISE_HZ := 0.32        # the base width's noise: ~3 m stretches along the bank
const CURVE_K := 0.55         # the width per 1/m of the bank's bend (headland wider, bay narrower)
const SPREAD := Vector2(1.6, 2.0)   # a rock's foam radius over its own, small to big (1.2–1.6 left the rocks' feet thin)
const ROCK_R := Vector2(0.15, 0.6)  # the radii the spread runs between (v7's rocks: ~0.16–0.57 m)
const RING_MIN := 0.12        # a small rock's ring no thinner than this (radius × 0.2 would vanish under the base's)
const LEE := Vector2(-0.85, 0.53)   # where the shader's foam pattern drifts (foam_uv's flow, reversed): the lee side
const TAIL := 0.6             # the lee tail: the ring stretched this much more that way
const PAST_SLOPE := 2.0       # past a contact's ring the distance climbs this much faster than a metre a metre
const REED_W := 0.16          # a cattail's ring
const CORE := 0.5             # the froth's inner share left whole (the shader breaks it up only past it)
const CONTACT_OPACITY := 0.85   # pond_water's contact_foam_opacity on the wild ponds (0.60 elsewhere)
const DEEP_M := 1.55          # deeper than this the base gives no foam at all (the texel stays 1.0)

## `extent`: the template's (pond_extent); `distances`: PondWildGround.water_distances' (metres to the waterline, < 0
## in the water, SDF_PX a cell); `rocks` / `reeds`: Vector3(x, z, radius) each; `seed_value`: the pond's.
static func build(extent: Vector2, distances: PackedFloat32Array, rocks: Array, reeds: Array, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(image(extent, distances, rocks, reeds, seed_value))

static func image(extent: Vector2, distances: PackedFloat32Array, rocks: Array, reeds: Array, seed_value: int) -> Image:
	var w := roundi(extent.x / PX)
	var h := roundi(extent.y / PX)
	var out := PackedFloat32Array()
	out.resize(w * h)
	out.fill(1.0)
	_base(out, w, h, distances, seed_value)
	var lee := LEE.normalized()
	for r in rocks:
		var radius := float(r.z)
		var t := clampf((radius - ROCK_R.x) / (ROCK_R.y - ROCK_R.x), 0.0, 1.0)
		_ring(out, w, h, Vector2(r.x, r.y), radius, maxf(radius * (lerpf(SPREAD.x, SPREAD.y, t) - 1.0), RING_MIN), lee, TAIL)
	for r in reeds:
		_ring(out, w, h, Vector2(r.x, r.y), float(r.z), REED_W, lee, TAIL * 0.5)
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for i in w * h:
		bytes[i] = roundi(clampf(out[i], 0.0, 1.0) * 255.0)
	return Image.create_from_data(w, h, false, Image.FORMAT_R8, bytes)

## A distance squeezed so `width` of froth reads as the shader's FOAM_W — its inner CORE share at 0, the froth there
## unbroken — then climbing at `slope` past it.
static func squeeze(s: float, width: float, slope: float) -> float:
	return maxf(maxf(s - width * CORE, 0.0) * FOAM_W / (width * (1.0 - CORE)), FOAM_W + (s - width) * slope)

## The waterline's own foam: per ground cell (0.25 m) near the water its width and gap, then each texel from the
## distance and those, interpolated.
static func _base(out: PackedFloat32Array, w: int, h: int, d: PackedFloat32Array, seed_value: int) -> void:
	var gw := int(G.SDF_EXTENT.x / G.SDF_PX)
	var gh := int(G.SDF_EXTENT.y / G.SDF_PX)
	var cell := G.SDF_PX
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = NOISE_HZ
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	# the cells the texture covers, a margin round; per cell the width (metres) and the gap
	var x0 := maxi(int((0.0 - G.SDF_ORIGIN.x) / cell) - 2, 4)
	var x1 := mini(int((w * PX - G.SDF_ORIGIN.x) / cell) + 2, gw - 5)
	var y0 := maxi(int((-h * PX - G.SDF_ORIGIN.y) / cell) - 2, 4)
	var y1 := mini(int((0.0 - G.SDF_ORIGIN.y) / cell) + 2, gh - 5)
	var width := PackedFloat32Array()
	width.resize(gw * gh)
	width.fill(BASE_W.y)
	var gap := PackedFloat32Array()
	gap.resize(gw * gh)
	var near: Array[int] = []
	var raw := PackedFloat32Array()   # the noise at the cell's waterline point
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * gw + x
			var s := d[i]
			if s < -DEEP_M - 0.3 or s > 0.6: continue
			# the waterline point this cell is off (along the distance's gradient), so a width holds across the band
			var gx := (d[i + 1] - d[i - 1]) / (2.0 * cell)
			var gz := (d[i + gw] - d[i - gw]) / (2.0 * cell)
			var px := G.SDF_ORIGIN.x + (x + 0.5) * cell - gx * s
			var pz := G.SDF_ORIGIN.y + (y + 0.5) * cell - gz * s
			near.append(i)
			raw.append(noise.get_noise_2d(px, pz))
	# the weak share: the noise's own quantile over the waterline's cells, so WEAK_SHARE of the bank, whatever the seed
	var line: Array[float] = []
	for k in near.size():
		if absf(d[near[k]]) < cell: line.append(raw[k])
	line.sort()
	var weak_at := line[int(line.size() * WEAK_SHARE)] if not line.is_empty() else 0.0
	var top := line[int(line.size() * 0.95)] if not line.is_empty() else 1.0
	for k in near.size():
		var i: int = near[k]
		var n := raw[k]
		var weak := 1.0 - smoothstep(weak_at - 0.06, weak_at + 0.06, n)
		var strong := smoothstep(weak_at, maxf(top, weak_at + 0.01), n)
		# the bank's bend: the distance's laplacian over a metre (> 0 the water wraps round a bay, < 0 a headland)
		var lap := (d[i + 4] + d[i - 4] + d[i + 4 * gw] + d[i - 4 * gw] - 4.0 * d[i]) / 1.0
		var bend := clampf(1.0 - (lap - 0.2) * CURVE_K, 0.75, 1.3)
		var wide := lerpf(0.55, BASE_W.y, strong) * bend
		width[i] = clampf(lerpf(wide, BASE_W.x, weak), BASE_W.x, BASE_W.y)
		gap[i] = weak * WEAK_GAP
	# each texel: the distance, width and gap from the cells round it
	var inv := 1.0 / cell
	for ty in h:
		var z := -(ty + 0.5) * PX
		var fy := (z - G.SDF_ORIGIN.y) * inv - 0.5
		var cy := int(fy)
		var ay := fy - cy
		for tx in w:
			var fx := ((tx + 0.5) * PX - G.SDF_ORIGIN.x) * inv - 0.5
			var cx := int(fx)
			var i := cy * gw + cx
			var a := d[i]
			if a < -DEEP_M - 0.2: continue   # the open water: stays 1.0
			var ax := fx - cx
			var s := lerpf(lerpf(a, d[i + 1], ax), lerpf(d[i + gw], d[i + gw + 1], ax), ay)
			if s < -DEEP_M: continue
			var wd := lerpf(lerpf(width[i], width[i + 1], ax), lerpf(width[i + gw], width[i + gw + 1], ax), ay)
			var gp := lerpf(lerpf(gap[i], gap[i + 1], ax), lerpf(gap[i + gw], gap[i + gw + 1], ax), ay)
			out[ty * w + tx] = squeeze(maxf(-s, 0.0), wd, 1.0) + gp

## A contact's ring: `width` of froth out from its edge (`radius` round `at`), stretched `tail` more on the `lee` side,
## its distance climbing PAST_SLOPE past the ring; drawn into its own box only, the nearer kept.
static func _ring(out: PackedFloat32Array, w: int, h: int, at: Vector2, radius: float, width: float, lee: Vector2, tail: float) -> void:
	var reach := radius + width + (1.0 - FOAM_W) / PAST_SLOPE   # where its distance reaches 1.0
	var box := Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	box = box.merge(Rect2(at + lee * reach * tail - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	var tx0 := maxi(int(box.position.x / PX), 0)
	var tx1 := mini(int(box.end.x / PX) + 1, w - 1)
	var ty0 := maxi(int(-box.end.y / PX), 0)
	var ty1 := mini(int(-box.position.y / PX) + 1, h - 1)
	var squash := tail / (1.0 + tail)
	for ty in range(ty0, ty1 + 1):
		var vz := -(ty + 0.5) * PX - at.y
		for tx in range(tx0, tx1 + 1):
			var vx := (tx + 0.5) * PX - at.x
			var along := vx * lee.x + vz * lee.y
			var ux := vx
			var uz := vz
			if along > 0.0:
				ux -= lee.x * along * squash
				uz -= lee.y * along * squash
			var q := sqrt(ux * ux + uz * uz) - radius
			var v := 0.0 if q <= 0.0 else squeeze(q, width, PAST_SLOPE)
			var k := ty * w + tx
			if v < out[k]: out[k] = v
