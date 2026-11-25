extends SceneTree
## C-106 review pictures of the dynamic farm map's UI and the sign-in panel in their states, on the in-memory claim
## stand-in (no server, no native map: a still of the map art stands behind the UI). Not device or map evidence.
##   godot --path <project> --resolution 360x780 --script res://tools/dev/dynamic_farm/map_ui_shots.gd -- <empty out dir>
## Run with a display (or a virtual one); SENSEN_OFFLINE=1 keeps Net from signing in. Works on the map before C-106 too
## (the same states, for the before / after comparison).
const Claims := preload("res://modules/dynamic_farm/map/claim_controller.gd")
const ClaimApi := preload("res://modules/dynamic_farm/map/claim_api.gd")
const Selection := preload("res://modules/dynamic_farm/map/selection_controller.gd")
const FakeServer := preload("res://modules/dynamic_farm/map/fake_parcel_server.gd")
const CameraInput := preload("res://modules/dynamic_farm/map/geo_native_camera.gd")
const OWN_FARM := "sensen/dynamic_farm/own_farm"
const MAP_STILL := "res://assets/ui/backgrounds/map-social.png"

class Selector extends Node:
	signal changed
	var selection := {}
	var busy := false
	var map_ready := true
	var generation := 4
	var message := Selection.PROMPT
	var manifest := {"native_map": {"minzoom": 16, "center": [-122.41, 37.78], "initial_zoom": 17.5}}
	var _options: Array = []
	func open_farm() -> void: pass
	func pause() -> void: pass
	func activate() -> void: pass
	func choose(_id: String) -> void: pass

var out := ""

func _initialize() -> void:
	_run.call_deferred()

## Ids the stand-in server treats as free (as test_claim_controller.gd's _free_ids) or as someone else's.
func _free(n: int) -> String:
	var found := 0
	var i := 0
	while true:
		i += 1
		var id := "p-%d" % (3139000 + i)
		if id.hash() % 3 != 0:
			found += 1
			if found == n: return id
	return ""

func _taken() -> String:
	var i := 0
	while true:
		i += 1
		var id := "p-%d" % (5402000 + i)
		if id.hash() % 3 == 0: return id
	return ""

func _parcel(id: String, name: String) -> Dictionary:
	return {"block_id": id, "name": name, "core_cell_count": 412, "extension_cell_count": 96, "center": [-122.41, 37.78]}

func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(360, 780)
	var still := TextureRect.new()
	still.name = "MapStill"
	still.texture = load(MAP_STILL)
	still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ProjectSettings.set_setting(OWN_FARM, true)
	var net = root.get_node_or_null("Net")
	var server := FakeServer.new()
	var page = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
	root.add_child(page)
	var selector := Selector.new(); root.add_child(selector)
	page._selector = selector; page._camera = CameraInput.new(); page.add_child(page._camera); page.move_child(page._camera, 0)
	page.add_child(still); page.move_child(still, 1) # over the camera's backdrop, under the UI
	page._framed = true; page._area_generation = selector.generation
	var claims := _claims(server, "fake-a")
	page._claims = claims; claims.changed.connect(page._render)
	await claims.start()
	if net != null: # signed in as "Lin" for the account chip
		net.account.token = "fake-a"; net.account.user_id = "u-lin"; net.account.display_name = "Lin"
	page._render()
	await _shot("01_no_home_nothing_selected")
	selector.selection = _parcel(_free(1), "1200 MARKET ST")
	page._render()
	await _shot("02_free_parcel_selected")
	page._claim.pressed.emit()
	await _shot("03_claim_confirm")
	page._claim_selection()
	await process_frame
	page._render()
	await _shot("04_my_home_selected")
	selector.selection = {}
	page._render()
	await _shot("05_home_nothing_selected")
	var taken := _taken()
	selector.selection = _parcel(taken, "88 FELL ST")
	claims.owners[taken] = {"owner": "other", "nickname": "Mia"}
	page._render()
	await _shot("06_someone_elses_parcel")
	selector.selection = {}
	selector.message = Selection.QUERY_FAILED
	page._render()
	await _shot("07_load_failed")
	selector.message = Selection.PROMPT
	if net != null:
		net.restore_error = "HTTP_503"
		page._render()
		await _shot("08_account_kept")
		net.restore_error = ""
		page._account_action()
		await _shot("09_sign_out_confirm")
		if page._sign_out_confirm.visible: page._sign_out_confirm.hide()
		net.account.token = ""; net.account.user_id = ""; net.account.display_name = ""
	var guest := _claims(server, "nobody")
	await guest.start()
	page._claims = guest; guest.changed.connect(page._render)
	selector.selection = _parcel(_free(2), "1202 MARKET ST")
	page._render()
	await _shot("10_signed_out_parcel")
	selector.selection = {}
	page._render()
	await _shot("11_signed_out_nothing_selected")
	var panel_script: GDScript = load("res://scenes/account/account_panel.gd")
	var v3: bool = panel_script.get_script_method_list().any(func(m): return m.name == "_build_v3")
	var panel = panel_script.open(page, "sign_in", "", true) if v3 else panel_script.open(page, "sign_in")
	await _shot("12_sign_in")
	panel._email.text = "lin@example.com"; panel._password.text = "secret-pass"
	panel._say(AccountSession.describe("INVALID_CREDENTIALS"))
	if v3: panel._say_v3(AccountSession.describe("INVALID_CREDENTIALS"), false)
	await _shot("13_sign_in_wrong_password")
	panel._say(AccountSession.describe("TRANSPORT"))
	await _shot("14_sign_in_no_network")
	panel.set_mode("sign_up")
	await _shot("15_sign_up")
	panel.set_mode("verify")
	panel._code.text = "481"; panel._code.text_changed.emit("481"); panel._code.grab_focus()
	await _shot("16_verify_code")
	panel.set_mode("profile")
	await _shot("17_profile")
	panel.queue_free()
	await process_frame
	quit(0)

func _claims(server: RefCounted, token: String) -> Node:
	var c := Claims.new(); c.api = ClaimApi.new(server.client(token)); c.bridge = MapBridge.new()
	root.add_child(c)
	return c

func _shot(name: String) -> void:
	for i in 40: await process_frame # past the panels' M-04 motion
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))
	print("SHOT ", name)
