class_name FirebaseAuth
extends RefCounted
## Firebase Authentication 的 REST 封装（08-30 调研 §4.1：Godot 没有官方 SDK，走 Identity Toolkit REST；
## 原生插件拿到 Apple / Google id_token 后一次 POST signInWithIdp 直换会话）。
##
## 只做协议翻译，不碰 UI 与持久化：每个方法返回统一字典
##   {ok, code, user_id, email, id_token, refresh_token, expires_in_s, is_new_user}
## 失败时 code 为 Firebase 的错误标识（EMAIL_NOT_FOUND / INVALID_PASSWORD / …）、HTTP_<status>
## 或传输层文本。refresh() 额外遵守 AuthSession.refresher 契约（多一个 fatal 字段）。
##
## transport 与 ApiClient 同签名，测试复用 FakeTransport。

const IDENTITY_BASE := "https://identitytoolkit.googleapis.com/v1"
const TOKEN_BASE := "https://securetoken.googleapis.com/v1"
## 这些刷新失败意味着刷新令牌本身作废，应登出而不是稍后重试。
const FATAL_REFRESH_CODES := ["TOKEN_EXPIRED", "USER_DISABLED", "USER_NOT_FOUND", "INVALID_REFRESH_TOKEN", "INVALID_GRANT_TYPE", "MISSING_REFRESH_TOKEN"]

var api_key := ""
var identity_base := IDENTITY_BASE
var token_base := TOKEN_BASE
## transport.call(method, url, headers, body_text) -> ApiClient.Response
var transport: Callable

func _init(p_api_key := "", p_transport := Callable()) -> void:
	api_key = p_api_key
	transport = p_transport

func configured() -> bool:
	return not api_key.is_empty()

func sign_up(email: String, password: String) -> Dictionary:
	return _session_result(await _identity("signUp", {"email": email, "password": password, "returnSecureToken": true}))

func sign_in_with_password(email: String, password: String) -> Dictionary:
	return _session_result(await _identity("signInWithPassword", {"email": email, "password": password, "returnSecureToken": true}))

## provider_id: "apple.com" / "google.com"。Apple 需把登录时用的 raw nonce 一起带上。
func sign_in_with_idp(provider_id: String, id_token: String, nonce := "") -> Dictionary:
	var post_body := "id_token=%s&providerId=%s" % [id_token.uri_encode(), provider_id.uri_encode()]
	if not nonce.is_empty():
		post_body += "&nonce=%s" % nonce.uri_encode()
	return _session_result(await _identity("signInWithIdp", {
		"postBody": post_body,
		"requestUri": "http://localhost",
		"returnIdpCredential": true,
		"returnSecureToken": true,
	}))

func send_verification_email(id_token: String) -> Dictionary:
	return _simple_result(await _identity("sendOobCode", {"requestType": "VERIFY_EMAIL", "idToken": id_token}))

func send_password_reset(email: String) -> Dictionary:
	return _simple_result(await _identity("sendOobCode", {"requestType": "PASSWORD_RESET", "email": email}))

## 登录后拉资料（M1 出口「登录 → 拿到用户资料」在后端 D2 落地前先以 Firebase 侧为准）。
func lookup(id_token: String) -> Dictionary:
	var r: ApiClient.Response = await _identity("lookup", {"idToken": id_token})
	var out := _simple_result(r)
	if out.ok:
		var users: Array = r.json.get("users", [])
		var u: Dictionary = users[0] if users.size() > 0 and users[0] is Dictionary else {}
		out["user_id"] = str(u.get("localId", ""))
		out["email"] = str(u.get("email", ""))
		out["email_verified"] = bool(u.get("emailVerified", false))
	return out

## 删号（Apple 5.1.1(v)）：Firebase 侧 accounts:delete；后端级联与 Apple token revocation 归 D2。
func delete_account(id_token: String) -> Dictionary:
	return _simple_result(await _identity("delete", {"idToken": id_token}))

## AuthSession.refresher 契约：{ok, id_token, refresh_token, expires_in_s, fatal, error}。
func refresh(refresh_token: String) -> Dictionary:
	if not configured():
		return {"ok": false, "fatal": false, "error": "NOT_CONFIGURED"}
	var r: ApiClient.Response = await _post(
		"%s/token?key=%s" % [token_base, api_key],
		"grant_type=refresh_token&refresh_token=%s" % refresh_token.uri_encode(),
		PackedStringArray(["content-type: application/x-www-form-urlencoded"]))
	if not r.is_success():
		var code := error_code(r)
		return {"ok": false, "fatal": FATAL_REFRESH_CODES.has(code), "error": code}
	return {
		"ok": true,
		"id_token": str(r.json.get("id_token", "")),
		"refresh_token": str(r.json.get("refresh_token", refresh_token)),
		"expires_in_s": int(str(r.json.get("expires_in", "3600"))),
		"user_id": str(r.json.get("user_id", "")),
		"fatal": false,
		"error": "",
	}

## Firebase 错误体 {error:{message:"EMAIL_NOT_FOUND"}}；WEAK_PASSWORD 带说明文字，只取标识部分。
static func error_code(r: ApiClient.Response) -> String:
	if not r.ok:
		return r.error if not r.error.is_empty() else "TRANSPORT"
	var err = r.json.get("error", null)
	if err is Dictionary and err.has("message"):
		var msg := str(err.message).strip_edges()
		var cut := msg.find(" ")
		return msg.substr(0, cut) if cut > 0 else msg
	return "HTTP_%d" % r.status

## 给玩家看的文案，已翻译（静态函数拿不到 Object.tr，走 TranslationServer）；调用方直接显示，不要再包 tr()。
static func describe(code: String) -> String:
	return TranslationServer.translate(describe_key(code)) % code if describe_key(code).contains("%s") else TranslationServer.translate(describe_key(code))

## 未翻译的 key（含 %s 占位），供 describe() 与 i18n 抽取。
static func describe_key(code: String) -> String:
	match code:
		"EMAIL_NOT_FOUND", "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS":
			return "Email or password is incorrect." ## i18n
		"EMAIL_EXISTS":
			return "An account with this email already exists." ## i18n
		"WEAK_PASSWORD":
			return "Password must be at least 6 characters." ## i18n
		"INVALID_EMAIL":
			return "Enter a valid email address." ## i18n
		"USER_DISABLED":
			return "This account has been disabled." ## i18n
		"TOO_MANY_ATTEMPTS_TRY_LATER":
			return "Too many attempts. Try again later." ## i18n
		"OPERATION_NOT_ALLOWED":
			return "This sign-in method is not enabled." ## i18n
		"NOT_CONFIGURED":
			return "Sign-in is not configured yet." ## i18n
		"TRANSPORT":
			return "No connection. Check your network and try again." ## i18n
	# Firebase 的业务码全是 UPPER_SNAKE；其余（HTTP_xxx、传输层文本如 "timeout" / "transport error: 3"）
	# 对玩家来说都是"网络不通"。
	if code.begins_with("HTTP_") or code != code.to_upper() or code.contains(" "):
		return "No connection. Check your network and try again." ## i18n
	return "Sign-in failed (%s)." ## i18n

func _identity(action: String, body: Dictionary) -> ApiClient.Response:
	if not configured():
		return ApiClient.Response.new(false, 0, {}, "NOT_CONFIGURED")
	return await _post("%s/accounts:%s?key=%s" % [identity_base, action, api_key], JSON.stringify(body),
		PackedStringArray(["content-type: application/json"]))

func _post(url: String, body_text: String, headers: PackedStringArray) -> ApiClient.Response:
	if not transport.is_valid():
		return ApiClient.Response.new(false, 0, {}, "no transport")
	var r = await transport.call("POST", url, headers, body_text)
	return r if r is ApiClient.Response else ApiClient.Response.new(false, 0, {}, "bad transport result")

func _session_result(r: ApiClient.Response) -> Dictionary:
	if not r.is_success():
		return {"ok": false, "code": error_code(r)}
	return {
		"ok": true,
		"code": "",
		"user_id": str(r.json.get("localId", "")),
		"email": str(r.json.get("email", "")),
		"id_token": str(r.json.get("idToken", "")),
		"refresh_token": str(r.json.get("refreshToken", "")),
		"expires_in_s": int(str(r.json.get("expiresIn", "3600"))),
		"is_new_user": bool(r.json.get("isNewUser", false)),
	}

func _simple_result(r: ApiClient.Response) -> Dictionary:
	return {"ok": r.is_success(), "code": "" if r.is_success() else error_code(r)}
