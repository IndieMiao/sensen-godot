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
	GameUi.register_modal(menu)
	menu.theme = theme.duplicate() if theme else GameUi.theme()
	for spec in [["radio_checked", "circle-check"], ["radio_unchecked", "circle"]]:
		menu.theme.set_icon(spec[0], "PopupMenu", GameUi._menu_radio(spec[1]))
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
		GameUi.register_modal(dialog)
		dialog.theme = GameUi.theme()
		dialog.theme.set_stylebox("panel", "AcceptDialog", GameUi.panel_style(18))
		dialog.borderless = true
		dialog.unresizable = true
		dialog.dialog_autowrap = true
		dialog.get_ok_button().theme_type_variation = &"AccentButton"
		dialog.dialog_text = "Language preference could not be saved."
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered(Vector2i(280, 120))
	_update_checks()
