extends GdUnitTestSuite
## 声音画像 H5 容器：渲染开关、返回键吞咽窗口、关闭原因的处理。

class FakeWebView extends Object:
	signal closed(reason: String)
	var opened: Array = []
	func open(url: String, hosts: String) -> void:
		opened.append([url, hosts])
	func close() -> void:
		closed.emit("closed")

var _fake: FakeWebView

func after_test() -> void:
	RenderingServer.render_loop_enabled = true
	if _fake:
		_fake.free()
		_fake = null

func _link() -> VoiceMatchLink:
	var link := VoiceMatchLink.new()
	_fake = FakeWebView.new()
	link._plugin = _fake
	_fake.closed.connect(func(reason: String): link._on_closed.call_deferred(reason))
	add_child(auto_free(link))
	return link

func test_open_hands_allowlist_to_plugin_and_pauses_rendering() -> void:
	var link := _link()
	link.open("solo")
	assert_bool(link.is_open()).is_true()
	assert_bool(RenderingServer.render_loop_enabled).is_false()
	assert_int(_fake.opened.size()).is_equal(1)
	assert_str(_fake.opened[0][0]).contains("mode=solo")
	assert_str(_fake.opened[0][1]).is_equal("match.sensenapp.com")
	link.open("solo") # 已打开时不重复叠加
	assert_int(_fake.opened.size()).is_equal(1)

func test_closing_restores_rendering_and_only_back_swallows_navigation() -> void:
	var link := _link()
	link.open()
	link.close()
	await get_tree().process_frame
	assert_bool(link.is_open()).is_false()
	assert_bool(RenderingServer.render_loop_enabled).is_true()
	assert_bool(link.blocks_back_navigation()).is_false()
	link.open()
	_fake.closed.emit("back")
	assert_bool(link.blocks_back_navigation()).is_true() # 信号尚未派发：仍算打开
	await get_tree().process_frame
	assert_bool(link.is_open()).is_false()
	assert_bool(link.blocks_back_navigation()).is_true() # 关掉网页的那次返回不能再退场景
	link._swallow_back_until = 0
	assert_bool(link.blocks_back_navigation()).is_false()

func test_debug_override_host_is_parsed_without_port() -> void:
	assert_str(VoiceMatchLink._host_of("http://localhost:5173/")).is_equal("localhost")
	assert_str(VoiceMatchLink._host_of("https://match.sensenapp.com/")).is_equal("match.sensenapp.com")
