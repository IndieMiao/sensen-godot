extends "res://modules/mining/monsters/f_creature_view.gd"

func _init() -> void:
	family = "mob_shroomling"

func build_placeholder() -> void:
	var cream := Color(str(style.accent))
	part(visual,"Stem",Vector3(0.28,0.46,0.28),Vector3(0,0.25,0),cream,false)
	part(visual,"Cap",Vector3(0.72,0.34,0.65),Vector3(0,0.55,0),Color(str(style.color)))
	for p in [Vector3(0,0.71,0),Vector3(0.2,0.64,0.13),Vector3(-0.2,0.64,0.13),Vector3(0.14,0.66,-0.18),Vector3(-0.14,0.66,-0.18)]:
		part(visual,"Spot",Vector3(0.11,0.035,0.11),p,cream,false)
	face(visual,Vector3(0,0.3,0.14),0.8)
