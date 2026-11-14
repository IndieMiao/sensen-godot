class_name P0AccConsent
extends P0AccShell
## ACC-CONSENT-OLD (SGODOT-491; 不知火舞's account spec v1.1 A, q(312); 659:198908 / 659:198931): an old player who
## passed voice's 13+ gate (no age asked again) agrees and goes on. On ACC-SHELL, 12 between: `Before you start` (left),
## the zero-tolerance line (Body 14, secondary), the consent row (P0AccAge's: never ticked for them, its links say
## which) and the key: `Agree to continue` (grey) till ticked, then `Continue` (agreed).
## `updated` (spec v2 §9, consent_outdated mid-way): the same card titled `We've updated our terms`.

signal agreed
signal link_pressed(which: String)

const TITLE := "Before you start"
const UPDATED := "We've updated our terms"
const GAP := 12.0

var consent: UiCheckbox
var go: UiCommandButton

func _init(updated := false) -> void:
	super()
	name = "AccConsent"
	add_title(UPDATED if updated else TITLE)
	add_gap(GAP)
	add_body(P0AccAge.ZERO_TOLERANCE, UiTokens.COLOR_TEXT)   # the text colour here, not secondary (659:198931)
	add_gap(GAP)
	consent = UiCheckbox.new(P0AccAge.AGREE, P0AccAge.LINKS)
	consent.name = "Consent"
	consent.toggled.connect(func(_on: bool): _refresh())
	consent.link_pressed.connect(func(i: int): link_pressed.emit(P0AccAge.LINK_IDS[i]))
	col.add_child(consent)
	add_gap(GAP)
	go = add_primary(P0AccAge.AGREE_FIRST)
	go.sends = false
	go.activated.connect(func(): if consent.checked: agreed.emit())
	_refresh()

func _refresh() -> void:
	go.label = P0AccAge.CONTINUE if consent.checked else P0AccAge.AGREE_FIRST
	go.disabled = not consent.checked
