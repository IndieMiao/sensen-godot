extends RefCounted
## Helpers use only resources in this folder; no room or game dependencies.
static func curve(points: Array) -> CurveTexture:
 var result := CurveTexture.new()
 var data := Curve.new()
 for point: Vector2 in points: data.max_value = maxf(data.max_value,point.y)
 for point: Vector2 in points: data.add_point(point)
 result.curve = data
 return result

## The particles' colour over their life, drawn as a linear vertex colour (the sprite's vertex_color_use_as_albedo). On
## Compatibility (GLES3) the material reads it as sRGB, a second decode: the ramp is given there sRGB-encoded, so it
## reads as it does on Mobile (SGODOT-458). Alpha as it is.
static func ramp(colors: PackedColorArray, offsets: PackedFloat32Array) -> GradientTexture1D:
 var texture := GradientTexture1D.new()
 var gradient := Gradient.new()
 if RenderingServer.get_current_rendering_method() == "gl_compatibility":
  var encoded := PackedColorArray()
  for c in colors: encoded.append(Color(c.linear_to_srgb(), c.a))
  colors = encoded
 gradient.colors = colors
 gradient.offsets = offsets
 texture.gradient = gradient
 return texture

static func sprite(texture: Texture2D, size: Vector2, frames: int, emissive: bool) -> QuadMesh:
 var mesh := QuadMesh.new()
 mesh.size = size
 var material := StandardMaterial3D.new()
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
 material.cull_mode = BaseMaterial3D.CULL_DISABLED
 material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
 material.particles_anim_h_frames = frames
 material.particles_anim_v_frames = 1
 material.particles_anim_loop = false
 material.vertex_color_use_as_albedo = true
 material.albedo_texture = texture
 material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
 if not emissive: material.albedo_color = Color(.74,.76,.77)
 if emissive:
  material.emission_enabled = true
  material.emission_texture = texture
  material.emission = Color("ff9b46")
  material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
  material.emission_energy_multiplier = .18
 mesh.material = material
 return mesh

static func particles(label: String, amount: int, lifetime: float, bounds: AABB) -> GPUParticles3D:
 var node := GPUParticles3D.new()
 node.name = label
 node.amount = amount
 node.lifetime = lifetime
 node.preprocess = lifetime
 node.fixed_fps = 30
 node.interpolate = true
 node.local_coords = true
 node.visibility_aabb = bounds
 node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 node.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
 node.use_fixed_seed = true
 node.seed = 178
 return node
