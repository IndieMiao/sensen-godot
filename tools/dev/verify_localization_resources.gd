extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var messages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/localization/zh_CN.json"))
	var selected := TranslationServer.get_locale()
	assert(selected == root.get_node("Localization").load_preference())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--expect-language="): assert(selected == arg.trim_prefix("--expect-language="))
	TranslationServer.set_locale("zh_CN")
	assert(TranslationServer.translate("Choose a city") == "选择城市")
	var font := load("res://assets/ui/fonts/NotoSansSC-Regular.otf") as Font
	assert(font.has_char("语".unicode_at(0)))
	assert(load("res://assets/ui/icons/lucide/languages.svg") is Texture2D)
	TranslationServer.set_locale("en")
	assert(TranslationServer.translate("Choose a city") == "Choose a city")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-language="):
			assert(str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sensen-localization-qa"))
			assert(root.get_node("Localization").select_language(arg.trim_prefix("--save-language=")) == OK)
	print("LOCALIZATION_RESOURCES_OK messages=", messages.size(), " startup_locale=", selected)
	quit()
