extends RefCounted
## ACC-SIGNOUT (SGODOT-491; 不知火舞's spec v2 §5; 720:201735): Settings' `Sign out` asks first — the confirm card
## (HOME-CHANGE-CONFIRM's, as the choose card's) over Settings: `Sign out?`, how this farm comes back (`You can sign in
## again with email.`; a code's `…with your test code.`: whole sentences, 李白), `Sign out` (primary) and `Cancel`. The
## scrim is Cancel too. Signed out, the host shows the sign-in page.

const Confirm := preload("res://scenes/p0/panels/p0_home_move_confirm.gd")
const TITLE := "Sign out?"
const AGAIN := {"apple": "You can sign in again with Apple.", "google": "You can sign in again with Google.",
	"email": "You can sign in again with email.", "code": "You can sign in again with your test code."}
const SIGN_OUT := "Sign out"

## `account`: "apple" / "google" / "email" / "code". Its move_pressed is Sign out, its cancelled Cancel.
static func card(account: String) -> Control:
	var c = Confirm.new()
	c.name = "SignOutCard"
	c.theme = UiKit.theme()
	(c.card.find_child("Title", true, false) as Label).text = TITLE
	(c.card.find_child("Body", true, false) as Label).text = str(AGAIN.get(account, ""))
	c.move.label = SIGN_OUT
	c.move.sends = false
	return c
