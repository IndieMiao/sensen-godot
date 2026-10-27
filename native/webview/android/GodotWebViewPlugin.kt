package com.sensen.webview

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.TextView
import com.sensen.permission.PermissionActivity
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Full-screen in-app H5 page above the Godot surface (the window layer sits over the
 * media-overlay SurfaceView). One page at a time; closing destroys the WebView so the
 * microphone and audio focus are released even if the page never cleans up itself.
 */
class GodotWebViewPlugin(godot: Godot) : GodotPlugin(godot) {
    companion object {
        /** Only these hosts may load inside the overlay or receive microphone access. */
        internal fun hostAllowed(host: String?, allowed: Set<String>): Boolean =
            host != null && allowed.any { host == it || host.endsWith(".$it") }
    }

    private var root: FrameLayout? = null
    private var webView: WebView? = null
    private var allowedHosts: Set<String> = emptySet()
    private var pendingPermission: PermissionRequest? = null

    override fun getPluginName() = "GodotWebView"

    override fun getPluginSignals() = setOf(SignalInfo("closed", String::class.java))

    @UsedByGodot fun is_open(): Boolean = root != null

    /** `hosts` is a comma-separated allowlist; links elsewhere open in the system browser. */
    @UsedByGodot fun open(url: String, hosts: String) = runOnUiThread {
        val activity = activity ?: return@runOnUiThread
        if (root != null) return@runOnUiThread
        allowedHosts = hosts.split(',').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()
        if (!hostAllowed(Uri.parse(url).host?.lowercase(), allowedHosts)) {
            emitSignal("closed", "blocked")
            return@runOnUiThread
        }
        if ((activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            WebView.setWebContentsDebuggingEnabled(true) // chrome://inspect for QA builds only.
        }
        val web = createWebView(activity)
        val frame = FrameLayout(activity).apply {
            setBackgroundColor(Color.parseColor("#FFFDF8"))
            isClickable = true // Touches must never fall through to the Godot surface.
            addView(web, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            addView(closeButton(activity), FrameLayout.LayoutParams(dp(40), dp(40), Gravity.TOP or Gravity.END).apply {
                topMargin = dp(12); rightMargin = dp(12)
            })
        }
        // Immersive mode hides the bars; still keep content clear of cutouts.
        frame.setOnApplyWindowInsetsListener { v, insets ->
            val cut = insets.displayCutout
            v.setPadding(cut?.safeInsetLeft ?: 0, cut?.safeInsetTop ?: 0, cut?.safeInsetRight ?: 0, 0)
            insets
        }
        activity.addContentView(frame, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        frame.requestApplyInsets()
        root = frame
        webView = web
        // Key events (system back) must reach the WebView, not the Godot surface;
        // otherwise Godot also receives GO_BACK and pops the scene underneath.
        web.isFocusableInTouchMode = true
        web.requestFocus()
        web.loadUrl(url)
    }

    @UsedByGodot fun close() = runOnUiThread { dismiss("closed") }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(activity: android.app.Activity) = WebView(activity).apply {
        setBackgroundColor(Color.TRANSPARENT)
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true // Language / theme choices live in localStorage.
        settings.mediaPlaybackRequiresUserGesture = false // Review screen plays the clip back.
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                if (hostAllowed(uri.host?.lowercase(), allowedHosts)) return false
                runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                return true
            }
        }
        webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                activity.runOnUiThread { handlePermission(request) }
            }

            override fun onPermissionRequestCanceled(request: PermissionRequest) {
                if (pendingPermission == request) pendingPermission = null
            }
        }
    }

    private fun handlePermission(request: PermissionRequest) {
        val wantsAudio = PermissionRequest.RESOURCE_AUDIO_CAPTURE in request.resources
        if (!wantsAudio || !hostAllowed(request.origin.host?.lowercase(), allowedHosts)) {
            request.deny()
            return
        }
        val activity = activity ?: return request.deny()
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
            return
        }
        pendingPermission?.deny()
        pendingPermission = request
        // Not activity.requestPermissions: GodotActivity's result would start the engine's own microphone input,
        // left open until the app quits (SGODOT-349; PermissionActivity).
        PermissionActivity.request(activity, Manifest.permission.RECORD_AUDIO) { granted ->
            if (pendingPermission != request) return@request // Closed or replaced meanwhile: already denied.
            pendingPermission = null
            if (granted) request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) else request.deny()
        }
    }

    /** System back: history first, then close; Godot never sees it while the page is up. */
    override fun onMainBackPressed(): Boolean {
        val web = webView ?: return false
        runOnUiThread { if (web.canGoBack()) web.goBack() else dismiss("back") }
        return true
    }

    // WebView.onPause hides the page (visibilitychange) and stops its timers, so a
    // well-behaved page drops the microphone when the app goes to the background.
    override fun onMainPause() { webView?.onPause() }

    override fun onMainResume() { webView?.onResume() }

    override fun onMainDestroy() { dismiss("destroyed") }

    private fun dismiss(reason: String) {
        val frame = root ?: return
        pendingPermission?.deny()
        pendingPermission = null
        webView?.apply {
            stopLoading()
            loadUrl("about:blank")
            (parent as? ViewGroup)?.removeView(this)
            destroy()
        }
        webView = null
        (frame.parent as? ViewGroup)?.removeView(frame)
        root = null
        emitSignal("closed", reason)
    }

    private fun closeButton(activity: android.app.Activity) = TextView(activity).apply {
        text = "✕"
        contentDescription = "Close"
        gravity = Gravity.CENTER
        setTextColor(Color.parseColor("#232B30"))
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.WHITE)
            setStroke(dp(1), Color.parseColor("#E4E1D8"))
        }
        elevation = dp(3).toFloat()
        setOnClickListener { dismiss("closed") }
    }

    private fun dp(value: Int): Int = (value * (activity?.resources?.displayMetrics?.density ?: 1f)).toInt()
}
