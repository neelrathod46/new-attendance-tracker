package com.example.attendance

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val profileChannelName = "attendance/student_profile"
    private val profilePreferenceName = "student_profile"
    private val profilePreferenceKey = "encrypted_profile"
    private val encryptionKeyAlias = "attendance_student_profile_key"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            profileChannelName,
        ).setMethodCallHandler { call, result ->
            try {
                val preferences = getSharedPreferences(profilePreferenceName, MODE_PRIVATE)
                when (call.method) {
                    "load" -> {
                        val stored = preferences.getString(profilePreferenceKey, null)
                        result.success(stored?.let { decryptProfile(it) })
                    }
                    "save" -> {
                        val profile = call.argument<String>("profile")
                            ?: throw IllegalArgumentException("Missing profile data")
                        preferences.edit().putString(profilePreferenceKey, encryptProfile(profile)).apply()
                        result.success(null)
                    }
                    "clear" -> {
                        preferences.edit().remove(profilePreferenceKey).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                if (call.method == "load") {
                    getSharedPreferences(profilePreferenceName, MODE_PRIVATE)
                        .edit().remove(profilePreferenceKey).apply()
                    result.success(null)
                    return@setMethodCallHandler
                }
                result.error("PROFILE_STORE", error.message, null)
            }
        }
    }

    private fun profileKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(encryptionKeyAlias, null)
        if (existing is SecretKey) return existing

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                encryptionKeyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encryptProfile(profile: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, profileKey())
        val encrypted = cipher.doFinal(profile.toByteArray(Charsets.UTF_8))
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val body = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        return "$iv.$body"
    }

    private fun decryptProfile(stored: String): String? {
        val parts = stored.split('.', limit = 2)
        if (parts.size != 2) return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            profileKey(),
            GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)),
        )
        val plaintext = cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP))
        return String(plaintext, Charsets.UTF_8)
    }
}
