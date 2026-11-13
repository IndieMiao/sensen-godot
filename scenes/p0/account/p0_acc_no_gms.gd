class_name P0AccNoGms
extends P0AccShell
## ACC-NO-GMS (SGODOT-491; 不知火舞's spec v2 §4; 720:201658): an Android phone without Google Play services while email
## sign-in is off — after the launch, before AGE. On ACC-SHELL, the card at 190: `Can't sign in on this phone`, 12, `Sign-in
## needs Google Play services.` (Body Bold 14, secondary), 20, `Contact us` (primary: the system's mail to the support
## address with the build and the phone — no support code: there is no account yet) and 8 under it the quiet `Use a test
## code` (Dismiss, in either build). No ‹ (Android's Back: the home screen).

signal test_code_pressed

const TITLE := "Can't sign in on this phone"
const LINE := "Sign-in needs Google Play services."
const CONTACT := "Contact us"
const TOP := 190.0
const GAP := 12.0
const HEAD_GAP := 20.0
const QUIET_GAP := 8.0

func _init() -> void:
	super()
	name = "AccNoGms"
	card_top = TOP
	add_title(TITLE)
	add_gap(GAP)
	add_body(LINE)
	add_gap(HEAD_GAP)
	var go := add_primary(CONTACT)
	go.sends = false
	go.activated.connect(func(): ExternalLink.open(mail_url()))
	add_gap(QUIET_GAP)
	var code := UiDismissButton.new(P0AccSignIn.TEST_CODE)
	code.name = "TestCode"
	code.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	code.pressed.connect(func(): test_code_pressed.emit())
	col.add_child(code)

## The mail: to the support address (the user 11-12), the build and the phone in its body, nothing else.
static func mail_url(version := "", phone := "") -> String:
	if version == "": version = P0Legal.version_line(P0Session.demo_config(
		FileAccess.get_file_as_string(P0Session.DEMO_CONFIG) if FileAccess.file_exists(P0Session.DEMO_CONFIG) else ""))
	if phone == "": phone = "%s %s" % [OS.get_name(), OS.get_version()]
	var body := "Version: %s\nPhone: %s\n\n" % [version, phone]
	return "mailto:%s?subject=%s&body=%s" % [P0Legal.SUPPORT_EMAIL, "Gensen support".uri_encode(), body.uri_encode()]
