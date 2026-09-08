class_name Scrub
extends RefCounted
## E2 数据卫生：任何要离开设备的诊断数据（崩溃报告、埋点、日志）都先过这里。
##
## 两条硬规矩（08-30 调研 §5 与合规 R8 数据流说明）：
## 1. **位置不出设备**——除了 B5 的好友位置接口本身。经纬度绝不进埋点 / 崩溃上下文。
## 2. **消息与 UGC 正文不出设备**——聊天内容、动态正文、评论、图注一律不带。
## 剩下的按键名与文本模式兜一层：邮箱、token、Authorization、长数字串。

## 命中即整值替换的键（大小写与下划线不敏感）。
const DROP_KEYS := [
	"lat", "lng", "latitude", "longitude", "accuracy_m", "coords", "coordinate", "address",
	"text", "body", "message", "comment", "caption", "content", "bio", "display_name",
	"email", "phone", "password", "id_token", "refresh_token", "access_token", "token",
	"authorization", "api_key", "apikey", "secret", "dsn",
]
const REDACTED := "[redacted]"

static func _norm(key: String) -> String:
	return key.to_lower().replace("_", "").replace("-", "")

static func is_sensitive_key(key: String) -> bool:
	var k := _norm(key)
	for candidate in DROP_KEYS:
		if k == _norm(candidate):
			return true
	return false

## 文本里的邮箱、Bearer token、经纬度对、超长数字串一律打码。
static func text(s: String) -> String:
	if s.is_empty():
		return s
	var out := s
	out = _sub(out, "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", REDACTED)
	out = _sub(out, "(?i)bearer\\s+[A-Za-z0-9._~+/-]+=*", "Bearer " + REDACTED)
	out = _sub(out, "(?i)(eyJ)[A-Za-z0-9._-]{20,}", REDACTED) # JWT
	out = _sub(out, "-?\\d{1,3}\\.\\d{4,}\\s*,\\s*-?\\d{1,3}\\.\\d{4,}", REDACTED) # 经纬度对
	out = _sub(out, "\\d{9,}", REDACTED)
	return out

static func _sub(s: String, pattern: String, with: String) -> String:
	var re := RegEx.create_from_string(pattern)
	return re.sub(s, with, true) if re != null else s

## URL 只留 scheme + host + path；query 里常有游标 / token。
static func url(u: String) -> String:
	var q := u.find("?")
	return u if q < 0 else u.substr(0, q) + "?[redacted]"

## 递归清洗字典 / 数组：敏感键整值替换，字符串值再过一遍模式匹配。
static func payload(value: Variant, depth := 0) -> Variant:
	if depth > 8:
		return REDACTED
	if value is Dictionary:
		var out := {}
		for k in (value as Dictionary):
			var key := str(k)
			out[key] = REDACTED if is_sensitive_key(key) else payload((value as Dictionary)[k], depth + 1)
		return out
	if value is Array:
		var arr := []
		for v in (value as Array):
			arr.append(payload(v, depth + 1))
		return arr
	if value is String:
		return text(value as String)
	return value
