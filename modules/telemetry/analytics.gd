class_name Analytics
extends RefCounted
## E5 埋点（PostHog capture）。口径来自开发拆解 §3 E5：注册转化 / DAU / IM 发送 /
## feed 发布 / 语音房进房 / 举报 / 删号。**不采位置、不弹 ATT、不带 UGC 正文**——
## 所有属性过 Scrub，键名一旦命中敏感表整值替换。
##
## 没配 key 就是彻底关闭（enabled() == false），一条也不发；SSLAUNCH D8 给到项目后
## 只需填 env / config，不用改代码。用户在设置里关掉分享（opt_out）后同样一条不发。

## 用户是否关掉了「分享匿名使用数据」；存 UiState，重装即回到默认（开）。
const OPT_OUT_KEY := "telemetry_opt_out"
const HOST_DEFAULT := "https://us.i.posthog.com"
const BATCH_MAX := 20

## 事件名白名单：新事件必须先在这里登记，避免随手 capture 出一堆没人认领的名字。
const EVENTS := [
	"app_open", "sign_up_completed", "sign_in_completed",
	"message_sent", "post_published", "post_liked", "comment_added",
	"voice_room_joined", "content_reported", "user_blocked", "account_deleted",
	"map_opened", "friend_opened",
]

var api_key := ""
var host := HOST_DEFAULT
var opted_out := false
## 注入点：func(url: String, headers: PackedStringArray, body: String) -> ApiClient.Response
var transport: Callable
var queue: Array = []
var sent: Array = []

func _init(p_key := "", p_host := "", p_transport := Callable()) -> void:
	api_key = p_key if not p_key.is_empty() else OS.get_environment("SENSEN_POSTHOG_KEY")
	host = p_host if not p_host.is_empty() else _env_or(OS.get_environment("SENSEN_POSTHOG_HOST"), HOST_DEFAULT)
	transport = p_transport

static func _env_or(v: String, fallback: String) -> String:
	return v if not v.is_empty() else fallback

## 从持久化状态读一次开关。
func load_opt_out() -> void:
	opted_out = bool(UiState.read().get(OPT_OUT_KEY, false))

static func set_opt_out(value: bool) -> void:
	UiState.write({OPT_OUT_KEY: value})

static func is_opted_out() -> bool:
	return bool(UiState.read().get(OPT_OUT_KEY, false))

func enabled() -> bool:
	return not api_key.is_empty() and not opted_out

## 记一个事件。distinct_id 用自有 user id（未登录用匿名安装 id，由调用方给）。
## 返回是否入队（关闭 / 未登记的事件名返回 false）。
func capture(event: String, distinct_id: String, props: Dictionary = {}) -> bool:
	if not enabled() or not EVENTS.has(event):
		return false
	queue.append({
		"event": event,
		"distinct_id": distinct_id if not distinct_id.is_empty() else "anonymous",
		"properties": Scrub.payload(props),
		"timestamp": Time.get_datetime_string_from_system(true, true),
	})
	if queue.size() >= BATCH_MAX:
		await flush()
	return true

## 把队列发出去；没有传输层就只记在 sent 里（测试与离线）。返回发出的条数。
func flush() -> int:
	if queue.is_empty() or not enabled():
		return 0
	var batch := queue.duplicate()
	queue.clear()
	var body := JSON.stringify({"api_key": api_key, "batch": batch})
	sent.append(batch)
	if transport.is_valid():
		var r = await transport.call("%s/batch/" % host.rstrip("/"),
			PackedStringArray(["content-type: application/json"]), body)
		if r != null and not bool(r.ok):
			# 发不出去就退回队列，下次再试；埋点不该因为断网丢事件，也不该重试到天荒地老。
			queue.append_array(batch.slice(0, BATCH_MAX))
			return 0
	return batch.size()
