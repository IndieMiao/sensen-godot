package com.sensen.notify

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject

/**
 * The crop-ready local notification (q(236), SGODOT-350): one at a time, set when the app goes to the background and
 * cancelled when it comes back. An inexact alarm (no SCHEDULE_EXACT_ALARM), so it may come a few minutes late; it
 * fires with the app's process gone, but a phone restart drops it until the app runs again.
 */
class GodotNotifyPlugin(godot: Godot) : GodotPlugin(godot) {
    companion object {
        internal const val CHANNEL_ID = "crops_ready"
        internal const val NOTIFICATION_ID = 350
        internal const val EXTRA_TITLE = "title"
        internal const val EXTRA_BODY = "body"
        internal const val EXTRA_CHANNEL = "channel"
        private const val PERMISSION_CODE = 8618
        private const val PREFS = "sensen_notify"
        private const val ASKED = "asked"

        internal fun ensureChannel(context: Context, name: String) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            // Re-creating keeps a player's own channel settings; it only renames.
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    override fun getPluginName() = "GodotNotify"

    override fun getPluginSignals() = setOf(SignalInfo("permission", java.lang.Boolean::class.java))

    /** {sdk, needs_grant (Android 13+), allowed (the app's notifications and the channel both on), asked (ever by us),
     * app (the name the phone shows for it: `Notifications are off for P0 Demo`)}. */
    @UsedByGodot fun state(): String {
        val context = activity ?: return JSONObject().put("allowed", false).toString()
        return JSONObject()
            .put("sdk", Build.VERSION.SDK_INT)
            .put("needs_grant", Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            .put("allowed", allowed(context))
            .put("asked", context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(ASKED, false))
            .put("app", context.applicationInfo.loadLabel(context.packageManager).toString())
            .toString()
    }

    /** The system dialog (Android 13+); `permission(granted)` answers. Older Android has none: it answers at once. */
    @UsedByGodot fun request_permission() = runOnUiThread {
        val activity = activity ?: return@runOnUiThread emitSignal("permission", false)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return@runOnUiThread emitSignal("permission", allowed(activity))
        activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(ASKED, true).apply()
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_CODE)
    }

    override fun onMainRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        if (code != PERMISSION_CODE) return
        emitSignal("permission", results.isNotEmpty() && results[0] == PackageManager.PERMISSION_GRANTED)
    }

    /** The system's notification settings for this app (Settings › Notifications when the system said no). */
    @UsedByGodot fun open_settings() = runOnUiThread {
        val activity = activity ?: return@runOnUiThread
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + activity.packageName))
        }
        runCatching { activity.startActivity(intent) }
    }

    /** One notification at `atMs` (unix ms), replacing any set before. `channel` is the channel's name. */
    @UsedByGodot fun schedule(atMs: Double, title: String, body: String, channel: String) {
        val context = activity?.applicationContext ?: return
        ensureChannel(context, channel)
        val alarms = context.getSystemService(AlarmManager::class.java)
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs.toLong(), alarm(context, title, body, channel))
    }

    /** The alarm not fired yet and the notification already shown, both gone. */
    @UsedByGodot fun cancel_all() {
        val context = activity?.applicationContext ?: return
        context.getSystemService(AlarmManager::class.java).cancel(alarm(context, "", "", ""))
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun allowed(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        val channel = manager.getNotificationChannel(CHANNEL_ID) ?: return true
        return channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    // One request code and FLAG_UPDATE_CURRENT: a new schedule replaces the old alarm and its words.
    private fun alarm(context: Context, title: String, body: String, channel: String): PendingIntent =
        PendingIntent.getBroadcast(context, 0,
            Intent(context, NotifyReceiver::class.java).putExtra(EXTRA_TITLE, title).putExtra(EXTRA_BODY, body).putExtra(EXTRA_CHANNEL, channel),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
}

/** The alarm went off: show the notification; a tap opens the app as the launcher would, with no deep link. */
class NotifyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra(GodotNotifyPlugin.EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(GodotNotifyPlugin.EXTRA_BODY) ?: ""
        GodotNotifyPlugin.ensureChannel(context, intent.getStringExtra(GodotNotifyPlugin.EXTRA_CHANNEL) ?: "Crops ready")
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        val open = launch?.let { PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, GodotNotifyPlugin.CHANNEL_ID) else Notification.Builder(context)
        val notification = builder
            .setSmallIcon(com.godot.game.R.drawable.ic_notify)   // i-notify (安其拉, 不知火舞 350 04ff7e63)
            .setColor(0xFF3E7D43.toInt())   // color/primary
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .apply { if (open != null) setContentIntent(open) }
            .build()
        runCatching { context.getSystemService(NotificationManager::class.java).notify(GodotNotifyPlugin.NOTIFICATION_ID, notification) }
    }
}
