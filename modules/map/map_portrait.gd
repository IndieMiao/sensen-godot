class_name MapPortrait
extends AvatarFocusButton
## Cached head portrait: never a live full-body actor in the map world.
var config: AvatarConfig
var npc := false

func _ready() -> void:
	super._ready()
	Avatar.outfit_saved.disconnect(set_outfit)
	_direction_arrow.hide()
	custom_minimum_size = Vector2(36, 36)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if config: set_outfit(config)
	show()

func _style_portrait() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e9f0de") if npc else Color("f7f6ee")
		style.border_color = Color("a7df74") if npc else Color.WHITE
		style.set_border_width_all(2)
		style.set_corner_radius_all(18)
		style.shadow_color = Color(0.18, 0.22, 0.17, 0.13)
		style.shadow_size = 2
		add_theme_stylebox_override(state, style)
