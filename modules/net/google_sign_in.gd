class_name GoogleSignIn
extends RefCounted
## Sign in with Google（2026-09-29）：Android 原生插件 GodotGoogleSignIn（Credential Manager）。
## 发 signIn(Web 客户端 ID, nonce 的 SHA-256)，收 google_sign_in_result(JSON)。原始 nonce 留在这边，
## 连同 ID token 发给服务端比对（与 Apple 同一约定）。

const SINGLETON := "GodotGoogleSignIn"
## Google Cloud 项目 gensen-preview 的 OAuth Web 客户端 ID（不是秘密）；服务端 GOOGLE_CLIENT_IDS 须包含它。
const DEFAULT_WEB_CLIENT := "105022638066-s710gs2tsaikbkhbtvstdino7cq661go.apps.googleusercontent.com"
## 测试与桌面预览可强制显示按钮。
static var force_available := false

static var _play_services := -1

## 插件在、且手机有可用的 Google Play 服务才显示按钮；结果缓存，避免每次重画都跨 JNI。
static func available() -> bool:
	if force_available: return true
	if not Engine.has_singleton(SINGLETON): return false
	if _play_services < 0:
		var plugin := Engine.get_singleton(SINGLETON)
		# Android plugin singletons do not report their methods through has_method(); call it directly.
		_play_services = 1 if bool(plugin.call("isAvailable")) else 0
	return _play_services == 1

static func web_client_id() -> String:
	return str(ProjectSettings.get_setting("sensen/auth/google_web_client_id", DEFAULT_WEB_CLIENT))

## 解析原生回包；返回 {ok, code, id_token, given_name, family_name, email}。
static func parse_result(payload: String) -> Dictionary:
	var data = JSON.parse_string(payload)
	if not data is Dictionary: return {"ok": false, "code": "GOOGLE_UNKNOWN"}
	if bool(data.get("ok", false)) and not str(data.get("id_token", "")).is_empty():
		return {"ok": true, "code": "", "id_token": str(data.id_token), "given_name": str(data.get("given_name", "")),
			"family_name": str(data.get("family_name", "")), "email": str(data.get("email", ""))}
	return {"ok": false, "code": str(data.get("code", "GOOGLE_UNKNOWN"))}

## 调起系统账号选择。transport 可注入：func(nonce_hash: String) -> String（测试替身，返回原生回包）。
static func authorize(nonce: String, transport: Callable = Callable()) -> Dictionary:
	if transport.is_valid(): return parse_result(await transport.call(nonce.sha256_text()))
	if not Engine.has_singleton(SINGLETON): return {"ok": false, "code": "GOOGLE_UNAVAILABLE"}
	var plugin := Engine.get_singleton(SINGLETON)
	plugin.signIn(web_client_id(), nonce.sha256_text())
	var payload = await plugin.google_sign_in_result
	return parse_result(str(payload))
