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

        /** `done` runs on the main thread with the answer; a request still waiting is answered `false` first. */
        fun request(from: Activity, permission: String, done: (Boolean) -> Unit) {
            pending?.invoke(false)
            pending = done
            from.startActivity(Intent(from, PermissionActivity::class.java).putExtra(EXTRA, permission)
                .addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION))
        }
    }

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

    private fun answer(granted: Boolean) {
        val done = pending
        pending = null
        finish()
        overridePendingTransition(0, 0)
        done?.invoke(granted)
    }
}
