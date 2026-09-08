class_name ErrorReports
extends RefCounted
## E4 崩溃 / 错误上报（Sentry store 端点，不引 SDK）。所有内容过 Scrub：
## 位置、消息正文、token 一律不出设备（E2）。
##
## 边界要说清楚：GDScript 侧只能上报**我们自己捕获到的错误**（接口失败、装配失败、
## WS 断线原因）。引擎级崩溃（段错误 / OOM）要 sentry-godot 那个 GDExtension 才能抓，
## 那部分留在 SGODOT-64 里，等 SSLAUNCH D7 给出 org 与 DSN 之后再接。
##
## 没配 DSN 就是彻底关闭：一条不发。

const LEVELS := ["fatal", "error", "warning", "info"]
const MAX_BREADCRUMBS := 20

var dsn := ""
var release := ""
var environment := "dev"
## 注入点：func(url, headers, body) -> ApiClient.Response
var transport: Callable
var breadcrumbs: Array = []
var sent: Array = []

func _init(p_dsn := "", p_transport := Callable()) -> void:
	dsn = p_dsn if not p_dsn.is_empty() else OS.get_environment("SENSEN_SENTRY_DSN")
	transport = p_transport
	release = ProjectSettings.get_setting("application/config/version", "")
	environment = "release" if not OS.is_debug_build() else "dev"

func enabled() -> bool:
	return not dsn.is_empty()

## DSN → {url, key}；解析不了返回空字典（等于关闭）。
static func parse_dsn(raw: String) -> Dictionary:
	var re := RegEx.create_from_string("^https://([0-9a-fA-F]+)@([^/]+)/(\\d+)$")
	var m := re.search(raw.strip_edges()) if re != null else null
	if m == null:
		return {}
	return {"key": m.get_string(1), "url": "https://%s/api/%s/store/" % [m.get_string(2), m.get_string(3)]}

## 面包屑：出错前发生了什么。只留结构化的短信息，同样过脱敏。
func breadcrumb(category: String, message: String, data: Dictionary = {}) -> void:
	if not enabled():
		return
	breadcrumbs.append({
		"category": category, "message": Scrub.text(message),
		"data": Scrub.payload(data), "timestamp": Time.get_unix_time_from_system(),
	})
	if breadcrumbs.size() > MAX_BREADCRUMBS:
		breadcrumbs = breadcrumbs.slice(breadcrumbs.size() - MAX_BREADCRUMBS)

## 上报一条错误。返回是否真的发了。
func capture(message: String, context: Dictionary = {}, level := "error") -> bool:
	if not enabled():
		return false
	var target := parse_dsn(dsn)
	if target.is_empty():
		return false
	var event := {
		"message": Scrub.text(message),
		"level": level if LEVELS.has(level) else "error",
		"platform": "other",
		"release": release,
		"environment": environment,
		"tags": {"os": OS.get_name(), "godot": Engine.get_version_info().get("string", "")},
		"extra": Scrub.payload(context),
		"breadcrumbs": {"values": breadcrumbs.duplicate()},
		"timestamp": Time.get_unix_time_from_system(),
	}
	sent.append(event)
	if transport.is_valid():
		var headers := PackedStringArray([
			"content-type: application/json",
			"x-sentry-auth: Sentry sentry_version=7, sentry_key=%s, sentry_client=sensen-godot/1" % str(target.key),
		])
		var r = await transport.call(str(target.url), headers, JSON.stringify(event))
		return r != null and bool(r.ok)
	return true

## 接口失败的统一入口：URL 去 query、body 不带。
func capture_api_failure(method: String, url: String, status: int, code: String) -> bool:
	return await capture("api %s %s -> %d %s" % [method, Scrub.url(url), status, code],
		{"method": method, "url": Scrub.url(url), "status": status, "code": code},
		"warning" if status < 500 else "error")
