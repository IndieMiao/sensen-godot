class_name AppRoutes
extends RefCounted
## 海外版页面路由表（08-30 调研 §3.1）：登录 → 壳（地图 / 动态 / 消息 / 我的四个 Tab）→ 压栈子页。
## 这里只有数据：场景路径、Tab 顺序、标题与图标。整场景切换在 AppRouter，Tab 切换在 AppShell。
## Tab id 用 String 而不是 StringName：作为 Dictionary 键和 UiState 持久化值时少一次类型换算。

const BOOT := "res://scenes/app/boot.tscn"
## 首启合规流（R2 年龄门 → R3 同意 → 登录）
const AGE_GATE := "res://scenes/app/age_gate_page.tscn"
const CONSENT := "res://scenes/app/consent_page.tscn"
const LOGIN := "res://scenes/app/login_page.tscn"
const SHELL := "res://scenes/app/app_shell.tscn"

const TAB_MAP := "map"
const TAB_FEED := "feed"
const TAB_IM := "im"
const TAB_PROFILE := "profile"
## Tab 顺序即底栏顺序。地图是首页，也是常驻底层——§3.1：Mapbox 原生 view 只在地图页垫底，
## 进出地图页时显隐，其余页面纯 Godot 全屏。
const TABS: Array[String] = [TAB_MAP, TAB_FEED, TAB_IM, TAB_PROFILE]

const TAB_SCENES := {
	TAB_MAP: "res://scenes/app/pages/map_page.tscn",
	TAB_FEED: "res://scenes/app/pages/feed_page.tscn",
	TAB_IM: "res://scenes/app/pages/im_page.tscn",
	TAB_PROFILE: "res://scenes/app/pages/profile_page.tscn",
}
const TAB_TITLES := {TAB_MAP: "Map", TAB_FEED: "Feed", TAB_IM: "Chats", TAB_PROFILE: "Me"} ## i18n 由 AppShell tr()
const TAB_ICONS := {TAB_MAP: "map-pin", TAB_FEED: "book-open", TAB_IM: "users-round", TAB_PROFILE: "user-round"}

## 压栈子页（AppRouter.push_instance）：全屏、带返回按钮，弹出后回到壳的当前 Tab。
const SETTINGS := "res://scenes/app/pages/settings_page.tscn"
const VOICE_ROOM := "res://scenes/app/pages/voice_room_page.tscn"
## B2 聊天页：push_instance 时 args = {"conversation": 会话字典}。
const CHAT := "res://scenes/app/pages/chat_page.tscn"
## 用户主页：args = {"user_id": uuid} 或 {"handle": "ali"}；动态详情：args = {"post": 帖子字典} 或 {"post_id": id}。
const USER := "res://scenes/app/pages/user_page.tscn"
const POST := "res://scenes/app/pages/post_page.tscn"
## 调试构建才有入口（设置页）：A6 生命周期通知探针。
const LIFECYCLE_PROBE := "res://scenes/app/pages/lifecycle_probe_page.tscn"

static func is_tab(id: String) -> bool:
	return TABS.has(id)

static func tab_index(id: String) -> int:
	return TABS.find(id)

static func tab_scene(id: String) -> String:
	return str(TAB_SCENES.get(id, ""))

static func tab_title(id: String) -> String:
	return str(TAB_TITLES.get(id, id))

static func tab_icon(id: String) -> String:
	return str(TAB_ICONS.get(id, ""))

static func home_tab() -> String:
	return TAB_MAP
