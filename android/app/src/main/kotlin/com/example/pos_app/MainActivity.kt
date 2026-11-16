package com.example.pos_app

import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "urbanthread/whatsapp")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sharePdf" -> try {
                        result.success(
                            sharePdf(
                                call.argument<ByteArray>("bytes")!!,
                                call.argument<String>("fileName")!!,
                                call.argument<String>("phone"),
                                call.argument<String>("caption") ?: "",
                            )
                        )
                    } catch (e: Exception) {
                        result.error("share_failed", e.message, null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Hands the PDF straight to WhatsApp (or WhatsApp Business). With a
     * [phone] (international digits, e.g. 923001234567) WhatsApp opens that
     * chat; without one it shows its own chat picker.
     * Returns "ok" or "not_installed".
     */
    private fun sharePdf(bytes: ByteArray, fileName: String, phone: String?, caption: String): String {
        val pkg = listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull { isInstalled(it) }
            ?: return "not_installed"

        // Cache dir: Android clears it when space is needed; bills are small.
        val dir = File(cacheDir, "shared_bills").apply { mkdirs() }
        val file = File(dir, fileName).apply { writeBytes(bytes) }
        val uri = FileProvider.getUriForFile(this, "$packageName.billshare", file)

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            setPackage(pkg)
            putExtra(Intent.EXTRA_STREAM, uri)
            if (caption.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, caption)
            if (!phone.isNullOrEmpty()) putExtra("jid", "$phone@s.whatsapp.net")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
        return "ok"
    }

    private fun isInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
}
