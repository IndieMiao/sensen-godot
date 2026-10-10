extends ColorRect
## The map's fog (plan v2 §11.7.1–11.7.3, SGODOT-275): a full-screen grey veil under the pins, bubbles and names, with a
## soft hole round every explored city, so explored cities read in full colour and the rest of the world is greyed. Only
## colouring: it takes no touches and hides nothing — city names, bubbles, online counts and friends draw over it, and
## what can be entered is decided by the server's passes. The host gives the holes each frame ({at: Vector2 px,
## r: float px}); with none it stays clear (Journey has no fog). It stays at every zoom (不知火舞 on #227: a neighbour
## city's pins would otherwise turn full colour up close); inside an explored city its hole covers the screen.

const SHADER := preload("res://modules/map/shaders/map_fog.gdshader")
const MAX_HOLES := 64
## The design's veil (不知火舞 on 279 6c0377f7): COLOR_SECONDARY at 40 %; the earlier light blue-grey washed out over the
## pale Mapbox base on the phone. On the device only the opacity is tuned (35–45 %), never the colour.
const FOG := Color(UiTokens.COLOR_SECONDARY, 0.40)

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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # the host may place it over the whole screen instead

## Holes in the host's pixels ({at, r}), shifted by `offset` into this layer's (the host draws inside the safe area, the
## veil covers the whole screen); hidden when the host has no fog. The shader is only fed when something changed.
var _applied: Array = []
var _applied_k := -1.0
var _applied_offset := Vector2.INF

func apply(new_holes: Array, _zoom: float, enabled: bool, offset := Vector2.ZERO) -> void:
	var k := 1.0 if enabled else 0.0
	visible = k > 0.0
	if not visible: return
	if is_same(new_holes, _applied) and k == _applied_k and offset == _applied_offset and _mat.get_shader_parameter("size") == size:
		return
	_applied = new_holes
	_applied_k = k
	_applied_offset = offset
	holes = new_holes.slice(0, MAX_HOLES)
	var packed: Array = []
	for h in holes: packed.append(Vector4(h.at.x + offset.x, h.at.y + offset.y, float(h.r), 0.0))
	while packed.size() < MAX_HOLES: packed.append(Vector4.ZERO)
	_mat.set_shader_parameter("holes", packed)
	_mat.set_shader_parameter("count", holes.size())
	_mat.set_shader_parameter("size", size)
	_mat.set_shader_parameter("fog_color", Color(FOG, FOG.a * k))
