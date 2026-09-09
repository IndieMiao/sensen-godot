extends Node
## Real controls -> shared FarmSession -> loopback HTTP -> dedicated PostgreSQL QA database.
## Only QA clock commands accelerate days; chapters are never assigned by this driver.

const RESUME_RUN := "g3_vivo_tool_life_03"
const RESUME_REPORT := "user://g3-vivo-tool-life-03/report.json"
const RESUME_BACK_RUN := "g3_vivo_tool_life_04"
const RESUME_BACK_REPORT := "user://g3-vivo-tool-life-04/report.json"

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
var _touch := false
var _touch_run := ""
var _touch_id := 0
var _touch_actions: Array = []
var _bypasses: Array = []
var _map: Node
var _received_touches: Array = []
var _qa_install_key := ""
var _decoration_world_evidence := {"revision": 1, "attempted": false, "passed": false}
var _resume_run := ""
var _resume_report: Dictionary = {}
var _resume_prefix: Array = []
var _resume_step := 0
var _resume_validated := false
var _resume_evidence: Dictionary = {}
var _ledger_index := -1
var _place_back_transitions: Array = []
var _popup_geometry_evidence: Array = []

func _input(event: InputEvent) -> void:
	if _touch: _record_touch(event, get_viewport())

func _record_touch(event: InputEvent, viewport: Viewport) -> void:
	if event is InputEventScreenTouch and event.pressed:
		var screen: Vector2 = viewport.get_screen_transform() * event.position
		_received_touches.append({"ticks_ms": Time.get_ticks_msec(), "screen": [screen.x, screen.y], "viewport": str(viewport.get_path())})

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
		if arg.begins_with("--week-touch="): _touch = arg.trim_prefix("--week-touch=") == "true"
		if arg.begins_with("--week-run="): _touch_run = arg.trim_prefix("--week-run=")
		if arg.begins_with("--week-resume="): _resume_run = arg.trim_prefix("--week-resume=")
	if _touch_run.is_empty(): _touch_run = "week_" + Crypto.new().generate_random_bytes(8).hex_encode()
	_output = ProjectSettings.globalize_path(_output)
	DirAccess.make_dir_recursive_absolute(_output)
	for path in [FarmChoice.PATH, ApiClient.INSTALL_KEY_PATH, FarmRegions.CHOICE_PATH, UiState.PATH]:
		_backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	get_tree().create_timer(3600 if _touch else 1200, true, false, true).timeout.connect(func():
		_check(false, "Seven-day UI run exceeded its deadline")
		_finish())
	call_deferred("_run")

func _transport() -> Callable:
	var http := ApiClient.make_http_transport(self)
	var install := _qa_install_key if _touch else Crypto.new().generate_random_bytes(16).hex_encode()
	return func(method: String, url: String, headers: PackedStringArray, body_text: String) -> ApiClient.Response:
		if not _resume_run.is_empty() and not _resume_validated and url.ends_with("/commands"):
			_check(false, "Resume refused a command before account and checkpoint validation")
			return ApiClient.Response.new(false, 0, {}, "Resume checkpoint is not validated")
		var body: Dictionary = JSON.parse_string(body_text) if not body_text.is_empty() else {}
		if url.ends_with("/auth/anonymous"):
			body.install_key = install
			body_text = JSON.stringify(body)
		var response: ApiClient.Response = await http.call(method, url, headers, body_text)
		if url.ends_with("/commands"):
			_wire.append({"type": body.get("type"), "payload": body.get("payload"), "status": response.status, "code": response.json.get("code", ""), "version": response.json.get("version", -1)})
			if not response.is_success(): _check(false, "HTTP %s: %s" % [str(body.get("type")), response.json.get("code", response.error)])
		return response

func _prepare_touch_identity() -> bool:
	if not _check(OS.get_name() == "Android" and OS.is_debug_build() and OS.has_feature("g3_device_qa"), "Touch account storage requires the Android QA export"): return false
	var identifier := RegEx.new()
	identifier.compile("^[A-Za-z0-9_-]{1,96}$")
	if not _check(identifier.search(_touch_run) != null, "Touch run ID is a safe private filename"): return false
	var directory := "user://g3_qa_accounts"
	var path := directory.path_join(_touch_run + ".txt")
	if not _check(not FileAccess.file_exists(path), "QA run account is new; reused run IDs are refused"): return false
	if not _check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK, "Prepare private QA account storage"): return false
	if _resume_run.is_empty():
		_qa_install_key = Crypto.new().generate_random_bytes(16).hex_encode()
	else:
		var previous_key := directory.path_join(_resume_run + ".txt")
		if not _check(FileAccess.file_exists(previous_key), "Resume account identity exists"): return false
		_qa_install_key = FileAccess.get_file_as_string(previous_key).strip_edges()
		identifier.compile("^[a-f0-9]{32}$")
		if not _check(identifier.search(_qa_install_key) != null, "Resume account identity is valid"): return false
	for target in [path, ApiClient.INSTALL_KEY_PATH]:
		var file := FileAccess.open(target, FileAccess.WRITE)
		if not _check(file != null, "Write private QA account identity"): return false
		file.store_string(_qa_install_key)
		file.close()
		if not _check(FileAccess.get_file_as_string(target) == _qa_install_key, "Verify private QA account identity"): return false
	return true

func _load_resume_report() -> bool:
	for path in [RESUME_REPORT, RESUME_BACK_REPORT]:
		if _output.simplify_path().trim_suffix("/") == ProjectSettings.globalize_path(str(path).get_base_dir()).simplify_path().trim_suffix("/"):
			_output = ProjectSettings.globalize_path("user://g3-resume-refused")
			DirAccess.make_dir_recursive_absolute(_output)
			return _check(false, "Resume preserves both parent report directories")
	if not _check(_touch and _resume_run in [RESUME_RUN, RESUME_BACK_RUN] and route == "tool" and style == "life"
		and _touch_run not in [RESUME_RUN, RESUME_BACK_RUN] and _base == "http://127.0.0.1:3103/v1", "Resume is restricted to the known tool/life QA failures"): return false
	if not _check(FileAccess.file_exists(RESUME_REPORT), "Parent device report exists"): return false
	var source := FileAccess.get_file_as_string(RESUME_REPORT)
	var parsed = JSON.parse_string(source)
	if not _check(parsed is Dictionary, "Parent report is an object"): return false
	_resume_report = parsed
	if not _check(_resume_report.get("passed") == false and _resume_report.get("touch_run_id") == RESUME_RUN
		and _resume_report.get("path") == route and _resume_report.get("style") == style
		and _resume_report.get("errors") == ["Plot ray command targets the source cell"]
		and _resume_report.get("platform") == "Android" and _resume_report.get("state_source") == "HTTP_PostgreSQL",
		"Parent failed only the known row-tool assertion"): return false
	if not _check(_resume_report.get("steps") is Array and _resume_report.steps.size() == 96
		and _resume_report.get("commands") is Array and _resume_report.commands.size() >= 3
		and _resume_report.get("state") is Dictionary and _resume_report.get("touch_actions") is Array
		and not _resume_report.touch_actions.is_empty(), "Parent contains the known 96-step checkpoint"): return false
	var last_touch: Dictionary = _resume_report.touch_actions.back()
	if not _check(last_touch.get("checkpoint", {}).get("id") == 623
		and last_touch.get("checkpoint", {}).get("label") == "plot:4,8:apply_care"
		and last_touch.get("ack", {}).get("ok") == true and last_touch.get("touch_observation", {}).get("matched") == true,
		"Parent's last row-tool touch reached Android and Godot"): return false
	var row := ["26,42", "27,42", "28,42"]
	var tail: Array = _resume_report.commands.slice(-3)
	for index in 3:
		var applied: Dictionary = tail[index]
		if not _check(applied.get("type") == "apply_care" and applied.get("status") == 200
			and int(applied.get("version", -1)) == 270 + index
			and applied.get("payload") == {"cell_ids": [row[index]], "kind": "shelter"},
			"Parent row-tool command %d applied exactly once" % index): return false
	_resume_step = _resume_report.steps.size()
	_resume_prefix = _resume_report.steps.duplicate(true)
	_resume_evidence = {"parent_report": RESUME_REPORT, "parent_report_sha256": source.sha256_text(),
		"parent_completed_steps": _resume_step, "parent_last_version": 272, "parent_applied_cells": row,
		"inherited_chapters": _resume_report.get("chapters", []).duplicate(true), "skipped_care_cells": [],
		"chain": [{"run_id": RESUME_RUN, "report": RESUME_REPORT, "sha256": source.sha256_text(),
			"passed": false, "segment_steps": 96, "completed_prefix": 96, "last_version": 272}]}
	return _load_resume_back_report() if _resume_run == RESUME_BACK_RUN else true

func _load_resume_back_report() -> bool:
	if not _check(FileAccess.file_exists(RESUME_BACK_REPORT), "Second parent device report exists"): return false
	var source := FileAccess.get_file_as_string(RESUME_BACK_REPORT)
	var parsed = JSON.parse_string(source)
	if not _check(parsed is Dictionary, "Second parent report is an object"): return false
	var report: Dictionary = parsed
	if not _check(report.get("passed") == false and report.get("touch_run_id") == RESUME_BACK_RUN
		and report.get("path") == route and report.get("style") == style and report.get("platform") == "Android"
		and report.get("state_source") == "HTTP_PostgreSQL" and report.get("errors") == ["Touch return restores map"]
		and report.get("resumed_from") == RESUME_RUN and report.get("continuous_seven_day_run") == false
		and report.get("farm_id") == _resume_report.get("farm_id"), "Second parent is the known navigation failure on the same farm"): return false
	var inherited: Dictionary = report.get("resume", {})
	if not _check(inherited.get("validated") == true and inherited.get("parent_report") == RESUME_REPORT
		and inherited.get("parent_report_sha256") == _resume_evidence.parent_report_sha256
		and int(inherited.get("parent_completed_steps", -1)) == 96, "Both parent reports form the original verified chain"): return false
	if not _check(report.get("steps") is Array and report.steps.size() == 1 and report.get("commands") is Array
		and report.commands.size() == 6 and report.get("touch_actions") is Array and report.touch_actions.size() == 14
		and report.get("state") is Dictionary and report.get("event_scenes") == ["wind_and_opening"], "Second parent contains one completed shelter step and the wind story"): return false
	var done: Dictionary = report.steps[0]
	if not _check(int(done.get("ledger_index", -1)) == 96 and int(done.get("day", -1)) == 5
		and done.get("type") == "apply_care" and int(done.get("version", -1)) == 278, "Second parent completed ledger step 96"): return false
	var last_touch: Dictionary = report.touch_actions.back()
	if not _check(int(last_touch.get("checkpoint", {}).get("id", -1)) == 14
		and str(last_touch.get("checkpoint", {}).get("label", "")).begins_with("control:/root/Place/")
		and last_touch.get("ack", {}).get("ok") == true and last_touch.get("touch_observation", {}).get("matched") == true,
		"Second parent's back touch reached Godot"): return false
	var cells := ["25,40", "26,40", "27,40", "30,43", "31,43", "32,43"]
	for index in cells.size():
		var applied: Dictionary = report.commands[index]
		if not _check(applied.get("type") == "apply_care" and applied.get("status") == 200
			and int(applied.get("version", -1)) == 273 + index
			and applied.get("payload") == {"cell_ids": [cells[index]], "kind": "shelter"},
			"Second parent applied remaining shelter command %d" % index): return false
	var cared := 0
	for cell in report.state.get("cells", {}).values():
		if cell.get("care_done_at") != null: cared += 1
	if not _check(cared == 9, "Second parent has all nine plots cared for"): return false
	_resume_report = report
	_resume_prefix.append_array(report.steps)
	_resume_step = _resume_prefix.size()
	_resume_evidence.parent_report = RESUME_BACK_REPORT
	_resume_evidence.parent_report_sha256 = source.sha256_text()
	_resume_evidence.parent_completed_steps = _resume_step
	_resume_evidence.parent_last_version = 278
	_resume_evidence.parent_applied_cells = []
	_resume_evidence.inherited_chapters.append_array(report.get("chapters", []))
	_resume_evidence.chain.append({"run_id": RESUME_BACK_RUN, "report": RESUME_BACK_REPORT, "sha256": source.sha256_text(),
		"passed": false, "segment_steps": 1, "completed_prefix": 97, "last_version": 278})
	return true

func _validate_resume_checkpoint(ledger: Dictionary) -> bool:
	if not _check(session.farm_id == str(_resume_report.get("farm_id", "")) and not session.farm_id.is_empty()
		and session.version == int(_resume_report.commands.back().version), "Resume farm identity and version match the last applied command"): return false
	var previous: Dictionary = _resume_report.state
	if not _check(int(session.state.clock.chapter_index) == 5 and int(previous.get("clock", {}).get("chapter_index", -1)) == 5
		and session.state.clock.player_day_id == previous.clock.player_day_id
		and session.state.get("cells") == previous.get("cells") and session.state.get("growth_choice", {}).get("purchase") == "tool",
		"Resume preserves the D5 row-tool checkpoint and plot state"): return false
	if not _check(ledger.get("steps") is Array and _resume_step < ledger.steps.size(), "Resume checkpoint lies within the current ledger"): return false
	for index in _resume_step:
		var done: Dictionary = _resume_prefix[index]
		var expected: Dictionary = ledger.steps[index]
		if not _check(int(done.get("day", -1)) == int(expected.day) and done.get("type") == expected.cmd.type
			and int(done.get("ledger_index", index)) == index,
			"Parent completed ledger prefix step %d" % index): return false
	var next: Dictionary = ledger.steps[_resume_step]
	if _resume_run == RESUME_RUN:
		if not _check(int(next.day) == 5 and next.cmd.get("type") == "apply_care" and next.cmd.get("kind") == "shelter"
			and next.cmd.get("cell_ids") is Array and next.cmd.cell_ids.size() == 9
			and int(_resume_report.steps.back().version) == 269, "Only the partially applied D5 shelter step can resume"): return false
	elif not _check(_resume_step == 97 and int(next.day) == 6 and next.cmd.get("type") == "harvest_cells"
		and int(_resume_report.steps.back().version) == 278, "Navigation continuation resumes at the D5 to D6 boundary"): return false
	for day in (6 if _resume_run == RESUME_BACK_RUN else 5):
		if not _check(str(session.state.chapters[day].status) == "done", "Inherited D%d completion is retained, not replayed" % day): return false
	return true

func _run() -> void:
	if not _resume_run.is_empty() and not _load_resume_report(): return _finish()
	if _touch and not _prepare_touch_identity(): return _finish()
	Net.use_transport(_transport(), _base)
	Net.booting = true
	session = Net.session
	if _touch:
		if not _check(OS.get_name() == "Android", "Touch run requires an Android ADB target"): return _finish()
		var registration := await session.client.request("POST", "/qa/touch/runs", {
			"run_id": _touch_run, "route": route, "style": style, "platform": OS.get_name(), "display": _display_geometry()})
		if not _check(registration.is_success(), "Register isolated touch run " + _touch_run): return _finish()
		print("WEEK_TOUCH_RUN ", _touch_run)
	_bypasses.append({"scope": "setup", "action": "anonymous_login_and_create_farm" if _resume_run.is_empty() else "anonymous_login_and_reload_farm", "reason": "Dedicated QA account setup precedes gameplay input"})
	if not _check(await session.login(), "Anonymous QA login"): return _finish()
	if _resume_run.is_empty():
		if not _check(await session.ensure_farm("shanghai", "sh_a", 2), "Create QA farm"): return _finish()
	else:
		if not _check(await session.refresh(), "Read the existing resume farm without creating one"): return _finish()
		_bypasses.append({"scope": "product", "action": "prior_ledger_segment_not_replayed", "reason": "The parent report supplies earlier evidence; this run is a continuation, not a continuous seven-day run"})
	print("WEEK_UI_FARM ", session.farm_id)
	var ledger: ApiClient.Response = await session.client.request("GET", "/qa/ledger?path=%s&style=%s" % [route, style])
	if not _check(ledger.is_success(), "Load canonical command ledger"): return _finish()
	if not _resume_run.is_empty() and not _validate_resume_checkpoint(ledger.json): return _finish()
	if _touch:
		FarmRegions.save_choice("shanghai")
		FarmChoice.save(session.layout_patch_id, session.blueprint_revision, session.location)
		_map = (load(AppRouter.MAP) as PackedScene).instantiate()
		get_tree().root.add_child(_map)
		get_tree().current_scene = _map
		await _frames(12)
		if not _check(_map.my_farm_btn != null, "Real map farm entrance exists"): return _finish()
		await _return_farm()
		if _aborted(): return _finish()
	else:
		farm = AppRouter.push_instance(AppRouter.FARM, {"session": session})
	await _frames(4)
	if not _check(is_instance_valid(farm), "Farm scene exists before reading plots"): return _finish()
	var local_cells := []
	for bed in farm.bp.beds(): local_cells.append_array(bed.cells)
	local_cells.append_array(farm.bp.reserved_bed().cells)
	var logical: Array = ledger.json.beds + ledger.json.reserved
	for index in logical.size(): _cell_map[str(logical[index])] = local_cells[index]
	Engine.time_scale = 1.0 if _touch else 6.0
	var day := 0
	if _resume_run.is_empty():
		await _director("qa_set_clock", {"scale": 60})
		if _aborted(): return _finish()
		await _capture("d0-start")
	else:
		if _resume_run == RESUME_RUN:
			var targets := []
			for id in ledger.json.steps[_resume_step].cmd.cell_ids:
				var cell: Vector2i = _cell_map[str(id)]
				targets.append(farm.interior.source_id("%d,%d" % [cell.x, cell.y]))
			for id in _resume_evidence.parent_applied_cells:
				if not _check(targets.has(id) and session.state.cells[id].get("care_done_at") != null,
					"Previously applied care belongs to the resumed plot step"): return _finish()
		_resume_validated = true
		_resume_evidence.validated = true
		day = int(session.state.clock.chapter_index)
		await _capture("resume-d%d" % day)
	for index in range(_resume_step, ledger.json.steps.size()):
		_ledger_index = index
		var step: Dictionary = ledger.json.steps[index]
		if _finishing or not _errors.is_empty(): break
		if int(step.day) != day:
			if not _check(str(session.state.chapters[day].status) == "done", "D%d completed by real facts" % day): break
			await _day_capture(day)
			if _aborted(): return _finish()
			await _director("qa_skip_days", {"days": 1})
			if _aborted(): return _finish()
			day = int(step.day)
			if not _check(int(session.state.clock.chapter_index) == day, "Chapter D%d opened" % day): break
		var started := Time.get_ticks_msec()
		await _step(step.cmd)
		if _aborted(): return _finish()
		if str(step.cmd.type) in ["cook_dish", "submit_request", "attend_shared_event", "choose_nursery_appearance", "purchase_growth_choice"]:
			await _capture("d%d-%s" % [day, step.cmd.type])
		_steps.append({"ledger_index": index, "day": day, "type": step.cmd.type, "ms": Time.get_ticks_msec() - started, "version": session.version})
		print("WEEK_UI_STEP ", JSON.stringify(_steps.back()))
	if _errors.is_empty():
		await _day_capture(6)
		if _aborted(): return _finish()
		var expected := 305 if route == "tool" else 145
		if style == "sell": expected = 376 if route == "tool" else 200
		_check(int(session.state.wallet) == expected, "Final wallet %d (actual %d)" % [expected, session.state.wallet])
		_check(int(session.state.xp.total) == 301, "Final XP 301")
		_check(session.state.get("week_summary") is Dictionary, "Authoritative week summary")
		if session.state.get("week_summary") is Dictionary:
			_check(bool(session.state.week_summary.life_priority) == (style == "life"), "Correct ending branch")
		await _content_checks()
		if _aborted(): return _finish()
		await _open_place("courtyard", "events")
		if _aborted(): return _finish()
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
	if _aborted(): return _finish()
	await _press(place.active_panel, "Appearance_b")
	_check(str(session.state.nursery.appearance) == "b", "Painted nursery gate saved")
	await _capture("nursery-painted-gate")
	await _press(place.active_panel, "Appearance_a")
	await _capture("nursery-garden-arch")
	await _open_place("courtyard", "decorations")
	if _aborted(): return _finish()
	for index in DecorationLayout.IDS.size():
		var picker := place.active_panel.find_child("DecorationPicker", true, false) as OptionButton
		if _touch: await _select_option(picker, index)
		else: picker.item_selected.emit(index)
		if _aborted(): return _finish()
		await _frames(3)
		await _press(place.active_panel, "PlaceDecoration")
	_check(place.active_panel.preview().size() == 6, "All six courtyard pieces previewed")
	await _press(place.active_panel, "UndoDecoration")
	_check(place.active_panel.preview().size() == 5, "Undo restores previous preview")
	await _press(place.active_panel, "PlaceDecoration")
	await _press(place.active_panel, "SaveDecorations")
	_check(DecorationLayout.saved(session.state).size() == 6, "All six pieces saved through HTTP")
	await _capture("courtyard-six-pieces")
	if _touch:
		await _check_decoration_world_touches()
		if _aborted(): return _finish()
	await _return_farm()
	if _aborted(): return _finish()
	await session.refresh()
	await _open_place("courtyard", "decorations")
	if _aborted(): return _finish()
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

func _check_decoration_world_touches() -> void:
	var panel := place.active_panel as DecorationPanel
	if not _check(panel != null, "Decoration world controls exist"): return
	var baseline := panel.preview()
	var commands_before := _wire.size()
	var version_before := session.version
	_decoration_world_evidence.attempted = true
	_decoration_world_evidence.first_checkpoint = _touch_id + 1
	var plan := _decoration_touch_plan(panel)
	if not _check(not plan.is_empty(), "Visible decoration has a clear legal destination and adjustment"): return
	_decoration_world_evidence.prop_id = plan.id
	_decoration_world_evidence.before = baseline
	if not await _touch_viewport("decoration:pick:" + str(plan.id), [plan.source]): return
	await _idle()
	if not _check(panel.selected_prop == str(plan.id) and panel.preview() == baseline, "World touch selects the placed decoration without moving it"): return
	if not await _touch_viewport("decoration:place:" + str(plan.id), [plan.target]): return
	await _idle()
	if not _check(panel.preview() == plan.moved and panel.dirty, "World touch moves the decoration to the expected legal offset"): return
	_decoration_world_evidence.moved = panel.preview()
	await _capture("courtyard-world-move")
	await _press(panel, "MoveDecoration%d" % int(plan.direction))
	if _aborted(): return
	if not _check(panel.preview() == plan.nudged, "Direction control adjusts the decoration by one grid unit"): return
	_decoration_world_evidence.direction = int(plan.direction)
	_decoration_world_evidence.adjusted = panel.preview()
	await _press(panel, "UndoDecoration")
	if _aborted(): return
	if not _check(panel.preview() == plan.moved and panel.dirty, "Undo restores the world placement before cancellation"): return
	await _press(panel, "CancelDecoration")
	if _aborted(): return
	if not _check(panel.preview() == baseline and not panel.dirty, "Cancel restores all six saved decoration offsets"): return
	if not _check(_wire.size() == commands_before and session.version == version_before and DecorationLayout.saved(session.state) == baseline,
		"Decoration preview checks leave authoritative resources and layout unchanged"): return
	_decoration_world_evidence.after = panel.preview()
	_decoration_world_evidence.last_checkpoint = _touch_id
	_decoration_world_evidence.gameplay_commands = _wire.size() - commands_before
	_decoration_world_evidence.passed = true
	await _capture("courtyard-world-cancel")

func _decoration_touch_plan(panel: DecorationPanel) -> Dictionary:
	var camera: Camera3D = place.cam
	var area: Rect2 = place._decoration_world_area().grow(-12)
	var blocked: Array[Rect2] = []
	# Project the rendered resident meshes so world taps do not land on a character.
	if is_instance_valid(place._cast):
		for actor in place._cast.get_children():
			var bounds := Rect2()
			var found := false
			for child in actor.find_children("*", "MeshInstance3D", true, false):
				var mesh := child as MeshInstance3D
				if not mesh.is_visible_in_tree(): continue
				var box := mesh.get_aabb()
				for corner in 8:
					var point := camera.unproject_position(mesh.global_transform * box.get_endpoint(corner))
					bounds = bounds.expand(point) if found else Rect2(point, Vector2.ZERO)
					found = true
			if found: blocked.append(bounds.grow(6))
	var props := panel.preview()
	var limits: Dictionary = DecorationLayout.data().bounds_q
	var unit := float(DecorationLayout.data().unit_m)
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT]
	for prop in props:
		var id := str(prop.prop_id)
		if id == panel.selected_prop: continue
		var source := camera.unproject_position(DecorationLayout.world_position(prop))
		if not _decoration_point_is_clear(source, area, blocked): continue
		for z in range(int(limits.min_z), int(limits.max_z) + 1):
			for x in range(int(limits.min_x), int(limits.max_x) + 1):
				var q := Vector2i(x, z)
				var moved := DecorationLayout.with_position(props, id, q)
				if moved == props or not DecorationLayout.is_valid(moved): continue
				var direction := -1
				var nudged: Array = []
				for index in directions.size():
					var candidate := DecorationLayout.with_position(moved, id, q + directions[index])
					if DecorationLayout.is_valid(candidate):
						direction = index
						nudged = candidate
						break
				if direction < 0: continue
				# A half-metre move needs an off-centre tap outside the old 0.6m pick radius.
				for offset_x in [0.0, -0.38, 0.38]:
					for offset_z in [0.0, -0.38, 0.38]:
						var world := Vector3((x + offset_x) * unit, 0, (z + offset_z) * unit)
						var near_piece := false
						for existing in props:
							if world.distance_to(DecorationLayout.world_position(existing)) < 0.65: near_piece = true
						if near_piece: continue
						var target := camera.unproject_position(world)
						if not _decoration_point_is_clear(target, area, blocked): continue
						var hit = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(target), camera.project_ray_normal(target))
						if hit is Vector3 and DecorationLayout.quantize(hit) == q:
							return {"id": id, "source": source, "target": target, "moved": moved, "direction": direction, "nudged": nudged}
	return {}

func _decoration_point_is_clear(point: Vector2, area: Rect2, blocked: Array[Rect2]) -> bool:
	if not area.has_point(point): return false
	for bounds in blocked:
		if bounds.has_point(point): return false
	return true

func _read_event(event: Dictionary) -> void:
	await _open_place(str(event.place), "events")
	if _aborted(): return _finish()
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
	if _aborted(): return _finish()
	var type := str(command.type)
	if command.has("cell_ids"):
		await _return_farm()
		if _aborted(): return _finish()
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
				if not _resume_run.is_empty() and _ledger_index == _resume_step and type == "apply_care":
					var source_id: String = farm.interior.source_id(local_id)
					if not _check(session.state.cells.get(source_id, {}).get("care_done_at") != null, "Resume skips only plots already cared for"): return
					_resume_evidence.skipped_care_cells.append(source_id)
					continue
				if type in ["apply_care", "harvest_cells", "till_cells"]: continue
				_check(false, "Plot action mismatch %s / %s" % [action, type])
				return
			var commands_before := _wire.size()
			if _touch:
				var world: Vector3 = farm.bp.cell_to_world(local, farm.WORLD_SCALE)
				world.y = farm.BED_H * farm.WORLD_SCALE
				var point: Vector2 = farm.cam.unproject_position(world)
				if not _check(farm._projector().call(point) == local, "Camera ray identifies plot " + local_id): return
				await _touch_viewport("plot:" + local_id + ":" + type, [point])
			else: farm._tap_cell(local)
			await _idle()
			if _touch:
				if not _check(_wire.size() > commands_before, "Plot touch produces authoritative command " + local_id): return
				var targeted := false
				for applied in _wire.slice(commands_before):
					if not _check(str(applied.type) == type and int(applied.status) >= 200 and int(applied.status) < 300,
						"Plot command group contains only successful requested actions"): return
					if applied.payload.get("cell_ids", []).has(farm.interior.source_id(local_id)): targeted = true
				if not _check(targeted, "Plot command group includes the touched source cell"): return
		if type == "harvest_cells" and int(session.state.clock.chapter_index) == 0:
			await _director("qa_set_clock", {"scale": 1})
		return
	match type:
		"buy_seeds":
			await _return_farm()
			if _aborted(): return _finish()
			await _press_button(farm.hud._stall)
			await _frames(3)
			while farm.stall._buy_qty != int(command.qty):
				await _press_button(farm.stall._quantity_plus if farm.stall._buy_qty < int(command.qty) else farm.stall._quantity_minus)
			await _press_button(farm.stall._seed_rows[str(command.crop)].button)
		"sell_at_stall":
			await _return_farm()
			if _aborted(): return _finish()
			await _press_button(farm.hud._stall)
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
			if _aborted(): return _finish()
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
			if _aborted(): return _finish()
			await _press(place.active_panel, "Cook_" + str(command.recipe))
		"attend_shared_event":
			if command.event_id == "cooking_together":
				await _open_place("bistro", "kitchen")
				if _aborted(): return _finish()
				await _press(place.active_panel, "SharedCooking")
				await _press(place.active_panel, "ContinueShared")
				await _press(place.active_panel, "ContinueShared")
				await _press(place.active_panel, "CompleteShared")
			else:
				await _open_place("courtyard", "events")
				if _aborted(): return _finish()
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
			if _aborted(): return _finish()
			for crop in command.items:
				for count in int(command.items[crop]): await _press(place.active_panel, "Reserve_" + str(crop))
		"submit_engineering":
			await _open_place("nursery", "project")
			if _aborted(): return _finish()
			await _press(place.active_panel, "SubmitAll")
		"choose_nursery_appearance":
			await _open_place("nursery", "project")
			if _aborted(): return _finish()
			await _press(place.active_panel, "Appearance_" + str(command.appearance))
		"set_growth_intent": await _economy("growth", "Growth_" + str(command.choice))
		"purchase_growth_choice": await _economy("growth", "Purchase_" + str(command.choice))
		"record_visit_return":
			if _touch:
				await _visit_by_touch()
				return
			await _return_farm()
			var entry: Dictionary = PresetSnapshots.entries("shanghai")[0]
			var result: Dictionary = await Net.snapshot(str(entry.farm_id))
			if not _check(bool(result.ok), "Read real visitor snapshot"): return
			var snap: Dictionary = result.snapshot
			var visitor := AppRouter.push_instance(AppRouter.FARM, {"visitor": true, "snapshot": snap,
				"layout_patch_id": snap.layout_patch_id, "revision": snap.blueprint_revision})
			await _frames(40)
			await _capture("d4-visit")
			await _press_button(visitor.exit_btn)
			await _idle()
		_: _check(false, "Unhandled UI command " + type)

func _economy(section: String, button: String) -> void:
	await _return_farm()
	if _aborted(): return _finish()
	await _press(farm.hud, "LifeButton")
	await _frames(3)
	if _aborted(): return _finish()
	if not _check(is_instance_valid(farm.life_sheet) and farm.life_sheet.visible, "Harvest sheet opened"): return _finish()
	await _press_button(farm.life_sheet._tabs[section])
	await _frames(3)
	await _press(farm.life_sheet.active, button)

func _open_place(id: String, tab: String) -> void:
	if _aborted(): return _finish()
	if _touch:
		await _return_map()
		if _aborted(): return _finish()
		await _press_button(_map.nearby_panel._place_tab)
		if _aborted(): return _finish()
		await _press_button(_map.nearby_panel._place_buttons[id])
		if _aborted(): return _finish()
		place = AppRouter.top_instance()
		if not _check(is_instance_valid(place) and place.scene_file_path == AppRouter.PLACE, "Map opened place " + id): return _finish()
	else:
		await _return_farm()
		if _aborted(): return _finish()
		place = AppRouter.push_instance(AppRouter.PLACE, {"place_id": id, "session": session})
	await _frames(3)
	var button: Button = place._tab_buttons.get(tab)
	if not _check(button != null, "Place tab " + tab): return
	await _press_button(button)

func _return_farm() -> void:
	if _aborted(): return _finish()
	if _touch:
		if is_instance_valid(place): await _return_map()
		if _aborted(): return _finish()
		if not is_instance_valid(farm) or AppRouter.top_instance() != farm:
			await _press_button(_map.my_farm_btn)
			if _aborted(): return _finish()
			farm = AppRouter.top_instance()
			if not _check(is_instance_valid(farm) and farm.scene_file_path == AppRouter.FARM, "Map opened own farm"): return _finish()
			await _frames(4)
		await _close_farm_modal()
		return
	if is_instance_valid(place):
		AppRouter.pop_instance()
		place = null
		await _frames(3)
	farm.hud.close_modal()
	await _frames(2)

func _director(type: String, payload: Dictionary) -> void:
	await _return_farm()
	if _aborted(): return _finish()
	if _touch:
		var title: Control = farm.title
		var point := _control_screen(title, title.size * 0.5)
		await _touch_screen("director:hold-title", [point, point], 3400)
		await _idle()
		if not _check(farm.director.visible, "Long press opens director"): return
		var label := "%dx" % int(payload.scale) if type == "qa_set_clock" else "+%d day%s" % [int(payload.days), "" if int(payload.days) == 1 else "s"]
		var button := _find_button(farm.director, label)
		if not _check(button != null, "Director option " + label): return
		await _press_button(button)
		await _close_farm_modal()
		return
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
	if _aborted(): return _finish()
	if not _check(is_instance_valid(parent), "Parent exists for control " + id): return _finish()
	await _frames(2)
	var button := parent.find_child(id, true, false) as Button
	if not _check(button != null, "Control " + id): return
	await _press_button(button)

func _press_button(button: Button) -> void:
	if _finishing or not _errors.is_empty(): return
	if not _check(is_instance_valid(button), "Touch target exists"): return
	if not _check(not button.disabled, "Enabled control " + str(button.name)): return
	if _touch:
		if not await _reveal(button): return
		var point := _control_screen(button, button.size * 0.5)
		await _touch_screen("control:" + str(button.get_path()), [point])
		await _idle()
		return
	var parent := button.get_parent()
	while parent:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			break
		parent = parent.get_parent()
	button.pressed.emit()
	await _idle()

func _find_button(parent: Node, text_or_tip: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.is_visible_in_tree() and (child.text == text_or_tip or child.tooltip_text == text_or_tip): return child
		var nested := _find_button(child, text_or_tip)
		if nested: return nested
	return null

func _close_farm_modal() -> void:
	if not is_instance_valid(farm) or not farm.hud.modal_open(): return
	var modal: Control = farm.hud._modal
	var close: Button
	for tip in ["Close", "Close director", "Close stall", "Close goals"]:
		close = _find_button(modal, tip)
		if close: break
	if close:
		await _press_button(close)
	else:
		var scrim: Control = farm.hud._scrim
		var visible := scrim.get_global_rect().intersection(get_viewport().get_visible_rect())
		var point := Vector2(visible.get_center().x, visible.position.y + 12)
		await _touch_viewport("modal:scrim-close", [point])
		await _idle()
	_check(not farm.hud.modal_open(), "Modal closed by touch")

func _return_map() -> void:
	if _aborted(): return _finish()
	if is_instance_valid(place):
		for layer in 4:
			if not _check(AppRouter.top_instance() == place, "Back targets the active place scene"): return _finish()
			var before := _place_back_state(place)
			await _press_button(place._exit)
			if _aborted(): return _finish()
			await _frames(3)
			var next := AppRouter.top_instance()
			var after := _place_back_state(next)
			_place_back_transitions.append({"checkpoint_id": _touch_id, "layer": layer, "before": before, "after": after})
			if not _check(before != after, "Place back advances its view or exits its scene"): return _finish()
			if is_instance_valid(next) and next.scene_file_path == AppRouter.PLACE:
				place = next
			else:
				place = null
				break
		if not _check(not is_instance_valid(place), "Place returns through at most four back layers"): return _finish()
	if is_instance_valid(farm) and AppRouter.top_instance() == farm:
		await _close_farm_modal()
		if _aborted(): return _finish()
		await _press_button(farm.exit_btn)
		if _aborted(): return _finish()
		farm = null
	await _frames(5)
	_check(AppRouter.top_instance() == null, "Touch return restores map")

func _place_back_state(scene: Node) -> Dictionary:
	if not is_instance_valid(scene): return {"scene_id": 0}
	var result := {"scene_id": scene.get_instance_id(), "scene_path": scene.scene_file_path}
	if scene.scene_file_path != AppRouter.PLACE: return result
	result.tab = scene.selected_tab
	var panel: SessionPanel = scene.active_panel
	if panel is EventsPanel:
		result.view = (panel as EventsPanel)._view
		result.event_id = (panel as EventsPanel)._event_id
	elif panel is ResidentPanel:
		result.view = (panel as ResidentPanel)._view
		result.resident = (panel as ResidentPanel).selected_resident
	elif panel is KitchenPanel:
		result.shared_step = (panel as KitchenPanel)._shared_step
	elif panel is DecorationPanel:
		result.confirm_leave = (panel as DecorationPanel)._confirm_leave
	return result

func _visit_by_touch() -> void:
	await _return_map()
	if _aborted(): return _finish()
	var nearby: NearbyPanel = _map.nearby_panel
	await _press_button(nearby._farm_tab)
	var start := Time.get_ticks_msec()
	while nearby._cards.is_empty() and Time.get_ticks_msec() - start < 15000: await _frames(1)
	if not _check(not nearby._cards.is_empty() and not _map._nearby_from_presets, "Real nearby farms loaded through HTTP"): return
	await _press_button(nearby._cards[0])
	start = Time.get_ticks_msec()
	while nearby.visit_button.disabled and Time.get_ticks_msec() - start < 15000: await _frames(1)
	await _press_button(nearby.visit_button)
	var visitor := AppRouter.top_instance()
	if not _check(is_instance_valid(visitor) and bool(visitor.visitor), "Visit entered through real map controls"): return
	await _frames(40)
	await _capture("d4-visit")
	await _press_button(visitor.exit_btn)
	await _return_farm()

func _reveal(control: Control) -> bool:
	if not _check(control.is_visible_in_tree(), "Visible touch target " + str(control.name)): return false
	var ancestor := control.get_parent()
	while ancestor:
		if ancestor is ScrollContainer:
			var scroll: ScrollContainer = ancestor
			for attempt in 16:
				var bounds := scroll.get_global_rect().intersection(get_viewport().get_visible_rect()).grow(-8)
				var center := control.get_global_rect().get_center()
				if bounds.has_point(center): break
				var from := bounds.get_center()
				var to := from
				if center.y > bounds.end.y or center.y < bounds.position.y:
					var direction := 1.0 if center.y > bounds.end.y else -1.0
					from.y += bounds.size.y * 0.3 * direction
					to.y -= bounds.size.y * 0.3 * direction
				else:
					var direction := 1.0 if center.x > bounds.end.x else -1.0
					from.x += bounds.size.x * 0.3 * direction
					to.x -= bounds.size.x * 0.3 * direction
				if not await _touch_viewport("scroll:" + str(control.name), [from, to], 320): return false
				await get_tree().create_timer(0.2, true, false, true).timeout
			if not _check(scroll.get_global_rect().grow(-4).has_point(control.get_global_rect().get_center()), "Scroll reveals " + str(control.name)): return false
		ancestor = ancestor.get_parent()
	return _check(get_viewport().get_visible_rect().has_point(control.get_global_rect().get_center()), "Target lies in viewport")

func _select_option(picker: OptionButton, index: int) -> void:
	if _aborted(): return _finish()
	if not _check(is_instance_valid(picker), "Decoration picker exists"): return _finish()
	if not await _reveal(picker): return
	var popup := picker.get_popup()
	popup.window_input.connect(func(event): _record_touch(event, popup))
	await _touch_screen("picker:open", [_control_screen(picker, picker.size * 0.5)])
	if _aborted(): return _finish()
	await _frames(4)
	if not _check(popup.visible and not popup.is_native_menu(), "Visible Godot option menu"): return
	var geometry := _popup_public_geometry(popup, index)
	_popup_geometry_evidence.append(geometry)
	if not _check(bool(geometry.supported) and bool(geometry.uniform_rows), "Popup contains six uniform single-line radio items"): return
	if not _check(bool(geometry.unclipped), "Popup shows every item without scrolling or clipping"): return
	geometry.checkpoint_id = _touch_id + 1
	var point := Vector2(float(geometry.screen_point[0]), float(geometry.screen_point[1]))
	if not await _touch_screen("picker:item:%d" % index, [point]): return
	await _idle()
	geometry.closed = not is_instance_valid(popup) or not popup.visible
	if not _check(bool(geometry.closed), "Popup closes after the item touch"): return
	geometry.selected = _check(str(place.active_panel.selected_prop) == str(DecorationLayout.IDS[index]), "Option selected through touch")

func _popup_public_geometry(popup: PopupMenu, index: int) -> Dictionary:
	var visible := popup.get_visible_rect()
	var panel := popup.get_theme_stylebox("panel")
	var font := popup.get_theme_font("font")
	var font_size := popup.get_theme_font_size("font_size")
	var separation := popup.get_theme_constant("v_separation")
	var margins := Vector4(panel.get_margin(SIDE_LEFT), panel.get_margin(SIDE_TOP), panel.get_margin(SIDE_RIGHT), panel.get_margin(SIDE_BOTTOM))
	var shadow := Vector4.ZERO
	if panel is StyleBoxFlat and (popup.is_embedded() or DisplayServer.is_window_transparency_available()):
		var flat := panel as StyleBoxFlat
		var offset := flat.shadow_offset
		if popup.is_layout_rtl(): offset.x = -offset.x
		shadow = Vector4(maxf(0, flat.shadow_size - offset.x), maxf(0, flat.shadow_size - offset.y),
			maxf(0, flat.shadow_size + offset.x), maxf(0, flat.shadow_size + offset.y))
	var checked := popup.get_theme_icon("checked")
	var radio := popup.get_theme_icon("radio_checked")
	var check_height := maxi(checked.get_height(), radio.get_height())
	var check_width := maxi(checked.get_width(), radio.get_width())
	var heights: Array[int] = []
	var max_text_width := 0.0
	var supported := popup.item_count == 6 and index >= 0 and index < popup.item_count
	if popup.has_method("is_search_bar_enabled") and bool(popup.call("is_search_bar_enabled")): supported = false
	for item in popup.item_count:
		var text := popup.get_item_text(item)
		supported = supported and not popup.is_item_separator(item) and popup.get_item_icon(item) == null \
			and popup.is_item_radio_checkable(item) and popup.get_item_indent(item) == 0 and not text.contains("\n") and not text.contains("\r")
		var line := TextLine.new()
		line.add_string(popup.tr(text), font, font_size, popup.get_item_language(item))
		var text_height := int(line.get_size().y)
		if text_height == 0: text_height = int(font.get_height(font_size))
		heights.append(maxi(text_height, check_height))
		max_text_width = maxf(max_text_width, line.get_size().x)
	var row_height := float(heights[0] + separation) if not heights.is_empty() else 0.0
	var uniform := row_height > 0
	for height in heights:
		if float(height + separation) != row_height: uniform = false
	# Equal natural and visible heights mean all rows fit and no scroll offset is possible.
	var content := visible.grow_individual(-margins.x - shadow.x, -margins.y - shadow.y, -margins.z - shadow.z, -margins.w - shadow.w)
	var natural_height := margins.y + shadow.y + popup.item_count * row_height + margins.w + shadow.w
	var required_width := max_text_width + check_width + popup.get_theme_constant("h_separation") \
		+ popup.get_theme_constant("item_start_padding") + popup.get_theme_constant("item_end_padding")
	var screen_rect := popup.get_screen_transform() * visible
	var root_rect := get_viewport().get_screen_transform() * get_viewport().get_visible_rect()
	var unclipped := absf(visible.size.y - natural_height) <= 1.0 and content.size.x + 1.0 >= required_width \
		and root_rect.grow(1).encloses(screen_rect)
	var local := Vector2(content.get_center().x, content.position.y + (float(index) + 0.5) * row_height)
	var screen := popup.get_screen_transform() * local
	return {"item_index": index, "item_count": popup.item_count, "supported": supported, "uniform_rows": uniform, "unclipped": unclipped,
		"visible_rect": [visible.position.x, visible.position.y, visible.size.x, visible.size.y], "window_size": [popup.size.x, popup.size.y],
		"embedded": popup.is_embedded(), "content_scale_factor": popup.content_scale_factor, "screen_transform": str(popup.get_screen_transform()),
		"panel_margins": [margins.x, margins.y, margins.z, margins.w], "shadow_margins": [shadow.x, shadow.y, shadow.z, shadow.w],
		"font_size": font_size, "check_height": check_height, "item_heights": heights, "v_separation": separation, "row_height": row_height,
		"natural_height": natural_height, "required_width": required_width, "local_point": [local.x, local.y], "screen_point": [screen.x, screen.y], "closed": false, "selected": false}

func _display_geometry() -> Dictionary:
	var viewport := get_viewport().get_visible_rect().size
	var window := DisplayServer.window_get_size()
	var origin := DisplayServer.window_get_position()
	return {"viewport": [viewport.x, viewport.y], "window": [window.x, window.y], "window_origin": [origin.x, origin.y],
		"stretch": str(ProjectSettings.get_setting("display/window/stretch/mode")), "screen_transform": str(get_viewport().get_screen_transform())}

func _control_screen(control: Control, local: Vector2) -> Vector2:
	return control.get_viewport().get_screen_transform() * control.get_global_transform_with_canvas() * local

func _touch_viewport(label: String, points: Array, duration := 0) -> bool:
	var screen := []
	for point in points: screen.append(get_viewport().get_screen_transform() * (point as Vector2))
	return await _touch_screen(label, screen, duration)

func _touch_screen(label: String, points: Array, duration := 0) -> bool:
	if _finishing or not _errors.is_empty(): return false
	_touch_id += 1
	var packed := []
	for point in points: packed.append([float(point.x), float(point.y)])
	var action := {"id": _touch_id, "kind": "tap" if points.size() == 1 else "swipe", "label": label,
		"screen_points": packed, "display": _display_geometry()}
	if duration > 0: action.duration_ms = duration
	var prefix := "/qa/touch/runs/%s/checkpoints" % _touch_run
	var started := Time.get_ticks_msec()
	var submitted := await session.client.request("POST", prefix, action)
	if not _check(submitted.is_success(), "Queue Android input " + label): return false
	while Time.get_ticks_msec() - started < 60000 and not _finishing:
		var status := await session.client.request("GET", prefix + "/%d" % _touch_id)
		if status.is_success() and status.json.get("ack") is Dictionary:
			var ack: Dictionary = status.json.ack
			var evidence := {"checkpoint": action, "ack": ack}
			_touch_actions.append(evidence)
			if not _check(bool(ack.get("ok", false)), "ADB applied " + label): return false
			var observation_started := Time.get_ticks_msec()
			var observed := false
			var received_ticks := -1
			# ADB acknowledgement can precede Android's delivery to the render thread.
			while not _finishing:
				for received in _received_touches:
					if int(received.ticks_ms) >= started and Vector2(received.screen[0], received.screen[1]).distance_to(points[0]) < 40:
						observed = true
						received_ticks = int(received.ticks_ms)
						break
				if observed or Time.get_ticks_msec() - observation_started >= 2000: break
				await get_tree().process_frame
			evidence.touch_observation = {"matched": observed, "wait_ms": Time.get_ticks_msec() - observation_started,
				"received_ticks_ms": received_ticks, "deadline_ms": 2000}
			return _check(observed, "Godot received Android touch " + label)
		await get_tree().create_timer(0.1, true, false, true).timeout
	return _check(false, "ADB acknowledgement timed out: " + label)

func _idle() -> void:
	await _frames(3)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 90000:
		var busy: bool = session._serving != session._next_ticket
		if is_instance_valid(farm): busy = busy or farm.runner.is_busy() or farm._in_flight > 0
		busy = busy or (is_instance_valid(place) and place.active_panel != null and place.active_panel.busy)
		if is_instance_valid(farm): busy = busy or (farm.stall != null and farm.stall.is_busy()) or (farm.life_sheet != null and farm.life_sheet.is_busy())
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
			if _aborted(): return _finish()
	await _return_farm()
	if _aborted(): return _finish()
	_check(str(session.state.chapters[day].status) == "done", "D%d authoritative completion" % day)
	_chapters.append({"day": day, "wallet": session.state.wallet, "xp": session.state.xp.total,
		"engineering": session.state.engineering.duplicate(true), "chapter": session.state.chapters[day].duplicate(true)})
	await _capture("d%d-complete" % day)

func _capture(label: String) -> bool:
	if DisplayServer.get_name() == "headless": return false
	await _frames(4)
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().save_png(_output.path_join(label + ".png")) == OK

func _check(value: bool, message: String) -> bool:
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		_errors.append(message)
		call_deferred("_finish")
	return value

func _aborted() -> bool:
	return _finishing or not _errors.is_empty()

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
	call_deferred("_complete_finish")

func _complete_finish() -> void:
	var failure_screenshot := ""
	if not _errors.is_empty() and await _capture("failure"):
		failure_screenshot = _output.path_join("failure.png")
	_restore()
	var file := FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE)
	var report := {"passed": _errors.is_empty(), "path": route, "style": style,
		"state_source": "HTTP_PostgreSQL", "interaction": "adb_input_tap_swipe" if _touch else "real_controls_and_plot_callbacks", "physical_device": false,
		"device_evidence": "host_worker_report_required" if _touch else "not_collected", "touch_run_id": _touch_run if _touch else "",
		"touch_actions": _touch_actions, "received_touch_events": _received_touches, "interaction_bypasses": _bypasses,
		"decoration_world_interactions": _decoration_world_evidence,
		"resumed_from": _resume_run, "resume": _resume_evidence, "continuous_seven_day_run": _resume_run.is_empty(),
		"place_back_transitions": _place_back_transitions,
		"popup_geometry": _popup_geometry_evidence,
		"platform": OS.get_name(), "photo_path": _photo_path, "failure_screenshot": failure_screenshot, "event_scenes": _event_scenes,
		"elapsed_seconds": (Time.get_ticks_msec() - _started) / 1000.0, "farm_id": session.farm_id if session else "",
		"chapters": _chapters, "steps": _steps, "commands": _wire, "state": session.state if session else {}, "errors": _errors}
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("WEEK_UI_RESULT ", JSON.stringify({"passed": _errors.is_empty(), "errors": _errors, "output": _output}))
	if _touch and session:
		call_deferred("_publish_touch_report", report)
		return
	get_tree().quit(0 if _errors.is_empty() else 1)

func _publish_touch_report(report: Dictionary) -> void:
	var result := await session.client.request("POST", "/qa/touch/runs/%s/finish" % _touch_run, report)
	if not result.is_success(): push_error("Host touch report could not be published")
	get_tree().quit(0 if _errors.is_empty() and result.is_success() else 1)

func _exit_tree() -> void:
	_restore()
