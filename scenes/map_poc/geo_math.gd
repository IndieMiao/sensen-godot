class_name MapGeoMath
extends RefCounted
## 地图 PoC 的地理↔本地米制换算（等距近似 + 浮动原点）。
## 世界系约定：原点 = 当前锚点地理坐标，x=东，-z=北，单位米。
## 等距近似在城市尺度（几 km）误差可忽略；跨城/跨洋距离只用于剔除判断，
## 精确性由浮动原点重锚保证（相机附近永远是小坐标）。

const EARTH_CIRCUM := 40075016.686
const M_PER_DEG_LAT := 111319.4908 # 2πR/360，R=6378137

## 经度差环绕到 [-180,180)：上海(121.47E)→洛杉矶(118.24W) 的最短方向是向东跨日界线，
## 直接相减得 -239.7° 会把部件放到向西 2.3 万公里外——必须环绕。
static func wrap_dlng(dlng: float) -> float:
	return fposmod(dlng + 180.0, 360.0) - 180.0

static func geo_to_world(lat: float, lng: float, anchor_lat: float, anchor_lng: float) -> Vector3:
	var dlng := wrap_dlng(lng - anchor_lng)
	return Vector3(
		dlng * M_PER_DEG_LAT * cos(deg_to_rad(anchor_lat)),
		0.0,
		-(lat - anchor_lat) * M_PER_DEG_LAT)

static func world_to_geo(w: Vector3, anchor_lat: float, anchor_lng: float) -> Vector2:
	var lat := anchor_lat + (-w.z) / M_PER_DEG_LAT
	var lng := anchor_lng + w.x / (M_PER_DEG_LAT * cos(deg_to_rad(anchor_lat)))
	return Vector2(lat, wrapf(lng, -180.0, 180.0))

## 地图逻辑像素（512 瓦片 × pixelRatio）下，纬度 lat 处每逻辑像素的地面米数。
static func meters_per_logical_px(lat: float, zoom: float) -> float:
	return EARTH_CIRCUM * cos(deg_to_rad(lat)) / (512.0 * pow(2.0, zoom))

## Mapbox 相机到注视点的距离（米）：d_px = (H/2)/tan(fov/2)，再乘地面分辨率。
static func cam_distance_m(viewport_h_logical_px: float, fov_deg: float, lat: float, zoom: float) -> float:
	return (viewport_h_logical_px * 0.5) / tan(deg_to_rad(fov_deg * 0.5)) \
			* meters_per_logical_px(lat, zoom)

## Web Mercator 归一化坐标 [0,1)（x 向东、y 向南），与 Mapbox 一致；纬度钳在 ±85.051129°。
static func mercator_x(lng: float) -> float:
	return (lng + 180.0) / 360.0

static func mercator_y(lat: float) -> float:
	var phi := deg_to_rad(clampf(lat, -85.051129, 85.051129))
	return (1.0 - log(tan(PI * 0.25 + phi * 0.5)) / PI) * 0.5
