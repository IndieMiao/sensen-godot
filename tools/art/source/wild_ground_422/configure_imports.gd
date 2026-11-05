extends SceneTree
## Run after the editor generated UIDs. Keep packed alpha from rewriting RGB.
func _initialize() -> void:
	for filename in ["meadow_color.png", "crescent_layout.png", "gourd_layout.png", "meander_layout.png"]:
		var path: String = "res://assets/ponds/ground/" + filename + ".import"
		var cfg := ConfigFile.new()
		assert(cfg.load(path) == OK)
		assert(str(cfg.get_value("remap", "uid", "")).begins_with("uid://"))
		cfg.set_value("params", "compress/mode", 0) # Lossless data, deterministic masks.
		cfg.set_value("params", "mipmaps/generate", true)
		cfg.set_value("params", "process/fix_alpha_border", false)
		cfg.set_value("params", "process/premult_alpha", false)
		cfg.set_value("params", "detect_3d/compress_to", 0)
		assert(cfg.save(path) == OK)
	quit()
