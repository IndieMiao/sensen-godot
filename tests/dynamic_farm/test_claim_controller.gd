extends SceneTree
## C-32 claim flow against the in-memory C-31 stand-in and a fake native bridge. Fake data proves the client
## logic only; it is not evidence of a real claim, a save or device rendering.
const Claims := preload("res://modules/dynamic_farm/map/claim_controller.gd")
const ClaimApi := preload("res://modules/dynamic_farm/map/claim_api.gd")
const FakeServer := preload("res://modules/dynamic_farm/map/fake_parcel_server.gd")
const Fixture := preload("res://tests/dynamic_farm/selection_fixtures.gd")
const CameraInput := preload("res://modules/dynamic_farm/map/geo_native_camera.gd")
const OWN_FARM := "sensen/dynamic_farm/own_farm"
class Native extends MapBridge:
	var states := {} # block_id -> {selected, claimed, own}, as native ParcelLayerState keeps them
	var batches: Array = []
	var names: Array = []
	var highlights: Array = []
	func supports_parcels() -> bool: return true
	func set_parcel_states(gen: int, batch: String) -> void:
		batches.append([gen, JSON.parse_string(batch)])
		for row in JSON.parse_string(batch):
			if row.selected or row.claimed or row.own: states[row.block_id] = row
			else: states.erase(row.block_id)
	func set_parcel_claims(_gen: int, claims: String) -> void: names = JSON.parse_string(claims)
	func set_parcel_building_highlight(gen: int, key: String, parcel := "") -> void: highlights.append([gen, key, parcel])
class Selector extends Node:
	signal changed
	var selection := {}
	var busy := false
	var map_ready := true
	var generation := 4
	var message := ""
	var manifest := {"native_map": {"minzoom": 16}}
	var _options: Array = []
	var opened := 0
	func open_farm() -> void: opened += 1
	func pause() -> void: pass
	func activate() -> void: pass
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", text)

func controller(server: RefCounted, token: String, native: Native) -> Node:
	var c := Claims.new(); c.api = ClaimApi.new(server.client(token)); c.bridge = native
	root.add_child(c)
	return c

func _run() -> void:
	await _server_contract()
	await _first_home_flow()
	await _map_card()
	await _account_restore()
	await _account_kept_on_server_errors()
	await _account_row()
	await _home_framing()
	await _guest_play_sign_in()
	print("DYNAMIC CLAIM ", checks - failures, "/", checks)
	quit(1 if failures else 0)

func _server_contract() -> void:
	var server := FakeServer.new()
	var a := ClaimApi.new(server.client("fake-a"))
	var b := ClaimApi.new(server.client("fake-b"))
	var center := [-122.45, 37.73]
	var free_id := _free_ids(server, 2)
	var first: Dictionary = await a.claim(free_id[0], center)
	check(first.ok and first.status == 201 and first.parcel.parcel_id == free_id[0], "first claim is created (201)")
	var again: Dictionary = await a.claim(free_id[0], center)
	check(again.ok and again.status == 200, "retrying the same claim is idempotent (200)")
	var second: Dictionary = await a.claim(free_id[1], center)
	check(not second.ok and second.code == "ALREADY_CLAIMED" and second.parcel.parcel_id == free_id[0], "a second parcel is refused with the player's own parcel")
	var taken: Dictionary = await b.claim(free_id[0], center)
	check(not taken.ok and taken.code == "PARCEL_TAKEN", "another player's parcel cannot be claimed")
	var seen: Dictionary = await b.owners([free_id[0], free_id[1]])
	check(seen.owners[free_id[0]].owner == "other" and seen.owners[free_id[0]].nickname == "Ash", "the other account sees owner 'other' with the claimer's nickname")
	check(seen.owners[free_id[1]].owner == "none", "untouched parcel is unclaimed")
	var mine: Dictionary = await a.owners([free_id[0]])
	check(mine.owners[free_id[0]].owner == "mine", "the claimer sees owner 'mine'")
	var area: Dictionary = await b.owners_in([-122.46, 37.72, -122.44, 37.74])
	check(area.ok and area.owners.has(free_id[0]), "area query lists claimed parcels")
	check(not (await a.owners_in([-123.0, 37.0, -122.0, 38.0])).ok, "area wider than 0.25° is not requested")
	server.reselect = false
	var refused: Dictionary = await a.abandon()
	check(not refused.ok and refused.status == 403 and refused.code == "RESELECT_DISABLED", "release server refuses give-up")
	check((await a.mine()).parcel.parcel_id == free_id[0], "refused give-up keeps the home")
	server.reselect = true
	check((await a.abandon()).ok and (await a.mine()).parcel.is_empty(), "internal server lets the player give up and choose again")
	check((await ClaimApi.new(server.client("nobody")).claim(free_id[1], center)).code == "UNAUTHENTICATED", "unknown token cannot claim")
	# C-43: claims carry the configured release; a client still on another release is refused.
	var r5 := FakeServer.new(); r5.dataset = "sf-dynamic-farm-20261124-r5"
	var r5_id: String = _free_ids(r5, 1)[0]
	var stale: Dictionary = await ClaimApi.new(r5.client("fake-a")).claim(r5_id, center)
	check(not stale.ok and stale.code == "SCHEMA", "claim for another dataset release is refused")
	var current: Dictionary = await ClaimApi.new(r5.client("fake-a"), r5.dataset).claim(r5_id, center)
	check(current.ok and current.parcel.dataset_version == r5.dataset, "claim on the configured release records that release")
	check((await ClaimApi.new(r5.client("fake-a"), r5.dataset).owners([r5_id])).owners[r5_id].owner == "mine", "owner query uses the configured release")

func _first_home_flow() -> void:
	var server := FakeServer.new()
	var ids := _free_ids(server, 2)
	var taken := _taken_id(server)
	var native := Native.new()
	var a := controller(server, "fake-a", native)
	await a.start()
	check(a.mine_known and not a.has_home(), "a new player has no home yet")
	a.attach(4, ids[0])
	await process_frame
	check(a.status(ids[0]) == "none" and native.states.is_empty(), "claimable selection adds no parcel state (C-28 yellow building fill stays)")
	check(native.highlights.is_empty(), "claimable selection keeps the yellow building highlight")
	await a.claim({"block_id": ids[0], "center": [-122.45, 37.73]})
	check(a.has_home() and a.status(ids[0]) == "mine", "claim makes the parcel the player's home")
	check(native.states[ids[0]].own and native.states[ids[0]].selected and not native.states[ids[0]].claimed, "own parcel is sent as own (green) and selected")
	check(native.highlights.back() == [4, "", ""], "owned selection drops the yellow highlight so green shows")
	a.attach(4, ids[1])
	await process_frame
	check(a.status(ids[1]) == "none" and a.has_home(), "another free parcel stays unclaimable for a player with a home")
	check(native.states[ids[0]].own and not native.states[ids[0]].selected, "home stays green after selecting elsewhere")
	await a.claim({"block_id": ids[1], "center": [-122.45, 37.73]})
	check(a.message == "You already have a home." and a.status(ids[1]) == "none", "client cannot take a second parcel")
	a.attach(4, taken)
	await process_frame
	check(a.status(taken) == "other" and native.states[taken].claimed and not native.states[taken].own, "someone else's parcel is sent as claimed (red)")
	check(native.names.any(func(row): return row.block_id == taken and row.nickname == FakeServer.NEIGHBOUR), "claimer name layer gets the neighbour's nickname")
	# Reopen: a fresh controller and a new native generation read the home back from the server.
	a.pause(); a.queue_free()
	var reopened := Native.new()
	var again := controller(server, "fake-a", reopened)
	await again.start()
	again.attach(9, "")
	check(again.has_home() and reopened.states[ids[0]].own and reopened.batches.back()[0] == 9, "reopening restores the green home on the new generation")
	var b_native := Native.new()
	var b := controller(server, "fake-b", b_native)
	await b.start()
	b.attach(4, ids[0])
	await process_frame
	check(b.status(ids[0]) == "other" and b.nickname(ids[0]) == "Ash" and b_native.states[ids[0]].claimed, "second account sees the first account's home in red with its name")
	await b.claim({"block_id": ids[0], "center": [-122.45, 37.73]})
	check(not b.has_home() and b.message == "Someone just claimed this parcel.", "second account cannot claim the first account's home")
	again.reselect = false
	await again.abandon()
	check(again.has_home(), "without the internal setting give-up does nothing")
	again.reselect = true
	await again.abandon()
	check(not again.has_home() and not reopened.states.has(ids[0]), "internal give-up clears the home and its green state")
	var guest := controller(server, "nobody", Native.new())
	await guest.start()
	check(guest.signed_out and not guest.mine_known, "signed-out player is told to sign in, not offered a claim")
	# A failed first read is retried when the player picks a parcel.
	var flaky := controller(server, "fake-b", Native.new())
	flaky.api.client.token = "nobody"
	await flaky.start()
	check(not flaky.mine_known, "first read can fail")
	flaky.api.client.token = "fake-b"
	flaky.attach(4, ids[1])
	await process_frame
	check(flaky.mine_known and not flaky.signed_out and flaky.status(ids[1]) == "none", "selecting a parcel retries the player's own parcel")
	# Area reads keep adding rows; the list stays bounded and keeps the home and the selection.
	var many := {}
	for i in Claims.MAX_OWNERS + 50: many["p-9%05d" % i] = {"owner": "other", "nickname": "N"}
	again.mine = {"parcel_id": "p-home"}; again.owners["p-home"] = {"owner": "mine", "nickname": ""}
	again.attach(9, "p-sel"); again.owners["p-sel"] = {"owner": "other", "nickname": "S"}
	again._merge(many)
	check(again.owners.size() == Claims.MAX_OWNERS and again.owners.has("p-home") and again.owners.has("p-sel") and again.owners.has("p-9%05d" % (Claims.MAX_OWNERS + 49)), "owner list is capped below the native limit, keeping home, selection and newest rows")
	again.queue_free(); b.queue_free(); guest.queue_free(); flaky.queue_free()

func _map_card() -> void:
	var server := FakeServer.new()
	var ids := _free_ids(server, 2)
	var taken := _taken_id(server)
	var native := Native.new()
	var page = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
	root.add_child(page) # Without the isolated build flag the page builds its UI only.
	var selector := Selector.new(); root.add_child(selector)
	page._selector = selector; page._camera = CameraInput.new(); page.add_child(page._camera)
	page._framed = true; page._area_generation = selector.generation # No native camera: skip framing and area reads.
	page._claims = controller(server, "fake-a", native); page._claims.changed.connect(page._render)
	await page._claims.start()
	page._claims.reselect = false
	# C-35: with nothing selected the card says where to go next, only in a package that enters one's own farm.
	selector.selection = {}
	page._render()
	check(page._details.text == page.PICK_PREVIEW, "preview package, nothing selected: 'Choose a parcel to explore in 3D.'")
	ProjectSettings.set_setting(OWN_FARM, true)
	page._render()
	check(page._details.text == page.PICK_FIRST, "no home yet, nothing selected: 'Tap a building to choose your first home.'")
	var farming_page = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
	root.add_child(farming_page)
	check(page.find_children("*", "Label", true, false).any(func(l): return l.text.begins_with("Explore and walk.")) \
		and not farming_page.find_children("*", "Label", true, false).any(func(l): return l.text.begins_with("Explore and walk.")),
		"only the preview package still says farming comes later")
	farming_page.queue_free()
	selector.selection = Fixture.metadata(ids[0]); selector.selection.block_id = ids[0]
	page._render(); await process_frame
	check(page._claim.visible and not page._claim.disabled and not page._enter.visible and page._open.visible, "free parcel shows 'Make this my first home'")
	page._claim.pressed.emit()
	check(page._confirm.visible and not page._claim.visible, "claim asks for confirmation first")
	page._claim_selection(); await process_frame
	check(page._enter.visible and not page._claim.visible and not page._open.visible, "after claiming the card offers 'Enter my farm'")
	var picked: Dictionary = selector.selection
	selector.selection = {}
	page._render()
	check(page._details.text == page.PICK_HOME, "with a home, nothing selected: 'Tap your green parcel, then Enter my farm.'")
	ProjectSettings.set_setting(OWN_FARM, false)
	selector.selection = picked
	page._render()
	check(not page._reselect.visible, "release package shows no give-up entry")
	check(native.states[ids[0]].own, "claimed parcel turns green on the map")
	page._enter.pressed.emit()
	check(selector.opened == 1 and page._entering == ids[0], "'Enter my farm' opens the parcel as an entry to that home")
	page._preview()
	check(selector.opened == 2 and page._entering.is_empty(), "'Preview in 3D' opens a read-only preview")
	page._claims.reselect = true; page._render()
	check(page._reselect.visible, "internal package shows 'Give up and choose again'")
	selector.selection = Fixture.metadata(ids[1]); selector.selection.block_id = ids[1]
	page._render(); await process_frame
	check(not page._claim.visible and page._details.text.ends_with("You already have a home."), "a second free parcel cannot be claimed")
	selector.selection = Fixture.metadata(taken); selector.selection.block_id = taken
	page._render(); await process_frame
	check(not page._claim.visible and page._open.visible and page._details.text.ends_with("Claimed by " + FakeServer.NEIGHBOUR), "someone else's parcel is view-only with the claimer's name")
	page._claims.owners[taken].nickname = "" # An owner without a display name, or a PARCEL_TAKEN race before the re-read.
	page._render()
	check(page._details.text.ends_with("\nClaimed") and native.names.any(func(row): return row.block_id == taken and row.nickname == "Claimed"), "an owner without a name reads 'Claimed' on the card and on the map")
	page._claims.owners[taken].nickname = FakeServer.NEIGHBOUR
	page._claims.reselect = true
	selector.selection = Fixture.metadata(ids[0]); selector.selection.block_id = ids[0]
	page._render(); await process_frame
	page._reselect.pressed.emit(); await process_frame
	check(not page._claims.has_home() and page._claim.visible, "giving up lets the player choose again")
	var guest := controller(server, "nobody", Native.new())
	await guest.start()
	page._claims = guest; guest.changed.connect(page._render)
	selector.selection = Fixture.metadata(ids[1]); selector.selection.block_id = ids[1]
	page._render(); await process_frame
	check(guest.status(ids[1]) == "unknown" and page._details.text.ends_with("Sign in to claim a home.") and not page._claim.visible, "signed-out player sees 'Sign in to claim a home.' even though ownership can't be read")
	check(page._account_button.visible and page._account_button.text == "Sign in", "signed-out player gets a 'Sign in' button")
	page._account_button.pressed.emit(); await process_frame
	var panels: Array = page.find_children("*", "AccountPanel", true, false)
	check(panels.size() == 1 and panels[0].mode == "sign_in", "'Sign in' opens the existing account panel")
	for panel in panels: panel.free()
	# After signing in, ownership is re-read for the new identity.
	guest.api.client.token = "fake-b"
	guest.forget(); await process_frame
	page._render()
	check(not guest.signed_out and guest.mine_known and guest.status(ids[1]) == "none" and page._claim.visible, "after signing in the card re-reads ownership and offers the claim")
	page.queue_free(); selector.queue_free(); guest.queue_free()
	await process_frame

## Parcel ids the fake neighbour does not own.
func _free_ids(server: RefCounted, count: int) -> Array:
	var ids: Array = []
	var n := 0
	while ids.size() < count:
		n += 1
		var id := "p-%d" % (3139000 + n)
		if id.hash() % 3 != 0: ids.append(id)
	return ids

func _taken_id(_server: RefCounted) -> String:
	var n := 0
	while true:
		n += 1
		var id := "p-%d" % (5402000 + n)
		if id.hash() % 3 == 0: return id
	return ""

## Net.restore_saved_account: reloads a saved token only; an invalid token is dropped, nothing signs in anonymously.
func _account_restore() -> void:
	var net = root.get_node_or_null("Net")
	if net == null:
		check(false, "Net autoload is present"); return
	var calls: Array = []
	var valid := {"value": true}
	var transport := func(method: String, url: String, headers: PackedStringArray, _body: String) -> ApiClient.Response:
		calls.append([method, url.trim_prefix("https://restore.test/v1"), "authorization: Bearer saved-token" in headers])
		if url.ends_with("/users/me"):
			return ApiClient.Response.new(true, 200, {"user_id": "u1", "player_id": "p1", "display_name": "Ash"}) if valid.value else ApiClient.Response.new(true, 401, {"code": "UNAUTHENTICATED"})
		return ApiClient.Response.new(true, 404, {"code": "NOT_FOUND"})
	var path := "user://c32_restore_account.json"
	net.use_transport(transport, "https://restore.test/v1", path)
	check(not await net.restore_saved_account() and calls.is_empty(), "no saved account: nothing is requested, no anonymous login")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"token": "saved-token", "user_id": "u1", "player_id": "p1"})); f.close()
	check(await net.restore_saved_account() and net.client.token == "saved-token", "saved account token is restored")
	check(calls.size() == 1 and calls[0] == ["GET", "/users/me", true], "restore only checks /users/me with the saved token")
	net.use_transport(transport, "https://restore.test/v1", path)
	valid.value = false; calls.clear()
	check(not await net.restore_saved_account() and net.client.token.is_empty() and not FileAccess.file_exists(path), "rejected token is cleared, not replaced by a guest login")
	check(calls.all(func(c): return c[1] == "/users/me"), "no other endpoint is called on restore")

## C-110: only an explicit 401 drops the saved account. Server errors, rate limits and a lost network keep it
## (and its file), record why for the map's notice, and a later check that reaches the server clears the notice.
func _account_kept_on_server_errors() -> void:
	var net = root.get_node_or_null("Net")
	if net == null:
		check(false, "Net autoload is present"); return
	var path := "user://c110_restore_account.json"
	var saved := {"token": "saved-token", "user_id": "u1", "player_id": "p1", "display_name": "Ash"}
	var cases := [
		["503 server error", ApiClient.Response.new(true, 503, {}), "HTTP_503"],
		["500 with a code", ApiClient.Response.new(true, 500, {"code": "INTERNAL"}), "INTERNAL"],
		["429 rate limit", ApiClient.Response.new(true, 429, {"code": "RATE_LIMITED"}), "RATE_LIMITED"],
		["no network", ApiClient.Response.new(false, 0, {}, "offline"), "TRANSPORT"],
	]
	for row in cases:
		var answer: ApiClient.Response = row[1]
		var transport := func(_m: String, _u: String, _h: PackedStringArray, _b: String) -> ApiClient.Response: return answer
		net.use_transport(transport, "https://restore.test/v1", path)
		_write(path, JSON.stringify(saved))
		var kept: bool = await net.restore_saved_account()
		check(kept and net.account.signed_in() and net.client.token == "saved-token", "%s: saved account is kept" % row[0])
		check(str(net.get("restore_error")) == row[2], "%s: the reason is kept for the map's notice (%s)" % [row[0], row[2]])
		var reread := AccountSession.new()
		check(reread.load_saved(path) and reread.token == "saved-token" and reread.display_name == "Ash", "%s: account file is left intact" % row[0])
	# The next check reaches the server: the notice goes away and the account is refreshed.
	var calls: Array = []
	var ok_transport := func(_m: String, u: String, _h: PackedStringArray, _b: String) -> ApiClient.Response:
		calls.append(u); return ApiClient.Response.new(true, 200, {"user_id": "u1", "player_id": "p1", "display_name": "Ash B"})
	net.client.transport = ok_transport
	check(await net.restore_saved_account() and str(net.get("restore_error")).is_empty() and calls.size() == 1 and net.account.display_name == "Ash B", "a kept account is checked again and the notice clears once the server answers")
	# Only 401 clears it.
	var gone := func(_m: String, _u: String, _h: PackedStringArray, _b: String) -> ApiClient.Response: return ApiClient.Response.new(true, 401, {"code": "UNAUTHENTICATED"})
	net.use_transport(gone, "https://restore.test/v1", path)
	_write(path, JSON.stringify(saved))
	check(not await net.restore_saved_account() and not net.account.signed_in() and net.client.token.is_empty() and not FileAccess.file_exists(path) and str(net.get("restore_error")).is_empty(), "401: saved account and its file are cleared")
	net.use_transport(gone, "https://restore.test/v1", "user://test_account.json")

## C-110: the top panel always shows who is signed in with Sign in / Sign out, selected parcel or not.
func _account_row() -> void:
	var net = root.get_node_or_null("Net")
	if net == null:
		check(false, "Net autoload is present"); return
	var path := "user://c110_row_account.json"
	var calls: Array = []
	var transport := func(method: String, url: String, headers: PackedStringArray, _b: String) -> ApiClient.Response:
		calls.append([method, url.trim_prefix("https://row.test/v1"), "authorization: Bearer row-token" in headers])
		if url.ends_with("/auth/token"): return ApiClient.Response.new(true, 200, {"ok": true})
		return ApiClient.Response.new(true, 401, {"code": "UNAUTHENTICATED"})
	net.use_transport(transport, "https://row.test/v1", path)
	var server := FakeServer.new()
	var page = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
	root.add_child(page)
	var selector := Selector.new(); root.add_child(selector)
	page._selector = selector; page._camera = CameraInput.new(); page.add_child(page._camera)
	page._framed = true; page._area_generation = selector.generation
	page._claims = controller(server, "nobody", Native.new()); page._claims.changed.connect(page._render)
	await page._claims.start()
	page._render()
	check(page._account_line.visible and page._account_line.text == page.NOT_SIGNED_IN and page._account_button.visible and page._account_button.text == "Sign in", "signed out, nothing selected: 'Not signed in' with 'Sign in'")
	page._restoring = true; page._render()
	check(page._account_line.text == page.CHECKING and not page._account_button.visible, "while the saved account is checked: 'Checking your account…' and no button")
	page._restoring = false
	net.account.adopt({"token": "row-token", "user_id": "u1", "player_id": "p1", "display_name": "Ash"}, path)
	net.client.token = "row-token"
	page._render()
	check(page._account_line.text == "Signed in as Ash" and page._account_button.text == "Sign out" and not page._account_note.visible, "signed in: 'Signed in as Ash' with 'Sign out'")
	selector.selection = Fixture.metadata(_free_ids(server, 1)[0]); selector.selection.block_id = _free_ids(server, 1)[0]
	page._render()
	check(page._account_line.visible and page._account_button.visible and page._account_button.text == "Sign out", "the account entry stays while a parcel is selected")
	net.restore_error = "HTTP_503"; page._render()
	check(page._account_note.visible and page._account_note.text == page.ACCOUNT_KEPT and page._account_button.text == "Sign out", "an account kept through a server error says so and can still sign out")
	net.restore_error = ""
	page._account_button.pressed.emit(); await process_frame
	check(page._sign_out_confirm.visible and not page._account_button.visible and net.account.signed_in(), "'Sign out' asks first; nothing is cleared yet")
	page._sign_out_confirm.get_child(1).get_child(1).pressed.emit(); await process_frame
	check(not page._sign_out_confirm.visible and page._account_button.visible and net.account.signed_in(), "'Cancel' keeps the account")
	page._account_button.pressed.emit(); await process_frame
	calls.clear()
	await page._sign_out()
	check(not net.account.signed_in() and not FileAccess.file_exists(path) and net.client.token.is_empty(), "'Sign out' clears this phone's account and its file")
	check(calls.size() >= 1 and calls[0] == ["DELETE", "/auth/token", true] and not calls.any(func(c): return c[1] == "/auth/anonymous"), "sign-out revokes this phone's token and does not sign in as a guest")
	check(page._account_line.text == page.NOT_SIGNED_IN and page._account_button.text == "Sign in", "after signing out the panel offers 'Sign in' again")
	# C-100: an install-and-play package (guest_play) goes on as this installation's guest after signing out.
	net.account.adopt({"token": "row-token", "user_id": "u1", "player_id": "p1", "display_name": "Ash"}, path)
	net.client.token = "row-token"
	ProjectSettings.set_setting("sensen/dynamic_farm/guest_play", true)
	calls.clear()
	await page._sign_out()
	ProjectSettings.set_setting("sensen/dynamic_farm/guest_play", null)
	check(not net.account.signed_in() and calls.size() >= 2 and calls[0][1] == "/auth/token" and calls.any(func(c): return c[1] == "/auth/anonymous"), "with guest_play, sign-out revokes the account token and signs in as this installation's guest")
	page.queue_free(); selector.queue_free()
	await process_frame
	net.use_transport(transport, "https://row.test/v1", "user://test_account.json")

## C-110: the map opens on the player's home, waits for the account and home before the first framing, never moves
## a camera the player moved, and "My home" brings the camera back.
func _home_framing() -> void:
	var server := FakeServer.new()
	var home_id: String = _free_ids(server, 1)[0]
	var home_center := [-122.4101, 37.7801]
	await ClaimApi.new(server.client("fake-a")).claim(home_id, home_center)
	var area := [-122.4519, 37.7294]
	var make := func(token: String) -> Array:
		var page = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
		root.add_child(page)
		var selector := Selector.new(); root.add_child(selector)
		selector.manifest = {"native_map": {"minzoom": 16, "center": area, "initial_zoom": 16.5}}
		page._selector = selector; page._camera = CameraInput.new(); page.add_child(page._camera)
		page._camera.user_moved.connect(func(): page._player_moved = true)
		page._area_generation = selector.generation
		page._claims = controller(server, token, Native.new()); page._claims.changed.connect(page._render)
		page._camera.frame_center(-122.50, 37.80, 15.0) # Wherever the native map happened to start.
		return [page, selector]
	var near := func(camera: Control, point: Array, zoom: float) -> bool:
		return absf(camera.center[0] - point[0]) < 1e-6 and absf(camera.center[1] - point[1]) < 1e-6 and is_equal_approx(camera.zoom, zoom)
	var pair: Array = make.call("fake-a")
	var page = pair[0]
	page._restoring = true; page._render()
	check(not page._framed and near.call(page._camera, [-122.50, 37.80], 15.0), "the first framing waits while the saved account is checked")
	page._restoring = false
	await page._claims.start()
	check(page._framed and near.call(page._camera, home_center, page.HOME_ZOOM), "with a home, the map opens on the home")
	check(page._home.visible and not page._home.disabled and page._places.visible, "'My home' is shown for a player with a home")
	page._camera.frame_center(-122.43, 37.76, 16.0); page._camera.user_moved.emit()
	page._render()
	check(near.call(page._camera, [-122.43, 37.76], 16.0), "later renders do not pull a moved camera back")
	page._home.pressed.emit()
	check(near.call(page._camera, home_center, page.HOME_ZOOM), "'My home' brings the camera back to the home")
	# Back from the parcel: the same map page keeps the player's view.
	page._camera.frame_center(-122.42, 37.77, 17.0); page._camera.user_moved.emit()
	await page._claims.start(); page._render()
	check(near.call(page._camera, [-122.42, 37.77], 17.0), "re-reading the home after a return does not reframe")
	page.queue_free(); pair[1].queue_free()
	# No home: the dataset's area.
	pair = make.call("fake-b")
	page = pair[0]
	await page._claims.start()
	check(page._framed and near.call(page._camera, area, 16.5) and not page._home.visible, "without a home, the map opens on the dataset's area and has no 'My home'")
	page.queue_free(); pair[1].queue_free()
	# The player moved before the home was known: their view is kept.
	pair = make.call("fake-a")
	page = pair[0]
	page._camera.frame_center(-122.44, 37.75, 17.0); page._camera.user_moved.emit()
	await page._claims.start()
	check(near.call(page._camera, [-122.44, 37.75], 17.0) and page._home.visible, "a camera the player already moved is not taken over; 'My home' is still offered")
	page.queue_free(); pair[1].queue_free()
	# A home that becomes known after the first framing (sign-in, retried read) is framed once.
	pair = make.call("nobody")
	page = pair[0]
	await page._claims.start()
	check(page._framed and near.call(page._camera, area, 16.5), "signed out: the dataset's area")
	page._claims.api.client.token = "fake-a"
	page._account_changed(); await process_frame; await process_frame
	check(near.call(page._camera, home_center, page.HOME_ZOOM), "after signing in the map moves to the new account's home")
	page.queue_free(); pair[1].queue_free()
	await process_frame

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text); f.close()

## C-100 install-and-play: Net.dynamic_farm_sign_in signs in anonymously only with guest_play and only when no saved
## account was restored; a restored account is never replaced by a guest, and an existing guest token is reused.
func _guest_play_sign_in() -> void:
	var net = root.get_node_or_null("Net")
	if net == null:
		check(false, "Net autoload is present"); return
	var calls: Array = []
	var transport := func(method: String, url: String, headers: PackedStringArray, body: String) -> ApiClient.Response:
		var path := url.trim_prefix("https://guest.test/v1")
		calls.append([method, path])
		if path == "/auth/anonymous":
			var key = JSON.parse_string(body).get("install_key", "") if JSON.parse_string(body) is Dictionary else ""
			return ApiClient.Response.new(true, 200, {"player_id": "g-" + str(key).left(6), "token": "guest-token"})
		if path == "/users/me":
			return ApiClient.Response.new(true, 200, {"user_id": "u1", "player_id": "p1"}) if "authorization: Bearer saved-token" in headers else ApiClient.Response.new(true, 401, {"code": "UNAUTHENTICATED"})
		return ApiClient.Response.new(true, 404, {"code": "NOT_FOUND"})
	var path := "user://c100_guest_account.json"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	net.use_transport(transport, "https://guest.test/v1", path)
	check(not await net.dynamic_farm_sign_in(true, false) and calls.is_empty() and net.client.token.is_empty(), "without guest_play nothing signs in anonymously")
	check(await net.dynamic_farm_sign_in(true, true) and net.client.token == "guest-token", "with guest_play and no saved account the installation signs in as a guest")
	check(calls.size() == 1 and calls[0] == ["POST", "/auth/anonymous"], "the guest sign-in is one anonymous login with the installation key")
	calls.clear()
	check(await net.dynamic_farm_sign_in(true, true) and calls.is_empty(), "an existing guest token is reused, not signed in again")
	net.use_transport(transport, "https://guest.test/v1", path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"token": "saved-token", "user_id": "u1", "player_id": "p1"})); f.close()
	calls.clear()
	check(await net.dynamic_farm_sign_in(true, true) and net.client.token == "saved-token", "a saved account wins over guest play")
	check(calls.all(func(c): return c[1] != "/auth/anonymous"), "no anonymous login when the account was restored")
	net.use_transport(transport, "https://guest.test/v1", path)
	calls.clear()
	check(await net.dynamic_farm_sign_in(false, true) and net.client.token == "guest-token", "a package that does not restore accounts plays as a guest")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
