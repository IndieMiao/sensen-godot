class_name ApiClient
extends RefCounted
## 服务端 HTTP 封装。**不做重试策略以外的任何判断**：状态码与 JSON 原样返回，
## 由上层会话决定怎么处理。
##
## 为什么可注入 transport：真实 HTTPRequest 需要场景树、需要网络，慢且不稳定。
## 把「发一次请求」抽成一个 Callable，单测就能覆盖 409/422/超时/断线这些真网络里
## 很难稳定复现的分支。
##
## A1 补三件事（08-30 调研 §3.1 网络层）：
## - token_provider：每次请求现取 token（AuthSession.access_token），刷新后不用回填字段；
## - on_unauthorized：401 时给会话一次刷新机会，成功就用新 token 重发一次；
## - request_idempotent：带 Idempotency-Key 的写请求，传输层失败按同一把键重试，
##   业务失败（4xx/5xx 已拿到响应）不重试——服务端按键去重，重发也没用。

const DEFAULT_BASE := "https://farm.sensenjoy.cn/v1"
const TIMEOUT_S := 10.0
const INSTALL_KEY_PATH := "user://install_key.txt"

## 一次请求的结果。`ok` 只表示**传输层**成功；业务失败（4xx/5xx）时 ok 仍为 true，
## 看 `status` 与 `json.code`。
class Response extends RefCounted:
	var ok := false        ## 传输层是否拿到了响应
	var status := 0
	var json: Dictionary = {}
	var error := ""
	## 原始响应体（只有 put_bytes / get_bytes 这类原始请求会填）。
	var bytes := PackedByteArray()

	func _init(p_ok := false, p_status := 0, p_json: Dictionary = {}, p_error := "") -> void:
		ok = p_ok
		status = p_status
		json = p_json
		error = p_error

	func is_success() -> bool:
		return ok and status >= 200 and status < 300

	## 统一错误码：服务端 json.code 优先；没有就 HTTP_<status>；传输层失败给 error 文本或 TRANSPORT。
	func code() -> String:
		if not ok:
			return error if not error.is_empty() else "TRANSPORT"
		if json.has("code"):
			return str(json.code)
		return "HTTP_%d" % status

var base_url := DEFAULT_BASE
## 静态 token（农场匿名会话仍在用）。token_provider 返回非空时优先。
var token := ""
## () -> String
var token_provider: Callable
## () -> bool（可为协程）。401 时调用一次；返回 true 则用新 token 重发原请求一次。
var on_unauthorized: Callable
## 幂等重试的退避基数（秒）；测试置 0 跳过等待。
var retry_delay_s := 0.5
## transport.call(method, url, headers, body_text) -> Response
var transport: Callable
## raw_transport.call(method, url, headers, bytes) -> Response（Response.bytes 带回响应体）。
## 上传到预签名地址、读图这类不走 base_url、不带 token 的原始字节请求用它。
var raw_transport: Callable

func _init(p_base_url := DEFAULT_BASE, p_transport := Callable()) -> void:
	base_url = p_base_url
	transport = p_transport

## 首装生成 128 位随机安装密钥并持久化；之后复用。
##
## 用随机密钥而不是设备 ID：可猜的设备标识意味着任何人都能登进别人的账号
## （服务端 spec §7.1 同一条理由）。
static func install_key() -> String:
	if FileAccess.file_exists(INSTALL_KEY_PATH):
		var existing := FileAccess.get_file_as_string(INSTALL_KEY_PATH).strip_edges()
		if existing.length() == 32:
			return existing
	var bytes := Crypto.new().generate_random_bytes(16)
	var key := bytes.hex_encode()
	var f := FileAccess.open(INSTALL_KEY_PATH, FileAccess.WRITE)
	if f:
		f.store_string(key)
		f.close()
	return key

static func new_idempotency_key() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func current_token() -> String:
	if token_provider.is_valid():
		var t = token_provider.call()
		if t is String and not (t as String).is_empty():
			return t
	return token

## 协程：真实 HTTP 传输是异步的，调用方一律 `await`。
## FakeTransport 是同步的——`await` 一个非协程值会立刻返回，所以单测不受影响。
## G1-B 曾把这里写成同步，结果 e2e 只能绕开 FarmSession 直接打传输层才跑通。
func request(method: String, path: String, body: Variant = null, extra_headers: PackedStringArray = PackedStringArray()) -> Response:
	var r: Response = await _send(method, path, body, extra_headers)
	if r.ok and r.status == 401 and on_unauthorized.is_valid():
		var recovered = await on_unauthorized.call()
		if recovered is bool and recovered:
			r = await _send(method, path, body, extra_headers)
	return r

## 带幂等键的写请求。传输层失败（超时 / 断线）按同一把键重试至多 max_attempts 次；
## 一旦拿到任何 HTTP 响应就返回，不管成败。
func request_idempotent(method: String, path: String, body: Variant = null, idempotency_key := "", max_attempts := 3) -> Response:
	var key := idempotency_key if not idempotency_key.is_empty() else new_idempotency_key()
	var headers := PackedStringArray(["idempotency-key: %s" % key])
	var r: Response = null
	for attempt in range(maxi(1, max_attempts)):
		r = await request(method, path, body, headers)
		if r.ok:
			return r
		if attempt + 1 < max_attempts:
			await _backoff(attempt)
	return r

func _send(method: String, path: String, body: Variant, extra_headers: PackedStringArray) -> Response:
	var headers := PackedStringArray(["content-type: application/json"])
	var tok := current_token()
	if not tok.is_empty():
		headers.append("authorization: Bearer %s" % tok)
	for h in extra_headers:
		headers.append(h)
	# 带 content-type: application/json 却不带 body，Fastify 会报 FST_ERR_CTP_EMPTY_JSON_BODY（2026-09-07 桌面
	# QA 实例撞到）。写方法没有 body 就发 {}；GET / DELETE 照旧不带。
	var text := ""
	if body != null:
		text = JSON.stringify(body)
	elif method in ["POST", "PUT", "PATCH"]:
		text = "{}"
	if not transport.is_valid():
		return Response.new(false, 0, {}, "no transport")
	var r = await transport.call(method, base_url + path, headers, text)
	return r if r is Response else Response.new(false, 0, {}, "bad transport result")

func _backoff(attempt: int) -> void:
	var delay := retry_delay_s * float(1 << attempt)
	if delay <= 0.0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(delay).timeout

## 开发机代理：Godot 的 HTTPRequest 不读系统代理，也不读环境变量；国内开发机直连 googleapis
## 会超时。这里按 HTTPS_PROXY / HTTP_PROXY（形如 http://127.0.0.1:7890）与 NO_PROXY（逗号分隔的
## 主机后缀）决定是否走代理。生产设备上没有这些环境变量，行为不变。
## 返回 {host, port}；不走代理时 host 为空。
static func proxy_for(url: String, https_proxy_env: String, no_proxy_env: String) -> Dictionary:
	var none := {"host": "", "port": 0}
	var proxy := https_proxy_env.strip_edges()
	if proxy.is_empty():
		return none
	var target_host := url
	var scheme_end := target_host.find("://")
	if scheme_end >= 0:
		target_host = target_host.substr(scheme_end + 3)
	var slash := target_host.find("/")
	if slash >= 0:
		target_host = target_host.substr(0, slash)
	var colon := target_host.find(":")
	if colon >= 0:
		target_host = target_host.substr(0, colon)
	for raw in no_proxy_env.split(","):
		var suffix := raw.strip_edges()
		if suffix.is_empty():
			continue
		if target_host == suffix or target_host.ends_with("." + suffix.trim_prefix(".")):
			return none
	var p := proxy
	var p_scheme := p.find("://")
	if p_scheme >= 0:
		p = p.substr(p_scheme + 3)
	p = p.trim_suffix("/")
	var p_colon := p.rfind(":")
	if p_colon <= 0:
		return none
	var port := int(p.substr(p_colon + 1))
	return {"host": p.substr(0, p_colon), "port": port} if port > 0 else none

static func env_proxy_for(url: String) -> Dictionary:
	var https := OS.get_environment("HTTPS_PROXY")
	if https.is_empty():
		https = OS.get_environment("https_proxy")
	if https.is_empty():
		https = OS.get_environment("HTTP_PROXY")
	var no := OS.get_environment("NO_PROXY")
	if no.is_empty():
		no = OS.get_environment("no_proxy")
	return proxy_for(url, https, no)

## 原始字节 PUT 到任意 URL（预签名上传地址）。headers 形如 ["content-type: image/jpeg"]。
func put_bytes(url: String, headers: PackedStringArray, bytes: PackedByteArray) -> Response:
	return await _raw("PUT", url, headers, bytes)

## 原始字节 GET（读图）。
func get_bytes(url: String, headers := PackedStringArray()) -> Response:
	return await _raw("GET", url, headers, PackedByteArray())

func _raw(method: String, url: String, headers: PackedStringArray, bytes: PackedByteArray) -> Response:
	if not raw_transport.is_valid():
		return Response.new(false, 0, {}, "NO_RAW_TRANSPORT")
	return await raw_transport.call(method, url, headers, bytes)

## 真实原始字节传输：HTTPRequest.request_raw；响应是 JSON 才解析（图片字节喂给 JSON 会刷错误）。
static func make_raw_http_transport(host: Node) -> Callable:
	return func(method: String, url: String, headers: PackedStringArray, bytes: PackedByteArray) -> Response:
		var req := HTTPRequest.new()
		req.timeout = 60.0 # 上传几 MB 的图，弱网下比 API 请求慢得多
		var proxy := env_proxy_for(url)
		if not str(proxy.host).is_empty():
			req.set_https_proxy(proxy.host, int(proxy.port))
			req.set_http_proxy(proxy.host, int(proxy.port))
		host.add_child(req)
		var verb := HTTPClient.METHOD_GET
		match method:
			"PUT": verb = HTTPClient.METHOD_PUT
			"POST": verb = HTTPClient.METHOD_POST
		var err := req.request_raw(url, headers, verb, bytes)
		if err != OK:
			req.queue_free()
			return Response.new(false, 0, {}, "request failed: %d" % err)
		var result: Array = await req.request_completed
		req.queue_free()
		if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
			return Response.new(false, 0, {}, "transport error: %d" % int(result[0]))
		var r := Response.new(true, int(result[1]), {}, "")
		r.bytes = result[3]
		for h in (result[2] as PackedStringArray):
			if str(h).to_lower().begins_with("content-type:") and str(h).to_lower().contains("json"):
				var parsed = JSON.parse_string(r.bytes.get_string_from_utf8())
				if parsed is Dictionary:
					r.json = parsed
				break
		return r

## 真实传输：需要一个在场景树里的 Node 来挂 HTTPRequest。
static func make_http_transport(host: Node) -> Callable:
	return func(method: String, url: String, headers: PackedStringArray, body: String) -> Response:
		var req := HTTPRequest.new()
		req.timeout = TIMEOUT_S
		var proxy := env_proxy_for(url)
		if not str(proxy.host).is_empty():
			req.set_https_proxy(proxy.host, int(proxy.port))
			req.set_http_proxy(proxy.host, int(proxy.port))
		host.add_child(req)
		var verb := HTTPClient.METHOD_GET
		match method:
			"POST": verb = HTTPClient.METHOD_POST
			"PUT": verb = HTTPClient.METHOD_PUT
			"PATCH": verb = HTTPClient.METHOD_PATCH
			"DELETE": verb = HTTPClient.METHOD_DELETE
		var err := req.request(url, headers, verb, body)
		if err != OK:
			req.queue_free()
			return Response.new(false, 0, {}, "request failed: %d" % err)
		var result: Array = await req.request_completed
		req.queue_free()
		# result = [result_code, response_code, headers, body]
		if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
			return Response.new(false, 0, {}, "transport error: %d" % int(result[0]))
		var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
		return Response.new(true, int(result[1]), parsed if parsed is Dictionary else {}, "")
