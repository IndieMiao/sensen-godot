@tool
extends "res://scenes/coffee_shop/coffee_shop_art.gd"
## Preserve printed drink colours under the fridge's atlas-based emission.
func _ready() -> void:
 if _assembled: return
 super._ready()
 for module_name in ["chilled_drinks_stock", "chilled_drinks_stock_second"]:
  _set_stock_emission(get_node(module_name))

func _set_stock_emission(node: Node) -> void:
 if node is MeshInstance3D:
  var material := node.material_override as StandardMaterial3D
  material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
 for child in node.get_children(): _set_stock_emission(child)
