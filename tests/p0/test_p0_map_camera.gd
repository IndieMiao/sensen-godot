extends GdUnitTestSuite
## int5 hand test 31: back from an outpost or a pond, the P0 map stays where it was. map_poc.resume() rebuilds the
## region (and flies the camera home to the homestead) whenever _nearby_region differs from the shown region, and P0
## has no nearby list, so _refresh_nearby must still mark the region as set up.

const P0_MAP := "res://scenes/p0/p0_map.tscn"

func test_resume_keeps_the_camera_where_the_player_left_it() -> void:
	var map: Node = auto_free((load(P0_MAP) as PackedScene).instantiate())
	add_child(map)
	for i in 5: await get_tree().process_frame
	assert_str(map.get("_nearby_region")).is_equal(str(map.get("region").get("id", "")))
	var shop := P0Outposts.place_entry(P0Outposts.by_role("tackle"))
	map.call("_city_bounds")   # city-wide pan bounds, as when the player picks a far pin
	map.call("fly_to", float(shop.lat), float(shop.lng))
	var lat: float = map.get("center_lat")
	var lng: float = map.get("center_lng")
	map.call("suspend")   # an outpost or a pond pushed on top …
	await get_tree().process_frame
	map.call("resume")    # … and closed again
	for i in 3: await get_tree().process_frame
	assert_float(map.get("center_lat")).is_equal_approx(lat, 1e-6)
	assert_float(map.get("center_lng")).is_equal_approx(lng, 1e-6)

## The P0Runtime singleton the map brought up goes with the suite (P0Runtime.free_instance_for_tests).
func after() -> void:
	P0Runtime.free_instance_for_tests()
