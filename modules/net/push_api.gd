class_name PushApi
extends RefCounted
## D7 客户端侧的设备 token 上报（server/README.md「推送」）。真正拿 token 要 C2 原生插件；
## 这里只负责「拿到了就报上去 / 登出时注销」，插件没到位时调用方拿不到 token，什么也不发。

var client: ApiClient

func _init(p_client: ApiClient) -> void:
	client = p_client

## platform: "ios" | "android"。
func register(token: String, platform := "") -> Dictionary:
	var p := platform if not platform.is_empty() else default_platform()
	return AccountApi.wrap_response(await client.request("PUT", "/devices", {"token": token, "platform": p}))

## 登出 / 关通知时注销；只能注销自己名下的 token。
func unregister(token: String) -> Dictionary:
	return AccountApi.wrap_response(await client.request("DELETE", "/devices", {"token": token}))

static func default_platform() -> String:
	if OS.has_feature("ios"):
		return "ios"
	if OS.has_feature("android"):
		return "android"
	return "" # 桌面没有推送通道：服务端会按 SCHEMA 拒掉，调用方不该走到这里
