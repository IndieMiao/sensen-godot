extends SceneTree

func _initialize() -> void:
	var path := "res://assets/rooms/basic_room/room_albedo_ao.png.import"
	var config := ConfigFile.new()
	assert(config.load(path) == OK)
	config.set_value("params", "compress/mode", 2)
	config.set_value("params", "mipmaps/generate", true)
	config.set_value("params", "detect_3d/compress_to", 0)
	assert(config.save(path) == OK)
	print("ROOM_ATLAS_IMPORT VRAM compression, mipmaps enabled")
	quit()
