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
## C-211: slow motion for an emulator recording (GATHER_QA_TIME_SCALE=0.2): the software-rendered emulator draws a few
## frames a second, too few for a 160 ms fade; everything (tweens, timers, walking) runs at this rate.
const TIME_SCALE_SETTING := "sensen/dev/time_scale"

func _ready() -> void:
	UiMotion.reduced = bool(ProjectSettings.get_setting(REDUCED_SETTING, false))
	Engine.time_scale = float(ProjectSettings.get_setting(TIME_SCALE_SETTING, 1.0))
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
