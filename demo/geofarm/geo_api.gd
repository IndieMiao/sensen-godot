extends Node
## Dedicated demo endpoint only. No P0Session, credentials, production fallback or location APIs.
var base_url := ""
var timeout_s := 12.0
var max_bytes := 24 * 1024 * 1024
var transport := Callable() # unit fixture; production uses HTTPRequest

static func valid_base(url: String) -> bool:
	return url.begins_with("https://") and url.length()>8 and not "@" in url and not "?" in url and not "#" in url

func request(path: String, body: Dictionary = {}, expected_sha256: String = "") -> Dictionary:
	if transport.is_valid(): return await transport.call(path, body)
	if not valid_base(base_url): return {"ok":false,"code":"configuration"}
	if not path.begins_with("/") or ".." in path or "?" in path: return {"ok":false,"code":"invalid_path"}
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	http.body_size_limit = max_bytes
	http.max_redirects = 0
	add_child(http)
	var headers := PackedStringArray(["Accept: application/json", "Cache-Control: no-cache"])
	var method := HTTPClient.METHOD_GET
	var payload := ""
	if not body.is_empty():
		method = HTTPClient.METHOD_POST
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	var err := http.request(base_url.trim_suffix("/")+path,headers,method,payload)
	if err != OK:
		http.queue_free()
		return {"ok":false,"code":"network"}
	var reply: Array = await http.request_completed
	http.queue_free()
	if int(reply[0]) != HTTPRequest.RESULT_SUCCESS: return {"ok":false,"code":"network"}
	var bytes:PackedByteArray=reply[3]
	if not expected_sha256.is_empty():
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
		if hash.finish().hex_encode()!=expected_sha256:return {"ok":false,"code":"integrity"}
	var parser := JSON.new() # avoid printing response fragments (claim responses must never log identity)
	if parser.parse((reply[3] as PackedByteArray).get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"ok":false,"code":"invalid_response","status":int(reply[1])}
	var value: Dictionary = parser.data
	if int(reply[1]) < 200 or int(reply[1]) >= 300:
		value["ok"] = false
		if not value.has("code"): value["code"] = "network"
	value["_http_status"] = int(reply[1])
	value["_byte_count"] = bytes.size()
	return value
