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
