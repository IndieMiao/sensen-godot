package com.sensen.map

import android.app.Activity
import android.graphics.PixelFormat
import android.util.Log
import android.view.View
import android.widget.FrameLayout
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

    override fun getPluginName() = "GodotMap"

    override fun getPluginSignals() = setOf(
        SignalInfo("map_ready"),
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
            if (mapView != null) return@runOnUiThread
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

    /** HUD 调试用：当前相机状态。注意跨线程读取仅用于展示，不作同步依据。 */
    @UsedByGodot
    fun getCameraInfo(): String {
        val mv = mapView ?: return ""
        val c = mv.mapboxMap.cameraState
        return "%.5f,%.5f,z%.2f,b%.1f,p%.1f".format(
            c.center.latitude(), c.center.longitude(), c.zoom, c.bearing, c.pitch
        )
    }
}
