extends SceneTree
## C-32 claim flow against the in-memory C-31 stand-in and a fake native bridge. Fake data proves the client
## logic only; it is not evidence of a real claim, a save or device rendering.
const Claims := preload("res://modules/dynamic_farm/map/claim_controller.gd")
const ClaimApi := preload("res://modules/dynamic_farm/map/claim_api.gd")
const Selection := preload("res://modules/dynamic_farm/map/selection_controller.gd")
const FakeServer := preload("res://modules/dynamic_farm/map/fake_parcel_server.gd")
const Fixture := preload("res://tests/dynamic_farm/selection_fixtures.gd")
const CameraInput := preload("res://modules/dynamic_farm/map/geo_native_camera.gd")
const OWN_FARM := "sensen/dynamic_farm/own_farm"
const LOCAL_SAVE := "sensen/dynamic_farm/local_farm_save"
const Farm := preload("res://modules/dynamic_farm/parcel_farm.gd")
const RouterFixture := preload("res://tests/dynamic_farm/app_router_fixture.gd")
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
	var zones: Array = [] # [generation, zone JSON] as sent (C-130)
	func set_starter_zone(gen: int, json: String) -> void: zones.append([gen, json])
## The map's 3D opening needs a bridge that can make the map opaque (C-115's room opens like the parcel).
class OpaqueBridge extends MapBridge:
	func supports_surface_opacity() -> bool: return true
	func set_map_occlusion_color(_rgb: String) -> bool: return true
	func set_godot_surface_opaque(_opaque: bool) -> bool: return true
class Router extends Node:
	var opened: Array = []
	func open_instance(path: String, args: Dictionary) -> void: opened.append([path, args])
	func top_instance() -> Node: return null
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
	var releases_opened: Array = []
	var releases := {} # Earlier releases still serving their farms (selection_controller.release_base).
	var homes: Array = []
	func open_farm(release := "") -> void: opened += 1; releases_opened.append(release)
	func home_release(claimed: String) -> String: return claimed if releases.has(claimed) else str(manifest.get("dataset_version", ""))
	func select_home(id: String, release: String) -> void: homes.append([id, release])
	var taps := 0
	func tap(_point: Vector2, _zoom: float) -> void: taps += 1
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
	await _earlier_release_home()
	await _no_guest_sign_in()
	await _account_gate()
	await _starter_zone()
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
	check(page._message.text == page.PICK_PREVIEW and page._hint.visible and not page._card.visible,
		"preview package, nothing selected: the hint says 'Choose a parcel to explore in 3D.' and no card shows")
	ProjectSettings.set_setting(OWN_FARM, true)
	page._render()
	check(page._message.text == page.PICK_FIRST, "no home yet, nothing selected: 'Tap a building to choose your first home.'")
	# C-88#5: the selector's idle prompt and the next step said the same thing at the top and the bottom; one line now.
	selector.message = Selection.PROMPT
	page._render()
	var said := func(text: String) -> int: return page.find_children("*", "Label", true, false).filter(func(l): return l.text == text and l.is_visible_in_tree()).size()
	check(page._message.text == page.PICK_FIRST and said.call(page.PICK_FIRST) == 1 and said.call(Selection.PROMPT) == 0,
		"with no home the map says 'Tap a building to choose your first home.' once and not the idle prompt as well")
	selector.message = Selection.QUERY_FAILED
	page._render()
	check(page._error_card.visible and page._error_line.text == Selection.QUERY_FAILED and not page._hint.visible and page._retry.visible,
		"a failed read shows its line with Retry on the load-failure card, not in the hint")
	selector.message = "Zoom in to choose a farm."
	page._render()
	check(not page._error_card.visible and page._message.text == "Zoom in to choose a farm.", "what the map is doing reads in the hint")
	selector.message = ""
	var farming_page = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
	root.add_child(farming_page)
	check(page.find_children("*", "Label", true, false).any(func(l): return l.text.begins_with("Explore and walk.")) \
		and not farming_page.find_children("*", "Label", true, false).any(func(l): return l.text.begins_with("Explore and walk.")),
		"only the preview package still says farming comes later")
	farming_page.queue_free()
	selector.selection = Fixture.metadata(ids[0]); selector.selection.block_id = ids[0]
	page._render(); await process_frame
	check(page._claim.visible and not page._claim.disabled and not page._enter.visible and page._open.visible, "free parcel shows 'Make this my first home'")
	check(page._card.visible and not page._hint.visible and page._card_tag.text == "Parcel" and page._details.text == "Not claimed"
		and page._card_name.text == str(selector.selection.name), "the parcel card names the parcel, says it is not claimed, and the hint steps aside")
	page._claim.pressed.emit()
	check(page._confirm.visible and not page._claim.visible, "claim asks for confirmation first")
	page._claim_selection(); await process_frame
	check(page._enter.visible and not page._claim.visible and not page._open.visible, "after claiming the card offers 'Enter my farm'")
	check(page._card_tag.text == "Your home" and page._details.text == "Your home" and not page._confirm.visible and not page._claim_toast.visible,
		"the claimed parcel's card reads 'Your home'")
	page._claims.message = "Could not claim. Try again."; page._render()
	check(page._claim_toast.visible and page._claim_note.text == "Could not claim. Try again.", "a claim failure shows on a toast")
	page._claims.message = ""; page._render()
	var picked: Dictionary = selector.selection
	selector.selection = {}
	page._render()
	check(page._message.text == page.PICK_HOME, "with a home, nothing selected: 'Tap your green parcel, then Enter my farm.'")
	await _map_guide(page, selector, picked)
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
	# Q-156: the server refuses a guest's give-up, so a guest (no account) has no give-up entry; signing in shows it.
	var account: AccountSession = root.get_node("Net").account
	page._sync_guest(); page._render()
	check(page._claims.guest and not page._reselect.visible and page._enter.visible, "a guest with a home sees no give-up entry")
	page._claims.abandon(); await process_frame
	check(page._claims.has_home() and not page._claims.busy, "a guest's give-up is not sent")
	account.token = "fake-a"; account.user_id = "user-a"
	page._sync_guest(); page._render()
	check(not page._claims.guest and page._reselect.visible, "after signing in the give-up entry appears")
	account.token = ""; account.user_id = ""
	selector.selection = Fixture.metadata(ids[1]); selector.selection.block_id = ids[1]
	page._render(); await process_frame
	check(not page._claim.visible and page._details.text == "You already have a home.", "a second free parcel cannot be claimed")
	selector.selection = Fixture.metadata(taken); selector.selection.block_id = taken
	page._render(); await process_frame
	check(not page._claim.visible and page._open.visible and page._details.text == "Claimed by " + FakeServer.NEIGHBOUR, "someone else's parcel is view-only with the claimer's name")
	page._claims.owners[taken].nickname = "" # An owner without a display name, or a PARCEL_TAKEN race before the re-read.
	page._render()
	check(page._details.text == "Claimed" and native.names.any(func(row): return row.block_id == taken and row.nickname == "Claimed"), "an owner without a name reads 'Claimed' on the card and on the map")
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
	check(guest.status(ids[1]) == "unknown" and page._details.text == "Sign in to claim a home." and not page._claim.visible, "signed-out player sees 'Sign in to claim a home.' even though ownership can't be read")
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

## C-61: the card names the next step done off the parcel (the home's save). C-115: Market and Carpenter are gone; the
## Washington Square pin opens its place card and Go opens the 3D room through the router, with the home's parcel save.
func _map_guide(page: Control, selector: Node, home_pick: Dictionary) -> void:
	var home := str(page._claims.mine.parcel_id)
	var carrot := {"v": 1, "house": {"x": 4, "y": 4, "width": 3, "depth": 3, "rotation": 0}, "cleared": [], "tilled": [],
		"crops": {}, "bag": {"crop_carrot": 1}, "welcomed_at": 0}
	page.home_farm = Farm.normalize(carrot); page._farm_parcel = "p-elsewhere"
	page._render()
	check(page._message.text == page.PICK_HOME, "a save of another parcel says nothing about this home")
	page._farm_parcel = home
	# C-175: past the first sale, 0.4.5's steps (the coop, its egg, Scott's upgrade); those done on the parcel say PICK_HOME.
	var coop := {"id": 2, "type": "coop", "model": "chicken_yard", "x": 20, "y": 20, "width": 7, "depth": 5, "rotation": 0, "built_at": 1}
	var claimed := {"sales": 1, "bag": {}, "blueprints_claimed": {"coop": 1}}
	var lines := [[{}, "Tap Washington Square to sell your carrot."],
		[{"sales": 1, "bag": {}}, "Tap Washington Square to get your coop blueprint."],
		[claimed.merged({"bag": {"blueprint_coop": 1}}, true), page.PICK_HOME],
		[claimed.merged({"buildings": [coop]}, true), "Tap Washington Square to buy Carrot Seeds."],
		[claimed.merged({"buildings": [coop], "bag": {"crop_carrot": 1}}, true), page.PICK_HOME],
		[claimed.merged({"buildings": [coop], "drop_seq": 1, "bag": {"egg": 1}}, true), "Tap Washington Square to sell your egg."],
		[claimed.merged({"buildings": [coop], "drop_seq": 1}, true), "Enter my farm and gather Timber and Stone."],
		[claimed.merged({"buildings": [coop], "drop_seq": 1, "bag": {"wood": 6, "stone": 4}, "coins": 35}, true), "Enter my farm and grow carrots or collect eggs to sell."],
		[claimed.merged({"buildings": [coop], "drop_seq": 1, "bag": {"wood": 6, "stone": 4, "crop_carrot": 2}, "coins": 35}, true), "Tap Washington Square to sell carrots and eggs for coins."],
		[claimed.merged({"buildings": [coop], "drop_seq": 1, "bag": {"wood": 6, "stone": 4}, "coins": 40}, true), "Tap Washington Square to upgrade your farm."],
		[claimed.merged({"buildings": [coop], "drop_seq": 1, "level": 2}, true), page.PICK_HOME]]
	for row: Array in lines:
		var save: Dictionary = carrot.duplicate(true)
		save.merge(row[0], true)
		page.home_farm = Farm.normalize(save)
		page._render()
		check(page._message.text == row[1], "nothing selected, %s: '%s' (got '%s')" % [row[0], row[1], page._message.text])
	page.home_farm = Farm.normalize(carrot)
	selector.selection = home_pick
	page._render()
	check(page._details.text == "Your home" and page._guide.visible and page._guide.text == "Tap Washington Square to sell your carrot.", "the home selected: its card adds the next step")
	selector.selection = {}
	page._render(); await process_frame
	check(not page.find_children("*", "Button", true, false).any(func(b): return b.text in ["Market", "Carpenter", "Loading…"]),
		"the map has no Market or Carpenter button")
	var entry: Control = page._entry
	page._camera.frame_center(entry.LON, entry.LAT, 17.5)
	page._render(); await process_frame
	var at: Vector2 = entry.screen_point()
	check(entry.visible and entry.pin.visible and entry.pin.text == "Washington Square", "the Washington Square pin shows in San Francisco")
	check(at.distance_to(page._camera.size * 0.5) < 1.0, "the pin stands on its own spot (here the map's centre)")
	var taps: int = selector.taps
	page._on_map_tap((at + Vector2(0, 200)) / page._camera.size)
	check(selector.taps == taps + 1 and not entry.is_open(), "a tap elsewhere still picks a building")
	page._on_map_tap((at - Vector2(0, 16)) / page._camera.size)
	await process_frame
	check(selector.taps == taps + 1 and entry.is_open() and not page._bottom.visible, "a tap on the pin opens its place card instead")
	check(not page._locate.visible and not page._profile_button.visible and not page._home.visible,
		"the round locate, My home and profile keys step aside for the card")
	var labels: Array = entry.card.find_children("*", "Label", true, false).map(func(l): return l.text)
	check(labels.has("Washington Square Travel Post") and labels.has("Market · Carpenter") and labels.has("Distance")
		and entry.card.find_child("Primary", true, false) != null, "the card: name, Market · Carpenter, Distance from home, Go (%s)" % [labels])
	check(page.is_back_navigation_locked() and not entry.is_open() and page._bottom.visible and page._profile_button.visible
		and page._locate.visible and page._home.visible,
		"Back closes the card first; the keys come back")
	page._camera.frame_center(entry.LON, entry.LAT + 0.0004, 17.5) # the pin low on the screen, where the card goes
	await process_frame
	var low: Vector2 = entry.screen_point()
	page._on_map_tap((low - Vector2(0, 16)) / page._camera.size)
	check(low.y > page._camera.size.y * page.PIN_CLEAR_OF_CARD and entry.is_open() and page._camera.flying(),
		"a pin low on the screen flies to the middle as its card opens")
	entry.close_card(); page._camera.stop(); page._camera.frame_center(entry.LON, entry.LAT, 17.5)
	await process_frame
	var router := Router.new()
	var real_router := RouterFixture.install(root, router)
	page._bridge = OpaqueBridge.new()
	ProjectSettings.set_setting(LOCAL_SAVE, true) # the room trades through the device save, not a server
	page._on_map_tap((at - Vector2(0, 16)) / page._camera.size)
	await process_frame
	(entry.card.find_child("Primary", true, false) as UiCommandButton).activated.emit()
	await process_frame
	var opened: Array = router.opened.back() if not router.opened.is_empty() else ["", {}]
	check(opened[0] == "res://scenes/dynamic_farm/parcel_outpost.tscn" and str(opened[1].get("parcel_id")) == home
		and opened[1].get("store") != null and opened[1].store.block_id == home and not entry.is_open(),
		"Go opens the 3D room with the home's parcel save")
	RouterFixture.restore(root, router, real_router)
	page._bridge = null
	ProjectSettings.set_setting(LOCAL_SAVE, null)
	# Without a home the card says so and has no Go.
	entry.home_center = []
	entry.open_card()
	check(entry.card.find_child("Primary", true, false) == null and entry.card.find_children("*", "Label", true, false).any(
		func(l): return l.text == "Claim a home first."), "without a home: Claim a home first., no Go")
	entry.close_card()
	page.home_farm = {}; page._farm_parcel = ""
	page._render()

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

## C-110: the account chip always shows who is signed in with Sign in / Sign out, selected parcel or not (C-106: the
## chip at the top right, C-85 ⑤ D).
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
	check(page._account_button.visible and page._account_button.text == "Sign in" and not page._avatar.visible and not page._account_button.disabled,
		"signed out, nothing selected: the chip reads 'Sign in'")
	page._restoring = true; page._render()
	check(page._account_button.text == page.BUSY_DOTS and page._account_button.disabled, "while the saved account is checked: • • • on the chip and no tap")
	page._restoring = false
	net.account.adopt({"token": "row-token", "user_id": "u1", "player_id": "p1", "display_name": "Ash"}, path)
	net.client.token = "row-token"
	page._render()
	check(page._account_button.text == "Ash" and page._avatar.visible and not page._account_toast.visible, "signed in: the chip shows the avatar and 'Ash'")
	selector.selection = Fixture.metadata(_free_ids(server, 1)[0]); selector.selection.block_id = _free_ids(server, 1)[0]
	page._render()
	check(page._account_button.visible and page._account_button.text == "Ash", "the account entry stays while a parcel is selected")
	net.restore_error = "HTTP_503"; page._render()
	check(page._account_toast.visible and page._account_note.text == page.ACCOUNT_KEPT and page._account_button.text == "Ash" and not page._account_button.disabled,
		"an account kept through a server error says so and can still sign out")
	net.restore_error = ""
	page._account_button.pressed.emit(); await process_frame
	check(page._sign_out_confirm.visible and net.account.signed_in(), "a tap on the chip asks 'Sign out on this phone?' first; nothing is cleared yet")
	var answer := func(text: String) -> Button: return page._sign_out_confirm.find_children("*", "Button", true, false).filter(func(b): return b.text == text)[0]
	check(answer.call("Sign out").theme_type_variation == UiTokens.BUTTON_CMD_DESTRUCTIVE, "'Sign out' is the danger key")
	answer.call("Cancel").pressed.emit(); await process_frame
	check(not page._sign_out_confirm.visible and page._account_button.visible and net.account.signed_in(), "'Cancel' keeps the account")
	page._account_button.pressed.emit(); await process_frame
	calls.clear()
	await page._sign_out()
	check(not net.account.signed_in() and not FileAccess.file_exists(path) and net.client.token.is_empty(), "'Sign out' clears this phone's account and its file")
	check(calls.size() >= 1 and calls[0] == ["DELETE", "/auth/token", true] and not calls.any(func(c): return c[1] == "/auth/anonymous"), "sign-out revokes this phone's token and does not sign in as a guest")
	check(page._account_button.text == "Sign in" and not page._avatar.visible and not page._sign_out_confirm.visible, "after signing out the chip offers 'Sign in' again")
	# C-146: even with C-100's old install-and-play switch left set, nothing signs in as a guest any more.
	net.account.adopt({"token": "row-token", "user_id": "u1", "player_id": "p1", "display_name": "Ash"}, path)
	net.client.token = "row-token"
	ProjectSettings.set_setting("sensen/dynamic_farm/guest_play", true)
	calls.clear()
	await page._sign_out()
	ProjectSettings.set_setting("sensen/dynamic_farm/guest_play", null)
	check(not net.account.signed_in() and calls.size() >= 1 and calls[0][1] == "/auth/token" and not calls.any(func(c): return c[1] == "/auth/anonymous"), "C-146: sign-out never signs in as a guest, whatever the old guest_play setting says")
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
	check(page._home.visible and not page._home.disabled, "'My home' is shown for a player with a home")
	page._camera.frame_center(-122.43, 37.76, 16.0); page._camera.user_moved.emit()
	page._render()
	check(near.call(page._camera, [-122.43, 37.76], 16.0), "later renders do not pull a moved camera back")
	page._home.pressed.emit()
	check(page._camera.flying(), "'My home' flies (C-112)")
	await create_timer(page._camera.FLIGHT_MAX_S + 0.3).timeout
	check(near.call(page._camera, home_center, page.HOME_ZOOM), "'My home' brings the camera back to the home")
	# C-112: farm-dev's locate key flies back to the player's home too.
	page._camera.frame_center(-122.43, 37.76, 16.0); page._camera.user_moved.emit()
	check(page._locate.visible and not page._locate.disabled and page._locate.icon != null, "the locate key is shown and enabled")
	page._locate.pressed.emit()
	await create_timer(page._camera.FLIGHT_MAX_S + 0.3).timeout
	check(near.call(page._camera, home_center, page.HOME_ZOOM), "the locate key brings the camera back to the home")
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
	page._camera.frame_center(-122.43, 37.76, 18.0); page._camera.user_moved.emit()
	page._locate.pressed.emit()
	await create_timer(page._camera.FLIGHT_MAX_S + 0.3).timeout
	check(not page._locate.disabled and near.call(page._camera, area, 16.5), "without a home, the locate key goes back to the dataset's area")
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

## C-113 Q-172: with the map on r8, a home claimed on r6 is entered in its r6 farm, from the card or from "My home"
## (r8 has no farm for a few r6 parcels, so its building may not be on the map); a home claimed on r8 enters r8.
func _earlier_release_home() -> void:
	const R6 := "sf-dynamic-farm-20261124-r6"
	const R8 := "sf-dynamic-farm-20261125-r8"
	ProjectSettings.set_setting(OWN_FARM, true)
	for case in [[R6, R6, "r6"], [R8, R8, "r8"], ["sf-dynamic-farm-20261118-r4", R8, "an unlisted r4"]]:
		var server := FakeServer.new(); server.dataset = case[0]
		var home_id: String = _free_ids(server, 1)[0]
		await ClaimApi.new(server.client("fake-a"), case[0]).claim(home_id, [-122.4101, 37.7801])
		var page = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
		root.add_child(page)
		var selector := Selector.new(); root.add_child(selector)
		selector.manifest = {"dataset_version": R8, "native_map": {"minzoom": 16, "center": [-122.45, 37.73], "initial_zoom": 16.5}}
		selector.releases = {R6: "https://old.invalid/r6/"}
		page._selector = selector; page._camera = CameraInput.new(); page.add_child(page._camera)
		page._framed = true; page._area_generation = selector.generation
		page._claims = controller(server, "fake-a", Native.new()); page._claims.changed.connect(page._render)
		await page._claims.start()
		page._home.pressed.emit()
		check(selector.homes == ([[home_id, R6]] if case[1] == R6 else []), "home claimed on %s: 'My home' %s" % [case[2],
			"also selects it from its r6 farm" if case[1] == R6 else "only flies there"])
		selector.selection = Fixture.metadata(home_id); selector.selection.block_id = home_id
		page._render()
		check(page._enter.visible, "home claimed on %s: the card offers 'Enter my farm'" % case[2])
		page._enter.pressed.emit()
		check(selector.releases_opened == [case[1]] and page._entering == home_id, "home claimed on %s: 'Enter my farm' opens its %s farm" % [case[2], "r6" if case[1] == R6 else "r8"])
		page._preview()
		check(selector.releases_opened.back() == "", "a 3D preview always reads the map's release")
		page.queue_free(); selector.queue_free()
		await process_frame
	ProjectSettings.set_setting(OWN_FARM, false)

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text); f.close()

## C-146 (no guest entry): Net.dynamic_farm_sign_in only reloads a saved account; it never signs in anonymously, with or
## without a saved account, and a package that does not restore accounts signs in as nobody.
func _no_guest_sign_in() -> void:
	var net = root.get_node_or_null("Net")
	if net == null:
		check(false, "Net autoload is present"); return
	var calls: Array = []
	var transport := func(method: String, url: String, headers: PackedStringArray, _body: String) -> ApiClient.Response:
		var path := url.trim_prefix("https://guest.test/v1")
		calls.append([method, path])
		if path == "/auth/anonymous": return ApiClient.Response.new(true, 200, {"player_id": "g1", "token": "guest-token"})
		if path == "/users/me":
			return ApiClient.Response.new(true, 200, {"user_id": "u1", "player_id": "p1"}) if "authorization: Bearer saved-token" in headers else ApiClient.Response.new(true, 401, {"code": "UNAUTHENTICATED"})
		return ApiClient.Response.new(true, 404, {"code": "NOT_FOUND"})
	var path := "user://c146_guest_account.json"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	net.use_transport(transport, "https://guest.test/v1", path)
	check(not await net.dynamic_farm_sign_in(true) and calls.is_empty() and net.client.token.is_empty(), "no saved account: nothing signs in, no anonymous login")
	check(not await net.dynamic_farm_sign_in(false) and calls.is_empty() and net.client.token.is_empty(), "a package that does not restore accounts signs in as nobody")
	_write(path, JSON.stringify({"token": "saved-token", "user_id": "u1", "player_id": "p1"}))
	check(await net.dynamic_farm_sign_in(true) and net.client.token == "saved-token" and net.account.signed_in(), "a saved account is reloaded")
	check(calls.all(func(c): return c[1] != "/auth/anonymous"), "never an anonymous login")
	net.use_transport(transport, "https://guest.test/v1", path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	net.use_transport(transport, "https://guest.test/v1", "user://test_account.json")

## C-146: a package that signs in (account_restore) opens the map only with an account. Without a saved one the map
## stands behind the sign-in panel, which has no ✕ and closes only once signed in; Back there leaves the app instead of
## opening anything; signing out takes the map and its parcels away and brings the panel back.
class GateBridge extends MapBridge:
	var visible_calls: Array = []
	var backs := 0
	func set_map_visible(v: bool) -> void: visible_calls.append(v)
	func move_task_to_back() -> bool: backs += 1; return true
class GateSelector extends Selector:
	var paused := 0
	var activated := 0
	func pause() -> void: paused += 1
	func activate() -> void: activated += 1
func _account_gate() -> void:
	var net = root.get_node_or_null("Net")
	if net == null:
		check(false, "Net autoload is present"); return
	const RESTORE := "sensen/dynamic_farm/account_restore"
	var path := "user://c146_gate_account.json"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var calls: Array = []
	var transport := func(method: String, url: String, headers: PackedStringArray, _b: String) -> ApiClient.Response:
		calls.append([method, url.trim_prefix("https://gate.test/v1")])
		if url.ends_with("/users/me") and "authorization: Bearer gate-token" in headers:
			return ApiClient.Response.new(true, 200, {"user_id": "u1", "player_id": "p1", "display_name": "Ash"})
		if url.ends_with("/auth/token"): return ApiClient.Response.new(true, 200, {"ok": true})
		return ApiClient.Response.new(true, 401, {"code": "UNAUTHENTICATED"})
	net.use_transport(transport, "https://gate.test/v1", path)
	var page = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
	root.add_child(page)
	check(not page.account_required(), "the isolated preview (no account_restore) needs no account")
	check(await page.signed_in_first() and page.find_children("*", "AccountPanel", true, false).is_empty(), "…and opens without the sign-in panel")
	ProjectSettings.set_setting(RESTORE, true)
	check(page.account_required(), "internal and release packages (account_restore) need an account")
	# No saved account: the panel, with no way past it.
	var done := {"value": null}
	var entry := func(): done.value = await page.signed_in_first()
	entry.call()
	await process_frame
	var panels: Array = page.find_children("*", "AccountPanel", true, false)
	check(panels.size() == 1 and panels[0].gate and not panels[0]._close.visible, "no saved account: the sign-in panel opens with no ✕")
	check(panels[0].mode == "sign_in" and panels[0].action_button("to_sign_up") != null, "it signs in or leads to sign-up")
	check(not page._hud.visible and page._gated and done.value == null, "the map's keys are hidden and the map does not open")
	check(not calls.any(func(c): return c[1] == "/auth/anonymous"), "nothing signs in as a guest")
	panels[0].dismiss(); await process_frame
	check(is_instance_valid(panels[0]) and not panels[0].is_queued_for_deletion() and done.value == null, "it cannot be dismissed while signed out")
	page._bridge = GateBridge.new()
	check(page.is_back_navigation_locked() and page._bridge.backs == 1 and not page._suspended and not page._leaving, "Back on the panel leaves the app; nothing of the map is opened or suspended")
	# Signing in (sign-up signs in too) closes it and the map goes on.
	net.account.adopt({"token": "gate-token", "user_id": "u1", "player_id": "p1", "display_name": "Ash"}, path)
	net.client.token = "gate-token"
	panels[0].dismiss()
	for i in 5: await process_frame
	check(done.value == true and page._hud.visible and not page._gated, "once signed in the panel closes and the map opens")
	# A saved account goes straight in.
	calls.clear()
	check(await page.signed_in_first() and page.find_children("*", "AccountPanel", true, false).is_empty(), "a saved account opens the map without the panel")
	# Signing out takes the map away and brings the panel back; signing in again loads the map for that account.
	var selector := GateSelector.new(); root.add_child(selector)
	var server := FakeServer.new()
	page._selector = selector; page._camera = CameraInput.new(); page.add_child(page._camera)
	page._framed = true; page._area_generation = selector.generation
	page._claims = controller(server, "nobody", Native.new()); page._claims.changed.connect(page._render)
	page._claims.mine = {"parcel_id": "p-1", "center": [-122.4, 37.7]}; page._claims.mine_known = true
	var bridge := GateBridge.new(); page._bridge = bridge
	var out := {"done": false}
	var leave := func(): await page._sign_out(); out.done = true
	leave.call()
	for i in 5: await process_frame
	panels = page.find_children("*", "AccountPanel", true, false)
	check(not net.account.signed_in() and panels.size() == 1 and panels[0].gate, "after signing out the sign-in panel is back, with no ✕")
	check(selector.paused == 1 and not page._claims.mine_known and page._claims.mine.is_empty() and not page._hud.visible, "the map's parcels and the player's home are gone")
	check(not page._camera.input_enabled, "the map does not move behind the panel")
	root.transparent_bg = true
	page._notification(Node.NOTIFICATION_APPLICATION_PAUSED) # Google's account picker covers the app (C-175)
	check(page._suspended and not root.transparent_bg, "leaving the app behind the panel suspends the map")
	page._notification(Node.NOTIFICATION_APPLICATION_RESUMED) # back from the picker (or the background) meanwhile
	check(selector.activated == 0 and page._gated and not page._suspended, "returning to the app keeps the panel and does not load the map")
	net.account.adopt({"token": "gate-token", "user_id": "u1", "player_id": "p1", "display_name": "Ash"}, path)
	net.client.token = "gate-token"
	panels[0].dismiss()
	for i in 5: await process_frame
	check(out.done and selector.activated == 1 and bridge.visible_calls.has(true) and page._hud.visible and not page._gated, "signing in again loads the map for that account")
	check(root.transparent_bg, "a sign-in that left the app (Google) shows the map through the viewport, not a grey screen (C-175)")
	check(not calls.any(func(c): return c[1] == "/auth/anonymous"), "no guest sign-in at any point")
	ProjectSettings.set_setting(RESTORE, null)
	page.queue_free(); selector.queue_free()
	await process_frame
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	net.use_transport(transport, "https://gate.test/v1", "user://test_account.json")

## C-130 starter zone: the server's zone (fake stand-in with the same answers) decides where a player without a home may
## claim; the map lands there, hides the claim button outside it and sends the zone to its own native layer.
const ZONE_CENTER := [-122.40732, 37.79925]
func _zone(ids: Array) -> Dictionary:
	return {"id": "north-beach", "name": "North Beach", "community_id": "sf", "dataset_version": "x",
		"boundary": [[-122.409202, 37.800444], [-122.406038, 37.800839], [-122.405498, 37.79802], [-122.408632, 37.797627], [-122.409202, 37.800444]],
		"center": ZONE_CENTER, "zoom": 17, "parcel_ids": ids}

func _starter_zone() -> void:
	var server := FakeServer.new()
	var ids := _free_ids(server, 3)
	var api := ClaimApi.new(server.client("fake-a"))
	var off: Dictionary = await api.starter_zone()
	check(off.ok and off.zone.is_empty(), "zone switched off: an empty zone")
	server.zone = _zone([ids[0], ids[1]])
	var on: Dictionary = await ClaimApi.new(server.client("nobody")).starter_zone()
	check(on.ok and on.zone.parcel_ids.has(ids[0]) and not on.zone.parcel_ids.has(ids[2]) and on.zone.zoom == 17.0, "the zone is public and parsed")
	for bad in [{"boundary": []}, {"center": [0, 99]}, {"zoom": 30}, {"parcel_ids": ["3139001"]}, {"parcel_ids": []}]:
		var broken := _zone([ids[0]]); broken.merge(bad, true)
		check(ClaimApi.parse_zone(broken).is_empty(), "a malformed zone is refused: %s" % JSON.stringify(bad))
	var outside: Dictionary = await api.claim(ids[2], [-122.45, 37.73])
	check(not outside.ok and outside.status == 403 and outside.code == "OUTSIDE_STARTER_ZONE", "the stand-in refuses a claim outside the zone like the server")
	# Controller: the zone is read with the home and sent to its own native layer for every generation.
	var native := Native.new()
	var c := controller(server, "fake-b", native)
	await c.start(); await process_frame
	check(c.zone_known and c.in_zone(ids[0]) and not c.in_zone(ids[2]), "the controller knows which parcels are in the zone")
	c.attach(4, "")
	var sent: Dictionary = JSON.parse_string(native.zones.back()[1])
	check(native.zones.back()[0] == 4 and sent.boundary.size() == 5 and sent.line_color == "#3E7D43" and sent.mask_opacity == 0.55, "the zone goes to the native layer with its style")
	var count := native.zones.size()
	c.attach(4, ids[0]); await process_frame
	check(native.zones.size() == count, "the zone is not resent for the same generation")
	c.show_zone(4)
	check(native.zones.size() == count, "nor by the marker's own entry")
	c.show_zone(6)
	check(native.zones.size() == count + 1 and native.zones.back()[0] == 6 and native.zones.back()[1] == native.zones[count - 1][1], "its own entry sends it for a generation whose parcel layers are not ready yet")
	c.attach(5, ids[0]); await process_frame
	check(native.zones.back()[0] == 5, "a new generation gets the zone again")
	await c.claim({"block_id": ids[2], "center": [-122.45, 37.73]})
	check(not c.has_home() and c.message == Claims.OUTSIDE_ZONE, "a claim outside the zone says so and gives no home")
	await process_frame
	await c.claim({"block_id": ids[0], "center": [-122.45, 37.73]})
	check(c.has_home() and c.status(ids[0]) == "mine", "a claim inside the zone gives the home")
	c.queue_free()
	var plain := Native.new()
	var unzoned := controller(FakeServer.new(), "fake-a", plain)
	await unzoned.start(); unzoned.attach(4, "")
	check(unzoned.in_zone(ids[2]) and plain.zones.back() == [4, ""], "without a zone every parcel may be claimed and the layer is cleared")
	unzoned.queue_free()
	# Map: lands on the zone without a home, offers claiming only inside it.
	var page = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
	root.add_child(page)
	var selector := Selector.new(); root.add_child(selector)
	selector.manifest = {"native_map": {"minzoom": 16, "center": [-122.4519, 37.7294], "initial_zoom": 16.5}}
	page._selector = selector; page._camera = CameraInput.new(); page.add_child(page._camera)
	page._camera.user_moved.connect(func(): page._player_moved = true)
	page._area_generation = selector.generation
	var other := FakeServer.new(); other.zone = _zone([ids[0], ids[1]])
	var page_native := Native.new()
	page._claims = controller(other, "fake-b", page_native); page._claims.changed.connect(page._render)
	page._camera.frame_center(-122.50, 37.80, 15.0)
	selector.map_ready = false # C-130 V-362: below the selectable zoom the parcel layers do not load.
	await page._claims.start(); await process_frame
	check(not page_native.zones.is_empty() and page_native.zones.back()[0] == selector.generation and not page_native.zones.back()[1].is_empty(), "the starter zone marker is drawn before the parcel layers are ready")
	check(page_native.batches.is_empty(), "parcel colours still wait for the parcel layers")
	selector.map_ready = true
	var near := func(point: Array, zoom: float) -> bool:
		return absf(page._camera.center[0] - point[0]) < 1e-6 and absf(page._camera.center[1] - point[1]) < 1e-6 and is_equal_approx(page._camera.zoom, zoom)
	check(page._framed and near.call(ZONE_CENTER, 17.0), "without a home the map opens on the starter zone")
	ProjectSettings.set_setting(OWN_FARM, true)
	selector.selection = Fixture.metadata(ids[2]); selector.selection.block_id = ids[2]
	page._render(); await process_frame
	check(not page._claim.visible and page._details.text.ends_with(Claims.OUTSIDE_ZONE) and page._open.visible, "a free parcel outside the zone: no claim button, 'Not in the starter area.', preview still offered")
	selector.selection = Fixture.metadata(ids[1]); selector.selection.block_id = ids[1]
	page._render(); await process_frame
	check(page._claim.visible and not page._details.text.ends_with(Claims.OUTSIDE_ZONE), "a free parcel inside the zone can be claimed")
	page._camera.frame_center(-122.43, 37.76, 18.0); page._camera.user_moved.emit()
	page._locate.pressed.emit()
	await create_timer(page._camera.FLIGHT_MAX_S + 0.3).timeout
	check(near.call(ZONE_CENTER, 17.0), "without a home the locate key goes back to the starter zone")
	ProjectSettings.set_setting(OWN_FARM, false)
	page.queue_free(); selector.queue_free()
	# A home outside the zone (claimed before it) is still the home: the map opens there, never on the zone.
	var before := FakeServer.new()
	var far_home := [-122.4101, 37.7801]
	await ClaimApi.new(before.client("fake-a")).claim(ids[2], far_home)
	before.zone = _zone([ids[0]])
	var kept := controller(before, "fake-a", Native.new())
	await kept.start()
	check(kept.has_home() and kept.mine.parcel_id == ids[2], "a home outside the zone is kept")
	kept.queue_free()
	await process_frame
