extends GdUnitTestSuite

class ParcelPlugin extends Node:
	signal map_ready
	signal location_update(lat: float, lng: float, accuracy: float)
	signal parcel_ready(generation: int, style_generation: int, payload: String)
	signal parcel_query_result(request_id: int, generation: int, style_generation: int, payload: String)
	signal parcel_error(generation: int, style_generation: int, code: String)
	var calls: Array = []
	var lifecycle_epoch: int = 0
	func getParcelLifecycleEpoch() -> int: return lifecycle_epoch
	func pause_and_resume() -> void: lifecycle_epoch += 1
	func setParcelSources(g: int, config: String) -> void: calls.append(["sources", g, config])
	func queryParcelAt(r: int, g: int, x: float, y: float) -> void: calls.append(["query", r, g, x, y])
	func setParcelStates(g: int, batch: String) -> void: calls.append(["states", g, batch])
	func setParcelClaims(g: int, claims: String) -> void: calls.append(["claims", g, claims])
	func setParcelBuildingHighlight(g: int, key: String, parcel: String) -> void: calls.append(["highlight", g, key, parcel])
	func clearParcelLayers(g: int) -> void: calls.append(["clear", g])
	func setMapVisible(visible: bool) -> void: calls.append(["visible", visible])

var plugin: ParcelPlugin
var bridge: MapBridgeAndroid
var received: Array
var errors: Array

func before_test() -> void:
	plugin = ParcelPlugin.new()
	Engine.register_singleton("GodotMap", plugin)
	bridge = MapBridgeAndroid.new()
	received = []
	errors = []
	bridge.parcel_query_result.connect(func(r, g, s, body): received.append([r, g, s, body]))
	bridge.parcel_error.connect(func(g, s, code): errors.append([g, s, code]))

func after_test() -> void:
	Engine.unregister_singleton("GodotMap")
	if is_instance_valid(plugin): plugin.free()
	bridge = null

func test_queued_result_cannot_reenter_departed_map_scene() -> void:
	bridge.set_parcel_sources(10, "config")
	bridge.query_parcel_at(1, 10, Vector2(0.25, 0.75))
	plugin.parcel_query_result.emit(1, 10, 1, "old-building")
	bridge.set_map_visible(false)
	await get_tree().process_frame
	assert_that(received).is_empty()
	assert_that(plugin.calls.slice(-2)).is_equal([["clear", 10], ["visible", false]])

func test_reentry_requires_new_generation_and_rejects_old_ready_and_query() -> void:
	bridge.set_parcel_sources(10, "old")
	bridge.query_parcel_at(1, 10, Vector2.ZERO)
	plugin.parcel_query_result.emit(1, 10, 9, "old")
	bridge.clear_parcel_layers(10)
	bridge.set_parcel_sources(11, "new")
	bridge.query_parcel_at(1, 11, Vector2.ONE)
	plugin.parcel_ready.emit(10, 99, "old-ready")
	plugin.parcel_query_result.emit(1, 11, 1, "new")
	await get_tree().process_frame
	assert_that(received).is_equal([[1, 11, 1, "new"]])

func test_style_reload_and_newer_tap_reject_delayed_results() -> void:
	bridge.set_parcel_sources(10, "config")
	bridge.query_parcel_at(1, 10, Vector2.ZERO)
	plugin.parcel_ready.emit(10, 2, "reload")
	plugin.parcel_query_result.emit(1, 10, 1, "old-style")
	await get_tree().process_frame
	assert_that(received).is_empty()
	bridge.query_parcel_at(2, 10, Vector2.ONE)
	plugin.parcel_query_result.emit(1, 10, 2, "old-tap")
	plugin.parcel_query_result.emit(2, 10, 2, "current")
	await get_tree().process_frame
	assert_that(received).is_equal([[2, 10, 2, "current"]])

func test_coordinates_and_opaque_key_forward_without_density_or_geometry() -> void:
	assert_bool(bridge.supports_parcels()).is_true()
	bridge.set_parcel_sources(10, "config")
	bridge.query_parcel_at(1, 10, Vector2(0.125, 0.875))
	bridge.set_parcel_building_highlight(10, "opaque-1", "p-1")
	bridge.set_parcel_states(10, "[]")
	bridge.set_parcel_claims(10, "[]")
	assert_that(plugin.calls).is_equal([["sources", 10, "config"], ["query", 1, 10, 0.125, 0.875],
		["highlight", 10, "opaque-1", "p-1"], ["states", 10, "[]"], ["claims", 10, "[]"]])

func test_old_owner_cannot_clear_or_update_new_dataset() -> void:
	bridge.set_parcel_sources(10, "old")
	bridge.set_parcel_sources(11, "new")
	var count := plugin.calls.size()
	bridge.clear_parcel_layers(10)
	bridge.set_parcel_states(10, "stale")
	bridge.set_parcel_claims(10, "stale")
	bridge.set_parcel_building_highlight(10, "stale")
	assert_int(plugin.calls.size()).is_equal(count)
	bridge.query_parcel_at(1, 11, Vector2.ZERO)
	plugin.parcel_query_result.emit(1, 11, 1, "current")
	await get_tree().process_frame
	assert_that(received).is_equal([[1, 11, 1, "current"]])

func test_repeated_ids_are_rejected_without_calling_native_again() -> void:
	bridge.set_parcel_sources(10, "config")
	bridge.query_parcel_at(1, 10, Vector2.ZERO)
	var count := plugin.calls.size()
	bridge.set_parcel_sources(10, "replacement")
	bridge.query_parcel_at(1, 10, Vector2.ONE)
	assert_int(plugin.calls.size()).is_equal(count)
	assert_that(errors).is_equal([[10, 0, "invalid_generation"], [10, 0, "invalid_request_id"]])

func test_missing_or_disposed_plugin_is_explicitly_unsupported() -> void:
	Engine.unregister_singleton("GodotMap")
	plugin.free()
	assert_bool(bridge.supports_parcels()).is_false()
	bridge.query_parcel_at(1, 10, Vector2.ZERO)
	assert_int(received.size()).is_equal(1)
	assert_str(received[0][3]).contains('"error":"unsupported"')
	# Re-register a placeholder solely to preserve uniform teardown.
	plugin = ParcelPlugin.new()
	Engine.register_singleton("GodotMap", plugin)

func test_base_capability_and_process_generation_allocator() -> void:
	var base := MapBridge.new()
	assert_bool(base.supports_parcels()).is_false()
	var first := MapBridge.next_parcel_generation()
	assert_int(MapBridge.next_parcel_generation()).is_greater(first)


func test_already_emitted_result_dies_across_pause_resume_but_new_query_works() -> void:
	bridge.set_parcel_sources(10, "config")
	bridge.query_parcel_at(1, 10, Vector2.ZERO)
	# Callback completed natively; its payload is now queued for deferred Godot delivery.
	plugin.parcel_query_result.emit(1, 10, 1, "retired-building-key")
	# Deliberately do NOT clear sources/scene/request IDs or enqueue an invalidation signal.
	plugin.pause_and_resume()
	await get_tree().process_frame
	assert_that(received).is_empty()
	bridge.query_parcel_at(2, 10, Vector2.ONE)
	plugin.parcel_query_result.emit(2, 10, 1, "new-building-key")
	await get_tree().process_frame
	assert_that(received).is_equal([[2, 10, 1, "new-building-key"]])
