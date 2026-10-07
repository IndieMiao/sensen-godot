@tool
extends "res://scenes/coffee_shop/coffee_shop_art.gd"
## Three local lamp pools, no volumetrics or extra shadow passes.
func _ready() -> void:
 if _assembled: return
 super._ready()
 for p: Vector3 in [Vector3(-1.99,2.82,-1.84), Vector3(-1.04,2.66,-1.20), Vector3(-.44,2.87,-2.04)]:
  var light := SpotLight3D.new()
  light.name = "PendantPool"
  light.position = p
  light.rotation_degrees.x = -90
  light.light_color = Color("ffe0b8")
  light.light_energy = 3.0
  light.spot_range = 4.0
  light.spot_angle = 29.0
  light.spot_angle_attenuation = .7
  light.shadow_enabled = false
  add_child(light)
