class_name P0FarmMaterials
extends Node
## SGODOT-231 on the homestead: the mine mouth (LOCK-21 main action key, the EntryCard with New run, "The mine" sheet,
## the world badge and the once-only "Run ended at daily reset"), the five gathering spots (tap when near, 0 Energy,
## Ready / countdown marks, floats) and the workbench. One child node of the farm, so p0_farm.gd keeps a few one-line
## hooks; copy comes from P0MaterialLogic.

const P0_MINE := "res://scenes/p0/p0_mine.tscn"
const MOUTH_REACH := 2.4        # m: the key turns into Enter mine / Continue run, the EntryCard shows
const NOTICE_S := 2.0           # "Run ended at daily reset" float (q(44))
const SPOT_REACH := 3.0         # m: finger cards show and taps gather only this close (Arthur, 231)
const SPOTS := ["spot_grove", "spot_rock_pile", "spot_reed_bank", "spot_clay_bank", "spot_herb_patch"]

var farm: Node3D                # p0_farm.gd: actor, cam
var rt: P0Runtime
var mouth := Vector3.ZERO
var _entry: PanelContainer
var _entry_button: Button
var _entry_line: Label
var _entry_cmd := {}
var _reset_shown := 0.0
var _stored_shown := 0.0
var _opening := false
var _spots := {}                # spot id → world position (the spot's anchor cell)
var _bench := Vector3.ZERO

func setup(farm_node: Node3D, mouth_at: Vector3) -> P0FarmMaterials:
	farm = farm_node
	mouth = mouth_at
	name = "FarmMaterials"
	return self

func _ready() -> void:
	rt = P0Runtime.ensure()
	rt.session.state_changed.connect(_on_state)
	_build_entry_card()
	_build_spots()
	# Floats for a past auto-store are not news: only arrivals after entering the farm float.
	var auto = rt.session.current().get("storage", {}).get("auto", null)
	if auto is Dictionary: _stored_shown = float(auto.get("at", 0))

func _build_spots() -> void:
	var bp: FarmBlueprint = farm.bp
	for id in SPOTS:
		_spots[id] = bp.cell_to_world(bp.anchor(id))
		farm.add_child(P0SpotArt.build(id, _spots[id]))
	_bench = bp.cell_to_world(bp.anchor("workbench"))   # the anchor is the middle of its three cells
	farm.add_child(P0SpotArt.build("workbench", _bench))

func _exit_tree() -> void:
	if rt and rt.session.state_changed.is_connected(_on_state): rt.session.state_changed.disconnect(_on_state)
	if is_instance_valid(_entry): _entry.queue_free()

## The card lives on the shared UI layer: hide it whenever the farm is not the active world (the mine, the map).
func _process(_dt: float) -> void:
	if is_instance_valid(_entry) and rt and rt.world != farm: _entry.visible = false

func near_mouth() -> bool:
	return farm.actor.position.distance_to(mouth) < MOUTH_REACH

## The key at the mouth (LOCK-21): Enter mine · 2 Energy / Continue run · Free / Enter mine · No runs left.
func action(v: Dictionary) -> Dictionary:
	return P0MaterialLogic.mine_entry_action(v)

## Every frame on the farm: badge, EntryCard and the reset notice.
func frame(v: Dictionary) -> void:
	var cam: Camera3D = farm.cam
	var near := near_mouth()
	var top := cam.unproject_position(mouth + Vector3(0, 1.9, 0))
	# The mouth's world badge (MAT-1 / MINE-P0-5): display only, the mouth takes the tap (LOCK-07).
	rt.ui.badge("mine", UiStatusBadge.State.AVAILABLE, top, not rt.ui.has_modal(), P0MaterialLogic.mine_badge(v),
		P0Logic.icon("pickaxe"))
	top.y -= rt.ui.badge_height("mine")
	var card := P0MaterialLogic.mine_entry_card(v)
	_entry.visible = near and bool(card.get("show", false)) and not rt.ui.has_modal()
	if _entry.visible:
		_entry_button.text = str(card.label)
		_entry_button.disabled = not bool(card.enabled)
		_entry_line.text = str(card.line2)
		_entry_line.visible = _entry_line.text != ""
		_entry_cmd = card.cmd
		_entry.reset_size()
		_entry.position = top - Vector2(_entry.size.x * 0.5, _entry.size.y + 30)
	if near:
		var notice := P0MaterialLogic.reset_notice(v, _reset_shown)
		if notice != "":
			_reset_shown = float(v.mine.ended.at)
			rt.ui.float_text(notice, top + Vector2(0, -8), P0Ui.INK)
	_spot_marks(v)
	var stored := P0MaterialLogic.stored_notice(v, _stored_shown)
	if stored != "":
		_stored_shown = float(v.storage.auto.at)
		rt.ui.float_text(stored, rt.anchor() + Vector2(0, -36), P0Ui.GREEN_D)

## STATE-ICONS badge over a spot (READY, LOCKED for Clay Bank before Homestead Lv2; a countdown spot shows none until
## near) and, near it, the finger card (Timber Grove · Tap to gather / · Ready in 2h 10m / Clay Bank · Homestead Lv2)
## above the badge. Tapping the card is tapping the spot.
func _spot_marks(v: Dictionary) -> void:
	var cam: Camera3D = farm.cam
	var modal := rt.ui.has_modal()
	for m in P0MaterialLogic.gather_marks(v):
		var id := str(m.id)
		var at: Vector3 = _spots.get(id, Vector3.ZERO)
		var screen := cam.unproject_position(at + Vector3(0, 1.3, 0))
		var near: bool = farm.actor.position.distance_to(at) < SPOT_REACH
		var state := UiStatusBadge.State.READY if str(m.badge) == "ready" else UiStatusBadge.State.LOCKED
		rt.ui.badge(id, state, screen, not modal and str(m.badge) != "countdown")
		rt.ui.tag(id, str(m.caption), screen - Vector2(0, rt.ui.badge_height(id)), not modal and near,
			cam.unproject_position(at + Vector3(0, 0.6, 0)))
	var bench_screen := cam.unproject_position(_bench + Vector3(0, 1.4, 0))
	rt.ui.tag("workbench", "Workbench · Tap to craft", bench_screen,
		not modal and farm.actor.position.distance_to(_bench) < SPOT_REACH, cam.unproject_position(_bench + Vector3(0, 0.8, 0)))

## Taps on the farm's material facilities (LOCK-07): the mouth shows "The mine" (MINE-P0-1 / P0-8; entering stays on the
## key); a spot gathers when the player stands near it, a locked one shows MAT-3; the workbench opens its drawer.
func tap(screen: Vector2) -> bool:
	var cam: Camera3D = farm.cam
	if cam.unproject_position(mouth + Vector3(0, 0.8, 0)).distance_to(screen) < 60:
		P0MaterialCards.open_mine_sheet(rt.ui, rt.session.current())
		return true
	var v := rt.session.current()
	for m in P0MaterialLogic.gather_marks(v):
		var at: Vector3 = _spots.get(m.id, Vector3.ZERO)
		if cam.unproject_position(at + Vector3(0, 0.6, 0)).distance_to(screen) >= 64: continue
		if farm.actor.position.distance_to(at) >= SPOT_REACH: return false   # far away: the tap walks / does nothing
		farm.actor.face(at)
		match str(m.badge):
			"ready": rt.session.send({"type": "gather", "spot": str(m.id)})
			"locked": P0MaterialCards.open_locked_spot(rt.ui, v, str(m.id))
			_: rt.ui.toast(str(m.caption))
		return true
	if cam.unproject_position(_bench + Vector3(0, 0.8, 0)).distance_to(screen) < 64 and farm.actor.position.distance_to(_bench) < SPOT_REACH:
		farm.actor.face(_bench)
		_open_workbench()
		return true
	return false

## TODO(SGODOT-231): the B2-06 drawer extends 225's UiDrawer once feat/p0-panels-2b is in; a toast until then.
func _open_workbench() -> void:
	rt.ui.toast("Workbench · coming next")

## Commands this helper owns; false lets the farm handle the rest.
func act(cmd: Dictionary) -> bool:
	match str(cmd.get("type", "")):
		"mine_enter", "mine_new_run":
			rt.session.send(cmd)
		"toast":
			rt.ui.toast(str(cmd.get("text", "")))
		_:
			return false
	return true

## A run starts or continues: open the mine on the floor the server landed it on (Continue run: the deepest paid).
## A gather floats what went to storage at the spot (the runtime floats what went to the bag).
func _on_state(v: Dictionary, events: Array) -> void:
	if rt.world != farm or _opening: return
	for e in events:
		if str(e.get("kind", "")) == "gather":
			# Stacked above the runtime's own item floats (what went to the bag) at the same anchor, never across them.
			var dy := -20.0
			for line in P0MaterialLogic.gather_floats(v, e):
				rt.ui.float_text(line, rt.anchor() + Vector2(0, dy), P0Ui.GREEN_D)
				dy -= 16.0
	for e in events:
		if str(e.get("kind", "")) == "mine" and str(e.get("action", "")) in ["enter", "continue"]:
			_opening = true
			AppRouter.open_instance(P0_MINE, {"floor": int(e.get("floor", 1))})
			get_tree().create_timer(1.0).timeout.connect(func(): _opening = false)
			return

## EntryCard (1468:94344, MINE-P0-5): over the mouth, only near it, only with an unfinished run; one secondary text
## button (New run · 2 Energy, green; grey with the reason when it can't) and its small line.
func _build_entry_card() -> void:
	_entry = PanelContainer.new()
	_entry.mouse_filter = Control.MOUSE_FILTER_STOP
	_entry.add_theme_stylebox_override("panel", rt.ui._box(P0Ui.CARD, 12, P0Ui.EDGE, 1, Vector4(10, 6, 10, 6)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_entry.add_child(v)
	_entry_button = Button.new()
	_entry_button.flat = true
	_entry_button.focus_mode = Control.FOCUS_NONE
	_entry_button.add_theme_font_size_override("font_size", 12)
	_entry_button.add_theme_color_override("font_color", P0Ui.GREEN_D)
	_entry_button.add_theme_color_override("font_disabled_color", UiTokens.COLOR_DISABLED_INK)
	_entry_button.pressed.connect(_on_entry)
	v.add_child(_entry_button)
	_entry_line = rt.ui._label("", 9, UiTokens.COLOR_SECONDARY)
	_entry_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_entry_line)
	_entry.visible = false
	rt.ui.root.add_child(_entry)

func _on_entry() -> void:
	match str(_entry_cmd.get("type", "")):
		"mine_new_run":
			P0MaterialCards.open_new_run(rt.ui, rt.session.current(), func(cmd: Dictionary): rt.session.send(cmd))
		"energy_card":
			rt._on_action(_entry_cmd)
