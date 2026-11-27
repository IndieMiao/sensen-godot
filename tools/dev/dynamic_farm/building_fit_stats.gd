extends SceneTree
## C-193: which claimable parcels can hold the coop, the barn and the sheep pen with the yard cleared.
## The judgement is building_fit.gd's (the game's placement rule, yard cleared, all four turns; see there).
## Shapes: the coop with its real art (7×5 and its kept cells); the barn with its real art (C-202: 11×6 less the
## rear-left 2×2, the two cells outside its gate) and as C-192's draft (barn_8x6: the cell outside its entry); plain W×D sizes 5×3–10×8 with one walkable cell outside the front middle (the sheep pen's
## size is not set yet); and, in order, cottage → coop → barn → pen 8×6 each at the first passing spot (a greedy lower
## bound on all fitting together). How to fetch a dataset and rerun: docs/plans/C-193.md.
##   godot --headless --path "$QA" --script res://tools/dev/dynamic_farm/building_fit_stats.gd -- <out.json> <list.txt>
## <list.txt>: one parcel JSON path per line. Per parcel the output has fit[shape] = ok | none | path | reach and
## together = how many of the four went down.
const Fit = preload("res://tools/dev/dynamic_farm/building_fit.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("usage: -- <out.json> <list.txt>")
		quit(2)
		return
	var shapes := Fit.shapes()
	var order := [Fit.cottage(), shapes.coop, shapes.barn, shapes.plain_8x6]
	var rows := []
	var started := Time.get_ticks_msec()
	for line in FileAccess.get_file_as_string(args[1]).split("\n", false):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(line.strip_edges()))
		if not raw is Dictionary:
			rows.append({"file": line, "error": "unreadable"})
			continue
		var y := Fit.yard(raw)
		if not y.ok:
			rows.append({"block_id": str(raw.get("block_id", "")), "error": "decode"})
			continue
		var row := {"block_id": y.data.block_id, "core": y.core, "path": y.path.size(),
			"bounds": [y.bounds.size.x, y.bounds.size.y], "fit": {}}
		for name: String in shapes:
			row.fit[name] = Fit.VERDICT[Fit.best(y, shapes[name]).level]
		row["together"] = Fit.together(y, order)
		rows.append(row)
	var view := {}
	for name: String in shapes:
		var s: Dictionary = shapes[name]
		view[name] = {"base": [s.base.x, s.base.y], "keep": Fit.kept_view(s).map(func(c): return [c.x, c.y])}
	var out := FileAccess.open(args[0], FileAccess.WRITE)
	out.store_string(JSON.stringify({"shapes": view, "parcels": rows}))
	out.close()
	print("BUILDING_FIT parcels=%d ms=%d" % [rows.size(), Time.get_ticks_msec() - started])
	quit(0)
