// Sign in with Google（Android Credential Manager，2026-09-29）。
// Godot 调 signIn(webClientId, nonceHash)；结果以一个 JSON 字符串回 google_sign_in_result：
//   {"ok":true,"id_token":"…","given_name":"…","family_name":"…","email":"…"} 或 {"ok":false,"code":"GOOGLE_CANCELED"|…}
// 用 GetSignInWithGoogleOption：总是弹 Google 账号选择，适合"通过 Google 登录"按钮。
package com.sensen.googleauth

import android.os.CancellationSignal
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject

class GodotGoogleSignInPlugin(godot: Godot) : GodotPlugin(godot) {
    private val tag = "GodotGoogleSignIn"
    @Volatile private var busy = false

    override fun getPluginName() = "GodotGoogleSignIn"

    override fun getPluginSignals() = setOf(SignalInfo("google_sign_in_result", String::class.java))

    private fun emit(result: JSONObject) {
        busy = false
        emitSignal("google_sign_in_result", result.toString())
    }

    private fun fail(code: String) = emit(JSONObject().put("ok", false).put("code", code))

    @UsedByGodot
    fun signIn(webClientId: String, nonceHash: String) {
        val act = activity
        if (act == null) { fail("GOOGLE_UNAVAILABLE"); return }
        if (busy) { fail("GOOGLE_BUSY"); return }
        busy = true
        act.runOnUiThread {
            try {
                val option = GetSignInWithGoogleOption.Builder(webClientId).setNonce(nonceHash).build()
                val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
                CredentialManager.create(act).getCredentialAsync(act, request, CancellationSignal(), ContextCompat.getMainExecutor(act),
                    object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                        override fun onResult(result: GetCredentialResponse) {
                            val credential = result.credential
                            if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                                try {
                                    val google = GoogleIdTokenCredential.createFrom(credential.data)
                                    emit(JSONObject().put("ok", true).put("id_token", google.idToken)
                                        .put("given_name", google.givenName ?: "").put("family_name", google.familyName ?: "")
                                        .put("email", google.id))
                                } catch (e: Exception) {
                                    Log.w(tag, "bad Google credential", e)
                                    fail("GOOGLE_NO_TOKEN")
                                }
                            } else fail("GOOGLE_NO_TOKEN")
                        }
                        override fun onError(e: GetCredentialException) {
                            Log.w(tag, "Google sign-in failed: ${e.type}", e)
                            fail(when (e) {
                                is GetCredentialCancellationException -> "GOOGLE_CANCELED"
                                is NoCredentialException -> "GOOGLE_NO_ACCOUNT"
                                else -> "GOOGLE_FAILED"
                            })
                        }
                    })
            } catch (e: Exception) {
                Log.w(tag, "Google sign-in could not start", e)
                fail("GOOGLE_UNAVAILABLE")
            }
        }
    }
}
