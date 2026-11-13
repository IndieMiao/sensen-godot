class_name P0SignIn
extends RefCounted
## The phone's own sign-in for P0 accounts (SGODOT-487; tech-plan-yase §3.1; 不知火舞's ACC-SIGNIN-iOS 636:197174 /
## -Android 636:197202): what the native sheet answered, in the one shape the account screens read — the screens carry
## the words, this carries no text. Three results, never mixed (不知火舞 on 491 dffd8179):
##   ok         the token for the server (session/apple or /google) with the raw nonce it is checked against
##   cancelled  the player closed the sheet: back to the card, nothing said
##   failed     anything else (no network, the system, a bad reply): SYS-CMD-FAIL — never read as "no farm here"
## Only the provider's account number goes to the server (q(312), 李白 ②): Apple is asked for no name and no email, and
## whatever a reply carries besides the token is dropped here.

const APPLE := "apple"
const GOOGLE := "google"

## Which providers this phone offers: iOS both, Android Google (D2). Tests and the desktop preview force them on.
static var force := []
static func providers(os_name := OS.get_name()) -> Array:
	if not force.is_empty(): return force.duplicate()
	if os_name == "iOS": return [APPLE, GOOGLE]
	if os_name == "Android": return [GOOGLE]
	return []

static func new_nonce() -> String: return AppleSignIn.new_nonce()

## Sign in with Apple through tools/ios/AppleSignIn.swift (loopback UDP 46465). `transport` stands in for the bridge in
## tests: func(nonce_hash: String) -> String, the bridge's reply line.
static func apple(transport: Callable = Callable()) -> Dictionary:
	var nonce := new_nonce()
	var reply: Dictionary = await AppleSignIn.authorize(nonce, transport, true)
	return from_apple(reply, nonce)

## AppleSignIn.parse_reply's dictionary as one of the three results.
static func from_apple(reply: Dictionary, nonce: String) -> Dictionary:
	if bool(reply.get("ok", false)):
		return {"result": "ok", "provider": APPLE, "id_token": str(reply.get("identity_token", "")), "nonce": nonce,
			"auth_code": str(reply.get("authorization_code", ""))}
	var code := str(reply.get("code", "APPLE_UNKNOWN"))
	if code == "APPLE_CANCELED": return {"result": "cancelled", "provider": APPLE}
	return {"result": "failed", "provider": APPLE, "reason": code}

## Sign in with Google. iOS: tools/ios/GoogleSignInIOS.swift (loopback UDP 46468, the system's web sheet, `openid`
## only); Android: GodotGoogleSignIn (Credential Manager, GoogleSignIn.authorize). `transport` stands in for the
## native side in tests: on iOS func(line: String) -> String with the bridge's whole request line, on Android
## GoogleSignIn's func(nonce_hash: String) -> String.
const GOOGLE_PORT := 46468
## The iOS OAuth client id (not a secret; google-console-steps.md ②). Empty until the user's project has one: Google
## then fails as `GOOGLE_CONFIG` rather than opening a sheet that can only error.
const IOS_CLIENT_SETTING := "sensen/auth/google_ios_client_id"
static func ios_client_id() -> String: return str(ProjectSettings.get_setting(IOS_CLIENT_SETTING, ""))

static func google(transport: Callable = Callable(), os_name := OS.get_name()) -> Dictionary:
	var nonce := new_nonce()
	if os_name != "iOS":
		return from_google(await GoogleSignIn.authorize(nonce, transport), nonce)
	var client := ios_client_id()
	if client.is_empty(): return {"result": "failed", "provider": GOOGLE, "reason": "GOOGLE_CONFIG"}
	var line := "GOOGLE|%s|%s" % [client, nonce.sha256_text()]
	var reply := str(await transport.call(line)) if transport.is_valid() else await _google_bridge(line)
	return from_google(parse_google_line(reply), nonce)

## The iOS bridge's reply line in GoogleSignIn.parse_result's shape.
static func parse_google_line(line: String) -> Dictionary:
	var p := line.strip_edges().split("|", true)
	if p.size() >= 2 and p[0] == "GOOGLE_OK" and not p[1].is_empty(): return {"ok": true, "id_token": p[1]}
	if p.size() >= 2 and p[0] == "GOOGLE_ERR": return {"ok": false, "code": "GOOGLE_" + p[1].to_upper()}
	return {"ok": false, "code": "GOOGLE_UNKNOWN"}

static func from_google(reply: Dictionary, nonce: String) -> Dictionary:
	if bool(reply.get("ok", false)) and not str(reply.get("id_token", "")).is_empty():
		return {"result": "ok", "provider": GOOGLE, "id_token": str(reply.id_token), "nonce": nonce}
	var code := str(reply.get("code", "GOOGLE_UNKNOWN"))
	if code == "GOOGLE_CANCELED": return {"result": "cancelled", "provider": GOOGLE}
	return {"result": "failed", "provider": GOOGLE, "reason": code}

static func _google_bridge(line: String) -> String:
	var udp := PacketPeerUDP.new()
	if udp.connect_to_host("127.0.0.1", GOOGLE_PORT) != OK: return "GOOGLE_ERR|unavailable"
	udp.put_packet(line.to_utf8_buffer())
	var tree := Engine.get_main_loop() as SceneTree
	var waited := 0.0
	while waited < AppleSignIn.TIMEOUT_S:   # the player may sit in Google's sheet a long while (password, 2-step)
		await tree.process_frame
		waited += tree.root.get_process_delta_time()
		if udp.get_available_packet_count() > 0:
			var reply := udp.get_packet().get_string_from_utf8()
			udp.close()
			return reply
	udp.close()
	return "GOOGLE_ERR|timeout"
