extends RefCounted
## Network ban projection only (contract-accounts §1.1). Missing/malformed is UNKNOWN, never permanent/clear.
const UNKNOWN := 0
const CLEAR := 1
const LIMITED := 2
const PERMANENT := 3
const OFF := "Voice chat is off for you."
const UNTIL := "Voice chat is off for you until %s."
var kind := UNKNOWN
var until_ms := 0
var blocked := false  # Retained on stale/expired state until a fresh server ban:null, never auto-rejoin.
var stale := true

func reset() -> void:
	kind = UNKNOWN
	until_ms = 0
	blocked = false
	stale = true

static func parse_until(value: Variant) -> int:
	if not value is String or value.length() != 24 or value.substr(19, 1) != "." or not value.ends_with("Z"): return -1
	var regex := RegEx.new()
	regex.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$")
	if regex.search(value) == null: return -1
	var year := int(value.substr(0, 4))
	var month := int(value.substr(5, 2))
	var day := int(value.substr(8, 2))
	if year < 1970 or month < 1 or month > 12 or day < 1: return -1
	var days := [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if day > days[month - 1] or int(value.substr(11, 2)) > 23 or int(value.substr(14, 2)) > 59 or int(value.substr(17, 2)) > 59: return -1
	var seconds := Time.get_unix_time_from_datetime_string(value.left(19))
	if seconds < 0 or Time.get_datetime_string_from_unix_time(seconds, false) != value.left(19): return -1
	return seconds * 1000 + int(value.substr(20, 3))

func take(value: Variant) -> bool:
	if value == null:
		kind = CLEAR
		blocked = false
		until_ms = 0
	elif value is Dictionary and value.has("until"):
		if value.until == null:
			kind = PERMANENT
			until_ms = 0
		else:
			var at := parse_until(value.until)
			if at < 0:
				stale = true
				return false
			kind = LIMITED
			until_ms = at
		blocked = true
	else:
		stale = true
		return false
	stale = false
	return true

func expired(now_ms: int) -> bool: return kind == LIMITED and now_ms >= until_ms

func message(now_ms: int, bias_min := 100000) -> String:
	if kind == PERMANENT: return OFF
	if kind != LIMITED or expired(now_ms): return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) if bias_min == 100000 else bias_min
	var date := Time.get_datetime_dict_from_unix_time(int(until_ms / 1000) + bias * 60)
	return Localization.with_names(UNTIL, [P0Logic.month_day(int(date.month), int(date.day))])
