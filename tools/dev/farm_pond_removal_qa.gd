extends Node
## Own local account and server. Real farm scene, navigation, input and commands.
var farm: Node3D
var _elapsed := 0.0

func _ready() -> void:
	assert(bool(ProjectSettings.get_setting("sensen/network/online_qa", false)))
	var account: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://farm_pond_qa_account.json"))
	FileAccess.open(ApiClient.INSTALL_KEY_PATH,FileAccess.WRITE).store_string(account.key)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://farm-pond-proof"))
	_boot.call_deferred()

func _boot() -> void:
	assert(await Net.boot())
	assert(Net.session.has_farm())
	FarmChoice.save_choice(Net.session.farm_choice())
	farm = load("res://scenes/farm/farm.tscn").instantiate()
	farm.setup({"session":Net.session})
	add_child(farm)
	for frame in 40: await get_tree().process_frame
	# Show the reclaimed ground; the avatar remains at its authoritative spawn.
	farm.camera_pan.reset()
	farm._camera_center = farm.bp.cell_to_world(Vector2i(8,33)) + Vector3.UP*.7
	farm._camera_initialized = true
	farm._update_camera()

func _rect(control: Control) -> Array:
	var r := get_viewport().get_screen_transform() * control.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]

func _process(delta: float) -> void:
	_elapsed += delta
	if not is_instance_valid(farm) or not is_instance_valid(farm.mover) or _elapsed < .2: return
	_elapsed = 0
	var point: Vector2 = get_viewport().get_screen_transform() * farm.cam.unproject_position(farm.bp.cell_to_world(Vector2i(8,33)))
	var data := {"process_id":OS.get_process_id(),"target":[point.x,point.y],"position":str(farm.player.position),
		"moving":farm.mover.is_moving(),"work_mode":farm.work_mode,"mode_button":_rect(farm.hud._mode_toggle),
		"joined":farm.online.joined if farm.online else false,"online_error":farm.online.error if farm.online else "no connection","cells":Net.session.state.get("cells",{}),
		"farm_pond_mesh":farm.get_node_or_null("farm_pond") != null,
		"fishing_action":farm.hud._quick_actions.find_child("GoFishing",true,false) != null,
		"walkable":farm.bp.is_walkable(Vector2i(8,33)),"cultivable":farm.bp.mask_has("cultivable",Vector2i(8,33)),
		"version":Net.session.version,"fps":Engine.get_frames_per_second()}
	FileAccess.open("user://farm-pond-proof/state.json",FileAccess.WRITE).store_string(JSON.stringify(data))
