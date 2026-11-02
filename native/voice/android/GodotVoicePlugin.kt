package com.sensen.voice

import android.Manifest
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.livekit.android.LiveKit
import io.livekit.android.events.RoomEvent
import io.livekit.android.events.collect
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.participant.ParticipantTrackPermission
import io.livekit.android.room.participant.RemoteParticipant
import io.livekit.android.room.track.RemoteAudioTrack
import io.livekit.android.room.track.RemoteTrackPublication
import io.livekit.android.util.LoggingLevel
import com.twilio.audioswitch.AudioDevice
import com.sensen.permission.PermissionActivity
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicLong

/** Audio stays in the official native SDK. No samples, URLs or credentials are logged. */
class GodotVoicePlugin(godot: Godot) : GodotPlugin(godot) {
    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val micLock = Mutex()
    private var room: Room? = null
    private var eventJob: Job? = null
    private var connectJob: Job? = null
    private var session = ""
    private var foreground = true
    private var permissionRequest = ""
    private var permissionResult: Boolean? = null
    private var expiresAt = 0L
    private var desiredMic = false
    private var listening = true
    // P0 rooms (2026-11-02): per person, by LiveKit identity (the hub's peer id) — Mute is this phone's volume only,
    // Block never subscribes to them. Both last one session; Godot sets them again after each connect.
    private val muted = mutableSetOf<String>()
    private val blocked = mutableSetOf<String>()
    // SGODOT-384: whom this phone's own tracks are kept from — LiveKit refuses them the subscription (a changed client
    // cannot take it either); everyone else in the room is allowed, the list renewed as people come and go.
    private val denied = mutableSetOf<String>()
    private val decodedFrames = AtomicLong()
    private val decodedEnergy = AtomicLong()
    private val watchdog = object : Runnable {
        override fun run() {
            if (room != null && SystemClock.elapsedRealtime() >= expiresAt) finish("VOICE_EXPIRED")
            if (room != null) handler.postDelayed(this, 500)
        }
    }
    override fun getPluginName() = "GodotVoice"
    override fun getPluginSignals() = setOf(SignalInfo("voice_event", String::class.java))
    @UsedByGodot fun capabilities(): String = JSONObject().put("protocol", 1).put("supported", true).put("platform", "android")
        .put("per_participant", true)   // set_participant_volume / _subscribed (P0 Mute and Block, 2026-11-02)
        .put("publish_permissions", true).toString()   // set_publish_allowed (SGODOT-384)
    @UsedByGodot fun diagnostics(): String = JSONObject().put("decoded_frames", decodedFrames.get()).put("audio_energy", decodedEnergy.get()).toString()
    private fun emit(kind: String, id: String = session, body: JSONObject = JSONObject()) {
        body.put("event", kind).put("session", id)
        emitSignal("voice_event", body.toString())
    }
    @UsedByGodot fun request_permission(id: String) = runOnUiThread {
        val activity = activity ?: return@runOnUiThread emit("permission", id, JSONObject().put("granted", false))
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            emit("permission", id, JSONObject().put("granted", true))
        } else {
            permissionRequest = id
            permissionResult = null
            // Not activity.requestPermissions: GodotActivity's result would start the engine's own microphone input,
            // left open until the app quits (SGODOT-349; PermissionActivity).
            PermissionActivity.request(activity, Manifest.permission.RECORD_AUDIO) { granted ->
                if (permissionRequest != id) return@request
                permissionResult = granted
                flushPermission()
            }
        }
    }
    private fun flushPermission() {
        val result = permissionResult ?: return
        if (!foreground || permissionRequest.isEmpty()) return
        val id = permissionRequest
        permissionRequest = ""; permissionResult = null
        emit("permission", id, JSONObject().put("granted", result))
    }
    @UsedByGodot fun connect_voice(id: String, url: String, token: String) = runOnUiThread {
        finish("REPLACED", false)
        if (!foreground) return@runOnUiThread emit("disconnected", id, JSONObject().put("reason", "BACKGROUND"))
        session = id; desiredMic = false; listening = true; muted.clear(); blocked.clear(); denied.clear()
        decodedFrames.set(0); decodedEnergy.set(0)
        LiveKit.loggingLevel = LoggingLevel.OFF
        val current = LiveKit.create(activity!!.applicationContext)
        current.audioSwitchHandler?.loggingEnabled = false
        room = current
        expiresAt = SystemClock.elapsedRealtime() + 20000
        handler.post(watchdog)
        eventJob = scope.launch {
            current.events.collect { event ->
                if (room !== current || session != id) return@collect
                when (event) {
                    is RoomEvent.Connected, is RoomEvent.Reconnected -> { applyPermissions(); snapshot("connected") }
                    is RoomEvent.Reconnecting -> emit("reconnecting")
                    is RoomEvent.Disconnected -> finish("DISCONNECTED")
                    is RoomEvent.ParticipantConnected, is RoomEvent.ParticipantDisconnected -> {
                        applyPermissions()   // a newcomer allowed unless denied (SGODOT-384)
                        snapshot("participants")
                    }
                    is RoomEvent.ActiveSpeakersChanged, is RoomEvent.TrackMuted, is RoomEvent.TrackUnmuted,
                    is RoomEvent.TrackUnsubscribed, is RoomEvent.TrackSubscriptionPermissionChanged -> snapshot("participants")
                    is RoomEvent.TrackPublished -> {
                        // a blocked person's new track is never taken (P0 Block, 2026-11-02)
                        if (event.participant.identity?.value in blocked) (event.publication as? RemoteTrackPublication)?.setSubscribed(false)
                    }
                    is RoomEvent.TrackSubscribed -> {
                        val who = event.participant.identity?.value
                        if (who != null && who in blocked) {
                            (event.publication as? RemoteTrackPublication)?.setSubscribed(false)
                            return@collect
                        }
                        (event.track as? RemoteAudioTrack)?.let { track ->
                            track.setVolume(volumeFor(who))
                            // Counters only: no recording, retention or transport of PCM.
                            track.addSink { data, bits, _, _, _, _ ->
                                decodedFrames.incrementAndGet()
                                if (bits == 16) {
                                    val copy = data.duplicate().order(ByteOrder.LITTLE_ENDIAN)
                                    var energy = 0L
                                    while (copy.remaining() >= 2) {
                                        val sample = copy.short.toLong(); energy += sample * sample
                                        copy.position((copy.position() + 30).coerceAtMost(copy.limit()))
                                    }
                                    decodedEnergy.addAndGet(energy)
                                }
                            }
                        }
                        snapshot("participants")
                    }
                    else -> Unit
                }
            }
        }
        connectJob = scope.launch {
            try {
                current.connect(url, token)
                if (room === current && session == id) {
                    snapshot("connected")
                }
            } catch (_: CancellationException) { }
              catch (_: Exception) { if (room === current) finish("VOICE_CONNECT_FAILED") }
        }
    }
    @UsedByGodot fun renew_lease(id: String, milliseconds: Int) = runOnUiThread {
        if (id == session && room != null) expiresAt = SystemClock.elapsedRealtime() + milliseconds.coerceIn(0, 20000)
    }
    @UsedByGodot fun set_microphone(id: String, enabled: Boolean) = runOnUiThread {
        if (id != session || room == null) return@runOnUiThread
        desiredMic = enabled
        scope.launch {
            micLock.withLock {
                val current = room ?: return@withLock
                if (session != id) return@withLock
                try {
                    if (desiredMic && activity?.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        desiredMic = false
                        emit("error", body = JSONObject().put("code", "MICROPHONE_DENIED"))
                    }
                    current.localParticipant.setMicrophoneEnabled(desiredMic)
                    if (room === current && session == id) snapshot("microphone")
                } catch (_: Exception) { if (room === current) emit("error", body = JSONObject().put("code", "MICROPHONE_FAILED")) }
            }
        }
    }
    @UsedByGodot fun set_listening(id: String, enabled: Boolean) = runOnUiThread {
        if (id != session) return@runOnUiThread
        listening = enabled
        applyVolumes()
        snapshot("listening")
    }
    /** P0 Mute (2026-11-02): one person's volume on this phone only, 0 or 1; they still hear us. */
    @UsedByGodot fun set_participant_volume(id: String, identity: String, volume: Double) = runOnUiThread {
        if (id != session || identity.isEmpty()) return@runOnUiThread
        if (volume <= 0.0) muted.add(identity) else muted.remove(identity)
        applyVolumes()
        snapshot("participants")
    }
    /** P0 Block (2026-11-02): stop (or start again) taking one person's tracks; the server lists both ways' blocks. */
    @UsedByGodot fun set_participant_subscribed(id: String, identity: String, subscribed: Boolean) = runOnUiThread {
        if (id != session || identity.isEmpty()) return@runOnUiThread
        if (subscribed) blocked.remove(identity) else blocked.add(identity)
        room?.remoteParticipants?.values?.filter { it.identity?.value == identity }?.forEach { participant ->
            participant.trackPublications.values.forEach { (it as? RemoteTrackPublication)?.setSubscribed(subscribed) }
        }
        snapshot("participants")
    }
    /** SGODOT-384 Block: keep (or stop keeping) this phone's tracks from one person — LiveKit refuses their subscription. */
    @UsedByGodot fun set_publish_allowed(id: String, identity: String, allowed: Boolean) = runOnUiThread {
        if (id != session || identity.isEmpty()) return@runOnUiThread
        if (allowed) denied.remove(identity) else denied.add(identity)
        applyPermissions()
    }
    /** Nobody denied: everyone may subscribe. Otherwise only the room's others not denied, each by identity. */
    private fun applyPermissions() {
        val current = room ?: return
        if (denied.isEmpty()) {
            current.localParticipant.setTrackSubscriptionPermissions(true, emptyList())
            return
        }
        val allowed = current.remoteParticipants.values.mapNotNull { it.identity?.value }.filter { it !in denied }
            .map { ParticipantTrackPermission(it, null, true, emptyList()) }
        current.localParticipant.setTrackSubscriptionPermissions(false, allowed)
    }
    private fun volumeFor(identity: String?): Double = if (!listening || (identity != null && identity in muted)) 0.0 else 1.0
    private fun applyVolumes() {
        room?.remoteParticipants?.values?.forEach { participant ->
            val v = volumeFor(participant.identity?.value)
            participant.trackPublications.values.forEach { (it.track as? RemoteAudioTrack)?.setVolume(v) }
        }
    }
    @UsedByGodot fun set_speaker(id: String, enabled: Boolean) = runOnUiThread {
        if (id != session) return@runOnUiThread
        val audio = room?.audioSwitchHandler ?: return@runOnUiThread
        val target = audio.availableAudioDevices.firstOrNull {
            if (enabled) it is AudioDevice.Speakerphone else it is AudioDevice.Earpiece
        }
        audio.selectDevice(target)
    }
    @UsedByGodot fun disconnect_voice(id: String) = runOnUiThread {
        if (id == permissionRequest) { permissionRequest = ""; permissionResult = null }
        if (id == session) finish("LEFT")
    }
    private fun snapshot(kind: String) {
        val current = room ?: return
        val users = JSONArray()
        fun add(p: Participant, local: Boolean) {
            val id = p.identity?.value ?: return
            // SGODOT-384: someone is speaking, or has a microphone on, only as far as this phone takes their audio — LiveKit
            // still says a blocker speaks to the one they blocked, whose card would light with no sound (and tell them).
            val heard = local || audible(p)
            users.put(JSONObject().put("id", id).put("name", p.name ?: id.take(8))
                .put("speaking", p.isSpeaking && heard).put("microphone", p.isMicrophoneEnabled && heard).put("local", local)
                .put("audible", heard).put("muted", id in muted).put("blocked", id in blocked))
        }
        add(current.localParticipant, true)
        current.remoteParticipants.values.forEach { add(it, false) }
        emit(kind, body = JSONObject().put("participants", users).put("microphone", current.localParticipant.isMicrophoneEnabled)
            .put("listening", listening))
    }
    /** A remote participant whose audio this phone has subscribed to (allowed by them and taken by us). */
    private fun audible(p: Participant): Boolean = (p as? RemoteParticipant)?.trackPublications?.values?.any {
        val pub = it as? RemoteTrackPublication
        pub != null && pub.subscribed && pub.track is RemoteAudioTrack
    } ?: false
    private fun finish(reason: String, send: Boolean = true) {
        val previous = room; val id = session
        room = null; session = ""; desiredMic = false
        handler.removeCallbacks(watchdog)
        connectJob?.cancel(); connectJob = null
        eventJob?.cancel(); eventJob = null
        previous?.disconnect(); previous?.release()
        if (send && id.isNotEmpty()) emit("disconnected", id, JSONObject().put("reason", reason))
    }
    override fun onMainPause() {
        foreground = false
        if (permissionRequest.isEmpty()) finish("BACKGROUND")
    }
    override fun onMainResume() { foreground = true; flushPermission() }
    override fun onMainStop() {
        permissionRequest = ""; permissionResult = null
        finish("BACKGROUND")
    }
    override fun onMainDestroy() { finish("DESTROYED", false); scope.cancel(); super.onMainDestroy() }
}
