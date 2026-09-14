package com.sensen.map

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.ApplicationInfo
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
import com.mapbox.maps.extension.localization.localizeLabels
import com.mapbox.maps.plugin.attribution.attribution
import com.mapbox.maps.plugin.compass.compass
import com.mapbox.maps.plugin.logo.logo
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
        private const val QA_SCENE_EXTRA = "com.sensen.qa.SCENE"
        private const val QA_STRESS_SCENE = "stress"
        internal fun mapLabelLocale(language: String): Locale =
            if (language == "en") Locale.ENGLISH else Locale.SIMPLIFIED_CHINESE
        // demo 锚点由 GDScript 侧取"第一次收到的定位"锁定、之后永不更新（避免演示中途
        // 地图跳动）。所以 last-known 缓存一旦太旧就绝不能拿去当首帧发——发出去就是
        // 永久锚错城市，且后面真实 GPS 定位到达时也不会被拿来纠正。5 分钟内的缓存
        // 视为等同于"当前位置"；更旧的宁可没有，等下面的实时订阅。
        private const val LAST_KNOWN_MAX_AGE_MS = 5 * 60 * 1000L

        internal fun qaCommandLine(debuggable: Boolean, scene: String?): List<String> =
            if (debuggable && scene == QA_STRESS_SCENE) {
                listOf("++", "--qa-scene=stress")
            } else {
                emptyList()
            }

    }

    private var container: FrameLayout? = null
    private var mapView: MapView? = null
    private var mapLocale: Locale = Locale.SIMPLIFIED_CHINESE
    private var mapSceneVisible = true
    @Volatile private var mainLoopStarted = false
    private var renderPausedEarly = false

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

    override fun getCommandLineParams(_originalParams: List<String>): List<String> {
        val activity = getActivity() ?: return emptyList()
        val debuggable =
            (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        return qaCommandLine(
            debuggable,
            activity.intent?.getStringExtra(QA_SCENE_EXTRA),
        )
    }

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

    override fun onGodotMainLoopStarted() {
        mainLoopStarted = true
    }

    override fun onMainPause() {
        val renderView = godot.renderView ?: return
        if (mainLoopStarted) {
            // Godot 4.7 pauses Vulkan only onStop, after Android can retire the window surface.
            renderView.onActivityStopped()
            renderPausedEarly = true
        }
    }

    override fun onMainResume() {
        if (renderPausedEarly) {
            // onResume can follow a translucent activity without another onStart.
            godot.renderView?.onActivityStarted()
            renderPausedEarly = false
        }
    }

    @UsedByGodot
    fun createMap(token: String, lat: Double, lng: Double, zoom: Double) {
        runOnUiThread {
            if (mapView != null) {
                // 幂等重入（从其他场景返回）：恢复可见并补发 ready 信号，
                // 否则 GDScript 侧会永远停在"等待 map_ready"。
                updateMapSceneVisibility(true)
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
            mv.mapboxMap.loadStyle(Style.MAPBOX_STREETS) { style ->
                style.localizeLabels(mapLocale)
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

    @UsedByGodot
    fun setLanguage(language: String) {
        runOnUiThread {
            mapLocale = mapLabelLocale(language)
            mapView?.mapboxMap?.getStyle { style -> style.localizeLabels(mapLocale) }
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

    /** Pause the map under opaque Godot scenes, retaining its last composed buffer. */
    @UsedByGodot
    fun setMapVisible(visible: Boolean) {
        runOnUiThread {
            updateMapSceneVisibility(visible)
        }
    }

    private fun updateMapSceneVisibility(visible: Boolean) {
        val mv = mapView ?: return
        if (mapSceneVisible == visible) return
        mapSceneVisible = visible
        // Removing the SurfaceView reveals the launcher while Godot submits its first opaque frame.
        // onStop pauses rendering without removing that surface from Android's compositor.
        mv.logo.enabled = visible
        mv.attribution.enabled = visible
        mv.compass.enabled = visible
        if (visible) mv.onStart() else mv.onStop()
    }

    /** Android 根页返回遵循系统语义：任务进入后台并保留热启动状态。 */
    @UsedByGodot
    fun moveTaskToBack() {
        runOnUiThread {
            getActivity()?.moveTaskToBack(true)
        }
    }

    /**
     * 启动定位订阅。权限由 GDScript 侧的 OS.request_permissions() 拿（Android 12+
     * 必须 FINE+COARSE 同请求），本方法只在已授权时工作，未授权直接放弃——
     * GDScript 那边有 3 秒超时会回落默认点。
     *
     * 幂等重入（从换装房返回地图场景）：GDScript 侧的 home 锚点（map_poc.gd 的
     * _home_resolved）是场景实例变量，change_scene_to_file 重建地图场景后会
     * 再调一次本方法——参照上面 createMap() 的重入处理，last-known 的读取和
     * 补发必须每次都做，不能被 locationStarted 挡住。否则返回场景只能指望仍在
     * 跑的旧订阅（minDistance=5f，静止设备摸不到新数据），3 秒超时一到就永久
     * 错锚上海。locationStarted 只挡下面的 requestLocationUpdates 本身，避免
     * 重入把同一个 listener 在同一个 provider 上重复订阅。
     */
    @UsedByGodot
    fun startLocation() {
        runOnUiThread {
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

            // 先补一发 last-known：冷启动 GPS 首次定影可能要几十秒，而 demo 只等 3 秒。
            // 两个 provider 都取，谁的时间戳新用谁。每次调用 startLocation 都做
            // （不受下面的 locationStarted 影响）——重入时靠它把新鲜缓存立刻喂回去。
            val candidates = mutableListOf<Location>()
            for (p in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                try {
                    lm.getLastKnownLocation(p)?.let(candidates::add)
                } catch (e: Exception) {
                    Log.w(TAG, "getLastKnownLocation($p) 失败: ${e.message}")
                }
            }
            candidates.maxByOrNull { it.time }?.let {
                val ageMs = System.currentTimeMillis() - it.time
                if (ageMs <= LAST_KNOWN_MAX_AGE_MS) {
                    Log.i(TAG, "last-known 定位 ${it.latitude},${it.longitude} acc=${it.accuracy}")
                    emitLocation(it)
                } else {
                    Log.i(TAG, "last-known 定位太旧（${ageMs / 1000}秒前），不作为锚点发出，等实时订阅")
                }
            }

            if (locationStarted) return@runOnUiThread

            // 再订阅持续更新：GPS 与 NETWORK 两个 provider，权限允许的都订上。
            // 室内环境 GPS 常常几分钟拿不到定影，只订 GPS（原实现）会让 demo 在
            // 室内跑很容易撞上 3 秒超时回落；listener 本身与 provider 无关，
            // GDScript 侧取第一个到达的即可。这个订阅故意跨场景存活到插件销毁
            // 为止（不在场景退出时 stopLocation）——它是场景重入时唯一能保证
            // 送达新鲜定位的来源，见上面的函数注释。每个 provider 单独 try/catch，
            // 一个不可用不连累另一个。
            var subscribed = false
            if (fine) {
                try {
                    lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 2000L, 5f, locationListener)
                    subscribed = true
                    Log.i(TAG, "定位订阅启动 provider=${LocationManager.GPS_PROVIDER}")
                } catch (e: Exception) {
                    Log.e(TAG, "requestLocationUpdates(GPS) 失败: ${e.message}")
                }
            }
            if (coarse) {
                try {
                    lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 2000L, 5f, locationListener)
                    subscribed = true
                    Log.i(TAG, "定位订阅启动 provider=${LocationManager.NETWORK_PROVIDER}")
                } catch (e: Exception) {
                    Log.e(TAG, "requestLocationUpdates(NETWORK) 失败: ${e.message}")
                }
            }
            locationStarted = subscribed
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
