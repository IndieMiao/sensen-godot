class_name ProfileApi
extends RefCounted
## D4-a 资料 + 关注的客户端（server/README.md「资料与关注」）。返回格式同 AccountApi.wrap_response：
## {ok, status, code, reason, ...body}。id 参数可以是 uuid、"me" 或 "@handle"。

var client: ApiClient

func _init(p_client: ApiClient) -> void:
	client = p_client

func me() -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", "/users/me/profile"))

## patch 只放要改的字段：display_name / handle（null 清空）/ bio / avatar / following_visible。
func update(patch: Dictionary) -> Dictionary:
	return AccountApi.wrap_response(await client.request("PUT", "/users/me/profile", patch))

func get_profile(id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", "/users/%s/profile" % id.uri_encode()))

func follow(id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("PUT", "/users/%s/follow" % id.uri_encode()))

func unfollow(id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("DELETE", "/users/%s/follow" % id.uri_encode()))

func following(id: String, cursor := "", limit := 20) -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", _paged("/users/%s/following" % id.uri_encode(), cursor, limit)))

func followers(id: String, cursor := "", limit := 20) -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", _paged("/users/%s/followers" % id.uri_encode(), cursor, limit)))

## 新粉丝页：服务端读过即清未读。
func new_followers(cursor := "", limit := 20) -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", _paged("/users/me/new-followers", cursor, limit)))

static func _paged(path: String, cursor: String, limit: int) -> String:
	var q := "?limit=%d" % limit
	if not cursor.is_empty():
		q += "&cursor=%s" % cursor.uri_encode()
	return path + q
