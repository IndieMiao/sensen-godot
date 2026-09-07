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


## 用户输入的一串 handle（逗号 / 空格分隔，可带 @，大小写不敏感）→ 去重后的小写 handle 列表。
static func parse_handles(raw: String) -> PackedStringArray:
	var out := PackedStringArray()
	for piece in raw.replace("，", ",").replace(",", " ").split(" ", false):
		var h := str(piece).strip_edges().trim_prefix("@").to_lower()
		if not h.is_empty() and not out.has(h):
			out.append(h)
	return out

## 一组 handle → user_id 列表；任一查不到就整体失败并报出是哪一个（missing），调用方原样提示。
func user_ids_for(handles: PackedStringArray) -> Dictionary:
	var ids: Array = []
	for h in handles:
		var p: Dictionary = await get_profile("@" + h)
		if not bool(p.get("ok", false)):
			return {"ok": false, "missing": h, "status": int(p.get("status", 0)), "code": str(p.get("code", "")), "ids": ids}
		var id := str(p.get("user_id", ""))
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
	return {"ok": true, "ids": ids}
