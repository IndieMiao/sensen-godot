extends "res://modules/mining/monsters/f_creature_view.gd"

func _init() -> void:
	family = "mob_cave_bat"

func build_placeholder() -> void:
	var color := Color(str(style.color))
	var h := float(style.hover)
	part(visual,"Torso",Vector3(0.4,0.36,0.3),Vector3(0,h,0),color)
	for side in [-1,1]:
		part(visual,"Ear",Vector3(0.12,0.24,0.1),Vector3(side*0.12,h+0.23,0),color)
		var hinge := Node3D.new()
		hinge.name = "Wing"
		hinge.position = Vector3(side*0.18,h,0)
		visual.add_child(hinge)
		limbs.append(hinge)
		part(hinge,"WingMembrane",Vector3(0.46,0.07,0.34),Vector3(side*0.2,0,0),color)
		for i in 3:
			part(hinge,"WingLobe",Vector3(0.13,0.06,0.18),Vector3(side*(0.08+i*0.12),0,-0.14),color)
	face(visual,Vector3(0,h,0.15))
