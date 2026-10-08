@tool
extends "res://scenes/coffee_shop/coffee_shop_art.gd"
## Three actual unshadowed spotlights; authored targets expose floor/table pools.
func _ready() -> void:
 if _assembled: return
 super._ready()
 var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/clothing_store_a/layout.json"))
 if layout.has("bench_albedo_multiplier"):
  var tint: Array = layout.bench_albedo_multiplier
  _tint_bench(get_node("black_tufted_bench"),Color(tint[0],tint[1],tint[2]))
 for fixture: Dictionary in layout.get("pendant_pools", []):
  var light := SpotLight3D.new()
  light.name = str(fixture.name)
  light.position = Vector3(fixture.position[0],fixture.position[1],fixture.position[2])
  light.light_color = Color("ffe0b8")
  light.light_energy = float(fixture.energy)
  light.spot_range = 5.5
  light.spot_angle = float(fixture.angle)
  light.spot_angle_attenuation = 1.2
  light.shadow_enabled = false
  light.add_to_group("street_pendant_pools")
  add_child(light)
  light.look_at(Vector3(fixture.target[0],fixture.target[1],fixture.target[2]))

func _tint_bench(node: Node, tint: Color) -> void:
 if node is MeshInstance3D:
  var material := node.material_override.duplicate() as StandardMaterial3D
  material.albedo_color = tint
  node.material_override = material
 for child in node.get_children(): _tint_bench(child,tint)
