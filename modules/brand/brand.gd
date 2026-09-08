class_name Brand
extends RefCounted
## 应用身份（E6 / R11）的占位单一来源。品牌决策 = SSLAUNCH B1，尚未拍板。
##
## 三端开屏都从这里取值，但引擎和导出器读的是另外两个文件里的**字面值**：
##   Godot 引擎开屏  project.godot   [application] boot_splash/*
##   iOS 启动画面    export_presets.cfg  preset.1  storyboard/*
##   Android 12+     export_presets.cfg  preset.0  launcher_icons/*
##
## Android 侧不需要改 themes.xml：导出器按 launcher_icons/* 生成
## `@mipmap/icon_background` 与 `@drawable/splash_icon`，自动生成的
## GodotAppSplashTheme 正好引用这两个资源。android/build 是 gitignore 的，
## 重装模板即丢，任何定制都不许写进去（同 B5 地图插件改独立 AAR 的原因）。
##
## 改本文件必须同步改上面两个配置文件；tests/app/test_brand_splash.gd
## 守护三端不漂移，漏改哪一端就红哪一条。

## 开屏底色取壳的纸色：开屏 → 登录页不能闪一下别的颜色。
const SPLASH_BG := DesignTokens.UI_PAPER
## 标识主色，占位标识与 monochrome 图标都由它推导。
const MARK_INK := DesignTokens.UI_GREEN

## 商店名与包名仍是一期占位，定版属 E6（阻塞于 SSLAUNCH B1），本卡不动：
## 动包名会连带废掉 Firebase OAuth client 与 iOS 描述文件。
const DISPLAY_NAME := "SensenAvatar"

## B1 落地前恒为 true。发布前检查（docs/release-process.md）据此拦提审。
const PLACEHOLDER := true

const MARK_SVG := "res://assets/brand/logo_mark.svg"
const GENERATED_DIR := "res://assets/brand/generated"

const SPLASH_IMAGE := GENERATED_DIR + "/splash.png"
const ICON_LEGACY := GENERATED_DIR + "/icon_192.png"
const ICON_ADAPTIVE_FG := GENERATED_DIR + "/icon_adaptive_fg_432.png"
const ICON_ADAPTIVE_BG := GENERATED_DIR + "/icon_adaptive_bg_432.png"
const ICON_ADAPTIVE_MONO := GENERATED_DIR + "/icon_adaptive_mono_432.png"
const STORYBOARD_2X := GENERATED_DIR + "/storyboard_2x.png"
const STORYBOARD_3X := GENERATED_DIR + "/storyboard_3x.png"

## 生成物的边长，tools/brand/render_brand_assets.gd 与测试共用。
## 自适应图标的内容必须落在中心 66% 安全区内，否则被系统裁掉。
const SIZE_SPLASH := 512
const SIZE_LEGACY := 192
const SIZE_ADAPTIVE := 432
const ADAPTIVE_CONTENT_RATIO := 0.6
const SIZE_STORYBOARD_2X := 384
const SIZE_STORYBOARD_3X := 576

## 生成物路径 → 期望边长。生成脚本据此产出，测试据此校验。
static func expected_sizes() -> Dictionary:
	return {
		SPLASH_IMAGE: SIZE_SPLASH,
		ICON_LEGACY: SIZE_LEGACY,
		ICON_ADAPTIVE_FG: SIZE_ADAPTIVE,
		ICON_ADAPTIVE_BG: SIZE_ADAPTIVE,
		ICON_ADAPTIVE_MONO: SIZE_ADAPTIVE,
		STORYBOARD_2X: SIZE_STORYBOARD_2X,
		STORYBOARD_3X: SIZE_STORYBOARD_3X,
	}
