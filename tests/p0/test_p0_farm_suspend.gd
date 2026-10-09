extends GdUnitTestSuite
## SGODOT-256 ⑥ (int10c): the dressing room opened over the farm showed no character. The farm, suspended under it,
## only hid its canvas layers; a hidden CanvasLayer at −1 (FarmBackground) still took part in the dressing room's
## canvas background (BG_CANVAS, max layer −1), which then drew its backdrop over the 3D character. Suspended, the
## farm's canvas layers now leave the tree; resume puts them back in their places.

func _farm() -> Node3D:
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_farm.gd\"\nfunc _ready() -> void: pass\nfunc _exit_tree() -> void: pass\nfunc _process(_d) -> void: pass\n"
	stub.reload()
	var farm: Node3D = load("res://scenes/p0/p0_farm.tscn").instantiate()
	farm.set_script(stub)
	add_child(farm)
	return farm

func _layers(farm: Node) -> Array:
	return farm.get_children().filter(func(c): return c is CanvasLayer).map(func(c): return [str(c.name), c.get_index()])

func test_a_suspended_farm_takes_its_canvas_layers_out_of_the_tree() -> void:
	var farm := _farm()
	await get_tree().process_frame
	var before := _layers(farm)
	assert_array(before.map(func(l): return l[0])).contains(["FarmBackground", "OpaqueSceneLayer"])
	var others := farm.get_child_count() - before.size()
	farm.suspend()
	assert_array(_layers(farm)).is_empty()
	assert_object(farm.get_node_or_null("FarmBackground")).is_null()
	assert_int(farm.get_child_count()).is_equal(others)   # nothing else leaves
	farm.suspend()   # a second suspend holds them once
	farm.resume()
	assert_array(_layers(farm)).is_equal(before)   # back in their places
	for c in farm.get_children():
		if c is CanvasLayer: assert_bool((c as CanvasLayer).visible).is_true()
	farm.free()

func test_a_farm_freed_while_suspended_frees_its_canvas_layers() -> void:
	var farm := _farm()
	await get_tree().process_frame
	var bg: Node = farm.get_node("FarmBackground")
	farm.suspend()
	assert_bool(bg.is_inside_tree()).is_false()
	farm.free()
	assert_bool(is_instance_valid(bg)).is_false()   # no orphan left behind
