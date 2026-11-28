extends SceneTree
## C-243 (Google Play: deletion in the app): Settings › Delete account on the dynamic farm's profile, over the real map
## scene (no native map: the map stops after building its panels), with Net on a scripted transport. Keep my account,
## ✕ and Android Back delete nothing; a wrong password keeps the account; deleted, no guest sign-in, the profile closes
## and the sign-in panel comes back with its line. Back from the parcel without the account: the same panel. Headless.
const ACCOUNT_RESTORE := "sensen/dynamic_farm/account_restore"
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func():
		print("FAIL timed out")
		print("ACCOUNT DELETE ", checks - failures, "/", checks + 1)
		quit(1))
	_run.call_deferred()

func verify(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func sign_in_locally(net: Node) -> void:
	net.account.token = "tok"
	net.account.user_id = "u1"
	net.account.player_id = "p1"
	net.account.email = "ada@example.com"
	net.account.display_name = "Ada"
	net.account.has_password = true
	net.deleted_here = false # as Net.sign_in_with does

func frames(n := 3) -> void:
	for i in n: await process_frame

func actions(panel: Node) -> Array:
	return panel.find_child("Actions", true, false).get_children().filter(func(b): return b is Button).map(func(b): return str(b.name))

func gate_panel(map: Node) -> Node:
	for panel in map.find_children("*", "AccountPanel", false, false):
		if not panel.is_queued_for_deletion(): return panel
	return null

func open_settings(map: Node) -> Control:
	map._open_profile()
	for i in 600:
		if map._profile != null: break
		await process_frame
	var host: Control = map._profile
	host.top().settings_pressed.emit()
	await process_frame
	return host

func _run() -> void:
	var net: Node = root.get_node("Net")
	var t := FakeTransport.new([
		{"status": 401, "json": {"code": "INVALID_CREDENTIALS"}},
		{"status": 200, "json": {"ok": true, "deleted": true}},
		{"status": 200, "json": {"ok": true, "deleted": true}},
	])
	net.use_transport(t.callable(), "https://example.test/v1", "user://test_account_delete.json")
	var restore_was = ProjectSettings.get_setting(ACCOUNT_RESTORE, null)
	ProjectSettings.set_setting(ACCOUNT_RESTORE, true) # a package that needs an account (C-146)
	sign_in_locally(net)
	var map: Control = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
	map.profile_wait_seconds = 0.2
	root.add_child(map)
	current_scene = map
	await process_frame
	verify(map.account_required() and not map.account_gone(), "a package that needs an account, signed in")

	var host: Control = await open_settings(map)
	var settings: Control = host.top()
	var row: Node = settings.find_child("DeleteAccount", true, false)
	verify(row != null and row.is_visible_in_tree(), "signed in: Settings has Delete account")
	verify(settings.body.get_child(settings.body.get_child_count() - 1).is_ancestor_of(row), "at the foot of Settings, under Legal")
	verify(settings.find_child("SignOut", true, false) == null and settings.find_child("SignedInWith", true, false) == null,
		"no Sign out or Signed in with here: they stay on the map's account chip")
	verify(row.find_child("Title", true, false).text == "Delete account" and row.find_child("Line", true, false) == null,
		"the row reads Delete account, no line under it (C-243#9)")

	# Keep my account: nothing is deleted, Settings stays.
	row.pressed.emit(); await process_frame
	var panel: Node = host._delete_panel
	verify(panel != null and panel.mode == "delete" and panel.v3 and panel.english, "the account panel's delete step, v3, in English")
	verify(panel.find_child("Password", true, false).is_visible_in_tree(), "an account with a password asks for it")
	verify(actions(panel) == ["delete_now", "to_account"], "Delete permanently and Keep my account %s" % [actions(panel)])
	verify(panel._title.text == "Delete account?" and panel.action_button("delete_now").text == "Delete permanently"
		and panel.action_button("to_account").text == "Keep my account", "the confirm copy")
	panel.action_button("to_account").pressed.emit(); await frames()
	verify(not is_instance_valid(panel) and host._delete_panel == null, "Keep my account closes the delete step")
	verify(host.top() == settings and settings.visible and map._profile == host, "back on Settings")
	verify(t.requests.is_empty() and net.account.signed_in(), "nothing was sent or deleted")

	# ✕ and Android Back: the same.
	panel = host.open_delete_account()
	panel._close.pressed.emit(); await frames()
	verify(not is_instance_valid(panel) and host.top() == settings, "✕ closes it, Settings stays")
	panel = host.open_delete_account()
	verify(map.is_back_navigation_locked(), "Android Back is the profile's")
	await frames()
	verify(not is_instance_valid(panel) and host.top() == settings and map._profile == host, "Back closes the delete step only")
	verify(t.requests.is_empty() and net.account.signed_in(), "still nothing sent or deleted")

	# No password typed: asked for, nothing sent. A wrong one: the account stays.
	panel = host.open_delete_account()
	panel.action_button("delete_now").pressed.emit(); await process_frame
	verify(t.requests.is_empty() and panel._status.text == "Enter your password.", "no password: Enter your password.")
	panel._password.text = "nope"
	await panel._on_action("delete_now")
	verify(t.requests.size() == 1 and t.requests[0].method == "DELETE" and str(t.requests[0].url).ends_with("/users/me")
		and t.requests[0].body.get("password") == "nope", "the server's delete with the password")
	verify(net.account.signed_in() and is_instance_valid(panel) and not panel.busy and map._profile == host,
		"a wrong password keeps the account and the step")

	# Deleted: no guest sign-in, the profile closes, the sign-in panel says so.
	panel._password.text = "correct horse"
	await panel._on_action("delete_now")
	await frames()
	verify(t.requests.size() == 2 and t.requests[1].body.get("password") == "correct horse", "deleted with the right password")
	verify(not net.account.signed_in() and net.deleted_here, "signed out on this phone")
	verify(not FileAccess.file_exists("user://test_account_delete.json"), "the saved account is gone")
	verify(t.requests.size() == 2, "no guest sign-in afterwards (C-146)")
	verify(map._profile == null and not is_instance_valid(panel), "the profile and the delete step close")
	var gate: Node = gate_panel(map)
	verify(map._gated and gate != null and gate.mode == "sign_in" and gate.gate and not gate._close.visible,
		"the sign-in panel stands over the map, no ✕")
	verify(gate._subtitle.visible and gate._subtitle.text == "Your account has been deleted.", "with Your account has been deleted.")
	gate.set_mode("sign_up"); await process_frame
	verify(gate._subtitle.text != "Your account has been deleted.", "the line goes once another step shows")
	gate.set_mode("sign_in"); await process_frame
	verify(not gate._subtitle.visible, "and does not come back")
	# Someone signs in: the map comes back.
	sign_in_locally(net)
	gate.dismiss(); await frames()
	verify(not map._gated and map._hud.visible, "signed in again: the map is back")

	# Over the parcel: the map was covered; back on it without the account, the sign-in panel instead of the map.
	map.suspend()
	var deleted: Dictionary = await net.delete_account("correct horse", false)
	verify(deleted.ok and not net.account.signed_in() and t.requests.size() == 3, "deleted on the parcel's profile")
	map.resume(); await frames()
	gate = gate_panel(map)
	verify(map._gated and gate != null and gate._subtitle.text == "Your account has been deleted.", "back on the map: the sign-in panel says so")
	sign_in_locally(net)
	gate.dismiss(); await frames()
	verify(not map._gated, "signed in again")
	# The account gone some other way (not deleted here): the panel without that line.
	map.suspend()
	net.account.clear(net.account_path)
	map.resume(); await frames()
	gate = gate_panel(map)
	verify(map._gated and gate != null and not gate._subtitle.visible, "account gone otherwise: the plain sign-in panel")
	sign_in_locally(net)
	gate.dismiss(); await frames()

	map.queue_free(); await process_frame
	current_scene = null
	net.account.clear(net.account_path)
	ProjectSettings.set_setting(ACCOUNT_RESTORE, restore_was)
	print("ACCOUNT DELETE ", checks - failures, "/", checks)
	quit(1 if failures else 0)
