extends "res://modules/mining/monsters/f_creature_view.gd"

func _init() -> void:
	family = "mob_rock_beetle"

func build_placeholder() -> void:
	var color := Color(str(style.color))
	part(visual,"BrightRim",Vector3(0.94,0.2,0.74),Vector3(0,0.22,0),Color(str(style.accent)),false)
	part(visual,"Shell",Vector3(0.9,0.46,0.7),Vector3(0,0.3,0),color)
	part(visual,"Head",Vector3(0.38,0.28,0.3),Vector3(0,0.23,0.36),color)
	part(visual,"SingleHorn",Vector3(0.1,0.28,0.1),Vector3(0,0.44,0.43),Color(str(style.accent)),false)
	for row in 3:
		for side in [-1,1]:
			var hinge := Node3D.new()
			hinge.name = "Leg"
			hinge.position = Vector3(side*0.32,0.15,(row-1)*0.22)
			visual.add_child(hinge)
			limbs.append(hinge)
			var leg := part(hinge,"Upper",Vector3(0.23,0.055,0.07),Vector3(side*0.1,0,0),color)
			leg.rotation.z = side*0.3
			part(hinge,"Lower",Vector3(0.055,0.18,0.055),Vector3(side*0.2,-0.07,0.02),color)
	face(visual,Vector3(0,0.25,0.5))
