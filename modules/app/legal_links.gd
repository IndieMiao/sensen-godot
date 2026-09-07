class_name LegalLinks
extends RefCounted
## 隐私政策 / 服务条款 URL 与同意版本的唯一来源。URL 由 SSLAUNCH B2 / B3 / B6 提供后填入；
## 条款改版时把 CONSENT_VERSION 改成新日期，所有用户下次启动会被要求重新同意（R3）。
## 不做 WebView：一律 OS.shell_open 跳外部浏览器（08-30 调研 §3.1）。

const PRIVACY_URL := ""
const TERMS_URL := ""
const SUPPORT_EMAIL := ""
## 形如 2026-09-07；改版即改此值。
const CONSENT_VERSION := "2026-09-07"

static func has_privacy() -> bool:
	return not PRIVACY_URL.is_empty()

static func has_terms() -> bool:
	return not TERMS_URL.is_empty()

static func open(url: String) -> void:
	if not url.is_empty():
		OS.shell_open(url)
