extends GdUnitTestSuite

signal release_old_response

const FIRST_ENDPOINT := "https://first-identity-test.invalid/v1"
const SECOND_ENDPOINT := "https://second-identity-test.invalid/v1"
var _directory := ""

func before_test() -> void:
	_directory = "user://test_session_identity_" + Crypto.new().generate_random_bytes(8).hex_encode()

func after_test() -> void:
	if not DirAccess.dir_exists_absolute(_directory): return
	for name in DirAccess.get_files_at(_directory):
		DirAccess.remove_absolute(_directory.path_join(name))
	DirAccess.remove_absolute(_directory)

func _authenticated_session() -> FarmSession:
	var transport := FakeTransport.new([
		{"status": 200, "json": {"player_id": "p1", "token": "first-test-token"}},
		{"status": 200, "json": {"farm_id": "f1", "version": 4, "state": {"wallet": 30}}},
	])
	var session := FarmSession.new(ApiClient.new(FIRST_ENDPOINT, transport.callable()), _directory)
	await session.login()
	await session.refresh()
	return session

func _send_and_capture(session: FarmSession, results: Dictionary) -> void:
	results.command = await session.send("buy_seeds", {"crop": "R", "qty": 1})

func _login_and_capture(session: FarmSession, results: Dictionary) -> void:
	results.login = await session.login()

func _ensure_and_capture(session: FarmSession, results: Dictionary) -> void:
	results.created = await session.ensure_farm("shanghai", "sh_a", 2, {"lat": 31.225, "lng": 121.485})

func _refresh_and_capture(session: FarmSession, results: Dictionary) -> void:
	results.refreshed = await session.refresh()

func _frames() -> void:
	for index in 5: await get_tree().process_frame

func test_login_waits_for_previous_command_before_replacing_the_authenticated_farm() -> void:
	var session := await _authenticated_session()
	var previous_journal := session._journal.path
	var requests := []
	session.client.transport = func(method, url, _headers, _body):
		requests.append({"method": method, "url": url})
		if str(url).ends_with("/auth/anonymous"):
			return ApiClient.Response.new(true, 200, {"player_id": "p2", "token": "second-test-token"})
		if method == "POST":
			await release_old_response
			return ApiClient.Response.new(true, 200, {"farm_id": "f1", "version": 5, "state": {"wallet": 26}})
		return ApiClient.Response.new(true, 200, {"farm_id": "f2", "version": 1, "state": {"wallet": 50}})
	var results := {}
	_send_and_capture(session, results)
	_login_and_capture(session, results)
	await _frames()
	assert_int(requests.size()).is_equal(1)
	assert_bool(results.has("login")).is_false()
	release_old_response.emit()
	await _frames()
	assert_that(results).is_equal({"command": true, "login": true})
	assert_bool(await session.refresh()).is_true()
	assert_str(session.player_id).is_equal("p2")
	assert_str(session.farm_id).is_equal("f2")
	assert_int(session.version).is_equal(1)
	assert_int(session.state.wallet).is_equal(50)
	assert_bool(FileAccess.file_exists(previous_journal)).is_false()
	assert_that(requests.map(func(request): return request.url)).is_equal([
		FIRST_ENDPOINT + "/farms/me/commands", FIRST_ENDPOINT + "/auth/anonymous", FIRST_ENDPOINT + "/farms/me"])

func test_old_command_retry_keeps_its_endpoint_token_and_key_while_login_is_queued() -> void:
	var session := await _authenticated_session()
	var previous_journal := session._journal.path
	var requests := []
	var command_count := [0]
	session.client.transport = func(method, url, headers, body):
		requests.append({"method": method, "url": url, "headers": headers, "body": JSON.parse_string(body) if not str(body).is_empty() else {}})
		if str(url).ends_with("/auth/anonymous"):
			return ApiClient.Response.new(true, 200, {"player_id": "p2", "token": "second-test-token"})
		if method == "POST":
			command_count[0] += 1
			if command_count[0] == 1:
				await release_old_response
				return ApiClient.Response.new(false, 0, {}, "connection lost after commit")
			return ApiClient.Response.new(true, 200, {"outcome": "replayed", "replayed_outcome": "applied",
				"farm_id": "f1", "version": 5, "state": {"wallet": 26}})
		return ApiClient.Response.new(true, 200, {"farm_id": "f2", "version": 1, "state": {"wallet": 50}})
	var results := {}
	_send_and_capture(session, results)
	session.client.base_url = SECOND_ENDPOINT
	_login_and_capture(session, results)
	await _frames()
	assert_int(requests.size()).is_equal(1)
	release_old_response.emit()
	await _frames()
	assert_that(results).is_equal({"command": true, "login": true})
	assert_bool(await session.refresh()).is_true()
	assert_that(requests.map(func(request): return request.url)).is_equal([
		FIRST_ENDPOINT + "/farms/me/commands", FIRST_ENDPOINT + "/farms/me/commands",
		SECOND_ENDPOINT + "/auth/anonymous", SECOND_ENDPOINT + "/farms/me"])
	assert_that(requests[1].body).is_equal(requests[0].body)
	assert_bool(requests[0].headers.has("authorization: Bearer first-test-token")).is_true()
	assert_bool(requests[1].headers.has("authorization: Bearer first-test-token")).is_true()
	assert_str(session.player_id).is_equal("p2")
	assert_str(session.farm_id).is_equal("f2")
	assert_int(session.version).is_equal(1)
	assert_int(session.state.wallet).is_equal(50)
	assert_bool(FileAccess.file_exists(previous_journal)).is_false()

func test_version_conflict_retry_cannot_follow_an_endpoint_change_before_login() -> void:
	var session := await _authenticated_session()
	var requests := []
	var command_count := [0]
	session.client.transport = func(method, url, headers, body):
		requests.append({"method": method, "url": url, "headers": headers, "body": JSON.parse_string(body) if not str(body).is_empty() else {}})
		if str(url).ends_with("/auth/anonymous"):
			return ApiClient.Response.new(true, 200, {"player_id": "p2", "token": "second-test-token"})
		if method == "POST":
			command_count[0] += 1
			if command_count[0] == 1:
				await release_old_response
				return ApiClient.Response.new(true, 409, {"code": "VERSION_CONFLICT",
					"farm_id": "f1", "version": 5, "state": {"wallet": 30}})
			return ApiClient.Response.new(true, 200, {"farm_id": "f1", "version": 6, "state": {"wallet": 26}})
		return ApiClient.Response.new(true, 200, {"farm_id": "f2", "version": 1, "state": {"wallet": 50}})
	var results := {}
	_send_and_capture(session, results)
	session.client.base_url = SECOND_ENDPOINT
	_login_and_capture(session, results)
	release_old_response.emit()
	await _frames()
	assert_bool(results.get("command", false)).is_true()
	assert_bool(results.get("login", false)).is_true()
	assert_bool(await session.refresh()).is_true()
	assert_int(command_count[0]).is_equal(2)
	assert_str(requests[0].body.idempotency_key).is_not_equal(requests[1].body.idempotency_key)
	assert_int(int(requests[1].body.base_version)).is_equal(5)
	for request in requests:
		if not str(request.url).ends_with("/commands"): continue
		assert_str(request.url).is_equal(FIRST_ENDPOINT + "/farms/me/commands")
		assert_bool(request.headers.has("authorization: Bearer first-test-token")).is_true()
	assert_str(session.farm_id).is_equal("f2")
	assert_int(session.version).is_equal(1)

func test_farm_creation_keeps_its_identity_through_capability_check_and_creation() -> void:
	var auth := FakeTransport.new([{"status": 200, "json": {"player_id": "p1", "token": "first-test-token"}}])
	var session := FarmSession.new(ApiClient.new(FIRST_ENDPOINT, auth.callable()), _directory)
	await session.login()
	var requests := []
	session.client.transport = func(method, url, headers, body):
		requests.append({"method": method, "url": url, "headers": headers, "body": JSON.parse_string(body) if not str(body).is_empty() else {}})
		if str(url).ends_with("/auth/anonymous"):
			return ApiClient.Response.new(true, 200, {"player_id": "p2", "token": "second-test-token"})
		if str(url).ends_with("/regions"):
			return ApiClient.Response.new(true, 200, {"farm_placement_version": 1})
		if method == "POST":
			return ApiClient.Response.new(true, 201, {"farm_id": "f1", "version": 0, "state": {"wallet": 30}})
		if str(url).begins_with(FIRST_ENDPOINT):
			await release_old_response
			return ApiClient.Response.new(true, 404, {"code": "NO_FARM"})
		return ApiClient.Response.new(true, 200, {"farm_id": "f2", "version": 1, "state": {"wallet": 50}})
	var results := {}
	_ensure_and_capture(session, results)
	session.client.base_url = SECOND_ENDPOINT
	session.client.token = "externally-replaced-token"
	_login_and_capture(session, results)
	await _frames()
	assert_int(requests.size()).is_equal(1)
	assert_bool(results.has("login")).is_false()
	release_old_response.emit()
	await _frames()
	assert_that(results).is_equal({"created": true, "login": true})
	assert_bool(await session.refresh()).is_true()
	assert_that(requests.map(func(request): return request.url)).is_equal([
		FIRST_ENDPOINT + "/farms/me", FIRST_ENDPOINT + "/regions", FIRST_ENDPOINT + "/farms",
		SECOND_ENDPOINT + "/auth/anonymous", SECOND_ENDPOINT + "/farms/me"])
	for index in 3:
		assert_bool(requests[index].headers.has("authorization: Bearer first-test-token")).is_true()
	assert_str(requests[2].body.layout_patch_id).is_equal("sh_a")
	assert_that(requests[2].body.location).is_equal({"lat": 31.225, "lng": 121.485})
	assert_str(session.player_id).is_equal("p2")
	assert_str(session.farm_id).is_equal("f2")
	assert_int(session.version).is_equal(1)

func test_restarted_refresh_keeps_its_identity_for_initial_read_replay_and_final_read() -> void:
	var previous := await _authenticated_session()
	previous.client.transport = FakeTransport.new([{"error": "lost reply"}, {"error": "lost reply"}]).callable()
	assert_bool(await previous.send("buy_seeds", {"crop": "R", "qty": 1})).is_false()
	var journal_path := previous._journal.path
	var expected_command: Dictionary = JSON.parse_string(JSON.stringify(previous._unconfirmed_command))
	var auth := FakeTransport.new([{"status": 200, "json": {"player_id": "p1", "token": "first-test-token"}}])
	var session := FarmSession.new(ApiClient.new(FIRST_ENDPOINT, auth.callable()), _directory)
	await session.login()
	var requests := []
	var old_reads := [0]
	session.client.transport = func(method, url, headers, body):
		requests.append({"method": method, "url": url, "headers": headers, "body": JSON.parse_string(body) if not str(body).is_empty() else {}})
		if str(url).ends_with("/auth/anonymous"):
			return ApiClient.Response.new(true, 200, {"player_id": "p2", "token": "second-test-token"})
		if method == "POST":
			return ApiClient.Response.new(true, 200, {"outcome": "replayed", "replayed_outcome": "applied",
				"farm_id": "f1", "version": 5, "state": {"wallet": 26}})
		if str(url).begins_with(FIRST_ENDPOINT):
			old_reads[0] += 1
			if old_reads[0] == 1: await release_old_response
			return ApiClient.Response.new(true, 200, {"farm_id": "f1", "version": 5, "state": {"wallet": 26}})
		return ApiClient.Response.new(true, 200, {"farm_id": "f2", "version": 1, "state": {"wallet": 50}})
	var results := {}
	_refresh_and_capture(session, results)
	session.client.base_url = SECOND_ENDPOINT
	session.client.token = "externally-replaced-token"
	_login_and_capture(session, results)
	await _frames()
	assert_int(requests.size()).is_equal(1)
	assert_bool(results.has("login")).is_false()
	release_old_response.emit()
	await _frames()
	assert_that(results).is_equal({"refreshed": true, "login": true})
	assert_bool(await session.refresh()).is_true()
	assert_that(requests.map(func(request): return request.url)).is_equal([
		FIRST_ENDPOINT + "/farms/me", FIRST_ENDPOINT + "/farms/me/commands", FIRST_ENDPOINT + "/farms/me",
		SECOND_ENDPOINT + "/auth/anonymous", SECOND_ENDPOINT + "/farms/me"])
	for index in 3:
		assert_bool(requests[index].headers.has("authorization: Bearer first-test-token")).is_true()
	assert_that(requests[1].body).is_equal(expected_command)
	assert_bool(FileAccess.file_exists(journal_path)).is_false()
	assert_str(session.player_id).is_equal("p2")
	assert_str(session.farm_id).is_equal("f2")
	assert_int(session.version).is_equal(1)
	assert_int(session.state.wallet).is_equal(50)
