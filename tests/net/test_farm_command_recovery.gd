extends GdUnitTestSuite

var _directory := ""

func before_test() -> void:
	_directory = "user://test_command_journal_" + Crypto.new().generate_random_bytes(8).hex_encode()

func after_test() -> void:
	if DirAccess.dir_exists_absolute(_directory):
		for name in DirAccess.get_files_at(_directory):
			DirAccess.remove_absolute(_directory.path_join(name))
		DirAccess.remove_absolute(_directory)

func _state(version: int, farm := "f1") -> Dictionary:
	return {"farm_id": farm, "version": version, "state": {"wallet": 30 - version}}

func _pair(responses: Array, player := "p1", endpoint := "https://journal-test.invalid/v1") -> Array:
	var replies := [{"status": 200, "json": {"player_id": player, "token": "journal-test-token"}}]
	replies.append_array(responses)
	var transport := FakeTransport.new(replies)
	return [FarmSession.new(ApiClient.new(endpoint, transport.callable()), _directory), transport]

func _lose_reply(type := "cook_dish", payload := {"recipe": "salad"}) -> Array:
	var pair := _pair([{"status": 200, "json": _state(4)}, {"error": "timeout"}, {"error": "timeout"}])
	var session: FarmSession = pair[0]
	assert_bool(await session.login()).is_true()
	assert_bool(await session.refresh()).is_true()
	assert_bool(await session.send(type, payload)).is_false()
	return pair

func test_envelope_exists_before_http_and_restart_replays_it_before_allowing_another_purchase() -> void:
	var pair := _pair([{"status": 200, "json": _state(4)}])
	var first: FarmSession = pair[0]
	await first.login()
	await first.refresh()
	var journal := first._journal
	var sent := []
	first.client.transport = func(_method, _url, _headers, body):
		var envelope: Dictionary = JSON.parse_string(body)
		assert_that(journal.read_command()).is_equal(envelope)
		sent.append(envelope)
		return ApiClient.Response.new(false, 0, {}, "lost reply after commit")
	assert_bool(await first.send("buy_seeds", {"crop": "R", "qty": 2})).is_false()
	var stored := FileAccess.get_file_as_string(journal.path)
	assert_bool(stored.contains("journal-test-token")).is_false()
	assert_bool(stored.contains(ApiClient.install_key())).is_false()
	var restart := _pair([{"status": 200, "json": _state(5)},
		{"status": 200, "json": _state(5)}, {"status": 200, "json": _state(6)},
		{"status": 200, "json": _state(7)}])
	var second: FarmSession = restart[0]
	var transport: FakeTransport = restart[1]
	await second.login()
	assert_bool(await second.refresh()).is_true()
	assert_str(transport.requests[1].method).is_equal("GET")
	assert_that(transport.requests[2].body).is_equal(sent[0])
	assert_str(transport.requests[3].method).is_equal("GET")
	assert_int(second.version).is_equal(6)
	assert_bool(second.has_unconfirmed_command()).is_false()
	assert_bool(FileAccess.file_exists(journal.path)).is_false()
	assert_bool(await second.send("buy_seeds", {"crop": "R", "qty": 2})).is_true()
	assert_str(transport.requests[4].body.idempotency_key).is_not_equal(sent[0].idempotency_key)
	assert_int(int(transport.requests[4].body.base_version)).is_equal(6)

func test_restarted_conflict_resolves_without_creating_a_new_command() -> void:
	var lost := await _lose_reply()
	var original: Dictionary = (lost[1] as FakeTransport).requests[2].body
	var conflict := _state(8)
	conflict.code = "VERSION_CONFLICT"
	var pair := _pair([{"status": 200, "json": _state(8)},
		{"status": 409, "json": conflict}, {"status": 200, "json": _state(8)}])
	var session: FarmSession = pair[0]
	var transport: FakeTransport = pair[1]
	await session.login()
	assert_bool(await session.refresh()).is_true()
	assert_that(transport.requests[2].body).is_equal(original)
	assert_int(transport.requests.size()).is_equal(4)
	assert_bool(session.has_unconfirmed_command()).is_false()

func test_auth_failure_during_startup_keeps_disk_envelope_and_blocks_new_actions() -> void:
	var lost := await _lose_reply()
	var first: FarmSession = lost[0]
	var pair := _pair([{"status": 200, "json": _state(5)},
		{"status": 401, "json": {"code": "UNAUTHENTICATED"}}])
	var session: FarmSession = pair[0]
	var transport: FakeTransport = pair[1]
	await session.login()
	assert_bool(await session.refresh()).is_false()
	assert_bool(await session.send("cook_dish", {"recipe": "salad"})).is_false()
	assert_str(session.last_error_code).is_equal("PENDING_ACTION")
	assert_int(transport.requests.size()).is_equal(3)
	assert_that(session._journal.read_command()).is_equal(JSON.parse_string(JSON.stringify(first._unconfirmed_command)))

func test_other_server_player_and_farm_do_not_receive_a_saved_command() -> void:
	var lost := await _lose_reply()
	var first: FarmSession = lost[0]
	for identity in [["p1", "https://another.invalid/v1", "f1"],
			["p2", "https://journal-test.invalid/v1", "f1"],
			["p1", "https://journal-test.invalid/v1", "f2"]]:
		var pair := _pair([{"status": 200, "json": _state(4, identity[2])}], identity[0], identity[1])
		var session: FarmSession = pair[0]
		var transport: FakeTransport = pair[1]
		await session.login()
		assert_bool(await session.refresh()).is_true()
		assert_bool(session.has_unconfirmed_command()).is_false()
		assert_int(transport.requests.size()).is_equal(2)
	assert_bool(FileAccess.file_exists(first._journal.path)).is_true()

func test_installation_scope_does_not_load_another_installations_envelope() -> void:
	var first := FarmCommandJournal.new(_directory, "https://test.invalid/v1", "installation-a", "p1", "f1")
	var second := FarmCommandJournal.new(_directory, "https://test.invalid/v1", "installation-b", "p1", "f1")
	var command := {"idempotency_key": "a".repeat(32), "base_version": 4, "type": "cook_dish", "payload": {"recipe": "tea"}}
	assert_bool(first.write_command(command)).is_true()
	assert_that(second.read_command()).is_equal({})
	assert_that(first.read_command()).is_equal(JSON.parse_string(JSON.stringify(command)))

func test_authenticated_account_change_does_not_replay_the_previous_accounts_action() -> void:
	var lost := await _lose_reply()
	var session: FarmSession = lost[0]
	var old_path := session._journal.path
	var transport := FakeTransport.new([
		{"status": 200, "json": {"player_id": "p2", "token": "another-token"}},
		{"status": 200, "json": _state(1, "f2")},
	])
	session.client.transport = transport.callable()
	await session.login()
	assert_bool(await session.refresh()).is_true()
	assert_int(session.version).is_equal(1)
	assert_str(session.farm_id).is_equal("f2")
	assert_bool(session.has_unconfirmed_command()).is_false()
	assert_bool(FileAccess.file_exists(old_path)).is_true()
	assert_int(transport.requests.size()).is_equal(2)

func test_failed_journal_write_prevents_http_submission() -> void:
	var pair := _pair([{"status": 200, "json": _state(4)}])
	var session: FarmSession = pair[0]
	var transport: FakeTransport = pair[1]
	await session.login()
	await session.refresh()
	DirAccess.make_dir_recursive_absolute(_directory)
	var blocker := FileAccess.open(_directory.path_join("not-a-directory"), FileAccess.WRITE)
	blocker.close()
	session._journal.path = _directory.path_join("not-a-directory/command.json")
	assert_bool(await session.send("buy_seeds", {"crop": "R", "qty": 1})).is_false()
	assert_str(session.last_error_code).is_equal("LOCAL_STORAGE")
	assert_int(transport.requests.size()).is_equal(2)

func test_corrupt_journal_cannot_be_ignored_before_spending() -> void:
	var lost := await _lose_reply()
	var first: FarmSession = lost[0]
	var file := FileAccess.open(first._journal.path, FileAccess.WRITE)
	file.store_string("{\"format\":1,\"scope\":\"wrong-scope\"}")
	file.close()
	var pair := _pair([{"status": 200, "json": _state(5)}])
	var session: FarmSession = pair[0]
	var transport: FakeTransport = pair[1]
	await session.login()
	assert_bool(await session.refresh()).is_false()
	assert_bool(await session.send("cook_dish", {"recipe": "salad"})).is_false()
	assert_str(session.last_error_code).is_equal("LOCAL_STORAGE")
	assert_int(transport.requests.size()).is_equal(2)

func test_changing_api_endpoint_requires_authentication_before_recovery() -> void:
	var lost := await _lose_reply()
	var session: FarmSession = lost[0]
	var transport: FakeTransport = lost[1]
	session.client.base_url = "https://another.invalid/v1"
	assert_bool(await session.refresh()).is_false()
	assert_str(session.last_error_code).is_equal("SESSION_CHANGED")
	assert_int(transport.requests.size()).is_equal(4)

func test_authenticated_session_must_identify_its_farm_before_submitting() -> void:
	var pair := _pair([])
	var session: FarmSession = pair[0]
	var transport: FakeTransport = pair[1]
	await session.login()
	assert_bool(await session.send("buy_seeds", {"crop": "R", "qty": 1})).is_false()
	assert_str(session.last_error_code).is_equal("NO_FARM")
	assert_int(transport.requests.size()).is_equal(1)
