extends Control
## A stand-in for 哪吒's P0AccFlow (scenes/p0/account/p0_acc_flow.gd, its v1.4 signature of 11-13) in the runtime's glue
## tests: its constructor, its signals and the calls the runtime makes on it, written down.
signal agreed(age_ok: bool)
signal named(name: String, skip: bool)
signal sign_in(provider: String)
signal sign_in_again()
signal switch_farm()
signal code_entered(code: String)
signal consent_renewed()
signal blocked()
signal failed(code: String)
var kind := ""
var providers: Array = []
var hints := {}
var calls: Array = []   # [method, args…] as the runtime made them
var record := {}        # kept(): this phone's AGE answer
func _init(k: String, _name_check: Callable, p: Array, h := {}, _this_year := 0) -> void:
	kind = k
	providers = p
	hints = h
func name_refused(r: Dictionary) -> void: calls.append(["name_refused", r])
func code_refused(r: Dictionary) -> void: calls.append(["code_refused", r])
func no_farm(fresh := true) -> void: calls.append(["no_farm", fresh])
func conflict(farm: Dictionary, provider: String) -> void: calls.append(["conflict", farm, provider])
func claimed(linked: Array) -> void: calls.append(["claimed", linked])
func kept() -> Dictionary: return record
func sign_in_settled() -> void: calls.append(["settled"])
func consent_outdated(r: Dictionary) -> void: calls.append(["consent_outdated", str(r.get("terms_version", ""))])
func consent_settled(ok: bool) -> void: calls.append(["consent_settled", ok])
var said: Array = []
func say(text: String, error := false) -> void: said.append([text, error])
## 哪吒's static entry (11-14): NO-GMS where Google cannot sign in and email is off; Sign in's keys.
static var google_ok := true
static func entry(k: String, email_on: bool) -> Dictionary:
	if not google_ok and not email_on and not k in ["blocked", "old_blocked"]: return {"kind": "no_google", "providers": []}
	var p: Array = ["apple", "google"] if google_ok else ["apple"]
	if email_on: p.append("email")
	return {"kind": k, "providers": p}
func back() -> bool: return true
