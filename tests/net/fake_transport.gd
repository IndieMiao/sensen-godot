class_name FakeTransport
extends RefCounted
## 脚本化的假传输：按顺序吐预设响应，并记录每次请求。
## 真 HTTPRequest 要场景树 + 真网络，409/超时/断线这些分支在真网络里没法稳定复现。

var responses: Array = []      ## 每项 {status:int, json:Dictionary} 或 {error:String}
var requests: Array = []       ## 每项 {method, url, headers, body(Dictionary)}
var _cursor := 0

func _init(p_responses: Array = []) -> void:
	responses = p_responses

func callable() -> Callable:
	return func(method: String, url: String, headers: PackedStringArray, body: String) -> ApiClient.Response:
		var parsed = JSON.parse_string(body) if not body.is_empty() else {}
		requests.append({
			"method": method, "url": url, "headers": headers,
			"body": parsed if parsed is Dictionary else {},
		})
		if _cursor >= responses.size():
			return ApiClient.Response.new(false, 0, {}, "no scripted response")
		var spec: Dictionary = responses[_cursor]
		_cursor += 1
		if spec.has("error"):
			return ApiClient.Response.new(false, 0, {}, str(spec.error))
		return ApiClient.Response.new(true, int(spec.status), spec.get("json", {}), "")

func last_body() -> Dictionary:
	return requests[-1].body if requests.size() > 0 else {}

func bodies() -> Array:
	return requests.map(func(r): return r.body)
