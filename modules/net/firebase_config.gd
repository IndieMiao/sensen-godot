class_name FirebaseConfig
extends RefCounted
## Firebase 项目配置读取。优先 user://firebase.json（开发机覆盖，不进包），其次 res://config/firebase.json
## （CI 出包时由 R 模块注入；仓库只提交 firebase.example.json）。Web API key 是公开标识不是密钥，
## 但按 SSLAUNCH D9 台账规矩仍不入库。

const USER_PATH := "user://firebase.json"
const RES_PATH := "res://config/firebase.json"

static func load_config() -> Dictionary:
	for path in [USER_PATH, RES_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and not str(parsed.get("api_key", "")).is_empty():
			return parsed
	return {}

static func api_key() -> String:
	return str(load_config().get("api_key", ""))

## Google 登录用的 Web client ID（Android Credential Manager 的 serverClientId；iOS 走 Apple 为主）。
## 由 Firebase 开启 Google 提供方时自动生成；client secret 只存在 Firebase 侧，绝不进客户端。
static func google_web_client_id() -> String:
	return str(load_config().get("google_web_client_id", ""))
