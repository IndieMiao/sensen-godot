extends GdUnitTestSuite

class PickingStreet extends JourneyStreet:
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass

func _street() -> JourneyStreet:
	var street := auto_free(PickingStreet.new()) as JourneyStreet
	street.ui = Control.new()
	street.add_child(street.ui)
	street.ui.size = get_viewport().get_visible_rect().size
	street.header = VBoxContainer.new()
	street.ui.add_child(street.header)
	street.header.size = Vector2(street.ui.size.x, 100)
	street.dialogue = PanelContainer.new()
	street.ui.add_child(street.dialogue)
	street.dialogue.hide()
	street.cam = Camera3D.new()
	street.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	street.cam.size = 18
	street.add_child(street.cam)
	add_child(street)
	street.cam.position = Vector3(5, 27, 23)
	street.cam.look_at(Vector3.ZERO)
	var button := Button.new()
	street.ui.add_child(button)
	button.hide()
	street.targets = {"resident:nursery": {"button": button, "body": Vector3.ZERO}}
	return street

func test_visible_body_is_selectable_when_its_name_marker_is_hidden() -> void:
	var street := _street()
	var point := street.cam.unproject_position(Vector3.ZERO)
	assert_str(street._pick_target(point)).is_equal("resident:nursery")
	assert_str(street._pick_target(point + Vector2(24, 0))).is_equal("resident:nursery")
	assert_str(street._pick_target(point + Vector2(35, 0))).is_empty()

func test_hidden_offscreen_and_disabled_residents_cannot_capture_ground_taps() -> void:
	var street := _street()
	var point := street.cam.unproject_position(Vector3.ZERO)
	street.targets["resident:nursery"].button.disabled = true
	assert_str(street._pick_target(point)).is_empty()
	street.targets["resident:nursery"].button.disabled = false
	street.targets["resident:nursery"].body = Vector3(1000, 0, 0)
	assert_str(street._pick_target(point)).is_empty()
	street.targets["resident:nursery"].body = street.cam.position + street.cam.basis.z
	assert_str(street._pick_target(street.cam.unproject_position(street.targets["resident:nursery"].body))).is_empty()

func test_dialogue_and_header_do_not_pick_residents_behind_them() -> void:
	var street := _street()
	var point := street.cam.unproject_position(Vector3.ZERO)
	street.dialogue.show()
	assert_str(street._pick_target(point)).is_empty()
	street.dialogue.hide()
	assert_str(street._pick_target(Vector2(30, 30))).is_empty()

func test_closest_body_wins_when_touch_regions_overlap() -> void:
	var street := _street()
	var other := Button.new()
	street.ui.add_child(other)
	other.hide()
	var body := street.cam.basis.x * 0.8
	street.targets["resident:bistro"] = {"button": other, "body": body}
	assert_str(street._pick_target(street.cam.unproject_position(body))).is_equal("resident:bistro")
	assert_str(street._pick_target(street.cam.unproject_position(Vector3.ZERO))).is_equal("resident:nursery")
