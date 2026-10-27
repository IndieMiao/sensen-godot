extends RefCounted
## SGODOT-341 / 97156a0f: draft trigger only, pending the q(215) amendment. No prompt, permission or notification.
## A future bridge must persist `asked` per account when the SoftPrompt was actually shown (either button counts).
## Keep this off until the real local ripening notification and both platform permission bridges ship together.

const LOCAL_NOTIFICATIONS_READY := false
var asked := false

func _init(already_asked := false) -> void:
	asked = already_asked

## The caller supplies own-farm presence, all held input (not just sow), and a clear screen including end feedback.
## Checking eligibility never consumes the once flag; disabled builds must not silently use up the future prompt.
func ready(view: Dictionary, own_farm: bool, hand_held: bool, screen_busy: bool, enabled := LOCAL_NOTIFICATIONS_READY) -> bool:
	if not enabled or asked or not own_farm or hand_held or screen_busy: return false
	var g = view.get("guide")
	if not g is Dictionary or g.get("step") != null or str(g.get("end", "")) not in ["done", "timeout"]: return false
	return (view.get("plots", []) as Array).any(func(p): return str(p.get("crop", "")) == "crop_radish" \
		and str(p.get("state", "")) == "growing" and p.get("ready_in") != null and float(p.ready_in) > 0.0)

func shown() -> void:
	asked = true
