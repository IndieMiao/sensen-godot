extends Node
## Emulator QA entry for one's own parcel on the device save (C-60): opens the parcel named by
## `sensen/dynamic_farm/qa_parcel` straight into `dynamic_farm.tscn` with `own_parcel`, so the
## scene keeps the farm in `user://dynamic_farm_local/` (the staged build also sets
## `sensen/dynamic_farm/local_farm_save`). No map, server, account or network. Staged only by
## tools/dev/dynamic_farm/gather_qa_apk.sh; never the main scene of a delivered package.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const PARCEL_SETTING := "sensen/dynamic_farm/qa_parcel"
## C-211: the design's 减少动效 switch for a QA recording (gather_qa_apk.sh GATHER_QA_REDUCED_MOTION=1); no player setting.
const REDUCED_SETTING := "sensen/dev/reduced_motion"

func _ready() -> void:
	UiMotion.reduced = bool(ProjectSettings.get_setting(REDUCED_SETTING, false))
	var path := str(ProjectSettings.get_setting(PARCEL_SETTING, ""))
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	if not raw is Dictionary:
		push_error("QA parcel missing: " + path)
		return
	var scene: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup({"farm": raw, "dataset": raw.get("dataset_version"), "block_id": raw.get("block_id"), "own_parcel": true})
	scene.back_requested.connect(func(): get_tree().quit())
	scene.preview_error.connect(func(message): push_error(message))
	add_child(scene)
