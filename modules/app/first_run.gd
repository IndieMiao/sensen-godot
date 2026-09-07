class_name FirstRun
extends RefCounted
## 首启合规流（08-30 调研 §5.3 COPPA、§5.1#2 EULA）：年龄门 → 条款同意 → 登录。
## 中立年龄门：注册第一步收生日，<13 拒绝并持久化，重装前不可重试；采集任何 PI（含匿名登录）
## 之前先过门。**只存结论不存生日**——生日本身就是 PI，没必要留在设备上。
## 同意记录带版本号：条款改版（LegalLinks.CONSENT_VERSION 变化）后重新征求同意。
## 服务端侧的 age_gate_passed_at / consent_version 回写归 D2 账号服务。

const PATH := "user://first_run.json"
const MIN_AGE := 13

var age_gate_passed := false
var age_gate_blocked := false
var age_gate_at := ""
var consent_version := ""
var consent_at := ""

static func load_state() -> FirstRun:
	var f := FirstRun.new()
	if not FileAccess.file_exists(PATH):
		return f
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		return f
	var d: Dictionary = parsed
	f.age_gate_passed = bool(d.get("age_gate_passed", false))
	f.age_gate_blocked = bool(d.get("age_gate_blocked", false))
	f.age_gate_at = str(d.get("age_gate_at", ""))
	f.consent_version = str(d.get("consent_version", ""))
	f.consent_at = str(d.get("consent_at", ""))
	return f

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"age_gate_passed": age_gate_passed,
			"age_gate_blocked": age_gate_blocked,
			"age_gate_at": age_gate_at,
			"consent_version": consent_version,
			"consent_at": consent_at,
		}))

## 周岁：生日还没到就减一。today / birth 用 {year, month, day}。
static func age_years(birth: Dictionary, today: Dictionary) -> int:
	var years := int(today.year) - int(birth.year)
	if int(today.month) < int(birth.month) or (int(today.month) == int(birth.month) and int(today.day) < int(birth.day)):
		years -= 1
	return years

static func is_under_min_age(birth: Dictionary, today: Dictionary) -> bool:
	return age_years(birth, today) < MIN_AGE

## 记录年龄门结论（不记生日）。返回是否通过。
func record_age_gate(birth: Dictionary, today: Dictionary) -> bool:
	var ok := not is_under_min_age(birth, today)
	age_gate_passed = ok
	age_gate_blocked = not ok
	age_gate_at = Time.get_datetime_string_from_system(true)
	save()
	return ok

func consent_current() -> bool:
	return consent_version == LegalLinks.CONSENT_VERSION

func record_consent() -> void:
	consent_version = LegalLinks.CONSENT_VERSION
	consent_at = Time.get_datetime_string_from_system(true)
	save()

## 启动去向（boot.gd 用）：被拒 → 年龄门页（显示拒绝）；未过门 → 年龄门；同意过期 → 同意页；
## 之后按会话进壳或登录。
func next_route(signed_in: bool) -> String:
	if age_gate_blocked or not age_gate_passed:
		return AppRoutes.AGE_GATE
	if not consent_current():
		return AppRoutes.CONSENT
	return AppRoutes.SHELL if signed_in else AppRoutes.LOGIN
