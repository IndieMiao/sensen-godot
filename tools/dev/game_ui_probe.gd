extends "res://tools/dev/game_ui_observer.gd"
## Isolated HTTP actions; this bootstrap never ships in the Journey update.
func _ready() -> void:
	assert(bool(ProjectSettings.get_setting("sensen/network/online_qa", false)))
	super._ready()
	set_process(false)
	Localization.select_language("zh_CN")
	var account: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://ui_qa_account.json"))
	if ApiClient.install_key() != str(account.key):
		FileAccess.open(ApiClient.INSTALL_KEY_PATH, FileAccess.WRITE).store_string(str(account.key))
		FarmChoice.clear()
	var outfit := AvatarConfig.from_json_text(FileAccess.get_file_as_string("res://gallery_outfit.json"))
	assert(outfit != null and Avatar.save_outfit(outfit) == OK)
	var host := "10.0.2.2" if OS.get_name() == "Android" else "127.0.0.1"
	Net.use_transport(ApiClient.make_http_transport(self), "http://%s:3195/v1" % host)
	if not await Net.boot():
		push_error("GAME_UI_QA_LOGIN_FAILED")
		return
	FarmRegions.save_choice(Net.session.region_id)
	FarmChoice.save_choice(Net.session.farm_choice())
	var map_scene := (load(AppRouter.MAP) as PackedScene).instantiate()
	get_tree().root.add_child(map_scene)
	get_tree().current_scene = map_scene
	set_process(true)
	AppRouter.open_instance(AppRouter.FARM, {"session": Net.session})
