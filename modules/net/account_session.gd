class_name AccountSession
extends RefCounted
## 邮箱账号（SGODOT-135）。账号 token 与游客 token 用同一个 ApiClient：登录后换成账号
## token，登出或 token 失效就回到游客（install_key）身份。
##
## 决定 1：邮箱账户自建，大陆可用，不经 Firebase。决定 2：游客只能浏览，建农场要登录。

signal changed(signed_in: bool)

const PATH := "user://account.json"
const PASSWORD_MIN := 8

var token := ""
var user_id := ""
var player_id := ""
var email := ""
var email_verified := false

func signed_in() -> bool:
	return not token.is_empty() and not user_id.is_empty()

func load_saved(path := PATH) -> bool:
	token = ""
	user_id = ""
	player_id = ""
	email = ""
	email_verified = false
	if not FileAccess.file_exists(path): return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return false
	token = str(parsed.get("token", ""))
	user_id = str(parsed.get("user_id", ""))
	player_id = str(parsed.get("player_id", ""))
	email = str(parsed.get("email", ""))
	email_verified = bool(parsed.get("email_verified", false))
	return signed_in()

func save(path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify({"token": token, "user_id": user_id, "player_id": player_id,
		"email": email, "email_verified": email_verified}))
	f.close()
	return true

func clear(path := PATH) -> void:
	token = ""
	user_id = ""
	player_id = ""
	email = ""
	email_verified = false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## 接收服务端账号回包（注册 / 登录 / 重置 / users/me）。token 缺省时保留原 token。
func adopt(body: Dictionary, path := PATH) -> void:
	if body.has("token"): token = str(body.token)
	user_id = str(body.get("user_id", user_id))
	player_id = str(body.get("player_id", player_id))
	email = str(body.get("email", email)) if body.get("email") != null else email
	email_verified = bool(body.get("email_verified", email_verified))
	save(path)

static func valid_email(value: String) -> bool:
	var e := value.strip_edges()
	if e.length() > 254 or e.contains(" "): return false
	var at := e.find("@")
	return at > 0 and e.find(".", at + 2) > at + 1 and not e.ends_with(".")

static func valid_password(value: String) -> bool:
	return value.length() >= PASSWORD_MIN and value.length() <= 128 and not value.strip_edges().is_empty()

## 服务端错误码 → 给玩家看的一句话（英文源串，zh_CN.json 翻译）。
static func describe(code: String) -> String:
	match code:
		"INVALID_EMAIL": return "Enter a valid email address."
		"WEAK_PASSWORD": return "Use at least 8 characters for your password."
		"EMAIL_TAKEN": return "This email already has an account. Sign in instead."
		"INVALID_CREDENTIALS": return "Email or password is incorrect."
		"CODE_INVALID": return "That code is not right. Check the email and try again."
		"CODE_EXPIRED": return "That code has expired. Send a new one."
		"CODE_LOCKED": return "Too many wrong codes. Send a new one."
		"CODE_COOLDOWN": return "A code was just sent. Wait a minute before asking again."
		"RATE_LIMITED": return "Too many attempts. Try again later."
		"LOGIN_REQUIRED": return "Sign in to create your farm."
		"TRANSPORT": return "Can't reach the server. Check your connection."
	return "Something went wrong. Please try again."

## 以下接口只发请求、回 {ok, code, body}；token 切换由 NetService 负责。
static func register(client: ApiClient, p_email: String, password: String) -> Dictionary:
	return _result(await client.request("POST", "/auth/email/register", {"email": p_email.strip_edges(), "password": password}))

static func login(client: ApiClient, p_email: String, password: String) -> Dictionary:
	return _result(await client.request("POST", "/auth/email/login", {"email": p_email.strip_edges(), "password": password}))

static func request_code(client: ApiClient, p_email: String, purpose: String) -> Dictionary:
	return _result(await client.request("POST", "/auth/email/code", {"email": p_email.strip_edges(), "purpose": purpose}))

static func verify(client: ApiClient, code: String) -> Dictionary:
	return _result(await client.request("POST", "/auth/email/verify", {"code": code.strip_edges()}))

static func reset(client: ApiClient, p_email: String, code: String, password: String) -> Dictionary:
	return _result(await client.request("POST", "/auth/email/reset",
		{"email": p_email.strip_edges(), "code": code.strip_edges(), "password": password}))

static func me(client: ApiClient) -> Dictionary:
	return _result(await client.request("GET", "/users/me"))

static func delete_account(client: ApiClient, password: String) -> Dictionary:
	return _result(await client.request("DELETE", "/users/me", {"password": password}))

static func _result(r: ApiClient.Response) -> Dictionary:
	if not r.ok: return {"ok": false, "code": "TRANSPORT", "status": 0, "body": {}}
	var code := "" if r.is_success() else str(r.json.get("code", "HTTP_%d" % r.status))
	return {"ok": r.is_success(), "code": code, "status": r.status, "body": r.json}
