class_name P0AccNoFarm
extends P0AccShell
## ACC-NOFARM (SGODOT-491; 不知火舞's account spec §1.6, 636:197230): the sign-in found no farm for that account. On
## ACC-SHELL, the card at 190, 16 between: `No farm found` (centred), `This Google account has no farm yet.` (Apple's
## its own line: whole sentences, never `%s` — 李白 on #999, the table's Apple is the fruit), `Start a new farm`
## (primary: back to NAME, the farm made there links that account — the host keeps its pending) and `Try another
## account` (secondary: the sign-in card again).

signal start_new
signal try_another

const TITLE := "No farm found"
const BODY := {"google": "This Google account has no farm yet.", "apple": "This Apple account has no farm yet."}
const START := "Start a new farm"
const ANOTHER := "Try another account"
const TOP := 190.0
const GAP := 16.0

func _init(provider := "google") -> void:
	super()
	name = "AccNoFarm"
	card_top = TOP
	add_title(TITLE, true)
	add_gap(GAP)
	var body := add_body(str(BODY.get(provider, BODY.google)))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_gap(GAP)
	var go := add_primary(START)
	go.sends = false
	go.activated.connect(func(): start_new.emit())
	add_gap(GAP)
	var other := UiCommandButton.new(ANOTHER, UiCommandButton.Kind.SECONDARY)
	other.name = "Another"
	other.custom_minimum_size.y = KEY_H
	other.sends = false
	other.activated.connect(func(): try_another.emit())
	col.add_child(other)
