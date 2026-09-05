extends Node
## Real controls -> shared FarmSession -> loopback HTTP -> dedicated PostgreSQL QA database.
## Only QA clock commands accelerate days; chapters are never assigned by this driver.

var farm: Node
var place: Node
var session: FarmSession
var route := "tool"
var style := "life"
var _base := "http://127.0.0.1:3103/v1"
var _output := "res://output/g3-week/ui-tool-life"
var _cell_map := {}
var _errors: Array = []
var _wire: Array = []
var _steps: Array = []
var _chapters: Array = []
var _backups := {}
var _started := 0
var _finishing := false
var _photo_path := ""
var _event_scenes: Array[String] = []

func _enter_tree() -> void:
	Net.booting = true
	Net.booted_once = true

func _ready() -> void:
	_started = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--week-path="): route = arg.trim_prefix("--week-path=")
		if arg.begins_with("--week-style="): style = arg.trim_prefix("--week-style=")
		if arg.begins_with("--week-base="): _base = arg.trim_prefix("--week-base=")
		if arg.begins_with("--week-out="): _output = arg.trim_prefix("--week-out=")
	_output = ProjectSettings.globalize_path(_output)
	DirAccess.make_dir_recursive_absolute(_output)
	for path in [FarmChoice.PATH, ApiClient.INSTALL_KEY_PATH]:
		_backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	get_tree().create_timer(1200, true, false, true).timeout.connect(func():
		_check(false, "Seven-day UI run exceeded 20 minutes")
		_finish())
	call_deferred("_run")

func _transport() -> Callable:
	var http := ApiClient.make_http_transport(self)
	var install := Crypto.new().generate_random_bytes(16).hex_encode()
	return func(method: String, url: String, headers: PackedStringArray, body_text: String) -> ApiClient.Response:
		var body: Dictionary = JSON.parse_string(body_text) if not body_text.is_empty() else {}
		if url.ends_with("/auth/anonymous"):
			body.install_key = install
			body_text = JSON.stringify(body)
		var response: ApiClient.Response = await http.call(method, url, headers, body_text)
		if url.ends_with("/commands"):
			_wire.append({"type": body.get("type"), "payload": body.get("payload"), "status": response.status, "code": response.json.get("code", ""), "version": response.json.get("version", -1)})
			if not response.is_success(): _check(false, "HTTP %s: %s" % [str(body.get("type")), response.json.get("code", response.error)])
		return response

func _run() -> void:
	Net.use_transport(_transport(), _base)
	Net.booting = true
	session = Net.session
	if not _check(await session.login(), "Anonymous QA login"): return _finish()
	if not _check(await session.ensure_farm("shanghai", "sh_a", 2), "Create QA farm"): return _finish()
	print("WEEK_UI_FARM ", session.farm_id)
	var ledger: ApiClient.Response = await session.client.request("GET", "/qa/ledger?path=%s&style=%s" % [route, style])
	if not _check(ledger.is_success(), "Load canonical command ledger"): return _finish()
	farm = AppRouter.push_instance(AppRouter.FARM, {"session": session})
	await _frames(4)
	var local_cells := []
	for bed in farm.bp.beds(): local_cells.append_array(bed.cells)
	local_cells.append_array(farm.bp.reserved_bed().cells)
	var logical: Array = ledger.json.beds + ledger.json.reserved
	for index in logical.size(): _cell_map[str(logical[index])] = local_cells[index]
	Engine.time_scale = 6.0
	await _director("qa_set_clock", {"scale": 60})
	await _capture("d0-start")
	var day := 0
	for step in ledger.json.steps:
		if _finishing or not _errors.is_empty(): break
		if int(step.day) != day:
			if not _check(str(session.state.chapters[day].status) == "done", "D%d completed by real facts" % day): break
			await _day_capture(day)
			await _director("qa_skip_days", {"days": 1})
			day = int(step.day)
			if not _check(int(session.state.clock.chapter_index) == day, "Chapter D%d opened" % day): break
		var started := Time.get_ticks_msec()
		await _step(step.cmd)
		if str(step.cmd.type) in ["cook_dish", "submit_request", "attend_shared_event", "choose_nursery_appearance", "purchase_growth_choice"]:
			await _capture("d%d-%s" % [day, step.cmd.type])
		_steps.append({"day": day, "type": step.cmd.type, "ms": Time.get_ticks_msec() - started, "version": session.version})
		print("WEEK_UI_STEP ", JSON.stringify(_steps.back()))
	if _errors.is_empty():
		await _day_capture(6)
		var expected := 305 if route == "tool" else 145
		if style == "sell": expected = 376 if route == "tool" else 200
		_check(int(session.state.wallet) == expected, "Final wallet %d (actual %d)" % [expected, session.state.wallet])
		_check(int(session.state.xp.total) == 301, "Final XP 301")
		_check(session.state.get("week_summary") is Dictionary, "Authoritative week summary")
		if session.state.get("week_summary") is Dictionary:
			_check(bool(session.state.week_summary.life_priority) == (style == "life"), "Correct ending branch")
		await _content_checks()
		await _open_place("courtyard", "events")
		await _capture("ending")
		var photo_button := place.active_panel.find_child("TakePhoto", true, false) as Button
		if not _check(photo_button != null, "Group photo entry exists"): return _finish()
		await _press_button(photo_button)
		await _frames(90)
		await _capture("group-photo")
		if not _check(place.photo != null, "Group photo scene opened"): return _finish()
		place.photo.saved.connect(func(path): _photo_path = path)
		await _press(place.photo, "SavePhoto")
		if _check(not _photo_path.is_empty() and FileAccess.file_exists(_photo_path), "Save real group photo"):
			var picture := Image.load_from_file(_photo_path)
			_check(picture != null and picture.get_width() >= 32 and picture.get_width() == picture.get_height(), "Saved photo is square")
		_check(_event_scenes.size() == 5, "All five event scenes read")
		_check(await session.refresh(), "Reconnect owner state")
	_finish()

func _content_checks() -> void:
	await _open_place("nursery", "project")
	await _press(place.active_panel, "Appearance_b")
	_check(str(session.state.nursery.appearance) == "b", "Painted nursery gate saved")
	await _capture("nursery-painted-gate")
	await _press(place.active_panel, "Appearance_a")
	await _capture("nursery-garden-arch")
	await _open_place("courtyard", "decorations")
	for index in DecorationLayout.IDS.size():
		var picker := place.active_panel.find_child("DecorationPicker", true, false) as OptionButton
		picker.item_selected.emit(index)
		await _frames(3)
		await _press(place.active_panel, "PlaceDecoration")
	_check(place.active_panel.preview().size() == 6, "All six courtyard pieces previewed")
	await _press(place.active_panel, "UndoDecoration")
	_check(place.active_panel.preview().size() == 5, "Undo restores previous preview")
	await _press(place.active_panel, "PlaceDecoration")
	await _press(place.active_panel, "SaveDecorations")
	_check(DecorationLayout.saved(session.state).size() == 6, "All six pieces saved through HTTP")
	await _capture("courtyard-six-pieces")
	await _return_farm()
	await session.refresh()
	await _open_place("courtyard", "decorations")
	_check(place.active_panel.preview().size() == 6, "Saved courtyard restored after scene reentry")
	await _press(place.active_panel, "RemoveDecoration")
	await _press_button(place._tab_buttons.journal)
	await _press(place.active_panel, "DiscardDecorationChanges")
	_check(place.selected_tab == "journal" and DecorationLayout.saved(session.state).size() == 6, "Discard before navigation preserves saved layout")
	await _capture("week-journal")
	var events: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/events.json")).events
	for event in events:
		if int(event.chapter) == 5: continue
		await _read_event(event)

func _read_event(event: Dictionary) -> void:
	await _open_place(str(event.place), "events")
	if place.active_panel.find_child("AllEvents", true, false):
		await _press(place.active_panel, "AllEvents")
	await _press(place.active_panel, "Event_" + str(event.id))
	await _press(place.active_panel, "ReadScene")
	await _capture("story-" + str(event.id))
	for page in 8:
		if place.active_panel.find_child("FinishEventScene", true, false):
			await _press(place.active_panel, "FinishEventScene")
			_event_scenes.append(str(event.id))
			return
		await _press(place.active_panel, "ContinueEvent")
	_check(false, "Event scene did not finish: " + str(event.id))

func _step(command: Dictionary) -> void:
	var type := str(command.type)
	if command.has("cell_ids"):
		await _return_farm()
		if type == "sow_cells":
			var seed: Button = farm.hud._seed_buttons.get(str(command.crop))
			if seed: await _press_button(seed)
			else: _check(false, "Seed picker missing: " + str(command.crop))
		for id in command.cell_ids:
			var local: Vector2i = _cell_map[str(id)]
			var local_id := "%d,%d" % [local.x, local.y]
			if type == "harvest_cells" and NextStep.step_for(farm._cells_view().get(local_id, {}), session.server_now()).is_empty():
				for attempt in 15:
					await get_tree().create_timer(1, true, false, true).timeout
					await session.refresh()
					if not NextStep.step_for(farm._cells_view().get(local_id, {}), session.server_now()).is_empty(): break
			var action := str(NextStep.COMMAND.get(NextStep.step_for(farm._cells_view().get(local_id, {}), session.server_now()), ""))
			if action != type:
				if type in ["apply_care", "harvest_cells", "till_cells"]: continue
				_check(false, "Plot action mismatch %s / %s" % [action, type])
				return
			farm._tap_cell(local)
			await _idle()
		if type == "harvest_cells" and int(session.state.clock.chapter_index) == 0:
			await _director("qa_set_clock", {"scale": 1})
		return
	match type:
		"buy_seeds":
			await _return_farm()
			farm.hud.stall_pressed.emit()
			await _frames(3)
			while farm.stall._buy_qty != int(command.qty):
				await _press_button(farm.stall._quantity_plus if farm.stall._buy_qty < int(command.qty) else farm.stall._quantity_minus)
			await _press_button(farm.stall._seed_rows[str(command.crop)].button)
		"sell_at_stall":
			await _return_farm()
			farm.hud.stall_pressed.emit()
			await _frames(3)
			for item in command.items:
				for count in int(item.qty):
					var row: Dictionary = farm.stall._produce_rows[str(item.id)] if item.kind == "produce" else farm.stall._dish_rows[str(item.id)]
					if row.button.disabled: break
					await _press_button(row.button)
		"talk_to_resident", "give_gift", "submit_request":
			if type == "submit_request" and command.request_id == "d0_tutorial_buyback":
				await _economy("supplies", "TutorialBuyback")
				return
			var resident := str(command.get("resident_id", ""))
			if type == "submit_request":
				var requests: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/requests.json")).requests
				resident = str(requests[command.request_id].resident)
			await _open_place(str(ResidentCast.definition(resident).place), "people")
			if place.active_panel.selected_resident != resident:
				await _press(place.active_panel, "Select_" + resident)
			if type == "talk_to_resident": await _press(place.active_panel, "Talk")
			elif type == "give_gift":
				await _press(place.active_panel, "Gifts")
				await _press(place.active_panel, "Give_" + str(command.crop))
			else:
				await _press(place.active_panel, "Request_" + str(command.request_id))
				await _press(place.active_panel, "Deliver")
			await _dialogue()
		"cook_dish":
			await _open_place("bistro", "kitchen")
			await _press(place.active_panel, "Cook_" + str(command.recipe))
		"attend_shared_event":
			if command.event_id == "cooking_together":
				await _open_place("bistro", "kitchen")
				await _press(place.active_panel, "SharedCooking")
				await _press(place.active_panel, "ContinueShared")
				await _press(place.active_panel, "ContinueShared")
				await _press(place.active_panel, "CompleteShared")
			else:
				await _open_place("courtyard", "events")
				await _press(place.active_panel, "StartGathering")
				for page in 8:
					if place.active_panel.find_child("CompleteGathering", true, false):
						await _press(place.active_panel, "CompleteGathering")
						break
					await _press(place.active_panel, "ContinueEvent")
		"resolve_life_choice":
			await _economy("choices", {"gift": "ChoiceGift", "keep": "ChoiceKeep", "sold": "ChoiceSell"}[str(command.choice)])
		"claim_subsidy": await _economy("supplies", "Subsidy_" + str(command.subsidy_id))
		"sell_to_buyback_box": await _economy("supplies", "TeaBuyback")
		"reserve_engineering":
			await _open_place("nursery", "project")
			for crop in command.items:
				for count in int(command.items[crop]): await _press(place.active_panel, "Reserve_" + str(crop))
		"submit_engineering":
			await _open_place("nursery", "project")
			await _press(place.active_panel, "SubmitAll")
		"choose_nursery_appearance":
			await _open_place("nursery", "project")
			await _press(place.active_panel, "Appearance_" + str(command.appearance))
		"set_growth_intent": await _economy("growth", "Growth_" + str(command.choice))
		"purchase_growth_choice": await _economy("growth", "Purchase_" + str(command.choice))
		"record_visit_return":
			await _return_farm()
			var entry: Dictionary = PresetSnapshots.entries("shanghai")[0]
			var result: Dictionary = await Net.snapshot(str(entry.farm_id))
			if not _check(bool(result.ok), "Read real visitor snapshot"): return
			var snap: Dictionary = result.snapshot
			var visitor := AppRouter.push_instance(AppRouter.FARM, {"visitor": true, "snapshot": snap,
				"layout_patch_id": snap.layout_patch_id, "revision": snap.blueprint_revision})
			await _frames(40)
			await _capture("d4-visit")
			visitor.exit_btn.pressed.emit()
			await _idle()
		_: _check(false, "Unhandled UI command " + type)

func _economy(section: String, button: String) -> void:
	await _return_farm()
	farm.hud.life_pressed.emit()
	await _frames(3)
	farm.life_sheet._tabs[section].pressed.emit()
	await _frames(3)
	await _press(farm.life_sheet.active, button)

func _open_place(id: String, tab: String) -> void:
	await _return_farm()
	place = AppRouter.push_instance(AppRouter.PLACE, {"place_id": id, "session": session})
	await _frames(3)
	var button: Button = place._tab_buttons.get(tab)
	if not _check(button != null, "Place tab " + tab): return
	await _press_button(button)

func _return_farm() -> void:
	if is_instance_valid(place):
		AppRouter.pop_instance()
		place = null
		await _frames(3)
	farm.hud.close_modal()
	await _frames(2)

func _director(type: String, payload: Dictionary) -> void:
	await _return_farm()
	farm.hud.show_modal(farm.director)
	farm.director._send(type, payload)
	await _idle()
	farm.hud.close_modal()

func _dialogue() -> void:
	for page in 10:
		if not _errors.is_empty(): return
		if place.active_panel.find_child("FinishDialogue", true, false):
			await _press(place.active_panel, "FinishDialogue")
			return
		await _press(place.active_panel, "Continue")

func _press(parent: Node, id: String) -> void:
	await _frames(2)
	var button := parent.find_child(id, true, false) as Button
	if not _check(button != null, "Control " + id): return
	await _press_button(button)

func _press_button(button: Button) -> void:
	if not _check(not button.disabled, "Enabled control " + str(button.name)): return
	var parent := button.get_parent()
	while parent:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			break
		parent = parent.get_parent()
	button.pressed.emit()
	await _idle()

func _idle() -> void:
	await _frames(3)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 90000:
		var busy: bool = farm.runner.is_busy() or farm._in_flight > 0 or session._serving != session._next_ticket
		busy = busy or (is_instance_valid(place) and place.active_panel != null and place.active_panel.busy)
		busy = busy or (farm.stall != null and farm.stall.is_busy()) or (farm.life_sheet != null and farm.life_sheet.is_busy())
		if not busy: break
		await get_tree().process_frame
	await _frames(3)

func _frames(count: int) -> void:
	for index in count: await get_tree().process_frame

func _day_capture(day: int) -> void:
	if day == 5:
		var events: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/events.json")).events
		for event in events:
			if int(event.chapter) == 5: await _read_event(event)
	await _return_farm()
	_check(str(session.state.chapters[day].status) == "done", "D%d authoritative completion" % day)
	_chapters.append({"day": day, "wallet": session.state.wallet, "xp": session.state.xp.total,
		"engineering": session.state.engineering.duplicate(true), "chapter": session.state.chapters[day].duplicate(true)})
	await _capture("d%d-complete" % day)

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + ".png"))

func _check(value: bool, message: String) -> bool:
	print(("PASS " if value else "FAIL ") + message)
	if not value: _errors.append(message)
	return value

func _restore() -> void:
	for path in _backups:
		if _backups[path] == null:
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file: file.store_buffer(_backups[path])
	_backups.clear()

func _finish() -> void:
	if _finishing: return
	_finishing = true
	Engine.time_scale = 1
	_restore()
	var file := FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"passed": _errors.is_empty(), "path": route, "style": style,
		"state_source": "HTTP_PostgreSQL", "interaction": "real_controls_and_plot_callbacks", "physical_device": false,
		"platform": OS.get_name(), "photo_path": _photo_path, "event_scenes": _event_scenes,
		"elapsed_seconds": (Time.get_ticks_msec() - _started) / 1000.0, "farm_id": session.farm_id if session else "",
		"chapters": _chapters, "steps": _steps, "commands": _wire, "state": session.state if session else {}, "errors": _errors}, "\t"))
	print("WEEK_UI_RESULT ", JSON.stringify({"passed": _errors.is_empty(), "errors": _errors, "output": _output}))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _exit_tree() -> void:
	_restore()
