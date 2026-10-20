package com.carriez.flutter_hbb

// Electronics Remote: descarga la APK del bucket propio (o del release) con DownloadManager y
// abre el instalador del sistema. DownloadManager entrega un content:// propio,
// asi que no hace falta FileProvider.

import android.app.Activity
import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import java.security.MessageDigest

object ErUpdater {
    private const val TAG = "ErUpdater"
    private const val APK_MIME = "application/vnd.android.package-archive"
    private var receiver: BroadcastReceiver? = null

    /** [sha256]: el de latest.json del bucket; vacío = sin verificar (respaldo de GitHub). */
    fun downloadAndInstall(activity: Activity, url: String, sha256: String = ""): Boolean {
        if (!url.startsWith("https://github.com/Electronics-Mexico-2026/electronics-remote/releases/") &&
            !url.startsWith("https://storage.googleapis.com/electronics-mexico-webhooks-fotos-publicas/electronics-remote/")) {
            Log.e(TAG, "URL no permitida: $url")
            return false
        }
        return try {
            val ctx = activity.applicationContext
            val dm = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val request = DownloadManager.Request(Uri.parse(url))
                .setTitle("Electronics Remote")
                .setDescription("Descargando actualizacion")
                .setMimeType(APK_MIME)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalFilesDir(ctx, null, "ElectronicsRemote-update.apk")
            ctx.getExternalFilesDir(null)?.let { java.io.File(it, "ElectronicsRemote-update.apk").delete() }
            val id = dm.enqueue(request)
            register(activity, dm, id, sha256.trim().lowercase())
            true
        } catch (e: Exception) {
            Log.e(TAG, "No se pudo descargar: $e")
            false
        }
    }

    private fun register(activity: Activity, dm: DownloadManager, id: Long, sha256: String) {
        val ctx = activity.applicationContext
        receiver?.let { runCatching { ctx.unregisterReceiver(it) } }
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                if (intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) != id) return
                runCatching { ctx.unregisterReceiver(this) }
                receiver = null
                val uri = dm.getUriForDownloadedFile(id)
                if (uri == null) {
                    Log.e(TAG, "Descarga fallida")
                    toast(ctx, "No se pudo descargar la actualización. Revisa la red e inténtalo de nuevo.")
                    return
                }
                if (sha256.isEmpty()) {
                    install(activity, uri)
                    return
                }
                // 50+ MB: el sha256 se calcula fuera del hilo principal.
                Thread {
                    val got = runCatching {
                        ctx.contentResolver.openInputStream(uri)?.use { input ->
                            val md = MessageDigest.getInstance("SHA-256")
                            val buf = ByteArray(1 shl 16)
                            while (true) {
                                val n = input.read(buf)
                                if (n < 0) break
                                md.update(buf, 0, n)
                            }
                            md.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
                        }
                    }.getOrNull()
                    Handler(Looper.getMainLooper()).post {
                        if (got == sha256) {
                            install(activity, uri)
                        } else {
                            Log.e(TAG, "sha256 no coincide: $got != $sha256")
                            runCatching { dm.remove(id) }
                            toast(ctx, "La actualización llegó dañada y no se instaló. Inténtalo de nuevo.")
                        }
                    }
                }.start()
            }
        }
        receiver = r
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (Build.VERSION.SDK_INT >= 33) {
            ctx.registerReceiver(r, filter, Context.RECEIVER_EXPORTED)
        } else {
            ctx.registerReceiver(r, filter)
        }
    }

    private fun toast(ctx: Context, msg: String) {
        runCatching { Toast.makeText(ctx, msg, Toast.LENGTH_LONG).show() }
    }

    private fun install(activity: Activity, uri: Uri) {
        // Si falta el permiso «instalar apps desconocidas», el instalador del
        // sistema lo pide por si mismo.
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { activity.startActivity(intent) }
            .onFailure { Log.e(TAG, "No se pudo abrir el instalador: $it") }
    }
}
