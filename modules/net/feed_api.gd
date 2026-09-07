class_name FeedApi
extends RefCounted
## D4-b feed 的客户端（server/README.md「feed」）。返回格式同 AccountApi.wrap_response。

var client: ApiClient

func _init(p_client: ApiClient) -> void:
	client = p_client

## 时间线 = 我 + 我关注的人；{items, next_cursor}。
func timeline(cursor := "", limit := 20) -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", ProfileApi._paged("/feed", cursor, limit)))

func posts_of(id: String, cursor := "", limit := 20) -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", ProfileApi._paged("/users/%s/posts" % id.uri_encode(), cursor, limit)))

## 发帖。idempotency_key 由调用方生成并在重试间保持不变，服务端同 key 重放返回原帖。
func create_post(text: String, images: Array = [], idempotency_key := "") -> Dictionary:
	var key := idempotency_key if not idempotency_key.is_empty() else ApiClient.new_idempotency_key()
	var body := {"idempotency_key": key, "text": text}
	if not images.is_empty():
		body["images"] = images
	return AccountApi.wrap_response(await client.request("POST", "/posts", body))

func get_post(id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", "/posts/%s" % id.uri_encode()))

func delete_post(id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("DELETE", "/posts/%s" % id.uri_encode()))

func like(id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("PUT", "/posts/%s/like" % id.uri_encode()))

func unlike(id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("DELETE", "/posts/%s/like" % id.uri_encode()))

func comments(id: String, cursor := "", limit := 20) -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", ProfileApi._paged("/posts/%s/comments" % id.uri_encode(), cursor, limit)))

func add_comment(id: String, text: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("POST", "/posts/%s/comments" % id.uri_encode(), {"text": text}))

func delete_comment(id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("DELETE", "/comments/%s" % id.uri_encode()))
