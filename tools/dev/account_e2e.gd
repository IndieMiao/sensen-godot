extends Node
## 账号 + 全球城市的客户端端到端（SGODOT-135 / 136）：真 HTTP 打本地服，不碰线上。
##
##   SENSEN_OFFLINE=1 E2E_BASE=http://127.0.0.1:3117/v1 godot --headless --path . tools/dev/account_e2e.tscn
##
## 服务端需配 QA_EMAIL_DOMAIN=qa.sensen.test、QA_EMAIL_CODE=424242。只写 e2e 专用的 user:// 文件，结束即删。

const ACCOUNT := "user://e2e_account.json"
const CACHE := "user://e2e_city_cache.json"
const TOKYO := {"lat": 35.6812, "lng": 139.7671}
var failures := 0

func _ready() -> void:
	var base := OS.get_environment("E2E_BASE") if OS.has_environment("E2E_BASE") else "http://127.0.0.1:3117/v1"
	FarmRegions.cache_path = CACHE
	_cleanup()
	Net.use_transport(ApiClient.make_http_transport(Net), base, ACCOUNT)
	# 1. Guest boot: read-only.
	_check("guest boot", await Net.boot())
	_check("starts as guest", Net.is_guest())
	var guest_farm := await Net.session.ensure_generated_farm("gn-1850147", TOKYO)
	_check("guest cannot create a farm", not guest_farm and Net.session.last_error_code == "LOGIN_REQUIRED")
	# 2. Register + verify with the QA code.
	var email := "client-e2e-%d@qa.sensen.test" % Time.get_unix_time_from_system()
	var reg := await AccountSession.register(Net.client, email, "correct horse")
	_check("register", reg.ok)
	_check("sign in with the new account", await Net.sign_in_with(reg.body))
	_check("no longer a guest", not Net.is_guest())
	var verified := await AccountSession.verify(Net.client, "424242")
	_check("verify email", verified.ok and bool(verified.body.get("email_verified", false)))
	# 3. Global city: create a farm in Tokyo from real map data.
	var created := await Net.session.ensure_generated_farm("gn-1850147", TOKYO)
	_check("create Tokyo farm (%s)" % Net.session.last_error_code, created)
	_check("server resolved Tokyo", Net.session.region_id == "gn-1850147")
	var region := await Net.ensure_city(Net.session.region_id)
	_check("city cached for the map", str(region.get("name", "")) == "Tokyo" and FarmRegions.load_default().region("gn-1850147").timezone == "Asia/Tokyo")
	_check("generated city map", CityMapData.has_city("gn-1850147") and CityMapData.city("gn-1850147").residents.size() == 3)
	var farm_id := Net.session.farm_id
	# 4. A second device logs into the same farm.
	var second := await AccountSession.login(Net.client, email, "correct horse")
	_check("second device login", second.ok and str(second.body.get("player_id")) == Net.account.player_id)
	# 5. Sign out: back to guest, farm gone from this device.
	await Net.sign_out()
	_check("signed out to guest", Net.is_guest() and not Net.session.has_farm())
	# 6. Sign back in and get the same farm back.
	var again := await AccountSession.login(Net.client, email, "correct horse")
	_check("sign back in", again.ok and await Net.sign_in_with(again.body))
	_check("same farm after sign-in", Net.session.farm_id == farm_id)
	# 7. Delete the account.
	var wrong := await Net.delete_account("wrong password")
	_check("delete refuses a wrong password", not wrong.ok and wrong.code == "INVALID_CREDENTIALS")
	var gone := await Net.delete_account("correct horse")
	_check("delete account", gone.ok and Net.is_guest())
	var after := await AccountSession.login(Net.client, email, "correct horse")
	_check("deleted account cannot sign in", not after.ok)
	_cleanup()
	print("account_e2e: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures else 0)

func _check(what: String, ok: bool) -> void:
	print("account_e2e: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok: failures += 1

func _cleanup() -> void:
	for p in [ACCOUNT, CACHE]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
