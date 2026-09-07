class_name SafetyApi
extends RefCounted
## E1 / D6 的客户端：举报、拉黑、解除拉黑、拉黑列表（server/README.md「审核、举报、拉黑、封禁」）。
## 返回格式同 AccountApi.wrap_response。

## 与服务端 REPORT_REASONS 一致；顺序就是菜单顺序。
const REASONS: PackedStringArray = ["spam", "harassment", "sexual", "violence", "hate", "self_harm", "minor_safety", "other"]

var client: ApiClient

func _init(p_client: ApiClient) -> void:
	client = p_client

## target_type: post / comment / user。
func report(target_type: String, target_id: String, reason: String, detail := "") -> Dictionary:
	var body := {"target_type": target_type, "target_id": target_id, "reason": reason}
	if not detail.is_empty():
		body["detail"] = detail
	return AccountApi.wrap_response(await client.request("POST", "/reports", body))

func block(user_id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("PUT", "/users/%s/block" % user_id.uri_encode()))

func unblock(user_id: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("DELETE", "/users/%s/block" % user_id.uri_encode()))

func blocks() -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", "/users/me/blocks"))
