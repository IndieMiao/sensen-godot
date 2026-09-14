class_name AvatarRig
extends Node3D

signal config_applied(config: AvatarConfig)
signal slot_applied(slot: StringName, part_id: String)
signal part_load_failed(slot: StringName, part_id: String, err: int)
signal busy_changed(busy: bool)

@export var slot_table: AvatarSlotTable
var skeleton: Skeleton3D
var assembler: AvatarAssembler = AvatarAssemblerMerged.new()
var loader: PartLoader

var _current: Dictionary = {}      # slot -> part_id（已应用）
var _desired: Dictionary = {}      # slot -> part_id（目标）
var _slot_request: Dictionary = {} # slot -> request_id（in-flight）
var _req_slot: Dictionary = {}     # request_id -> slot
var _loaded_defs: Dictionary = {}  # slot -> AvatarPartDef（当前已装）
var _pending_defs: Dictionary = {} # slot -> AvatarPartDef|null（到货待应用）
var _initial_loading := false
var _last_busy := false

func _ready() -> void:
	if skeleton == null:
		skeleton = _find_skeleton(self)

func play_motion(id: String) -> void:
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null or not player.has_animation(id): return
	if player.current_animation == id and player.is_playing(): return
	# Locomotion clips omit tracks written by full-body labour clips.
	player.stop()
	if skeleton: skeleton.reset_bone_poses()
	player.play(id)
	player.advance(0)

func setup(p_loader: PartLoader) -> void:
	loader = p_loader
	loader.load_finished.connect(_on_load_finished)
	loader.load_failed.connect(_on_load_failed)

func apply_config(config: AvatarConfig) -> void:
	if _current.is_empty():
		_initial_loading = true
		visible = false
	for slot in slot_table.slot_names():
		_set_desired(slot, String(config.slots.get(slot, "")))
	_try_apply()
	_sync_busy_state()

func equip(slot: StringName, part_id: String) -> void:
	_set_desired(slot, part_id)
	_try_apply()
	_sync_busy_state()

func unequip(slot: StringName) -> void:
	var sdef := slot_table.slot(slot)
	if sdef and sdef.required:
		equip(slot, sdef.default_part)
	else:
		equip(slot, "")

func current_config() -> AvatarConfig:
	var cfg := AvatarConfig.new()
	for slot in slot_table.slot_names():
		cfg.slots[slot] = String(_current.get(slot, ""))
	return cfg

## 装配状态以目标请求为准。保存方必须等它变为 false，才能持久化 current_config()。
func is_busy() -> bool:
	return _initial_loading or not _slot_request.is_empty() or not _pending_defs.is_empty()

func is_slot_busy(slot: StringName) -> bool:
	return _slot_request.has(slot) or _pending_defs.has(slot)

## UI 用目标态即时标记用户刚点的选项，不必等异步资源到货后才改变选中态。
func desired_part(slot: StringName) -> String:
	return String(_desired.get(slot, _current.get(slot, "")))

func desired_config() -> AvatarConfig:
	var cfg := AvatarConfig.new()
	for slot in slot_table.slot_names():
		cfg.slots[slot] = desired_part(slot)
	return cfg

func _set_desired(slot: StringName, part_id: String) -> void:
	_desired[slot] = part_id
	if _slot_request.has(slot):
		var old_req: int = _slot_request[slot]
		loader.cancel(old_req)
		_req_slot.erase(old_req)
		_slot_request.erase(slot)
	if part_id == "":
		if _current.get(slot, "") != "" or _pending_defs.has(slot):
			_pending_defs[slot] = null
		return
	if String(_current.get(slot, "")) == part_id:
		_pending_defs.erase(slot)
		return
	var rid := loader.request_part(part_id)
	_slot_request[slot] = rid
	_req_slot[rid] = slot

func _on_load_finished(request_id: int, part_id: String, resource: Resource) -> void:
	var slot = _req_slot.get(request_id)
	if slot == null:
		return
	_req_slot.erase(request_id)
	_slot_request.erase(slot)
	var def := resource as AvatarPartDef
	if def == null:
		_handle_slot_failure(slot, part_id, ERR_INVALID_DATA)
		_sync_busy_state()
		return
	_pending_defs[slot] = def
	_try_apply()
	_sync_busy_state()

func _on_load_failed(request_id: int, part_id: String, err: int) -> void:
	var slot = _req_slot.get(request_id)
	if slot == null:
		return
	_req_slot.erase(request_id)
	_slot_request.erase(slot)
	_handle_slot_failure(slot, part_id, err)
	_sync_busy_state()

func _handle_slot_failure(slot: StringName, part_id: String, err: int) -> void:
	part_load_failed.emit(slot, part_id, err)
	var sdef := slot_table.slot(slot)
	if sdef and sdef.required and part_id != sdef.default_part and sdef.default_part != "":
		var rid := loader.request_part(sdef.default_part)
		_desired[slot] = sdef.default_part
		_slot_request[slot] = rid
		_req_slot[rid] = slot
		return
	_desired[slot] = String(_current.get(slot, ""))
	_try_apply()

func _try_apply() -> void:
	if _initial_loading and not _slot_request.is_empty():
		return
	if not _pending_defs.is_empty():
		var applied_slots := _pending_defs.keys()
		for slot in _pending_defs:
			var def = _pending_defs[slot]
			if def == null:
				_loaded_defs.erase(slot)
				_current[slot] = ""
			else:
				_loaded_defs[slot] = def
				_current[slot] = def.id
		_pending_defs.clear()
		assembler.rebuild(self, _loaded_defs)
		for slot in applied_slots:
			slot_applied.emit(slot, String(_current.get(slot, "")))
	if _initial_loading and _slot_request.is_empty():
		_initial_loading = false
		visible = true
		config_applied.emit(current_config())

func _sync_busy_state() -> void:
	var busy := is_busy()
	if busy == _last_busy:
		return
	_last_busy = busy
	busy_changed.emit(busy)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null
