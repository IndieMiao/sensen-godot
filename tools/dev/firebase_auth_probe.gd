extends SceneTree
## 用仓库自己的 FirebaseAuth 类对真实 Firebase 跑一遍：注册临时账号 → lookup → securetoken 刷新 → 删号。
## 用法：godot --headless --path . --script res://tools/dev/firebase_auth_probe.gd
## 读 user://firebase.json（FirebaseConfig）。会在项目里留下 0 个用户（最后删掉）。

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Node.new()
	root.add_child(host)
	var key := FirebaseConfig.api_key()
	if key.is_empty():
		printerr("PROBE: no api key (user://firebase.json)")
		quit(2)
		return
	var fb := FirebaseAuth.new(key, ApiClient.make_http_transport(host))
	var email := "probe+%d@example.com" % Time.get_unix_time_from_system()
	var pw := "Probe-%s" % Crypto.new().generate_random_bytes(6).hex_encode()
	var s: Dictionary = await fb.sign_up(email, pw)
	print("PROBE sign_up ok=%s code=%s user_id=%s" % [s.get("ok"), s.get("code", ""), s.get("user_id", "")])
	if not bool(s.get("ok", false)):
		quit(1)
		return
	var l: Dictionary = await fb.lookup(str(s.id_token))
	print("PROBE lookup ok=%s email=%s verified=%s" % [l.get("ok"), l.get("email", ""), l.get("email_verified", null)])
	var wrong: Dictionary = await fb.sign_in_with_password(email, "definitely-wrong")
	print("PROBE wrong password code=%s" % wrong.get("code", ""))
	var r: Dictionary = await fb.refresh(str(s.refresh_token))
	print("PROBE refresh ok=%s new_token=%s" % [r.get("ok"), "yes" if not str(r.get("id_token", "")).is_empty() else "no"])
	var d: Dictionary = await fb.delete_account(str(r.get("id_token", s.id_token)))
	print("PROBE delete ok=%s code=%s" % [d.get("ok"), d.get("code", "")])
	var again: Dictionary = await fb.sign_in_with_password(email, pw)
	print("PROBE post-delete sign-in code=%s (expect EMAIL_NOT_FOUND / INVALID_LOGIN_CREDENTIALS)" % again.get("code", ""))
	quit(0 if bool(d.get("ok", false)) else 1)
