extends RefCounted
## Duplicate the original ground material and keep both original texture bindings.
static func material(original: ShaderMaterial, shape: String) -> ShaderMaterial:
    var m := original.duplicate() as ShaderMaterial
    m.shader = load("res://pond_ground.sample.gdshader")
    for name in ["grass_detail", "surface_flow"]:
        m.set_shader_parameter(name, original.get_shader_parameter(name))
    m.set_shader_parameter("meadow_color", load("res://assets/ponds/ground/meadow_color.png"))
    m.set_shader_parameter("ground_layout", load("res://assets/ponds/ground/"+shape+"_layout.png"))
    m.set_shader_parameter("dry_ground_mask", load("res://assets/ponds/ground/dry_ground_mask.png"))
    m.set_shader_parameter("dry_channel", {"crescent":Vector3(1,0,0),"gourd":Vector3(0,1,0),"meander":Vector3(0,0,1)}[shape])
    return m
