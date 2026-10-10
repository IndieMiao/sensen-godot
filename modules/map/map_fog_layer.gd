extends ColorRect
## The map's fog (plan v2 §11.7.1–11.7.3, SGODOT-275): a full-screen grey veil under the pins, bubbles and names, with a
## soft hole round every explored city, so explored cities read in full colour and the rest of the world is greyed. Only
## colouring: it takes no touches and hides nothing — city names, bubbles, online counts and friends draw over it, and
## what can be entered is decided by the server's passes. The host gives the holes each frame ({at: Vector2 px,
## r: float px}); with none it stays clear (Journey has no fog). Fades out at street zoom, inside a city.

const SHADER := preload("res://modules/map/shaders/map_fog.gdshader")
const MAX_HOLES := 64
## Fully shown at or below FULL_ZOOM, gone at CLEAR_ZOOM and above (street level: the player is in a city).
const FULL_ZOOM := 11.0
const CLEAR_ZOOM := 14.0
const FOG := Color(0.62, 0.65, 0.68, 0.42)

var holes: Array = []
var _mat: ShaderMaterial

func _init() -> void:
	name = "MapFog"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## The veil's strength at a zoom (1 at the country and city zoom, 0 at street zoom).
static func strength(zoom: float) -> float:
	return clampf((CLEAR_ZOOM - zoom) / (CLEAR_ZOOM - FULL_ZOOM), 0.0, 1.0)

## Holes in this layer's pixels and the zoom; hidden when the zoom clears it or the host has no fog. The shader is only
## fed when something changed (the same holes array, the same strength: nothing to do).
var _applied: Array = []
var _applied_k := -1.0

func apply(new_holes: Array, zoom: float, enabled: bool) -> void:
	var k := strength(zoom) if enabled else 0.0
	visible = k > 0.0
	if not visible: return
	if is_same(new_holes, _applied) and k == _applied_k and _mat.get_shader_parameter("size") == size: return
	_applied = new_holes
	_applied_k = k
	holes = new_holes.slice(0, MAX_HOLES)
	var packed: Array = []
	for h in holes: packed.append(Vector4(h.at.x, h.at.y, float(h.r), 0.0))
	while packed.size() < MAX_HOLES: packed.append(Vector4.ZERO)
	_mat.set_shader_parameter("holes", packed)
	_mat.set_shader_parameter("count", holes.size())
	_mat.set_shader_parameter("size", size)
	_mat.set_shader_parameter("fog_color", Color(FOG, FOG.a * k))
