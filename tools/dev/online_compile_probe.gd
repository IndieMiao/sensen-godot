extends Node

func _ready() -> void:
	var scripts := ["res://modules/net/online_space.gd", "res://modules/net/online_crowd.gd", "res://scenes/mine/online_mine.gd"]
	for path in scripts:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			get_tree().quit(1)
			return
	print("ONLINE_COMPILE_OK")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(.3, .44, .3)), Vector3.ZERO))
	print("MULTIMESH_READBACK ", mm.get_instance_transform(0).basis.get_scale())
	get_tree().quit()
