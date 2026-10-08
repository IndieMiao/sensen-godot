extends GdUnitTestSuite
## Show on map (SGODOT-225; LOCK-08): a Today row, a NeedSource or an Energy tile elsewhere leaves for the map with
## after_leave "show:<target>"; on resume the map flies to that pin and selects it, and never enters anything.

const P0_MAP := "res://scenes/p0/p0_map.tscn"

var map: Node

# One map for the suite (it is a heavy scene; each test starts from where the last one left the camera).
func before() -> void:
	map = (load(P0_MAP) as PackedScene).instantiate()
	add_child(map)
	for i in 5: await get_tree().process_frame

func after() -> void:
	_settle_prewarm()
	if is_instance_valid(map): map.free()

## Selecting a pond pin pre-generates its banks on a worker (p0_map._prewarm_pond → WaterShore.prewarm). A task still
## running at the end crashed the headless runner at exit (signal 11) and its detached bank counted as an orphan.
func _settle_prewarm() -> void:
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

func _back_with(target: String) -> void:
	map.call("suspend")   # a world was on top …
	await get_tree().process_frame
	(map.get("rt") as P0Runtime).after_leave = target
	map.call("resume")    # … and left for the map
	for i in 3: await get_tree().process_frame

func _at(lat: float, lng: float) -> void:
	assert_float(map.get("center_lat")).is_equal_approx(lat, 1e-6)
	assert_float(map.get("center_lng")).is_equal_approx(lng, 1e-6)

func test_an_outpost_target_flies_to_its_pin_and_selects_it() -> void:
	await _back_with("show:outpost:tea")
	var tea := P0Outposts.by_role("tea")
	_at(float(tea.lat), float(tea.lng))
	assert_str(str(map.get("city_map").selected.get("id", ""))).is_equal(str(tea.id))
	assert_float(map.get("zoom")).is_equal_approx(map.get("SHOW_ZOOM"), 0.01)
	assert_object(AppRouter.top_instance()).is_null()   # guidance only: nothing opened

func test_a_pond_target_selects_the_pond_pin() -> void:
	await _back_with("show:pond:pond_shanghai_05")
	var pond := SystemPonds.location("pond_shanghai_05")
	_at(float(pond.lat), float(pond.lng))
	assert_str(str(map.get("city_map").selected.get("id", ""))).is_equal("pond_shanghai_05")
	_settle_prewarm()
	await get_tree().process_frame

func test_home_flies_to_the_homestead_without_selecting_or_entering() -> void:
	await _back_with("show:outpost:tackle")   # somewhere else first
	await _back_with("show:home")
	_at(float(map.get("home_lat")), float(map.get("home_lng")))
	assert_object(AppRouter.top_instance()).is_null()

func test_browse_the_map_and_unknown_targets_keep_the_camera() -> void:
	await _back_with("show:outpost:post")
	var lat: float = map.get("center_lat")
	var lng: float = map.get("center_lng")
	await _back_with("show:map")
	_at(lat, lng)
	await _back_with("show:outpost:nowhere")
	_at(lat, lng)

func test_the_tackle_shop_keeps_its_own_entry() -> void:
	await _back_with("tackle")
	var shop := P0Outposts.by_role("tackle")
	_at(float(shop.lat), float(shop.lng))
	assert_str(str(map.get("city_map").selected.get("id", ""))).is_equal(str(shop.id))

## On the map itself (蒙恬 on #44): a panel's Show flies to the pin at once; a homestead target is the homestead.
func test_show_from_a_panel_on_the_map_flies_at_once() -> void:
	assert_str(P0Ui.show_label("pond:pond_shanghai_05", "map", false)).is_equal("Show")
	assert_str(P0Ui.show_label("stove", "map", false)).is_equal("Show")
	assert_str(P0Ui.show_label("map", "map", false)).is_equal("")
	map.call("p0_show_spot", "outpost:post")
	var post := P0Outposts.by_role("post")
	_at(float(post.lat), float(post.lng))
	map.call("p0_show_spot", "stove")
	_at(float(map.get("home_lat")), float(map.get("home_lng")))
	var rt: P0Runtime = map.get("rt")
	rt.attach(map)
	rt.ui.show_on_map.emit("outpost:tea")   # a NeedSource / Energy tile on the map: no trip through after_leave
	var tea := P0Outposts.by_role("tea")
	_at(float(tea.lat), float(tea.lng))
	assert_str(rt.after_leave).is_equal("")
