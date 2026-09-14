extends Node

signal language_changed

const SETTINGS_PATH := "user://language.cfg"
const SUPPORTED := ["zh_CN", "en"]

func _init() -> void:
	var translation := Translation.new()
	translation.locale = "zh_CN"
	var messages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/localization/zh_CN.json"))
	for source in messages:
		translation.add_message(source, messages[source])
	TranslationServer.add_translation(translation)
	var locale := load_preference()
	# Godot consumes --language before autoloads; use an explicit QA override.
	var override := OS.get_environment("SENSEN_LANGUAGE")
	if override in SUPPORTED: locale = override
	TranslationServer.set_locale(locale)

func load_preference(path := SETTINGS_PATH) -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK: return "zh_CN"
	var saved := str(config.get_value("interface", "language", "zh_CN"))
	return saved if saved in SUPPORTED else "zh_CN"

func select_language(locale: String, path := SETTINGS_PATH) -> Error:
	if locale not in SUPPORTED: return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("interface", "language", locale)
	var error := config.save(path)
	if error != OK: return error
	TranslationServer.set_locale(locale)
	language_changed.emit()
	return OK
