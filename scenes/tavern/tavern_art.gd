@tool
extends "res://scenes/coffee_shop/coffee_shop_art.gd"
## Tavern/forge adapter: atlas-coloured emission and explicit local light pools.
func _ready() -> void:
 if _assembled: return
 super._ready()
 var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(kit_path + "/layout.json"))
 for placement: Dictionary in layout.assets + layout.instances:
  var node := get_node(NodePath(placement.name)) as Node3D
  if placement.has("scale"): node.scale = _vec(placement.scale)
  _multiply_emission(node)
 for lamp: Dictionary in layout.get("local_lights", []):
  var light := OmniLight3D.new()
  light.name = "LocalLight_" + str(lamp.name)
  light.position = _vec(lamp.position)
  light.light_color = Color(lamp.color)
  light.light_energy = float(lamp.energy)
  light.omni_range = float(lamp.range)
  light.omni_attenuation = float(lamp.get("attenuation", 1.0))
  light.shadow_enabled = false
  light.add_to_group("art_local_lights")
  add_child(light)

func _multiply_emission(node: Node) -> void:
 if node is MeshInstance3D:
  var material := node.material_override as StandardMaterial3D
  if material and material.emission_enabled:
   material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
 for child in node.get_children(): _multiply_emission(child)
