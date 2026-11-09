extends Node
## The wild ground's bake (SGODOT-422, 盘古; #917: the painted ground's per-pixel noise halved the frame rate on GLES).
## On entering a pond the full shader (pond_wild_ground.gdshader) is drawn once, top-down, into two images by a 2D pass
## (pond_wild_ground_bake.gdshader) — NEAR over the walk and the farthest view at NEAR_PX_M, the whole ground at FAR_PX_M
## — read back with mipmaps; then PaintedGround takes the baked material (pond_wild_ground_baked.gdshader: two texture
## reads, the large light, terrace tops and rock sides live, the same shadows). Until then (the frame it is drawn in) the
## full shader stays, so nothing flickers; headless (tests) a SubViewport never draws: the full shader stays for good.
## The bake waits for the scenery to be in the tree: the plants' feet (contact_points) are set after the ground is built.

const BAKE_SHADER := preload("res://modules/ponds/pond_wild_ground_bake.gdshader")
const BAKED_SHADER := preload("res://modules/ponds/pond_wild_ground_baked.gdshader")
## The walk (x −2.5…14.5, z −16…1.5) and what the farthest zoom (0.68) shows round it: 26 × 37 m. (At the walk's very
## corners the screen's corners reach x −8.1…21.3, z −24…15 — under the woods; the far image covers them, 11-09 shots.)
const NEAR := Rect2(-6, -24, 26, 37)
const NEAR_PX_M := 50.0   # 1300 × 1850 px
const FAR_PX_M := 8.0     # the whole ground (PondWildGround.AREA, 66 × 64 m): 528 × 512 px, mostly under the woods
const FAR_SUPER := 2      # … drawn at twice that and halved, so its fine grain averages out instead of aliasing
## The live material's settings, from the full one's.
const LIVE_KEYS := ["sun_k", "walk", "grass", "grass_far", "plateau", "rock", "gradient", "centre", "south_dark", "vignette", "seed_off", "detail",
	"shadow_tint", "shadow_tint_sand", "shadow_cool", "shadow_cool_sand"]
## One bake kept (≈ 14.3 MB of textures, see bytes()) while in a pond: a rebuild with the same plants takes it as it is;
## the gathering points coming bake anew and let the old one go. Leaving the pond lets it go too (P0Pond._exit_tree,
## clear_cache — 上官婉儿: the 14 MB not kept outside the wild), so a later visit bakes again (~46 ms on the desktop).
const CACHE_MAX := 1
static var _CACHE := {}   # key() -> [near ImageTexture, far ImageTexture]
## The last bake's timings, ms (dev: P0_BAKE_LOG prints them): read back, mipmaps, upload, total from the request.
static var last_ms := {}

var ground: MeshInstance3D
var shape_key := ""
var area := Rect2()
var _near_vp: SubViewport
var _far_vp: SubViewport
var _key := ""
var _t0 := 0

static func headless() -> bool: return DisplayServer.get_name() == "headless"

## What the bake depends on: the pond's shape and seed, and every setting of the full material but the water's distance
## texture (built from the shape), so the plants' feet and the bank's trees (they move with the gathering points) too.
static func key(shape: String, material: ShaderMaterial) -> String:
	var parts := PackedStringArray([shape])
	for u in BAKE_SHADER.get_shader_uniform_list():
		var v = material.get_shader_parameter(u.name)
		if v is Texture2D: continue
		parts.append("%s=%s" % [u.name, str(v)])
	return str("|".join(parts).hash()) + ":" + str("|".join(parts).length())

static func cached(k: String) -> bool: return _CACHE.has(k)
static func clear_cache() -> void: _CACHE.clear()

## Texture bytes of one bake with mipmaps (RGBA8): near, far.
static func bytes() -> Vector2i:
	var n := Vector2i(roundi(NEAR.size.x * NEAR_PX_M), roundi(NEAR.size.y * NEAR_PX_M))
	return Vector2i(_with_mips(n.x, n.y), _with_mips(roundi(66 * FAR_PX_M), roundi(64 * FAR_PX_M)))

static func _with_mips(w: int, h: int) -> int:
	var total := 0
	while true:
		total += w * h * 4
		if w == 1 and h == 1: return total
		w = maxi(1, w / 2)
		h = maxi(1, h / 2)
	return total

func _ready() -> void:
	if headless(): return   # no SubViewport draws headless: the full shader stays (the tests)
	if OS.get_environment("P0_WILD_NO_BAKE") != "": return   # dev: the full shader throughout (before / after shots)
	_start.call_deferred()   # the scenery has set the plants' feet by now; the same frame, before it is drawn

func _start() -> void:
	if not is_instance_valid(ground) or not (ground.material_override is ShaderMaterial): return
	var full := ground.material_override as ShaderMaterial
	_key = key(shape_key, full)
	if _CACHE.has(_key):   # the same pond, the same plants: no frame of the full shader
		_swap(full, _CACHE[_key])
		return
	_t0 = Time.get_ticks_usec()
	_near_vp = _viewport(full, NEAR, NEAR_PX_M)
	_far_vp = _viewport(full, area, FAR_PX_M * FAR_SUPER)
	RenderingServer.frame_post_draw.connect(_read, CONNECT_ONE_SHOT)   # dropped with this node if the scenery goes first

func _viewport(full: ShaderMaterial, rect: Rect2, px_m: float) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(rect.size.x * px_m), roundi(rect.size.y * px_m))
	vp.disable_3d = true
	vp.transparent_bg = true   # the alpha channel is data
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var m := ShaderMaterial.new()
	m.shader = BAKE_SHADER
	for u in BAKE_SHADER.get_shader_uniform_list():
		var v = full.get_shader_parameter(u.name)
		if v == null: continue
		m.set_shader_parameter(u.name, _as_seen(v))
	m.set_shader_parameter("bake_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	var r := ColorRect.new()
	r.size = Vector2(vp.size)
	r.material = m
	vp.add_child(r)
	add_child(vp)
	return vp

func _read() -> void:
	if not is_inside_tree() or not is_instance_valid(ground): return
	var t1 := Time.get_ticks_usec()
	var near := _near_vp.get_texture().get_image()
	var far := _far_vp.get_texture().get_image()
	_near_vp.queue_free()
	_far_vp.queue_free()
	if near == null or far == null or near.is_empty() or far.is_empty(): return   # the full shader stays
	var t2 := Time.get_ticks_usec()
	far.resize(far.get_width() / FAR_SUPER, far.get_height() / FAR_SUPER, Image.INTERPOLATE_TRILINEAR)
	near.generate_mipmaps()
	far.generate_mipmaps()
	var t3 := Time.get_ticks_usec()
	var textures := [ImageTexture.create_from_image(near), ImageTexture.create_from_image(far)]
	var t4 := Time.get_ticks_usec()
	while _CACHE.size() >= CACHE_MAX: _CACHE.erase(_CACHE.keys()[0])
	_CACHE[_key] = textures
	_swap(ground.material_override as ShaderMaterial, textures)
	last_ms = {"read": (t2 - t1) / 1000.0, "mipmaps": (t3 - t2) / 1000.0, "upload": (t4 - t3) / 1000.0,
		"cpu": (t4 - t1) / 1000.0, "total": (Time.get_ticks_usec() - _t0) / 1000.0}
	if OS.get_environment("P0_BAKE_LOG") != "": print("P0_BAKE ", JSON.stringify(last_ms))

## A colour as the full spatial shader sees its source_color uniform: Mobile / Forward+ linearise it, Compatibility
## (sRGB-space lighting) takes it as given — measured on both, 11-09 (a 2D pass converts nothing, so the bake is told).
static func _as_seen(v: Variant) -> Variant:
	if v is Color and RenderingServer.get_current_rendering_method() != "gl_compatibility": return (v as Color).srgb_to_linear()
	return v

## PaintedGround on the baked textures, its settings from the full material's.
func _swap(full: ShaderMaterial, textures: Array) -> void:
	var m := ShaderMaterial.new()
	m.shader = BAKED_SHADER
	for name in LIVE_KEYS: m.set_shader_parameter(name, full.get_shader_parameter(name))
	m.set_shader_parameter("baked_near", textures[0])
	m.set_shader_parameter("baked_far", textures[1])
	m.set_shader_parameter("near_rect", Vector4(NEAR.position.x, NEAR.position.y, NEAR.size.x, NEAR.size.y))
	m.set_shader_parameter("far_rect", Vector4(area.position.x, area.position.y, area.size.x, area.size.y))
	m.set_shader_parameter("w_soft", soft_share(full))
	ground.material_override = m

## The meadow's share of the colour where the pale band is strongest (pond_wild_ground_paint's soft band at full: 0.8 of
## the way to 0.55 × soft_grass × c / grass + 0.45 × soft_grass, on the plain grass): under it the baked alpha means sand
## or path, and the shadows take the sand's colour by how far under.
static func soft_share(full: ShaderMaterial) -> float:
	var g: Color = _as_seen(full.get_shader_parameter("grass"))
	var s: Color = _as_seen(full.get_shader_parameter("soft_grass"))
	var f := 0.8 * float(full.get_shader_parameter("seam_fix"))
	var gs := g.r + g.g + g.b
	var ss := s.r + s.g + s.b
	var meadow := (1.0 - f) * gs + f * 0.55 * ss
	return clampf(meadow / maxf(meadow + f * 0.45 * ss, 1e-4), 0.05, 1.0)
