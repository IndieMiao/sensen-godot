package com.sensen.permission

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle

/**
 * Asks for one runtime permission from its own invisible activity, so the result never reaches GodotActivity.
 * Godot 4.7.2 hands every result GodotActivity gets to GodotLib.requestPermissionResult, which starts the engine's own
 * audio input on a RECORD_AUDIO grant (java_godot_lib_jni.cpp) and nothing stops it: after the first grant from the
 * system dialog the microphone stayed open until the app quit (SGODOT-349, 李元芳 2f1822b4).
 */
class PermissionActivity : Activity() {
    companion object {
        private const val EXTRA = "permission"
        private const val CODE = 1
        private var pending: ((Boolean) -> Unit)? = null
        private var asking: String? = null   // the permission whose dialog is up, if any

        /** `done` runs on the main thread with the answer; a request still waiting is answered `false` first. Asked
         * again while its dialog is up, the one dialog answers the newer request: no second dialog (周瑜 on #519). */
        fun request(from: Activity, permission: String, done: (Boolean) -> Unit) {
            val previous = pending
            pending = done
            previous?.invoke(false)
            if (asking == permission) return
            asking = permission
            from.startActivity(Intent(from, PermissionActivity::class.java).putExtra(EXTRA, permission)
                .addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION))
        }
    }

    private var answered = false

    override fun onCreate(saved: Bundle?) {
        super.onCreate(saved)
        if (saved != null) return // Recreated while the dialog is up: its result still comes here.
        val permission = intent.getStringExtra(EXTRA) ?: return answer(false)
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return answer(true)
        requestPermissions(arrayOf(permission), CODE)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        // Back on the dialog gives an empty result: a denial.
        answer(code == CODE && results.isNotEmpty() && results[0] == PackageManager.PERMISSION_GRANTED)
    }

    // Gone without an answer, not to be recreated: a denial, so the asker hears back and the next request can show its
    // dialog (a config change outside configChanges — language, font size — recreates it, and the new one answers). Home while
    // the dialog is up, then the launcher icon, clears the task down to GodotActivity and finishes this one with the
    // dialog (李元芳 #519 6436847433 ⑧: before, the page waited for an answer that never came).
    override fun onDestroy() {
        super.onDestroy()
        if (!answered && !isChangingConfigurations) answer(false)   // recreated for a config change: the new one answers
    }

    private fun answer(granted: Boolean) {
        if (answered) return
        answered = true
        val done = pending
        pending = null
        asking = null
        if (!isFinishing && !isDestroyed) {
            finish()
            overridePendingTransition(0, 0)
        }
        done?.invoke(granted)
    }
}
