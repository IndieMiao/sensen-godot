class_name LocationApi
extends RefCounted
## B5 好友位置的客户端（server/README.md「好友位置」）。返回格式同 AccountApi.wrap_response。
## 上报只在地图页可见时发生（When-In-Use），由 map_page 节流；服务端只存最新一条。

var client: ApiClient

func _init(p_client: ApiClient) -> void:
	client = p_client

## 上报自己的位置；accuracy_m < 0 表示不知道精度。
func report(lat: float, lng: float, accuracy_m := -1.0) -> Dictionary:
	var body := {"lat": lat, "lng": lng}
	if accuracy_m >= 0.0:
		body["accuracy_m"] = accuracy_m
	return AccountApi.wrap_response(await client.request("PUT", "/location", body))

## 停止分享：服务端删掉我的位置，好友立刻看不到。
func stop() -> Dictionary:
	return AccountApi.wrap_response(await client.request("DELETE", "/location"))

## 互相关注的好友的最新位置 {items:[{user_id, display_name, handle, avatar, lat, lng, accuracy_m, updated_at}]}。
func friends() -> Dictionary:
	return AccountApi.wrap_response(await client.request("GET", "/friends/locations"))
