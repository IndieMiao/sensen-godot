class_name VoiceApi
extends RefCounted
## D5 语音房的客户端（server/README.md「语音房」）。返回格式同 AccountApi.wrap_response。
##
## 关键约定：**能不能说话不由客户端决定**——每次上下麦、被静音、续期，服务端都会返回一把
## 新的 LiveKit token，客户端拿新 token 重连即可；token 里的 canPublish 就是麦克风闸门。

var client: ApiClient

func _init(p_client: ApiClient) -> void:
	client = p_client

func rooms() -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", "/voice/rooms"))

func create_room(title: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/voice/rooms", {"title": title}))

func join(room_id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/voice/rooms/%s/join" % room_id.uri_encode()))

func leave(room_id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/voice/rooms/%s/leave" % room_id.uri_encode()))

## 自己上下麦；房主可以带 user_id 把别人请下麦。
func set_stage(room_id: String, on: bool, user_id := "") -> Dictionary:
	var body := {"on": on}
	if not user_id.is_empty():
		body["user_id"] = user_id
	return AccountApi.wrap_response(await client.request("POST", "/voice/rooms/%s/stage" % room_id.uri_encode(), body))

## 房主静音 / 解除某人（举报即静音也走这条）。
func set_muted(room_id: String, user_id: String, muted: bool) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/voice/rooms/%s/mute" % room_id.uri_encode(),
		{"user_id": user_id, "muted": muted}))

## 续一把 token（到期前换）。
func refresh_token(room_id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/voice/rooms/%s/token" % room_id.uri_encode()))
