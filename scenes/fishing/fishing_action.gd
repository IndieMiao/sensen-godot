extends Button
## A single thumb target for casting, hooking and holding tension.

var progress := 0.0
var pulling := false
static var _symbol: Texture2D

func _ready() -> void:
	if _symbol == null:
		var pixels := GameUi.icon("fish").get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		for y in pixels.get_height():
			for x in pixels.get_width(): pixels.set_pixel(x, y, Color(1, 1, 1, pixels.get_pixel(x, y).a))
		_symbol = ImageTexture.create_from_image(pixels)
		_symbol.set_size_override(Vector2i(24, 24))
	icon = _symbol

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 3
	if progress > 0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, GameUi.GOLD, 3.0, true)
	if pulling:
		draw_arc(center, radius - 5, 0, TAU, 64, Color(GameUi.PAPER, 0.65), 1.5, true)
