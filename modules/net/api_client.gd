class_name ApiClient
extends RefCounted
## 服务端 HTTP 封装。**不做重试策略以外的任何判断**：状态码与 JSON 原样返回，
## 由 FarmSession 决定怎么处理。
##
## 为什么可注入 transport：真实 HTTPRequest 需要场景树、需要网络、慢且不稳定。
## 把「发一次请求」抽成一个 Callable，单测就能覆盖 409/422/超时/断线这些真网络里
## 很难稳定复现的分支（仓库里此前零 HTTPRequest 用例，没有现成模式可抄）。

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

	func _init(p_ok := false, p_status := 0, p_json: Dictionary = {}, p_error := "") -> void:
		ok = p_ok
		status = p_status
		json = p_json
		error = p_error

	func is_success() -> bool:
		return ok and status >= 200 and status < 300

var base_url := DEFAULT_BASE
var token := ""
## transport.call(method, url, headers, body_text) -> Response
var transport: Callable

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

## 协程：真实 HTTP 传输是异步的，调用方一律 `await`。
## FakeTransport 是同步的——`await` 一个非协程值会立刻返回，所以单测不受影响。
## G1-B 曾把这里写成同步，结果昨天 e2e 只能绕开 FarmSession 直接打传输层才跑通。
func request(method: String, path: String, body: Variant = null) -> Response:
	var headers := PackedStringArray(["content-type: application/json"])
	if not token.is_empty():
		headers.append("authorization: Bearer %s" % token)
	var text := "" if body == null else JSON.stringify(body, "", true, true)
	if not transport.is_valid():
		return Response.new(false, 0, {}, "no transport")
	var r = await transport.call(method, base_url + path, headers, text)
	return r if r is Response else Response.new(false, 0, {}, "bad transport result")

const DEBUG_LOG := "user://net_debug.log"

## 手机 debug 包的网络失败记到 user://net_debug.log，便于用 devicectl 拉回来看（iOS 上 print 取不到）。
static func debug_log(line: String) -> void:
	if not (OS.is_debug_build() and OS.has_feature("mobile")): return
	var f := FileAccess.open(DEBUG_LOG, FileAccess.READ_WRITE if FileAccess.file_exists(DEBUG_LOG) else FileAccess.WRITE)
	if f == null: return
	if f.get_length() > 200_000: return
	f.seek_end()
	f.store_line("%s %s" % [Time.get_datetime_string_from_system(), line])
	f.close()

## 真实传输：需要一个在场景树里的 Node 来挂 HTTPRequest。
static func make_http_transport(host: Node) -> Callable:
	return func(method: String, url: String, headers: PackedStringArray, body: String) -> Response:
		var req := HTTPRequest.new()
		req.timeout = TIMEOUT_S
		if method == "POST" and url.ends_with("/relocation/preview"): req.timeout = 45.0
		if method == "POST" and url.ends_with("/farms"):
			var payload = JSON.parse_string(body)
			if payload is Dictionary and payload.has("generation_version"): req.timeout = 45.0
		host.add_child(req)
		var verb := HTTPClient.METHOD_GET
		match method:
			"POST": verb = HTTPClient.METHOD_POST
			"DELETE": verb = HTTPClient.METHOD_DELETE
			"PUT": verb = HTTPClient.METHOD_PUT
		var err := req.request(url, headers, verb, body)
		if err != OK:
			req.queue_free()
			debug_log("%s %s request() err=%d" % [method, url, err])
			return Response.new(false, 0, {}, "request failed: %d" % err)
		var result: Array = await req.request_completed
		req.queue_free()
		# result = [result_code, response_code, headers, body]
		if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
			debug_log("%s %s transport result=%d" % [method, url, int(result[0])])
			return Response.new(false, 0, {}, "transport error: %d" % int(result[0]))
		var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
		return Response.new(true, int(result[1]), parsed if parsed is Dictionary else {}, "")
