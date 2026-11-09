extends Node3D
## Homestead looks on the farm (LOOK-PICK, SGODOT-282; §8.3.1, q(24) / q(112); models by #875): the Porch (Lv5) and
## Kitchen Wing (Lv8) as standalone parts at the farmhouse, and at Lv15 the Master Farmhouse in the house's place, its
## own porch and wing built in (the standalone two put away while it stands; P0Garden.WING_WAITS: the old wing and house
## until the wing clears the bench) — each stage a (timber) or b (stone), as the view says (homestead.looks) or as
## LOOK-PICK previews it. A stage reached or swapped while the farm is up pops its parts in with dust (P0Fence.pop_in);
## a save already there shows them at once. The Fence & Mailbox stage (Lv3) is the fence's own (p0_fence.gd).
## A save past Lv8 whose wing's cells are held (q(303) ⑨, homestead.wing_blocked) has no wing, old or new, and the old
## house as WING_WAITS has it; cleared, the wing (or the Master Farmhouse) pops in and wing_cleared says which.
## Placements: P0Garden.look_parts / look_house.

const FarmArt = preload("res://modules/farm/farm_art.gd")
const Fence = preload("res://scenes/p0/p0_fence.gd")
const STAGES := ["porch", "kitchen_extension"]
const HOUSE_STAGE := "master_farmhouse"
const WING_STAGE := "kitchen_extension"

## The wing came up as its cells cleared (homestead.wing_blocked gone between two views): the stage now on show, its
## level and name for the farm's `Lv8 look · Kitchen Wing` (q(303) ⑨).
signal wing_cleared(stage: Dictionary)

var _bp: FarmBlueprint
var _house: MeshInstance3D     # the farm's house prop: its mesh changes at Lv15
var _style := "cottage"
var _shown := {}               # stage → "a" / "b" / "" on show
var _parts := {}               # stage → Node3D holding its parts
var _seen := false             # the first view shows what the save has without the pop
var previews := {}             # stage → the look LOOK-PICK is showing ("" / absent = the view's)
var _fence: Node3D             # p0_fence.gd: the Fence & Mailbox stage's own preview
var _ui: P0Ui
## The farm's path grid (p0_farm sets it once built): the cells a shown model stands on are solid (亚瑟 on #896).
var grid: BlueprintGrid
var _solid: Array[Vector2i] = []
var _wing_held := false        # homestead.wing_blocked as last synced

## ui: the P0Ui whose LOOK-PICK previews this farm (none in tests that drive preview() themselves).
func build(bp: FarmBlueprint, house: MeshInstance3D, style: String, fence: Node3D, ui: P0Ui = null) -> void:
	name = "Looks"
	_bp = bp
	_house = house
	_style = style
	_fence = fence
	_ui = ui
	if _ui: _ui.look_previewed.connect(_on_previewed)

func _exit_tree() -> void:
	if _ui and _ui.look_previewed.is_connected(_on_previewed): _ui.look_previewed.disconnect(_on_previewed)

func _on_previewed(stage: String, look: String) -> void:
	if stage == "fence":
		if _fence: _fence.preview = look
	else: preview(stage, look)

## LOOK-PICK's preview of a stage ("" ends it). A preview of the look the view already has ends by itself, so the
## card's Use keeps the farmhouse as it is while the reply comes back.
func preview(stage: String, look: String) -> void:
	if look == "": previews.erase(stage)
	else: previews[stage] = look

## Every frame with the projected view: cheap until a stage's look changes.
func sync(view: Dictionary) -> void:
	var changed := false
	var held := not P0Decor.wing_blocked(view).is_empty()
	var held_changed := held != _wing_held
	_wing_held = held
	for stage in STAGES + [HOUSE_STAGE]:
		var have := P0Logic.look_of(view, stage)
		if previews.get(stage, "") == have and _seen: previews.erase(stage)   # the reply landed (or nothing to preview)
		var want: String = previews.get(stage, have)
		if stage == WING_STAGE and held: want = ""   # q(303) ⑨: no wing while its cells are held
		# the house and the porch before it change with the wing's hold too (the old house while it waits)
		if want == _shown.get(stage, "") and not (held_changed and stage == HOUSE_STAGE): continue
		_shown[stage] = want
		changed = true
		if stage == HOUSE_STAGE:
			_set_house(want, _seen)
			# the porch that goes with this house (P0Garden.look_parts: the old barn keeps the old Timber Porch)
			if _parts.has("porch"): _set_parts("porch", shown("porch"), _seen)
		else: _set_parts(stage, want, _seen)
	if held_changed and not held and _seen:
		var up := HOUSE_STAGE if shown(HOUSE_STAGE) != "" else WING_STAGE
		if shown(up) != "": wing_cleared.emit(P0Logic.look_stage(up))
	# the Master Farmhouse has the porch and the wing in it: the standalone ones stand down while it is up
	var whole := P0Garden.whole_house(shown(HOUSE_STAGE), waits())
	for stage in STAGES:
		var root: Node3D = _parts.get(stage)
		if root and root.visible == whole: root.visible = not whole
	if not _seen or changed: _block(whole)
	_seen = true

## The yard cells under what is shown made solid, those of what went made walkable again (P0Garden.look_cells): the
## standalone models, or the whole house — none for the old wing and house, as before.
func _block(whole: bool) -> void:
	if grid == null: return
	var models: Array = []
	if whole: models.append(P0Garden.look_house(shown(HOUSE_STAGE), _style, waits()))
	else:
		for stage in STAGES:
			for p in P0Garden.look_parts(_bp, stage, shown(stage), shown(HOUSE_STAGE), waits()):
				var model := str(p.asset)
				if model.begins_with("porch_") or model.begins_with("kitchen_wing_"): models.append(model)
	var now: Array[Vector2i] = []
	for model in models:
		for c in P0Garden.look_cells(_bp, model): if not now.has(c): now.append(c)
	# only the cells the looks took: one something else already held is left to it, then and when the look goes (亚瑟)
	var held: Array[Vector2i] = []
	for c in _solid:
		if now.has(c): held.append(c)
		else: grid.set_solid(c, false)
	for c in now:
		if held.has(c) or grid.astar.is_point_solid(c): continue
		grid.set_solid(c, true)
		held.append(c)
	_solid = held

## The cells the shown looks hold solid, those they took (tests).
func solid_cells() -> Array[Vector2i]: return _solid

func shown(stage: String) -> String: return str(_shown.get(stage, ""))

## The old wing and house: WING_WAITS, or this save's wing cells held (q(303) ⑨).
func waits() -> bool: return P0Garden.WING_WAITS or _wing_held

## The Kitchen Wing's own model stands on its cells (the new wing, or the Master Farmhouse with it built in): the grass
## and flowers there are not drawn (q(303), P0GardenScenery.show_wing).
func wing_model_shown() -> bool:
	return not waits() and (shown(WING_STAGE) != "" or shown(HOUSE_STAGE) != "")

func _set_parts(stage: String, look: String, animate: bool) -> void:
	var old: Node3D = _parts.get(stage)
	if old: old.queue_free()
	_parts.erase(stage)
	if look == "": return
	var root := Node3D.new()
	root.name = "Look_%s_%s" % [stage, look]
	add_child(root)
	_parts[stage] = root
	for p in P0Garden.look_parts(_bp, stage, look, shown(HOUSE_STAGE), waits()):
		var m := FarmArt.instance(str(p.asset))
		m.transform = Transform3D(Basis(Vector3.UP, float(p.yaw)) * Basis.from_scale(p.scale), p.pos)
		root.add_child(m)
	if animate: Fence.pop_in(self, root.get_children())

func _set_house(look: String, animate: bool) -> void:
	if _house == null: return
	_house.mesh = FarmArt.mesh_for(P0Garden.look_house(look, _style, waits()))
	if animate and look != "": Fence.pop_in(self, [_house])

## The parts on show for a stage (tests, shots).
func parts(stage: String) -> Array:
	var root: Node3D = _parts.get(stage)
	return root.get_children() if root else []
