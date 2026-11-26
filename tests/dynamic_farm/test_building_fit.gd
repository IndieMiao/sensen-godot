extends SceneTree
## C-193 guard (Q-289 A): the two narrowest claimable r8 starter parcels, unmodified in fixtures/r8/, still hold the
## coop (7×5, its real art and kept cells), the barn (C-192's draft 8×6, the cell outside its entry) and the sheep
## pen up to 9×7 (one walkable cell outside its front) with the yard cleared, in at least one of the four turns.
## The judgement is the game's placement rule through tools/dev/dynamic_farm/building_fit.gd, the same code as the
## statistic (building_fit_stats.gd, docs/plans/C-193.md). If a new dataset or a larger building breaks this, rerun
## the statistic over the new starter zone before changing the fixtures.
## Controls, so a check that passes everything would fail here: p-0147008's core is 8 cells wide, so 10×8 does
## not fit; the r4 sample p-5402049 (core 267×3) holds none of them. p-5402049 is r4 only, it is not in r8 (nor in
## any release a home is entered on); it stays "does not fit" and is not a fixture to fix.
## The parcels passed after `--` (the r4 set from tools/ci/dynamic_farm_tests.sh) are not read.
##   godot --headless --path "$QA" --script res://tests/dynamic_farm/test_building_fit.gd
const Fit = preload("res://tools/dev/dynamic_farm/building_fit.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const R8 := "res://tests/dynamic_farm/fixtures/r8/"
const R4_NARROW := "res://tests/dynamic_farm/fixtures/r4/p-5402049.json"
const DATASET := "sf-dynamic-farm-20261125-r8"
## block_id → the largest plain size that must not fit (a boundary control), or null.
const NARROWEST := {"p-0147008": Vector2i(10, 8), "p-0078042": null}
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	var pinned := _pinned()
	_check(pinned.size() == NARROWEST.size() and NARROWEST.keys().all(func(k): return pinned.has(k + ".json")),
		"fixtures/r8: exactly the two narrowest parcels, pinned in SHA256SUMS")
	for block_id: String in NARROWEST:
		_narrow(block_id, pinned.get(block_id + ".json", ""))
	_r4_control()
	print("BUILDING_FIT_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

## file name → SHA-256 from fixtures/r8/SHA256SUMS.
func _pinned() -> Dictionary:
	var out := {}
	for line in FileAccess.get_file_as_string(R8 + "SHA256SUMS").split("\n", false):
		var parts := line.split(" ", false)
		if parts.size() == 2: out[parts[1].trim_prefix("*")] = parts[0]
	return out

func _narrow(block_id: String, sha: String) -> void:
	var path := R8 + block_id + ".json"
	_check(sha != "" and FileAccess.get_sha256(path) == sha, "%s: the file matches its pinned SHA-256 (the dataset's bytes)" % block_id)
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(raw is Dictionary and raw.get("block_id") == block_id and raw.get("dataset_version") == DATASET,
		"%s: an r8 payload for that block" % block_id)
	var y := Fit.yard(raw)
	_check(y.ok, "%s: decodes" % block_id)
	if not y.ok: return
	var shapes := {"coop 7×5": Fit.coop(), "barn 8×6": Fit.barn(), "pen 9×7": Fit.plain(Vector2i(9, 7))}
	for name: String in shapes:
		var s: Dictionary = shapes[name]
		var b := Fit.best(y, s)
		_check(b.level == Fit.OK, "%s: the cleared yard holds the %s (best: %s)" % [block_id, name, Fit.VERDICT[b.level]])
		if b.level != Fit.OK: continue
		if s.type != "":
			# The coop's spot passes the game's own rule, not just building_fit.gd's reading of it.
			_check(Building.reason(y.data, b.at, s.base, b.rotation, {}, y.path, y.walk.reserved, s.type) == "",
				"%s: Building.reason accepts the %s at %s turned %d" % [block_id, name, b.at, b.rotation])
		print("BUILDING_FIT parcel=%s shape=%s at=%s turn=%d" % [block_id, name, b.at, b.rotation])
	var limit = NARROWEST[block_id]
	if limit != null:
		var b := Fit.best(y, Fit.plain(limit))
		_check(b.level != Fit.OK, "%s: control, %d×%d does not fit (core %d wide)" % [block_id, limit.x, limit.y, y.bounds.size.x])

## The r4 sample from C-154/C-175: too narrow for any of them. It stays that way; it is not in r8.
func _r4_control() -> void:
	var y := Fit.yard(JSON.parse_string(FileAccess.get_file_as_string(R4_NARROW)))
	_check(y.ok and y.data.block_id == "p-5402049", "p-5402049 (r4): decodes")
	if not y.ok: return
	for s: Dictionary in [Fit.coop(), Fit.barn(), Fit.plain(Vector2i(9, 7))]:
		_check(Fit.best(y, s).level != Fit.OK, "p-5402049 (r4, core %d×%d): control, %d×%d does not fit"
			% [y.bounds.size.x, y.bounds.size.y, s.base.x, s.base.y])
