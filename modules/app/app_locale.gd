class_name AppLocale
extends RefCounted
## 语言：en-US 主、zh-CN 次（08-30 调研 §6.0#6 / SSLAUNCH F3）。翻译文件在 locale/*.po，
## 由 project.godot 的 internationalization/locale/translations 在引擎启动时加载。
## 玩家选择写 UiState；首次启动按系统语言：中文 → zh_CN，其余 → en。

const SUPPORTED: Array[String] = ["en", "zh_CN"]
const DEFAULT := "en"
const UI_STATE_KEY := "locale"
const NAMES := {"en": "English", "zh_CN": "简体中文"}

static func is_supported(locale: String) -> bool:
	return SUPPORTED.has(locale)

## saved 优先；否则按系统语言归一到支持列表。
static func resolve(saved: String, os_locale: String) -> String:
	if is_supported(saved):
		return saved
	if os_locale.begins_with("zh"):
		return "zh_CN"
	return DEFAULT

static func current() -> String:
	var loc := TranslationServer.get_locale()
	return loc if is_supported(loc) else DEFAULT

static func apply(locale: String, persist := true) -> void:
	var target := locale if is_supported(locale) else DEFAULT
	TranslationServer.set_locale(target)
	if persist:
		UiState.write({UI_STATE_KEY: target})

## 冷启动：读持久化，没有就看系统语言。
static func boot_apply() -> void:
	apply(resolve(str(UiState.read().get(UI_STATE_KEY, "")), OS.get_locale()), false)

static func display_name(locale: String) -> String:
	return str(NAMES.get(locale, locale))

static func next(locale: String) -> String:
	var i := SUPPORTED.find(locale)
	return SUPPORTED[(i + 1) % SUPPORTED.size()] if i >= 0 else DEFAULT
