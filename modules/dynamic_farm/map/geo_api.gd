extends Node
## Read-only preview transport. No installation credentials, POST or production fallback.
var base_url := ""
var transport := Callable()
var _epoch := 0
var _active: Array[HTTPRequest] = []

static func valid_base(url: String) -> bool:
	return url.begins_with("https://") and url.length() > 8 and not "@" in url and not "?" in url and not "#" in url

func request(path: String, expected_sha256 := "") -> Dictionary:
	var epoch := _epoch
	if not valid_base(base_url) or not path.begins_with("/") or ".." in path or "?" in path or "#" in path:
		return {"ok":false,"code":"configuration"}
	if transport.is_valid():
		var value: Dictionary = await transport.call(path)
		return value if epoch == _epoch else {"ok":false,"code":"superseded"}
	var http := HTTPRequest.new()
	http.timeout = 12.0
	http.body_size_limit = 2 * 1024 * 1024
	http.max_redirects = 0
	add_child(http)
	_active.append(http)
	var error := http.request(base_url.trim_suffix("/") + path, PackedStringArray(["Accept: application/json"]))
	if error != OK:
		_active.erase(http); http.queue_free()
		return {"ok":false,"code":"network"}
	var reply: Array = await http.request_completed
	_active.erase(http); http.queue_free()
	if epoch != _epoch: return {"ok":false,"code":"superseded"}
	if int(reply[0]) != HTTPRequest.RESULT_SUCCESS or int(reply[1]) != 200:
		return {"ok":false,"code":"network"}
	var bytes: PackedByteArray = reply[3]
	if not expected_sha256.is_empty():
		var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
		if hash.finish().hex_encode() != expected_sha256: return {"ok":false,"code":"integrity"}
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"ok":false,"code":"invalid_response"}
	return parser.data

func cancel_all() -> void:
	_epoch += 1
	var requests := _active.duplicate()
	_active.clear()
	for http in requests:
		if not is_instance_valid(http): continue
		http.cancel_request()
		# Wake our awaiting operation; epoch rejection happens before any consumer sees a payload.
		http.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())
