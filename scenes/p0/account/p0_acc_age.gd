class_name P0AccAge
extends P0AccShell
## ACC-AGE v1.1 (SGODOT-491; 不知火舞's account spec v1.1 A, q(312); 安其拉's row 158 659:198791 / 659:198825 /
## 659:198854): the first launch's age and consent, on ACC-SHELL. Centred `What year were you born?` (the voice age
## card's question), the year wheel (UiYearWheel: this year down a hundred, nothing picked), the consent row — `I agree
## to the Terms of Service and Privacy Policy`, its two names links, never ticked for the player — then 8 under it the
## zero-tolerance line (Caption 12, secondary; Apple 1.2's), and the key; 20 between them (the frame's card gap).
## The key says what is still missing, in order (q(28)): `Pick your birth year` (grey) → `Agree to continue` (grey) →
## `Continue`. Continue asks the same card for every answer (v2 §1.1 2a: a slip of the thumb, not a second guess) —
## `Born in 2001?`, Yes / Change (the confirm frame, HOME-CHANGE-CONFIRM's, as Block's): Yes says the answer (agreed:
## old enough or not; the year is never kept), Change closes the card on the page as it was, the tick kept.
## Links say which (link_pressed: "terms" / "privacy"); the host opens them. Nothing here touches the network.

signal agreed(age_ok: bool)
signal link_pressed(which: String)

const AgeCard := preload("res://scenes/p0/panels/p0_age_card.gd")
const Confirm := preload("res://scenes/p0/panels/p0_home_move_confirm.gd")
const QUESTION := AgeCard.QUESTION
const AGREE := "I agree to the Terms of Service and Privacy Policy"
const LINKS := ["Terms of Service", "Privacy Policy"]
const LINK_IDS := ["terms", "privacy"]
const ZERO_TOLERANCE := "Gensen is an online game with other players. We have zero tolerance for objectionable content or abusive behavior."
const PICK := "Pick your birth year"
const AGREE_FIRST := "Agree to continue"
const CONTINUE := "Continue"
const BORN := "Born in %d?"
const GAP := 20.0          # the card's (row 158: title, wheel, consent, key)
const CAPTION_GAP := 8.0   # the consent row to its line

var wheel: UiYearWheel
var consent: UiCheckbox
var go: UiCommandButton
var confirm: Control   # Born in …? while it is up
## Laid out at once, no settling (tests, shots).
var animate := true

func _init(this_year := 0) -> void:
	super()
	name = "AccAge"
	add_title(QUESTION, true)
	add_gap(GAP)
	wheel = UiYearWheel.new(this_year)
	wheel.picked.connect(func(_y: int): _refresh())
	col.add_child(wheel)
	add_gap(GAP)
	consent = UiCheckbox.new(AGREE, LINKS)
	consent.name = "Consent"
	consent.toggled.connect(func(_on: bool): _refresh())
	consent.link_pressed.connect(func(i: int): link_pressed.emit(LINK_IDS[i]))
	col.add_child(consent)
	add_gap(CAPTION_GAP)
	var rule := UiKit.label(ZERO_TOLERANCE, UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
	rule.name = "Rule"
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(rule)
	add_gap(GAP)
	go = add_primary(PICK)
	go.activated.connect(_on_go)
	_refresh()

func _ready() -> void:
	wheel.animate = animate   # a page laid out at once (tests): the wheel settles at once too

## The key as the page stands: what is still missing first.
func _refresh() -> void:
	go.label = PICK if wheel.year == 0 else (AGREE_FIRST if not consent.checked else CONTINUE)
	go.disabled = wheel.year == 0 or not consent.checked

func _on_go() -> void:
	if go.disabled or confirm != null: return
	var year := wheel.year
	var c = Confirm.new()
	confirm = c
	c.name = "BornConfirm"
	c.theme = UiKit.theme()
	(c.card.find_child("Title", true, false) as Label).text = BORN % year
	(c.card.find_child("Body", true, false) as Control).visible = false
	c.move.label = "Yes"
	c.move.sends = false
	c.cancel.label = "Change"
	c.cancelled.connect(_change)
	c.move_pressed.connect(func():
		_change()
		agreed.emit(AgeCard.ok_for(year, wheel.this_year)))
	add_child(c)

## Change (or the scrim): the card goes, the page as it was — the wheel on that year, the tick kept.
func _change() -> void:
	if confirm == null: return
	confirm.queue_free()
	confirm = null
