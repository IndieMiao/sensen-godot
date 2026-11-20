extends Node
## Temporary (苏烈, not committed): a generated city's outpost room with the given residents, to a PNG.
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")

func _ready() -> void:
	var role := OS.get_environment("ROLE")
	var room: Dictionary = P0Logic.content().get("world", {}).get("room", {}).get(role, {})
	var id := "gn-shot~%s0" % role
	P0CityPlaces.accept("gn-shot", {"detail": {"outposts": [{"id": id, "role": role, "name": "Test Outpost",
		"art": str(room.art), "anchors": str(room.anchors), "category": str(room.category), "lat": 1.0, "lng": 1.0,
		"capacity": 12, "keeper": {"role": "Keeper", "name": "Bea", "look": OS.get_environment("LOOK")},
		"residents": Array(OS.get_environment("RESIDENTS").split(","))}]}})
	var r = load("res://scenes/p0/p0_outpost.tscn").instantiate()
	r.setup({"outpost_id": id})
	r.use_runtime = false
	add_child(r)
	await get_tree().create_timer(6.0).timeout
	print("npcs ", r.npcs.keys())
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	get_tree().quit()
