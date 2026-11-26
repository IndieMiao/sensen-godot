package com.sensen.map

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.graphics.drawable.ColorDrawable
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.SurfaceView
import android.view.SurfaceHolder
import android.os.SystemClock
import android.widget.FrameLayout
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONArray
import org.json.JSONObject
import com.mapbox.bindgen.Value
import com.mapbox.maps.SourceQueryOptions
import com.mapbox.common.MapboxOptions
import com.mapbox.common.TelemetryUtils
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.MapView
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.Style
import com.mapbox.maps.extension.localization.localizeLabels
import com.mapbox.maps.extension.style.layers.properties.generated.ProjectionName
import com.mapbox.maps.extension.style.projection.generated.projection
import com.mapbox.maps.extension.style.projection.generated.setProjection
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
        // C-168: how long Godot's render thread waits between frames for the UI thread to change its Surface format.
        private const val FORMAT_SWAP_WAIT_MS = 1000L

        internal fun qaCommandLine(debuggable: Boolean, scene: String?): List<String> =
            if (debuggable && scene == QA_STRESS_SCENE) {
                listOf("++", "--qa-scene=stress")
            } else {
                emptyList()
            }

    }

    private var container: FrameLayout? = null
    private var mapView: MapView? = null
    private var mapPresentation: NativeMapPresentation? = null
    private val godotSurfaceMode = NativeGodotSurfaceMode()
    private var godotFormatHolder: SurfaceHolder? = null
    private var godotRequestedFormat = Int.MIN_VALUE
    private var godotObservedFormat = Int.MIN_VALUE
    private var godotSurfaceGeneration = 0L
    private var godotFormatError = ""
    private var presentationDestroyed = false
    private val godotSurfaceCallbacks = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            if (holder !== godotFormatHolder || presentationDestroyed) return
            godotSurfaceGeneration++
            godotObservedFormat = Int.MIN_VALUE
            // Do not change Surface format reentrantly from its creation callback.
            godot.renderView?.view?.post { applyGodotSurfaceMode() }
            cacheMapVisibility()
        }
        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            if (holder !== godotFormatHolder || presentationDestroyed) return
            godotObservedFormat = format
            cacheMapVisibility()
        }
        override fun surfaceDestroyed(holder: SurfaceHolder) {
            if (holder !== godotFormatHolder || presentationDestroyed) return
            godotObservedFormat = Int.MIN_VALUE
            cacheMapVisibility()
        }
    }
    private var mapOcclusionColor = 0xff202020.toInt()
    @Volatile private var mapVisibilityCache = "{\"created\":false}"
    private var parcelController: ParcelMapController? = null
    private var parcelActivityResumed = true
    private val parcelLifecycleEpoch = AtomicLong(0)
    private var mapLocale: Locale = Locale.SIMPLIFIED_CHINESE
    private var mapSceneVisible = true
    private var cityStyle = false
    private var styleIsReady = false
    private val originalCityProperties = mutableMapOf<Pair<String, String>, Value>()
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
        SignalInfo("parcel_ready", Long::class.javaObjectType, Long::class.javaObjectType, String::class.java),
        SignalInfo("parcel_query_result", Long::class.javaObjectType, Long::class.javaObjectType, Long::class.javaObjectType, String::class.java),
        SignalInfo("parcel_error", Long::class.javaObjectType, Long::class.javaObjectType, String::class.java),
        SignalInfo("pois_received", Long::class.javaObjectType, String::class.java),
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
        applyGodotSurfaceMode()
        return container
    }

    // 垫底：本插件的 View 加到 Godot 视图层级 index 0（Godot 渲染面之下）。
    override fun shouldBeOnTop() = false

    override fun onGodotMainLoopStarted() {
        mainLoopStarted = true
    }

    override fun onMainPause() {
        parcelLifecycleEpoch.incrementAndGet() // Before scheduling UI work or stopping Godot.
        runOnUiThread { parcelActivityResumed = false; applyMapPresentation() }
        val renderView = godot.renderView ?: return
        if (mainLoopStarted) {
            // Godot 4.7 pauses Vulkan only onStop, after Android can retire the window surface.
            renderView.onActivityStopped()
            renderPausedEarly = true
        }
    }

    override fun onMainResume() {
        runOnUiThread { parcelActivityResumed = true; applyGodotSurfaceMode(); applyMapPresentation() }
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
            // q(133) v3: no logo or ⓘ on the map (under the Godot surface they were punched out and their taps went to
            // Godot); the game draws one credit line, and its Licenses › Mapbox page holds the credits and the telemetry
            // switch (setTelemetryEnabled).
            mv.logo.enabled = false
            mv.attribution.enabled = false
            mv.mapboxMap.setCamera(
                CameraOptions.Builder()
                    .center(Point.fromLngLat(lng, lat))
                    .zoom(zoom)
                    .build()
            )
            parcelController = ParcelMapController(mv,
                ready = { generation, style, json -> emitSignal("parcel_ready", generation, style, json) },
                result = { request, generation, style, json -> emitSignal("parcel_query_result", request, generation, style, json) },
                error = { generation, style, code -> emitSignal("parcel_error", generation, style, code) })
            parcelController?.setInteractive(mapSceneVisible && parcelActivityResumed)
            mv.mapboxMap.loadStyle(Style.MAPBOX_STREETS) { style ->
                styleIsReady = true
                // Streets v12 在低 zoom 默认 globe：Godot 叠加层按 Web Mercator 投影标记，
                // 必须锁死 Mercator，否则国家级视野下 pin 与底图错位。
                style.setProjection(projection(ProjectionName.MERCATOR))
                style.localizeLabels(mapLocale)
                applyCityStyle(style)
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
            mapPresentation = NativeMapPresentation(
                background = { color -> parent.setBackgroundColor(color) },
                visibility = { shown ->
                    mv.visibility = if (shown) View.VISIBLE else View.INVISIBLE
                    mv.isEnabled = shown
                    mv.compass.enabled = shown
                },
                render = { running -> if (running) mv.onStart() else mv.onStop() },
            )
            applyMapPresentation()
            Log.i(TAG, "MapView created @($lat,$lng) z=$zoom")
        }
    }

    /** Cross-thread watermark: Godot reads this again immediately before deferred delivery. */
    @UsedByGodot
    fun getParcelLifecycleEpoch(): Long = parcelLifecycleEpoch.get()

    /** Dynamic farms: normalized points are relative to the full native MapView, not a Godot panel. */
    @UsedByGodot
    fun setParcelSources(generation: Long, configJson: String) {
        runOnUiThread {
            val parcels = parcelController
            if (parcels == null) emitSignal("parcel_error", generation, 0L, "map_not_ready")
            else parcels.setSources(generation, configJson)
        }
    }

    @UsedByGodot
    fun queryParcelAt(requestId: Long, generation: Long, xNormalized: Double, yNormalized: Double) {
        runOnUiThread {
            val parcels = parcelController
            if (parcels == null) emitSignal("parcel_error", generation, 0L, "map_not_ready")
            else parcels.queryAt(requestId, generation, xNormalized, yNormalized)
        }
    }

    @UsedByGodot
    fun setParcelStates(generation: Long, batchJson: String) {
        runOnUiThread { parcelController?.setStates(generation, batchJson) }
    }

    @UsedByGodot
    fun setParcelClaims(generation: Long, claimsJson: String) {
        runOnUiThread { parcelController?.setClaims(generation, claimsJson) }
    }

    @UsedByGodot
    fun setParcelBuildingHighlight(generation: Long, key: String, parcelId: String) {
        runOnUiThread { parcelController?.setBuildingHighlight(generation, key, parcelId) }
    }

    /** C-130: the dynamic farm starter zone marker (boundary and style JSON, "" clears it), its own layers. */
    @UsedByGodot
    fun setStarterZone(generation: Long, zoneJson: String) {
        runOnUiThread { parcelController?.setStarterZone(generation, zoneJson) }
    }

    @UsedByGodot
    fun clearParcelLayers(generation: Long) {
        runOnUiThread { parcelController?.clear(generation) }
    }

    @UsedByGodot
    fun setLanguage(language: String) {
        runOnUiThread {
            mapLocale = mapLabelLocale(language)
            mapView?.mapboxMap?.getStyle { style -> style.localizeLabels(mapLocale) }
        }
    }

    @UsedByGodot
    fun setCityStyle(enabled: Boolean) {
        runOnUiThread {
            cityStyle = enabled
            // C-145: another map page (city map, map_poc) takes the map: the dynamic farm map's hidden place icons come
            // back first, so the city palette records and later restores their own visibility.
            parcelController?.releasePlaceIcons()
            mapView?.mapboxMap?.getStyle { applyCityStyle(it) }
        }
    }

    private fun applyCityStyle(style: Style) {
        if (!cityStyle) {
            originalCityProperties.forEach { (key, value) -> style.setStyleLayerProperty(key.first, key.second, value) }
            originalCityProperties.clear()
            return
        }
        fun set(id: String, property: String, value: String) {
            val key = id to property
            if (!originalCityProperties.containsKey(key)) {
                originalCityProperties[key] = style.getStyleLayerProperty(id, property).value
            }
            style.setStyleLayerProperty(id, property, Value(value))
        }
        for (layer in style.styleLayers) {
            val id = layer.id
            if (id in ParcelMapController.LAYERS) continue // Own styles survive city palette/language changes.
            when {
                id == "land" -> set(id, "background-color", "#f4f1e7")
                id == "water" -> set(id, "fill-color", "#a3dcea")
                id == "water-shadow" -> set(id, "fill-color", "#8ec4d0")
                id == "waterway" -> set(id, "line-color", "#a3dcea")
                id == "landuse" || id == "national-park" -> set(id, "fill-color", "#d4e5c8")
                id == "landcover" -> set(id, "fill-color", "#e1ebd8")
                id == "building" -> set(id, "fill-color", "#e6e1d4")
                layer.type == "line" && (id.startsWith("road-") || id.startsWith("bridge-")) && !id.contains("rail") ->
                    set(id, "line-color", if (id.endsWith("case")) "#e3d8c5" else if (id.contains("motorway")) "#ead2af" else "#fffdf7")
                id == "poi-label" || id.contains("road-number") || id.contains("airport-label") || id.contains("transit-label") || id.contains("settlement-subdivision") -> set(id, "visibility", "none")
                layer.type == "symbol" -> {
                    set(id, "text-color", "#77877c")
                    set(id, "text-halo-color", "#faf8f0")
                    val key = id to "text-size"
                    if (!originalCityProperties.containsKey(key)) originalCityProperties[key] = style.getStyleLayerProperty(id,"text-size").value
                    // 国家级视野要分得出层级：国名 > 省州名 > 其余（城市街区统一 11）。
                    val size = when {
                        id.startsWith("country-label") || id.startsWith("continent-label") -> 14.0
                        id.startsWith("state-label") -> 12.0
                        else -> 11.0
                    }
                    style.setStyleLayerProperty(id, "text-size", Value(size))
                }
            }
        }
    }

    /** Read only loaded vector tiles. No persistent Search Box cache or user-location query. */
    @UsedByGodot
    fun queryCityPois(requestId: Long) {
        runOnUiThread {
            val mv = mapView
            if (mv == null || !styleIsReady) {
                emitSignal("pois_received", requestId, "{\"features\":[],\"error\":\"loading\"}")
                return@runOnUiThread
            }
            mv.mapboxMap.querySourceFeatures("composite", SourceQueryOptions(listOf("poi_label"), Value(true))) { result ->
                if (result.isError) {
                    Log.w(TAG, "POI query: ${result.error}")
                    emitSignal("pois_received", requestId, "{\"features\":[],\"error\":\"unavailable\"}")
                } else {
                    val rows = JSONArray()
                    val seen = HashSet<String>()
                    val center = mv.mapboxMap.cameraState.center
                    val features = result.value.orEmpty().map { it.queriedFeature.feature }
                        .filter { it.geometry() is Point }
                        .sortedBy { val p = it.geometry() as Point; kotlin.math.abs(p.latitude() - center.latitude()) + kotlin.math.abs(p.longitude() - center.longitude()) }
                    for (f in features) {
                        val point = f.geometry() as Point
                        val pixel = mv.mapboxMap.pixelForCoordinate(point)
                        if (pixel.x < 0 || pixel.y < 0 || pixel.x > mv.width || pixel.y > mv.height) continue
                        val props = f.properties() ?: continue
                        fun field(key: String): String = props.get(key)?.takeUnless { it.isJsonNull }?.asString.orEmpty()
                        val name = field(if (mapLocale.language == "en") "name_en" else "name_zh-Hans").ifBlank { field("name") }
                        if (name.isBlank()) continue
                        val id = "tile:" + (f.id() ?: (name + ":" + point.longitude() + ":" + point.latitude()))
                        if (!seen.add(id)) continue
                        rows.put(JSONObject().put("id", id).put("name", name).put("lat", point.latitude()).put("lng", point.longitude())
                            .put("maki", field("maki")).put("class", field("class"))
                            .put("category", field(if (mapLocale.language == "en") "category_en" else "category_zh-Hans"))
                            .put("rank", field("filterrank").toDoubleOrNull() ?: 5.0))
                        if (rows.length() >= 100) break
                    }
                    emitSignal("pois_received", requestId, JSONObject().put("features", rows).toString())
                }
            }
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

    /** Hide the actual native view tree and its Surface; onStop alone retains a visible buffer. */
    @UsedByGodot
    fun setMapVisible(visible: Boolean) {
        if (!visible) parcelLifecycleEpoch.incrementAndGet()
        runOnUiThread { updateMapSceneVisibility(visible) }
    }

    /** Scene-supplied opaque fallback behind the translucent Godot SurfaceView. */
    @UsedByGodot
    fun setMapOcclusionColor(rgb: String) {
        val color = NativeMapPresentation.opaqueRgb(rgb) ?: return
        runOnUiThread { mapOcclusionColor = color; applyMapPresentation() }
    }

    /** Explicit 3D-only mode; it is independent of Activity pause and MapView visibility. */
    @UsedByGodot
    fun setGodotSurfaceOpaque(opaque: Boolean) {
        godotSurfaceMode.request(opaque)
        // Read current intent when executed: a queued old transition cannot restore transparency.
        runOnUiThread { applyGodotSurfaceMode() }
    }

    private fun applyGodotSurfaceMode() {
        if (presentationDestroyed) return
        val surface = godot.renderView?.view ?: run { godotFormatError = "surface_unavailable"; return }
        val holder = surface.holder
        if (holder !== godotFormatHolder) {
            godotFormatHolder?.removeCallback(godotSurfaceCallbacks)
            godotFormatHolder = holder
            godotRequestedFormat = Int.MIN_VALUE
            godotObservedFormat = Int.MIN_VALUE
            holder.addCallback(godotSurfaceCallbacks)
        }
        val format = godotSurfaceMode.format()
        if (godotRequestedFormat != format) {
            godotRequestedFormat = format // Set before callbacks; same-format recreation must not loop.
            val renderView = godot.renderView
            if (mainLoopStarted && renderView != null && holder.surface.isValid) {
                // C-168: a new format replaces the Surface under Godot's render thread, and Godot's GLSurfaceView
                // does not wait for it: a frame in flight then presents to the old Surface (EGL_BAD_SURFACE) and the
                // thread draws nothing more until the Surface is destroyed (the app backgrounded). So the change is
                // made while that thread waits between frames; it then sees the new size and makes its EGL surface.
                renderView.queueOnRenderThread {
                    val applied = CountDownLatch(1)
                    if (!surface.post { setGodotFormat(holder, format); applied.countDown() }) applied.countDown()
                    applied.await(FORMAT_SWAP_WAIT_MS, TimeUnit.MILLISECONDS)
                }
            } else {
                setGodotFormat(holder, format)
            }
        }
        cacheMapVisibility()
    }

    /** UI thread. A request already replaced by a newer one (or a newer holder) is not applied. */
    private fun setGodotFormat(holder: SurfaceHolder, format: Int) {
        if (presentationDestroyed || holder !== godotFormatHolder || godotRequestedFormat != format) return
        try {
            holder.setFormat(format)
            godotFormatError = ""
        } catch (error: RuntimeException) {
            godotRequestedFormat = Int.MIN_VALUE
            godotFormatError = error.javaClass.simpleName
        }
        cacheMapVisibility()
    }

    /** Cached UI-thread snapshot only. Poll again to observe the refresh queued by this call. */
    @UsedByGodot
    fun getMapVisibilityState(): String {
        runOnUiThread { cacheMapVisibility() }
        return mapVisibilityCache
    }

    private fun updateMapSceneVisibility(visible: Boolean) {
        mapSceneVisible = visible // Retain an early hide even before MapView creation.
        applyMapPresentation()
    }

    private fun applyMapPresentation() {
        val shown = mapSceneVisible && parcelActivityResumed
        parcelController?.setInteractive(shown)
        mapPresentation?.apply(mapSceneVisible, parcelActivityResumed, mapOcclusionColor)
        // Before creation, the same opaque fallback prevents exposing the Activity/launcher.
        if (mapView == null) container?.setBackgroundColor(if (shown) 0 else mapOcclusionColor)
        cacheMapVisibility()
    }

    private fun cacheMapVisibility() {
        val mv = mapView
        val surfaces = JSONArray()
        fun inspect(view: View) {
            if (view is SurfaceView && surfaces.length() < 16) surfaces.put(JSONObject().apply {
                put("visibility", view.visibility); put("shown", view.isShown)
                put("surface_valid", view.holder.surface.isValid)
            })
            if (view is ViewGroup) for (index in 0 until view.childCount) inspect(view.getChildAt(index))
        }
        if (mv != null) inspect(mv)
        mapVisibilityCache = JSONObject().apply {
            put("created", mv != null); put("scene_visible", mapSceneVisible)
            put("activity_resumed", parcelActivityResumed)
            put("map_visibility", mv?.visibility ?: -1); put("map_shown", mv?.isShown ?: false)
            put("occlusion_color", String.format(Locale.US, "#%08X", mapOcclusionColor))
            put("backdrop_requested_opaque", !(mapSceneVisible && parcelActivityResumed))
            put("backdrop_argb", (container?.background as? ColorDrawable)?.color ?: 0)
            put("container_visibility", container?.visibility ?: -1)
            put("godot_surface_visibility", godot.renderView?.view?.visibility ?: -1)
            put("godot_surface_mode", godotSurfaceMode.snapshot())
            put("godot_requested_format", godotRequestedFormat)
            put("godot_observed_format", godotObservedFormat)
            put("godot_surface_generation", godotSurfaceGeneration)
            put("godot_format_error", godotFormatError)
            put("epoch", parcelLifecycleEpoch.get()); put("sample_uptime_ms", SystemClock.uptimeMillis())
            put("surfaces", surfaces)
        }.toString()
    }

    /**
     * Licenses › Mapbox › Share anonymous map usage (q(133) v3): Mapbox's telemetry, through Mapbox Common's public
     * TelemetryUtils (no map view needed). The SDK keeps the choice.
     */
    @UsedByGodot
    fun setTelemetryEnabled(enabled: Boolean) {
        try {
            TelemetryUtils.setEventsCollectionState(enabled) { }
        } catch (e: Throwable) {
            Log.e(TAG, "telemetry switch failed", e)
        }
    }

    @UsedByGodot
    fun isTelemetryEnabled(): Boolean {
        return try {
            TelemetryUtils.getEventsCollectionState()
        } catch (e: Throwable) {
            Log.e(TAG, "telemetry state unreadable", e)
            true
        }
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
        parcelLifecycleEpoch.incrementAndGet()
        runOnUiThread {
            presentationDestroyed = true
            godotFormatHolder?.removeCallback(godotSurfaceCallbacks)
            godotFormatHolder = null
            mapPresentation?.apply(false, false, mapOcclusionColor)
            mapPresentation = null
            parcelController?.close(); parcelController = null
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


/** Ordered UI effects, separated so delayed lifecycle transitions can be checked without a device. */
internal class NativeMapPresentation(
    private val background: (Int) -> Unit,
    private val visibility: (Boolean) -> Unit,
    private val render: (Boolean) -> Unit,
) {
    private var rendering: Boolean? = null
    fun apply(sceneVisible: Boolean, resumed: Boolean, color: Int) {
        val shown = sceneVisible && resumed
        if (shown) {
            if (rendering != true) render(true)
            visibility(true)
            background(0) // Map supplies the background again only after it is visible.
        } else {
            background(color or 0xff000000.toInt())
            visibility(false) // Remove the composed map/labels before stopping its render loop.
            if (rendering != false) render(false)
        }
        rendering = shown
    }
    companion object {
        fun opaqueRgb(value: String): Int? =
            if (Regex("#[0-9a-fA-F]{6}").matches(value)) (value.drop(1).toLong(16) or 0xff000000L).toInt() else null
    }
}


/** Packed atomic intent: bit zero is opaque, upper bits are the request sequence. */
internal class NativeGodotSurfaceMode {
    private val intent = AtomicLong(0L)
    fun request(opaque: Boolean) {
        intent.updateAndGet { old -> (((old ushr 1) + 1) shl 1) or (if (opaque) 1L else 0L) }
    }
    fun snapshot(): Long = intent.get()
    fun format(): Int = if ((intent.get() and 1L) != 0L) PixelFormat.RGBX_8888 else PixelFormat.TRANSLUCENT
}
