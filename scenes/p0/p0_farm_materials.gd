class_name P0FarmMaterials
extends Node
## SGODOT-231 on the homestead: the mine mouth (LOCK-21 main action key, the EntryCard with New run, "The mine" sheet,
## the world badge and the once-only "Run ended at daily reset"). Gathering spots and the workbench join here next
## (PR-C). One child node of the farm, so p0_farm.gd keeps a few one-line hooks; copy comes from P0MaterialLogic.

const P0_MINE := "res://scenes/p0/p0_mine.tscn"
const MOUTH_REACH := 2.4        # m: the key turns into Enter mine / Continue run, the EntryCard shows
const NOTICE_S := 2.0           # "Run ended at daily reset" float (q(44))

var farm: Node3D                # p0_farm.gd: actor, cam
var rt: P0Runtime
var mouth := Vector3.ZERO
var _entry: PanelContainer
var _entry_button: Button
var _entry_line: Label
var _entry_cmd := {}
var _reset_shown := 0.0
var _opening := false

func setup(farm_node: Node3D, mouth_at: Vector3) -> P0FarmMaterials:
	farm = farm_node
	mouth = mouth_at
	name = "FarmMaterials"
	return self

func _ready() -> void:
	rt = P0Runtime.ensure()
	rt.session.state_changed.connect(_on_state)
	_build_entry_card()

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
	rt.ui.tag("mine", P0MaterialLogic.mine_badge(v), top, not rt.ui.has_modal())
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

## Tapping the mouth (a facility, LOCK-07) shows "The mine" (MINE-P0-1 / P0-8); entering stays on the key.
func tap(screen: Vector2) -> bool:
	if farm.cam.unproject_position(mouth + Vector3(0, 0.8, 0)).distance_to(screen) >= 60: return false
	P0MaterialCards.open_mine_sheet(rt.ui, rt.session.current())
	return true

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
func _on_state(_v: Dictionary, events: Array) -> void:
	if rt.world != farm or _opening: return
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
