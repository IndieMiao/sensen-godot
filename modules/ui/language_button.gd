class_name LanguageButton
extends MenuButton

func _ready() -> void:
	name = "LanguageButton"
	icon = GameUi.icon("languages")
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tooltip_text = "Language"
	custom_minimum_size = Vector2(44, 44)
	theme_type_variation = &"SecondaryButton"
	focus_mode = Control.FOCUS_ALL
	switch_on_hover = false
	var menu := get_popup()
	menu.theme = theme.duplicate() if theme else GameUi.theme()
	for spec in [["radio_checked", "circle-check"], ["radio_unchecked", "circle"]]:
		var pixels := GameUi.icon(spec[1]).get_image()
		for y in pixels.get_height():
			for x in pixels.get_width():
				pixels.set_pixel(x, y, Color(GameUi.INK, pixels.get_pixel(x, y).a))
		menu.theme.set_icon(spec[0], "PopupMenu", ImageTexture.create_from_image(pixels))
	menu.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	menu.add_radio_check_item("简体中文", 0)
	menu.add_radio_check_item("English", 1)
	menu.id_pressed.connect(_select)
	about_to_popup.connect(_update_checks)
	_update_checks()

func _update_checks() -> void:
	for index in Localization.SUPPORTED.size():
		get_popup().set_item_checked(index, TranslationServer.get_locale() == Localization.SUPPORTED[index])

func _select(index: int) -> void:
	if index < 0 or index >= Localization.SUPPORTED.size(): return
	var error := Localization.select_language(Localization.SUPPORTED[index])
	if error != OK:
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "Language preference could not be saved."
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered(Vector2i(280, 120))
	_update_checks()
