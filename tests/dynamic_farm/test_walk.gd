extends SceneTree
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, name: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + name)

func _run() -> void:
	var corner := Walk.new({"cell_m":0.8,"grid_size":Vector2i(2,2),"spawn":Vector2i(1,1),
		"by_cell":{Vector2i(0,1):true,Vector2i(1,0):true,Vector2i(1,1):true}})
	_check(not corner.clear_position(Vector3(0.28,0,-0.08)),"body circle must not clip a concave missing cell")
	for path in OS.get_cmdline_user_args():
		if not path.ends_with(".json"): continue
		var data = Data.decode(JSON.parse_string(FileAccess.get_file_as_string(path)))
		_check(data.ok,"decode " + path.get_file())
		if not data.ok: continue
		var walk := Walk.new(data)
		_check(walk.clear_position(walk.position),"spawn clear")
		_check(walk.cell_at(walk.point(data.entry)) == data.entry,"entry roundtrip")
		var protected_before: int = data.protected.size()
		var cells_before: int = data.by_cell.size()
		var blocked_core := walk.try_box(AABB(walk.point(data.spawn)-Vector3(0.3,0,0.3),Vector3(0.6,2,0.6)),true)
		_check(blocked_core.is_empty(),"never place solid on core/protection")
		var planned := Scenery.plan(data,walk)
		_check(planned.ok,"scenery plan")
		if not planned.ok: continue
		Shade.enforce_budget(planned,data,walk)
		_check(walk.connected(),"all remaining walk cells connected")
		_check(data.protected.size()==protected_before and data.by_cell.size()==cells_before,"masks never edited")
		var footprints_valid := true
		for item in planned.layout:
			for cell: Vector2i in item.cells:
				if data.protected.has(cell) or data.by_cell[cell].zone != "extension": footprints_valid=false
		_check(footprints_valid,"whole prop footprint avoids core and reserve")
		for role in planned.roles:
			_check(planned.roles[role].accepted <= planned.roles[role].target and planned.roles[role].attempts <= 512,"bounded placement " + role)
		var again_walk := Walk.new(data)
		var again := Scenery.plan(data,again_walk)
		Shade.enforce_budget(again,data,again_walk)
		_check(planned.layout_sha256==again.layout_sha256,"same seed same layout")
		_check(walk.blocked==again_walk.blocked,"same seed same blockers")
		for dir in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
			walk.position=walk.point(data.spawn)
			for i in 100: walk.move(dir*0.2)
			_check(walk.clear_position(walk.position),"walking cannot leave ground")
	print("DYNAMIC_WALK_TESTS checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
