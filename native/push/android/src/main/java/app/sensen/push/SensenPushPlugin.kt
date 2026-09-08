// C2 推送（Android）：通知权限 + FCM registration token 的薄桥接。
// 接口与 iOS 桥一致：is_available() / request_authorization() / register_for_remote() /
// token() / platform()；信号 authorization(granted) / token_ready(token) /
// token_failed(reason) / notification(payload, opened)。
//
// 与 iOS 的差别：Android 这边拿的是 **FCM token**（服务端走 FCM HTTP v1），
// iOS 拿的是 APNs token（服务端直连 APNs）。服务端按 platform 分流。
package app.sensen.push

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.messaging.FirebaseMessaging
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class SensenPushPlugin(godot: Godot) : GodotPlugin(godot) {
    companion object {
        const val PERMISSION_REQUEST = 0x5E5F
        const val SIGNAL_AUTHORIZATION = "authorization"
        const val SIGNAL_TOKEN_READY = "token_ready"
        const val SIGNAL_TOKEN_FAILED = "token_failed"
        const val SIGNAL_NOTIFICATION = "notification"

        /** FirebaseMessagingService 是系统实例化的，拿不到插件引用：这里留一个弱入口。 */
        @Volatile
        var instance: SensenPushPlugin? = null
    }

    @Volatile private var cachedToken = ""

    init {
        instance = this
    }

    override fun getPluginName() = "SensenPush"

    override fun getPluginSignals() = setOf(
        SignalInfo(SIGNAL_AUTHORIZATION, java.lang.Boolean::class.java),
        SignalInfo(SIGNAL_TOKEN_READY, String::class.java),
        SignalInfo(SIGNAL_TOKEN_FAILED, String::class.java),
        SignalInfo(SIGNAL_NOTIFICATION, org.godotengine.godot.Dictionary::class.java, java.lang.Boolean::class.java),
    )

    @UsedByGodot
    fun is_available(): Boolean = activity != null

    /** Android 13 以下没有通知权限这回事，直接算授权。 */
    @UsedByGodot
    fun request_authorization() {
        val act = activity ?: return emit(SIGNAL_AUTHORIZATION, false)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return emit(SIGNAL_AUTHORIZATION, true)
        }
        if (act.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return emit(SIGNAL_AUTHORIZATION, true)
        }
        act.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    override fun onMainRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        emit(SIGNAL_AUTHORIZATION, granted)
    }

    /** 取 FCM token。缺 google-services.json 时 getInstance() 会抛——按 token_failed 回报，不崩。 */
    @UsedByGodot
    fun register_for_remote() {
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (task.isSuccessful && task.result != null) {
                    onToken(task.result)
                } else {
                    emit(SIGNAL_TOKEN_FAILED, task.exception?.message ?: "FCM_TOKEN_FAILED")
                }
            }
        } catch (e: Throwable) {
            emit(SIGNAL_TOKEN_FAILED, e.message ?: "FCM_NOT_CONFIGURED")
        }
    }

    @UsedByGodot
    fun token(): String = cachedToken

    @UsedByGodot
    fun platform(): String = "android"

    /** FirebaseMessagingService 轮换 token 时也走这里：上层按同一个信号重报。 */
    fun onToken(token: String) {
        cachedToken = token
        emit(SIGNAL_TOKEN_READY, token)
    }

    /** 用户点开通知（opened=true）或前台收到（false）。正文不进推送，payload 里只有路由 id。 */
    fun onNotification(data: Map<String, String>, opened: Boolean) {
        val dict = org.godotengine.godot.Dictionary()
        data.forEach { (k, v) -> dict[k] = v }
        emit(SIGNAL_NOTIFICATION, dict, opened)
    }

    private fun emit(signal: String, vararg args: Any) {
        emitSignal(signal, *args)
    }
}
