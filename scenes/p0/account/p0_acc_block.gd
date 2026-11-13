class_name P0AccBlock
extends P0AccShell
## ACC-AGE-BLOCK (SGODOT-491; 不知火舞's account spec §1.3, q(312); 安其拉's 634:197069): the end of the first launch for
## a birth year too late (14 by the year; never a number on screen, 13 nowhere). On ACC-SHELL, the card lower (220):
## centred `Sorry, you can't play Gensen.`, `Thanks for your interest in Gensen.` (Body Bold 14, secondary), and the
## `Privacy Policy ›` link (link_pressed: the host opens q(281)'s page in the system browser), 16 between. No key, no
## back, no second answer: the phone keeps the no and every launch stops here, nothing sent (the host's, B1).

signal link_pressed(which: String)

const TITLE := "Sorry, you can't play Gensen."
const BODY := "Thanks for your interest in Gensen."
const LINK := "Privacy Policy ›"
const TOP := 220.0
const GAP := 16.0

func _init() -> void:
	super()
	name = "AccBlock"
	card_top = TOP
	add_title(TITLE, true)
	add_gap(GAP)
	var body := add_body(BODY)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_gap(GAP)
	add_link(LINK).pressed.connect(func(): link_pressed.emit("privacy"))
