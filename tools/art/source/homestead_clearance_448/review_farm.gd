extends "res://scenes/p0/p0_farm.gd"
# QA-only: hold the actual native door-entry position for a clearance photograph.
var review_hold_door := false
var review_door_reached := false
func enter_farmhouse() -> void:
 if review_hold_door:
  review_door_reached=true
  actor.stand_still()
  _door_armed=false
  return
 super.enter_farmhouse()
