extends SceneTree

func _initialize():
	for room in ["poi_hotel_lobby", "poi_service_hall"]:
		var prefix = "res://assets/rooms/" + room + "/"
		var source = "room_albedo_ao.png" if room == "poi_hotel_lobby" else "hall_albedo_ao_n2.png"
		var original = ConfigFile.new()
		assert(original.load(prefix + source + ".import") == OK)
		for name in ["room_albedo_ao_b.png", "sign_b.png"]:
			var config = ConfigFile.new()
			assert(config.load(prefix + name + ".import") == OK)
			for key in original.get_section_keys("params"):
				config.set_value("params", key, original.get_value("params", key))
			assert(config.has_section_key("remap", "uid"))
			assert(config.save(prefix + name + ".import") == OK)
	print("B texture imports inherit their room A settings; unique UIDs retained")
	quit()
