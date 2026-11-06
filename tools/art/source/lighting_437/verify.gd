extends SceneTree
const KIT = "res://assets/landmarks/_shared/lighting/"
var checks = []

func check(ok, label):
	checks.append({"passed":bool(ok), "check":label})
	if not ok: push_error(label)

func _initialize(): run.call_deferred()

func shadow_values(sun):
	var values = {}
	for property in sun.get_property_list():
		if "shadow" in property.name and property.usage & PROPERTY_USAGE_STORAGE:
			values[property.name] = sun.get(property.name)
	return values

func run():
	var expected = Environment.new()
	expected.background_mode = Environment.BG_COLOR
	expected.background_color = Color("d000d0")
	expected.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	expected.ambient_light_color = Color("d5e4ee")
	expected.ambient_light_energy = 0.72
	var noon = load(KIT+"warm_noon.tres")
	var differences = []
	for property in expected.get_property_list():
		var key = property.name
		if not property.usage & PROPERTY_USAGE_STORAGE or key.begins_with("resource_") or key == "script": continue
		if expected.get(key) != noon.environment.get(key):
			differences.append({"name":key,"expected":str(expected.get(key)),"actual":str(noon.environment.get(key))})
	check(differences.is_empty(), "warm noon Environment matches every stored original setting")
	var original_sun = DirectionalLight3D.new()
	original_sun.shadow_enabled = true
	original_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	original_sun.directional_shadow_max_distance = 120.0
	original_sun.shadow_opacity = .48
	original_sun.shadow_bias = .035
	original_sun.shadow_normal_bias = .28
	var rig = load(KIT+"lighting_rig.tscn").instantiate()
	root.add_child(rig)
	await process_frame
	check(rig.get_child_count()==2, "fragment has only one environment and one sun")
	check(shadow_values(rig.get_node("Sun")) == shadow_values(original_sun), "all shadow properties match original Alcatraz")
	check(rig.get_node("Sun").light_color == Color(1,.965,.88), "noon original sun color")
	check(is_equal_approx(rig.get_node("Sun").light_energy,.98), "noon original sun energy")
	check(rig.get_node("Sun").rotation_degrees.is_equal_approx(Vector3(-56,-34,0)), "noon original sun rotation")
	check(rig.is_set_as_top_level(), "fragment sun is independent of host transform")
	var host = WorldEnvironment.new()
	var sun = DirectionalLight3D.new()
	# Griffith's different shadow profile must survive every preset switch.
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 0.0
	sun.directional_shadow_fade_start = 1.0
	sun.directional_shadow_pancake_size = 4.0
	sun.shadow_opacity = .48
	sun.shadow_bias = .035
	sun.shadow_normal_bias = .28
	sun.shadow_blur = 1.8
	var preserved = shadow_values(sun)
	var summary = {}
	for name in ["warm_noon","cool_morning","golden_dusk"]:
		var preset = load(KIT+name+".tres")
		preset.apply_to(host, sun)
		check(host.environment != preset.environment, name+": independent environment copy")
		check(shadow_values(sun)==preserved, name+": host Griffith shadow settings preserved")
		for key in ["ssao_enabled","ssr_enabled","sdfgi_enabled","volumetric_fog_enabled","fog_enabled","glow_enabled"]:
			check(not host.environment.get(key), name+": "+key+" off")
		check(host.environment.sky == null, name+": no sky or radiance resource")
		check(host.environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, name+": constant ambient source")
		var original_color = preset.environment.background_color
		host.environment.background_color = Color.RED
		check(preset.environment.background_color == original_color, name+": host edits do not pollute preset")
		rig.preset = preset
		check(rig.get_node("Sun").light_color==preset.sun_color, name+": scene preset switch applies sun")
		summary[name] = {"background":original_color.to_html(),"ambient":preset.environment.ambient_light_color.to_html(),"ambient_energy":preset.environment.ambient_light_energy,"sun":preset.sun_color.to_html(),"sun_energy":preset.sun_energy,"sun_rotation_degrees":str(preset.sun_rotation_degrees)}
	for script_name in ["lighting_preset.gd","lighting_rig.gd"]:
		var methods = load(KIT+script_name).get_script_method_list().map(func(method):return method.name)
		check(not "_process" in methods and not "_physics_process" in methods, script_name+": no per-frame callback")
	var result = {"passed":checks.all(func(c):return c.passed),"checks":checks,"noon_environment_differences":differences,"presets":summary,"alcatraz_shadow_settings":shadow_values(original_sun),"griffith_shadow_settings_preserved":preserved}
	FileAccess.open("res://../resource-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	original_sun.free();host.free();sun.free();rig.free()
	print("LIGHTING_RESOURCES ",result.passed," ",checks.size())
	quit(0 if result.passed else 1)
