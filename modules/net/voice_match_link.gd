class_name VoiceMatchLink
extends Node
## Opens the Gensen voice-match H5 inside the app (Android GodotWebView plugin).
## While the page is up: party voice mic is muted (the page needs the microphone)
## and 3D rendering stops, since the WebView covers the whole screen.

signal closed(reason: String)

const BASE_URL := "https://match.sensenapp.com/"
const HOSTS := "match.sensenapp.com"
## Godot 4.7 Android ignores plugin onMainBackPressed() return values and always
## forwards GO_BACK to the engine. The press that closed the page may reach the
## scene after our closed signal, so it is swallowed for this long.
const BACK_SWALLOW_MS := 600
## Debug builds only: first line replaces BASE_URL (e.g. http://localhost:5173/
## over `adb reverse`, which WebView treats as a secure context for getUserMedia).
const DEBUG_OVERRIDE_PATH := "user://voice_match_base_url.txt"

var _plugin: Object
var _open := false
var _restore_voice_mic := false
var _swallow_back_until := 0

func _ready() -> void:
	if Engine.has_singleton("GodotWebView"):
		_plugin = Engine.get_singleton("GodotWebView")
		# The plugin emits on the Android UI thread; hop back to the main loop.
		_plugin.connect("closed", func(reason: String): _on_closed.call_deferred(reason))

## In-app when the native plugin exists; elsewhere (desktop, iOS for now) the
## system browser keeps the entry usable.
## The H5 always opens in English (product decision 2026-09-25), whatever the game locale.
static func url_for(mode := "solo", base := BASE_URL) -> String:
	return "%s?embed=1&theme=gensen&mode=%s&lang=en" % [base, mode]

static func _base_url() -> String:
	if OS.is_debug_build() and FileAccess.file_exists(DEBUG_OVERRIDE_PATH):
		var line := FileAccess.get_file_as_string(DEBUG_OVERRIDE_PATH).strip_edges().get_slice("\n", 0)
		if line.begins_with("http"):
			return line
	return BASE_URL

static func _host_of(url: String) -> String:
	return url.get_slice("://", 1).get_slice("/", 0).get_slice(":", 0)

func is_open() -> bool:
	return _open

## True while the page is up and just after the system back press that closed it.
func blocks_back_navigation() -> bool:
	return _open or Time.get_ticks_msec() < _swallow_back_until

func open(mode := "solo") -> void:
	if _open:
		return
	var base := _base_url()
	var url := url_for(mode, base)
	if _plugin == null:
		OS.shell_open(url)
		return
	_open = true
	_restore_voice_mic = Voice.state == "connected" and Voice.microphone
	if _restore_voice_mic:
		Voice.set_microphone(false)
	RenderingServer.render_loop_enabled = false
	_plugin.call("open", url, HOSTS if base == BASE_URL else _host_of(base))

func close() -> void:
	if _open and _plugin:
		_plugin.call("close")

func _on_closed(reason: String) -> void:
	if not _open:
		return
	_open = false
	if reason == "back":
		_swallow_back_until = Time.get_ticks_msec() + BACK_SWALLOW_MS
	RenderingServer.render_loop_enabled = true
	if _restore_voice_mic:
		_restore_voice_mic = false
		Voice.set_microphone(true)
	closed.emit(reason)

func _exit_tree() -> void:
	# Leaving the scene with the page up must not strand rendering disabled.
	if _open:
		close()
		RenderingServer.render_loop_enabled = true
