extends Node
## C-236 review capture (development only, never a delivered scene): opens one's own parcel on a throwaway local save,
## stands the player beside a tree, a rock and a wild herb in turn and gathers each with the key held (three chops,
## two hits, one pull), then a yard tree; saves a frame every `every_s` of game time to `FRAME_DIR` (default
## user://gather_fx_frames) and a contact sheet per kind. Run under a display with Godot's movie writer for a video
## with the synthesised sounds:
##   FRAME_DIR=/abs/frames godot --path . --rendering-method mobile --fixed-fps 30 \
##     --write-movie /abs/gather.avi res://tools/dev/dynamic_farm/gather_fx_qa.tscn
## GATHER_FX_REDUCED=1 runs it with reduced motion (UiMotion.reduced); GATHER_FX_EVERY=0.0333 saves every frame at 30 fps.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const FARM := "res://tests/dynamic_farm/fixtures/r4/p-3139010.json"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")

var every_s := 0.1
var _scene: Node
var _out := ""
var _clock := 0.0
var _next := 0.0
var _take := ""
var _frames := []
var _sheets := {}

func _ready() -> void:
	_out = OS.get_environment("FRAME_DIR")
	if _out.is_empty(): _out = ProjectSettings.globalize_path("user://gather_fx_frames")
	DirAccess.make_dir_recursive_absolute(_out)
	UiMotion.reduced = OS.get_environment("GATHER_FX_REDUCED") == "1"
	if not OS.get_environment("GATHER_FX_EVERY").is_empty(): every_s = float(OS.get_environment("GATHER_FX_EVERY"))
	_run.call_deferred()

func _process(delta: float) -> void:
	_clock += delta
	if _take.is_empty() or _clock < _next: return
	_next = _clock + every_s
	var image := get_viewport().get_texture().get_image()
	var name := "%s-%03d.png" % [_take, _frames.size()]
	image.save_png(_out.path_join(name))
	_frames.append(image)

func _run() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FARM))
	var dir := "user://gather_fx_qa_%d" % Time.get_ticks_usec()
	_scene = (load(SCENE_PATH) as PackedScene).instantiate()
	_scene.setup({"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true,
		"farm_store": LocalStore.new(raw.block_id, dir)})
	var state := {"ready": false}
	_scene.preview_ready.connect(func(_summary): state.ready = true)
	add_child(_scene)
	while not state.ready: await get_tree().process_frame
	var farming: Node = _scene.get_node("ParcelFarming")
	while farming.farm.is_empty(): await get_tree().process_frame
	await _wait(1.0)
	var chosen := {}
	for i in farming.gatherables.size():
		var kind: String = farming.gatherables[i].kind
		if not chosen.has(kind) and _stand_by(farming, i): chosen[kind] = i
	for kind: String in ["tree", "rock", "flower"]:
		if not chosen.has(kind): continue
		_stand_by(farming, chosen[kind])
		farming.picked_object = chosen[kind]
		_scene._focus = _scene._actor.position
		await _wait(0.8)
		await _gather(farming, kind)
	await _yard_tree(farming)
	print("GATHER_FX_QA frames=%s" % _out)
	get_tree().quit()

func _gather(farming: Node, take: String) -> void:
	_begin(take)
	farming._key.pressed_down.emit()
	await get_tree().process_frame
	while farming.busy or farming.swinging: await get_tree().process_frame
	farming._key.released.emit()
	await _wait(2.2)
	_end()

func _yard_tree(farming: Node) -> void:
	for item: Dictionary in farming._core_plan.layout:
		if item.get("role") != "tree": continue
		var cell: Vector2i = item.cell
		farming.pick(cell)
		_scene._focus = _scene._walk.point(cell)
		await _wait(0.6)
		if farming.verb_label(farming.current) != "Chop": continue
		_begin("yard_tree")
		farming._key.pressed_down.emit()
		await get_tree().process_frame
		while farming.busy or farming.swinging: await get_tree().process_frame
		farming._key.released.emit()
		await _wait(1.5)
		_end()
		return

func _begin(take: String) -> void:
	_take = take
	_frames = []
	_next = _clock

## Stops saving frames and writes a contact sheet of up to 24 of them (4 columns) at half size.
func _end() -> void:
	var take := _take
	_take = ""
	if _frames.is_empty(): return
	var step := maxi(1, ceili(_frames.size() / 24.0))
	var picked := []
	for i in range(0, _frames.size(), step): picked.append(_frames[i])
	var w: int = (picked[0] as Image).get_width() / 2
	var h: int = (picked[0] as Image).get_height() / 2
	var cols := 4
	var rows := ceili(picked.size() / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in picked.size():
		var frame: Image = (picked[i] as Image).duplicate()
		frame.resize(w, h, Image.INTERPOLATE_BILINEAR)
		frame.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(frame, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(_out.path_join("sheet-%s.png" % take))

func _wait(seconds: float) -> void:
	var until := _clock + seconds
	while _clock < until: await get_tree().process_frame

## Beside object `index` on open ground, facing it (as the scene test stands the player).
func _stand_by(farming: Node, index: int) -> bool:
	var object: Dictionary = farming.gatherables[index]
	var box: AABB = object.box
	var walk = _scene._walk
	for step in 24:
		var angle := TAU * step / 24.0 + PI * 0.25
		var out := Vector3(cos(angle), 0, sin(angle))
		for reach: float in [0.35, 0.5]:
			var p: Vector3 = object.origin + out * (maxf(box.size.x, box.size.z) * 0.5 + reach)
			p.y = 0.0
			if not walk.clear_position(p) or _gap(box, p) > farming.GATHER_REACH_M: continue
			walk.position = p
			_scene._actor.position = p
			_scene._facing = -out
			_scene._actor.look_at(p - out, Vector3.UP)
			return true
	return false

func _gap(box: AABB, p: Vector3) -> float:
	var dx := maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0)
	var dz := maxf(maxf(box.position.z - p.z, p.z - box.end.z), 0.0)
	return Vector2(dx, dz).length()
