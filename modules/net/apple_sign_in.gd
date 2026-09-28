class_name AppleSignIn
extends RefCounted
## Sign in with Apple（SGODOT-135）。iOS 原生桥 tools/ios/AppleSignIn.swift 监听回环 UDP 46465：
## 发 "APPLE|<nonce 的 SHA-256>"，收 "APPLE_OK|token|名|姓|邮箱" 或 "APPLE_ERR|原因"。
## 原始 nonce 留在这边，连同 identity token 一起发给服务端比对。

const PORT := 46465
## 用户可能在系统弹窗里停很久（输密码、选隐藏邮箱），只在完全没有回音时放弃。
const TIMEOUT_S := 300.0
## 测试与非 iOS 桌面预览可强制打开按钮。
static var force_available := false

static func available() -> bool:
	return force_available or OS.get_name() == "iOS"

static func new_nonce() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()

## 解析原生回包；返回 {ok, code, identity_token, given_name, family_name, email}。
static func parse_reply(line: String) -> Dictionary:
	var p := line.strip_edges().split("|", true)
	if p.size() >= 2 and p[0] == "APPLE_OK" and not p[1].is_empty():
		return {"ok": true, "code": "", "identity_token": p[1],
			"given_name": p[2].strip_edges() if p.size() > 2 else "",
			"family_name": p[3].strip_edges() if p.size() > 3 else "",
			"email": p[4].strip_edges() if p.size() > 4 else ""}
	if p.size() >= 2 and p[0] == "APPLE_ERR":
		return {"ok": false, "code": "APPLE_" + p[1].to_upper()}
	return {"ok": false, "code": "APPLE_UNKNOWN"}

## 调起系统授权。transport 可注入：func(nonce_hash: String) -> String（测试替身，返回原生回包）。
static func authorize(nonce: String, transport: Callable = Callable()) -> Dictionary:
	if transport.is_valid(): return parse_reply(await transport.call(nonce.sha256_text()))
	var udp := PacketPeerUDP.new()
	if udp.connect_to_host("127.0.0.1", PORT) != OK: return {"ok": false, "code": "APPLE_UNAVAILABLE"}
	udp.put_packet(("APPLE|" + nonce.sha256_text()).to_utf8_buffer())
	var tree := Engine.get_main_loop() as SceneTree
	var waited := 0.0
	while waited < TIMEOUT_S:
		await tree.process_frame
		waited += tree.root.get_process_delta_time()
		if udp.get_available_packet_count() > 0:
			var reply := udp.get_packet().get_string_from_utf8()
			udp.close()
			return parse_reply(reply)
	udp.close()
	return {"ok": false, "code": "APPLE_TIMEOUT"}
