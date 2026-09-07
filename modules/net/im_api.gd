class_name ImApi
extends RefCounted
## D3 IM 的客户端（server/README.md「IM」）。返回格式同 AccountApi.wrap_response。
## 发消息的 client_id 由调用方生成并在重试间保持不变，服务端同 client_id 重放返回原消息。

var client: ApiClient

func _init(p_client: ApiClient) -> void:
	client = p_client

func open_dm(user_id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/im/dm", {"user_id": user_id}))

func create_group(title: String, member_ids: Array) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/im/groups", {"title": title, "member_ids": member_ids}))

func add_members(conversation_id: String, user_ids: Array) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/im/groups/%s/members" % conversation_id.uri_encode(), {"user_ids": user_ids}))

func leave_group(conversation_id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("DELETE", "/im/groups/%s/members/me" % conversation_id.uri_encode()))

func conversations() -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", "/im/conversations"))

## 历史：seq 倒序；before_seq <= 0 表示从最新开始。
func messages(conversation_id: String, before_seq := 0, limit := 30) -> Dictionary:
	var q := "?limit=%d" % limit
	if before_seq > 0:
		q += "&before_seq=%d" % before_seq
	return AccountApi.wrap_response(await client.request("GET", "/im/conversations/%s/messages%s" % [conversation_id.uri_encode(), q]))

func send_text(conversation_id: String, text: String, client_id := "") -> Dictionary:
	var cid := client_id if not client_id.is_empty() else ApiClient.new_idempotency_key()
	return AccountApi.wrap_response(await client.request("POST", "/im/conversations/%s/messages" % conversation_id.uri_encode(), {"client_id": cid, "kind": "text", "text": text}))

func send_image(conversation_id: String, image: Dictionary, caption := "", client_id := "") -> Dictionary:
	var cid := client_id if not client_id.is_empty() else ApiClient.new_idempotency_key()
	var body := {"client_id": cid, "kind": "image", "image": image}
	if not caption.is_empty():
		body["text"] = caption
	return AccountApi.wrap_response(await client.request("POST", "/im/conversations/%s/messages" % conversation_id.uri_encode(), body))

func mark_read(conversation_id: String, seq: int) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/im/conversations/%s/read" % conversation_id.uri_encode(), {"seq": seq}))

func delete_message(message_id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("DELETE", "/im/messages/%s" % message_id.uri_encode()))

## 增量同步：since 之后的 inbox 事件 + latest_seq。
func sync(since: int, limit := 200) -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", "/im/sync?since=%d&limit=%d" % [maxi(since, 0), limit]))
