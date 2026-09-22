extends GdUnitTestSuite
## A modal can live on a different CanvasLayer from the online HUD. Detect its
## actual visibility instead of comparing z_index or stopping online sessions.

func test_hidden_sheet_and_hidden_canvas_do_not_block_world() -> void:
	var host := auto_free(Node.new()) as Node
	add_child(host)
	var layer := CanvasLayer.new()
	host.add_child(layer)
	var sheet := Control.new()
	layer.add_child(sheet)
	GameUi.register_modal(sheet)
	assert_bool(GameUi.modal_is_open(host)).is_true()
	sheet.hide()
	assert_bool(GameUi.modal_is_open(host)).is_false()
	sheet.show()
	layer.hide()
	assert_bool(GameUi.modal_is_open(host)).is_false()
	layer.show()
	assert_bool(GameUi.modal_is_open(host)).is_true()

func test_party_can_exclude_its_own_sheet_but_sees_another_modal() -> void:
	var host := auto_free(Node.new()) as Node
	add_child(host)
	var party := Control.new()
	host.add_child(party)
	GameUi.register_modal(party)
	assert_bool(GameUi.modal_is_open(host, party)).is_false()
	var other := Control.new()
	host.add_child(other)
	GameUi.register_modal(other)
	assert_bool(GameUi.modal_is_open(host, party)).is_true()
	other.queue_free()
	assert_bool(GameUi.modal_is_open(host, party)).is_false()

func test_suspended_scene_and_closed_window_do_not_leave_stale_modal() -> void:
	var host := auto_free(Node3D.new()) as Node3D
	add_child(host)
	var sheet := Control.new()
	host.add_child(sheet)
	GameUi.register_modal(sheet)
	host.process_mode = Node.PROCESS_MODE_DISABLED
	assert_bool(GameUi.modal_is_open(self)).is_false()
	host.process_mode = Node.PROCESS_MODE_INHERIT
	host.hide()
	assert_bool(GameUi.modal_is_open(self)).is_false()
	host.show()
	assert_bool(GameUi.modal_is_open(self)).is_true()
	sheet.hide()
	var popup := Window.new()
	popup.visible = false
	host.add_child(popup)
	GameUi.register_modal(popup)
	assert_bool(GameUi.modal_is_open(self)).is_false()
