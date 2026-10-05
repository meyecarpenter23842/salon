package com.ungdungthongminh.salonmanager

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val alias = "salon_companion_device_v1"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(alias, null)
        if (existing is SecretKey) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).build())
        return generator.generateKey()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "salon/companion_credentials")
            .setMethodCallHandler { call, result ->
                try {
                    val prefs = getSharedPreferences("companion_credentials", MODE_PRIVATE)
                    when (call.method) {
                        "read" -> {
                            val stored = prefs.getString("ciphertext", null)
                            if (stored == null) {
                                result.success(null)
                            } else {
                                val parts = stored.split(":")
                                require(parts.size == 2)
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.DECRYPT_MODE, key(),
                                    GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                                result.success(String(cipher.doFinal(
                                    Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
                            }
                        }
                        "write" -> {
                            val value = call.arguments as String
                            require(value.length <= 32768)
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, key())
                            val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
                            val payload = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
                                Base64.encodeToString(encrypted, Base64.NO_WRAP)
                            check(prefs.edit().putString("ciphertext", payload).commit())
                            result.success(null)
                        }
                        "clear" -> {
                            check(prefs.edit().clear().commit())
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("credential_storage", "Không lưu được quyền điện thoại.", null)
                }
            }
    }
}
