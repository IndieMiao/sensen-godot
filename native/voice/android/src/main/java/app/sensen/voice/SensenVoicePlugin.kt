// C4 语音（Android）：LiveKit Android SDK 的薄桥接。接口与 iOS 桥一致：
// is_available() / connect_room(url, token) / disconnect_room() / set_mic(enabled) /
// set_volume(identity, volume) / speakers() / poll()；
// 信号 connected() / disconnected(reason) / speaking(identity, speaking) / error(message)。
//
// 与 iOS 的差别：这边直接发信号（JVM 侧回调进 Godot 是现成的），poll() 是空的——
// iOS 那边 Swift 回调不进 C++，只能每帧取快照。上层两边一视同仁地每帧 poll()。
//
// 麦克风闸门在**服务端签的 token** 上（canPublish）：setMic(true) 时若无发布权限，
// LiveKit 会抛，我们照实发 error，不去猜「应该能不能说」。
package app.sensen.voice

import android.Manifest
import android.content.pm.PackageManager
import io.livekit.android.LiveKit
import io.livekit.android.events.RoomEvent
import io.livekit.android.events.collect
import io.livekit.android.room.Room
import io.livekit.android.room.track.RemoteAudioTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class SensenVoicePlugin(godot: Godot) : GodotPlugin(godot) {
    companion object {
        const val PERMISSION_REQUEST = 0x5E60
        const val SIGNAL_CONNECTED = "connected"
        const val SIGNAL_DISCONNECTED = "disconnected"
        const val SIGNAL_SPEAKING = "speaking"
        const val SIGNAL_ERROR = "error"
    }

    private var room: Room? = null
    private var scope: CoroutineScope? = null
    private var eventJob: Job? = null
    private var speaking: Set<String> = emptySet()
    /// 权限还没给时先记着，拿到就接着连。
    private var pending: Pair<String, String>? = null

    override fun getPluginName() = "SensenVoice"

    override fun getPluginSignals() = setOf(
        SignalInfo(SIGNAL_CONNECTED),
        SignalInfo(SIGNAL_DISCONNECTED, String::class.java),
        SignalInfo(SIGNAL_SPEAKING, String::class.java, java.lang.Boolean::class.java),
        SignalInfo(SIGNAL_ERROR, String::class.java),
    )

    @UsedByGodot
    fun is_available(): Boolean = activity != null

    @UsedByGodot
    fun connect_room(url: String, token: String) {
        val act = activity ?: return emitSignal(SIGNAL_ERROR, "no_activity")
        if (act.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pending = url to token
            act.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
            return
        }
        doConnect(url, token)
    }

    override fun onMainRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val waiting = pending
        pending = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        // 没给录音权限也照样进房：能听不能说，和「服务端没给发布权限」是同一种降级。
        if (waiting != null) doConnect(waiting.first, waiting.second)
        if (!granted) emitSignal(SIGNAL_ERROR, "mic_permission_denied")
    }

    private fun doConnect(url: String, token: String) {
        val act = activity ?: return
        disconnectInternal()
        val created = LiveKit.create(act.applicationContext)
        room = created
        val s = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        scope = s
        eventJob = s.launch {
            created.events.collect { event -> onRoomEvent(event) }
        }
        s.launch {
            try {
                created.connect(url, token)
                created.localParticipant.setMicrophoneEnabled(false) // 上麦是显式动作
            } catch (e: Throwable) {
                emitSignal(SIGNAL_ERROR, e.message ?: "connect_failed")
                emitSignal(SIGNAL_DISCONNECTED, "connect_failed")
            }
        }
    }

    private fun onRoomEvent(event: RoomEvent) {
        when (event) {
            is RoomEvent.Connected -> emitSignal(SIGNAL_CONNECTED)
            is RoomEvent.Disconnected -> emitSignal(SIGNAL_DISCONNECTED, event.error?.let { "error" } ?: "closed")
            is RoomEvent.ActiveSpeakersChanged -> {
                val now = event.speakers.mapNotNull { it.identity?.value }.toSet()
                (now - speaking).forEach { emitSignal(SIGNAL_SPEAKING, it, true) }
                (speaking - now).forEach { emitSignal(SIGNAL_SPEAKING, it, false) }
                speaking = now
            }
            else -> Unit
        }
    }

    @UsedByGodot
    fun disconnect_room() {
        disconnectInternal()
    }

    private fun disconnectInternal() {
        eventJob?.cancel()
        eventJob = null
        room?.disconnect()
        room = null
        scope?.cancel()
        scope = null
        speaking = emptySet()
    }

    @UsedByGodot
    fun set_mic(enabled: Boolean) {
        val r = room ?: return
        scope?.launch {
            try {
                r.localParticipant.setMicrophoneEnabled(enabled)
            } catch (e: Throwable) {
                // 服务端没给发布权限时走这里：UI 保持静音。
                emitSignal(SIGNAL_ERROR, e.message ?: "mic_failed")
            }
        }
    }

    /** 本地压低某个人的声音（举报后立刻静音，不等服务端处理）。 */
    @UsedByGodot
    fun set_volume(identity: String, volume: Float) {
        val r = room ?: return
        val participant = r.remoteParticipants.values.firstOrNull { it.identity?.value == identity } ?: return
        // Android 侧是方法 setVolume(double)，不是属性（iOS 那边才是 .volume）。
        participant.audioTrackPublications.forEach { (_, track) ->
            (track as? RemoteAudioTrack)?.setVolume(volume.toDouble())
        }
    }

    @UsedByGodot
    fun speakers(): Array<String> = speaking.toTypedArray()

    /** iOS 侧靠它取状态快照；这边直接发信号，留个空的让上层一视同仁。 */
    @UsedByGodot
    fun poll() {
    }

    override fun onMainDestroy() {
        disconnectInternal()
    }
}
