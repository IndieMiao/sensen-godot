class_name AccountApi
extends RefCounted
## D2 账号服务的客户端（server/src/http/app.ts 的 /v1/auth/firebase 等五条）。
##
## 服务端每个请求都校验 Firebase ID token，而 ApiClient 的 Bearer 正是 AuthSession 里的
## id_token，所以这里不用再传 token，也没有第二套会话要管。返回统一是
## {ok, status, code, reason, ...body}：ok=false 时 code 为服务端错误码，网络层失败为 NETWORK。
##
## Dev 会话（provider=dev）没有真 token，调用方自己跳过；这里不判断。

var client: ApiClient

func _init(p_client: ApiClient) -> void:
	client = p_client

## 登录后把 Firebase 身份映射到自有 user id。首次 201 created=true。
func sign_in() -> Dictionary:
	return _wrap(await client.request("POST", "/auth/firebase"))

func me() -> Dictionary:
	return _wrap(await client.request("GET", "/users/me"))

## 应用内删号：服务端级联（资料 / IM / feed / …）。幂等：没账号也 200 deleted=false。
func delete_account() -> Dictionary:
	return _wrap(await client.request("DELETE", "/users/me"))

## CCPA / GDPR 访问请求：一份 JSON。
func export_data() -> Dictionary:
	return _wrap(await client.request("GET", "/users/me/export"))

static func _wrap(r: ApiClient.Response) -> Dictionary:
	if not r.ok:
		return {"ok": false, "status": 0, "code": "NETWORK", "reason": r.error}
	var body: Dictionary = r.json if r.json is Dictionary else {}
	var out := body.duplicate()
	out["status"] = r.status
	if r.status >= 200 and r.status < 300:
		out["ok"] = true
		return out
	out["ok"] = false
	out["code"] = str(body.get("code", "HTTP_%d" % r.status))
	out["reason"] = str(body.get("reason", ""))
	return out
