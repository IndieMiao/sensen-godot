package com.sensen.map

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import java.util.Locale
import com.mapbox.common.MapboxOptions
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.MapView
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.Style
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * G1 PoC 插件：Mapbox MapView 垫在 Godot 透明渲染面之下（方案 A 的 Android 合成验证）。
 *
 * 层序（自下而上）：MapView(SurfaceView, 常规层) → Godot SurfaceView(media overlay, TRANSLUCENT) → window(原生 UI)。
 * z-order 约束：setZOrderMediaOverlay 必须在 surface attach 到 window 前调用，
 * onMainCreate 处于 Activity.onCreate 流程内且 renderView 已创建（Godot.kt L546 先于 L631），时序合法。
 */
class GodotMapPlugin(godot: Godot) : GodotPlugin(godot) {
    companion object {
        private const val TAG = "GodotMapPlugin"
    }

    private var container: FrameLayout? = null
    private var mapView: MapView? = null

    private var locationManager: LocationManager? = null
    private var locationStarted = false

    private val locationListener = LocationListener { loc -> emitLocation(loc) }

    private fun emitLocation(loc: Location) {
        emitSignal("location_update", loc.latitude, loc.longitude, loc.accuracy.toDouble())
    }

    // MapboxMap 是 @MainThread API：相机状态在 UI 线程订阅时写入缓存，
    // getCameraInfo()（Godot 线程调用）只读缓存，避免跨线程读 native Map。
    @Volatile
    private var cameraInfoCache = ""

    override fun getPluginName() = "GodotMap"

    override fun getPluginSignals() = setOf(
        SignalInfo("map_ready"),
        SignalInfo(
            "location_update",
            Double::class.javaObjectType,
            Double::class.javaObjectType,
            Double::class.javaObjectType,
        ),
    )

    override fun onMainCreate(activity: Activity?): View? {
        val act = activity ?: getActivity() ?: return null
        val surface = godot.renderView?.view
        if (surface != null) {
            surface.setZOrderMediaOverlay(true)
            surface.holder.setFormat(PixelFormat.TRANSLUCENT)
            Log.i(TAG, "Godot SurfaceView -> setZOrderMediaOverlay(true) + TRANSLUCENT")
        } else {
            Log.w(TAG, "Godot renderView 为空，z-order 未设置（G1 失败信号之一）")
        }
        container = FrameLayout(act)
        return container
    }

    // 垫底：本插件的 View 加到 Godot 视图层级 index 0（Godot 渲染面之下）。
    override fun shouldBeOnTop() = false

    @UsedByGodot
    fun createMap(token: String, lat: Double, lng: Double, zoom: Double) {
        runOnUiThread {
            if (mapView != null) {
                // 幂等重入（从其他场景返回）：恢复可见并补发 ready 信号，
                // 否则 GDScript 侧会永远停在"等待 map_ready"。
                mapView?.visibility = View.VISIBLE
                emitSignal("map_ready")
                return@runOnUiThread
            }
            val parent = container ?: run {
                Log.e(TAG, "container 为空，createMap 失败")
                return@runOnUiThread
            }
            MapboxOptions.accessToken = token
            val mv = MapView(parent.context)
            parent.addView(
                mv,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
            mv.mapboxMap.setCamera(
                CameraOptions.Builder()
                    .center(Point.fromLngLat(lng, lat))
                    .zoom(zoom)
                    .build()
            )
            mv.mapboxMap.loadStyle(Style.MAPBOX_STREETS) {
                Log.i(TAG, "style loaded")
                emitSignal("map_ready")
            }
            mv.mapboxMap.subscribeCameraChanged {
                val c = mv.mapboxMap.cameraState
                cameraInfoCache = String.format(
                    Locale.US, "%.5f,%.5f,z%.2f,b%.1f,p%.1f",
                    c.center.latitude(), c.center.longitude(), c.zoom, c.bearing, c.pitch
                )
            }
            mapView = mv
            Log.i(TAG, "MapView created @($lat,$lng) z=$zoom")
        }
    }

    /** 单指拖拽平移：finger 位移 (dx,dy) px，地图内容随手指走。用地图自身投影换算，DPI 无关。 */
    @UsedByGodot
    fun panBy(dx: Double, dy: Double) {
        runOnUiThread {
            val mv = mapView ?: return@runOnUiThread
            val newCenter = mv.mapboxMap.coordinateForPixel(
                ScreenCoordinate(mv.width / 2.0 - dx, mv.height / 2.0 - dy)
            )
            mv.mapboxMap.setCamera(CameraOptions.Builder().center(newCenter).build())
        }
    }

    @UsedByGodot
    fun setZoom(zoom: Double) {
        runOnUiThread {
            mapView?.mapboxMap?.setCamera(CameraOptions.Builder().zoom(zoom).build())
        }
    }

    @UsedByGodot
    fun setPitch(pitch: Double) {
        runOnUiThread {
            mapView?.mapboxMap?.setCamera(CameraOptions.Builder().pitch(pitch).build())
        }
    }

    @UsedByGodot
    fun setBearing(bearing: Double) {
        runOnUiThread {
            mapView?.mapboxMap?.setCamera(CameraOptions.Builder().bearing(bearing).build())
        }
    }

    /** G2 预留：一次性设置完整位姿（单一权威位姿协议的桥接口）。 */
    @UsedByGodot
    fun setCamera(lat: Double, lng: Double, zoom: Double, bearing: Double, pitch: Double) {
        runOnUiThread {
            mapView?.mapboxMap?.setCamera(
                CameraOptions.Builder()
                    .center(Point.fromLngLat(lng, lat))
                    .zoom(zoom)
                    .bearing(bearing)
                    .pitch(pitch)
                    .build()
            )
        }
    }

    /** MapView 的像素密度（= MapInitOptions 默认 pixelRatio）。Godot 侧换算 zoom↔米每像素用。 */
    @UsedByGodot
    fun getPixelRatio(): Double {
        val ctx = container?.context ?: getActivity() ?: return 1.0
        return ctx.resources.displayMetrics.density.toDouble()
    }

    /** 地图整体显隐：离开地图场景时关掉，省 GPU/电（保留实例，返回时秒恢复）。 */
    @UsedByGodot
    fun setMapVisible(visible: Boolean) {
        runOnUiThread {
            mapView?.visibility = if (visible) View.VISIBLE else View.GONE
        }
    }

    /**
     * 启动定位订阅。权限由 GDScript 侧的 OS.request_permissions() 拿（Android 12+
     * 必须 FINE+COARSE 同请求），本方法只在已授权时工作，未授权直接放弃——
     * GDScript 那边有 3 秒超时会回落默认点。
     */
    @UsedByGodot
    fun startLocation() {
        runOnUiThread {
            if (locationStarted) return@runOnUiThread
            val act = getActivity() ?: return@runOnUiThread
            val fine = act.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            val coarse = act.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            if (!fine && !coarse) {
                Log.w(TAG, "定位权限未授予，startLocation 放弃（GDScript 侧靠超时回落）")
                return@runOnUiThread
            }
            val lm = act.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                ?: return@runOnUiThread
            locationManager = lm
            locationStarted = true

            // 先补一发 last-known：冷启动 GPS 首次定影可能要几十秒，而 demo 只等 3 秒。
            // 两个 provider 都取，谁的时间戳新用谁。
            val candidates = mutableListOf<Location>()
            for (p in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                try {
                    lm.getLastKnownLocation(p)?.let(candidates::add)
                } catch (e: Exception) {
                    Log.w(TAG, "getLastKnownLocation($p) 失败: ${e.message}")
                }
            }
            candidates.maxByOrNull { it.time }?.let {
                Log.i(TAG, "last-known 定位 ${it.latitude},${it.longitude} acc=${it.accuracy}")
                emitLocation(it)
            }

            // 再订阅持续更新：有 FINE 用 GPS，只有 COARSE 就退 NETWORK
            val provider = if (fine) LocationManager.GPS_PROVIDER else LocationManager.NETWORK_PROVIDER
            try {
                lm.requestLocationUpdates(provider, 2000L, 5f, locationListener)
                Log.i(TAG, "定位订阅启动 provider=$provider")
            } catch (e: Exception) {
                Log.e(TAG, "requestLocationUpdates 失败: ${e.message}")
            }
        }
    }

    override fun onMainDestroy() {
        runOnUiThread {
            try {
                locationManager?.removeUpdates(locationListener)
            } catch (e: Exception) {
                Log.w(TAG, "removeUpdates 失败: ${e.message}")
            }
        }
        super.onMainDestroy()
    }

    /** HUD 调试用：当前相机状态（UI 线程写入的缓存，任意线程可读）。 */
    @UsedByGodot
    fun getCameraInfo(): String = cameraInfoCache
}
