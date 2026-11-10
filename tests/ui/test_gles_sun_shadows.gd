extends GdUnitTestSuite
## SGODOT-456 (the user 11-09:「1. gles关闭阴影」): under the Compatibility renderer no DirectionalLight3D casts a shadow —
## one added with it on, or switched on by its owner just after it is added; other lights and other renderers keep theirs.

const GlesSunShadows := preload("res://modules/ui/gles_sun_shadows.gd")

func _watcher(active: bool) -> Node:
	var w: Node = GlesSunShadows.new()
	w.active = active
	add_child(auto_free(w))
	return w

func _sun(on_after_add := false) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = not on_after_add
	add_child(auto_free(sun))
	if on_after_add: sun.shadow_enabled = true
	return sun

func test_under_compatibility_no_sun_casts_a_shadow() -> void:
	var w := _watcher(true)
	var sun := _sun()
	var late := _sun(true)
	var lamp := OmniLight3D.new()
	lamp.shadow_enabled = true
	add_child(auto_free(lamp))
	await get_tree().process_frame
	assert_bool(sun.shadow_enabled).is_false()
	assert_bool(late.shadow_enabled).is_false()   # switched on after it entered the tree, off again by the frame's end
	assert_bool(lamp.shadow_enabled).is_true()    # only suns
	w.queue_free()

func test_other_renderers_keep_the_suns_shadow() -> void:
	_watcher(false)
	var sun := _sun()
	await get_tree().process_frame
	assert_bool(sun.shadow_enabled).is_true()

func test_it_is_an_autoload_that_reads_the_renderer() -> void:
	var w := get_tree().root.get_node_or_null("GlesSunShadows")
	assert_object(w).is_not_null()
	assert_bool(w.active).is_equal(RenderingServer.get_current_rendering_method() == "gl_compatibility")
