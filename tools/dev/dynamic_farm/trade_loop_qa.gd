extends Control
## Emulator QA entry for the parcel's trading loop (C-149): a plain stand-in for the map with two keys, the Washington
## Square room (parcel_outpost.tscn: Jasmine's counter) and the player's own parcel (dynamic_farm_host.tscn), both opened
## through AppRouter as the map opens them and both on the same device save (`sensen/dynamic_farm/local_farm_save`).
## The parcel is `sensen/dynamic_farm/qa_parcel`. On first start, when the parcel has no save yet, it is saved as the
## card's problem state: welcomed, the hoe and 2 carrots, no seeds left (C-137#4). No map, server, account or network.
## Staged only by tools/dev/dynamic_farm/gather_qa_apk.sh with GATHER_QA_ENTRY=trade; never the main scene of a delivered package.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const HOST := "res://scenes/dynamic_farm/dynamic_farm_host.tscn"
const ROOM := "res://scenes/dynamic_farm/parcel_outpost.tscn"
const PARCEL_SETTING := "sensen/dynamic_farm/qa_parcel"
const START_BAG := {"hoe_starter": 1, "crop_carrot": 2}

var farm := {}
var _status: Label

func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("E7F0DF")   # the map's occlusion colour
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var path := str(ProjectSettings.get_setting(PARCEL_SETTING, ""))
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	if not raw is Dictionary:
		push_error("QA parcel missing: " + path)
		return
	farm = raw
	var store := LocalStore.new(str(farm.block_id))
	if not FileAccess.file_exists(store._path):
		store._save(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": START_BAG,
			"welcomed_at": int(Time.get_unix_time_from_system() * 1000.0)}), 1)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(280, 0)
	box.position = Vector2(-140, -80)
	box.add_theme_constant_override(&"separation", 16)
	add_child(box)
	_status = UiKit.label("", UiTokens.STYLE_C14_XB)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	var town := UiCommandButton.new("Washington Square")
	town.name = "Town"
	town.activated.connect(_open.bind(ROOM))
	box.add_child(town)
	var mine := UiCommandButton.new("Enter my farm", UiCommandButton.Kind.SECONDARY)
	mine.name = "Farm"
	mine.activated.connect(_open.bind(HOST))
	box.add_child(mine)
	_refresh()

## The save's coins and seeds, read again on each return (QA only; the map has no such line).
func _refresh() -> void:
	var saved: Dictionary = LocalStore.new(str(farm.block_id)).read()
	var f: Dictionary = saved.get("farm", {})
	_status.text = "QA · %d coins · %d seeds · %d carrots" % [int(f.get("coins", 0)), int(f.get("bag", {}).get("seed_carrot", 0)),
		int(f.get("bag", {}).get("crop_carrot", 0))]

func _open(path: String) -> void:
	var router := get_node_or_null("/root/AppRouter")
	if router == null: return
	var block := str(farm.block_id)
	if path == ROOM:
		await router.open_instance(ROOM, {"store": LocalStore.new(block), "parcel_id": block})
	else:
		await router.open_instance(HOST, {"farm": farm, "dataset": farm.dataset_version, "block_id": block, "own_parcel": true})

func suspend() -> void:
	hide()

func resume() -> void:
	show()
	_refresh()
