package com.carriez.flutter_hbb

// Electronics Remote: descarga la APK del bucket propio (o del release) con DownloadManager,
// compara su sha256 con el de latest.json y abre el instalador del sistema.
// DownloadManager entrega un content:// propio, así que no hace falta FileProvider.

import android.app.Activity
import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import java.lang.ref.WeakReference
import java.security.MessageDigest

object ErUpdater {
    private const val TAG = "ErUpdater"
    private const val APK_MIME = "application/vnd.android.package-archive"
    private var receiver: BroadcastReceiver? = null
    private var activityRef: WeakReference<Activity>? = null
    // La app está al frente (MainActivity entre onResume y onPause).
    @Volatile private var resumed = false
    // APK ya verificada esperando a que la persona vuelva a la app: Android 10+
    // no deja abrir el instalador desde segundo plano.
    private var pendingInstall: Uri? = null

    fun onResume(activity: Activity) {
        resumed = true
        activityRef = WeakReference(activity)
        pendingInstall?.let {
            pendingInstall = null
            install(activity.applicationContext, it)
        }
    }

    fun onPause() {
        resumed = false
    }

    /**
     * [sha256]: el de latest.json del bucket; vacío = sin verificar (respaldo de GitHub).
     * [auto]: revisión automática: solo por WiFi (red sin medir).
     * Devuelve false si no se pudo (o si es automática y la red es de datos).
     */
    fun downloadAndInstall(activity: Activity, url: String, sha256: String = "", auto: Boolean = false): Boolean {
        if (!url.startsWith("https://github.com/Electronics-Mexico-2026/electronics-remote/releases/") &&
            !url.startsWith("https://storage.googleapis.com/electronics-mexico-webhooks-fotos-publicas/electronics-remote/")) {
            Log.e(TAG, "URL no permitida: $url")
            return false
        }
        activityRef = WeakReference(activity)
        val ctx = activity.applicationContext
        // Al tocar «Buscar actualizaciones» sin el permiso, primero se pide: en
        // Samsung, darlo desde el instalador suele cancelar la instalación.
        // En la automática no se abre Ajustes sin que la persona lo pida; ahí
        // el instalador del sistema lo pide por sí mismo.
        if (!auto && Build.VERSION.SDK_INT >= 26 && !ctx.packageManager.canRequestPackageInstalls()) {
            toast(ctx, "Permite «Instalar apps desconocidas» para Electronics Remote y vuelve a tocar «Buscar actualizaciones».")
            runCatching {
                activity.startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}"))
                )
            }.onFailure { Log.e(TAG, "No se pudo abrir el permiso de instalar: $it") }
            return true
        }
        if (auto) {
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (cm == null || cm.isActiveNetworkMetered) {
                Log.i(TAG, "Actualización automática pospuesta: no hay WiFi")
                return false
            }
        }
        return try {
            val dm = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val request = DownloadManager.Request(Uri.parse(url))
                .setTitle("Electronics Remote")
                .setDescription("Descargando actualización")
                .setMimeType(APK_MIME)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalFilesDir(ctx, null, "ElectronicsRemote-update.apk")
            if (auto) {
                // Nunca gastar datos móviles en la APK (unos 55 MB).
                request.setAllowedOverMetered(false).setAllowedOverRoaming(false)
            }
            ctx.getExternalFilesDir(null)?.let { java.io.File(it, "ElectronicsRemote-update.apk").delete() }
            val id = dm.enqueue(request)
            register(ctx, dm, id, sha256.trim().lowercase())
            true
        } catch (e: Exception) {
            Log.e(TAG, "No se pudo descargar: $e")
            false
        }
    }

    /** Estado real de la descarga según DownloadManager (no según quien mandó el aviso). */
    private fun status(dm: DownloadManager, id: Long): Int {
        return runCatching {
            dm.query(DownloadManager.Query().setFilterById(id))?.use { c ->
                if (c.moveToFirst()) {
                    c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                } else {
                    -1
                }
            } ?: -1
        }.getOrDefault(-1)
    }

    private fun register(ctx: Context, dm: DownloadManager, id: Long, sha256: String) {
        receiver?.let { runCatching { ctx.unregisterReceiver(it) } }
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                if (intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) != id) return
                // El receptor tiene que ser exportado para recibir el aviso de
                // DownloadProvider, así que cualquier app podría mandar uno falso:
                // solo se actúa si DownloadManager confirma que esa descarga terminó.
                val st = status(dm, id)
                if (st != DownloadManager.STATUS_SUCCESSFUL && st != DownloadManager.STATUS_FAILED) return
                runCatching { ctx.unregisterReceiver(this) }
                receiver = null
                val uri = if (st == DownloadManager.STATUS_SUCCESSFUL) dm.getUriForDownloadedFile(id) else null
                if (uri == null) {
                    Log.e(TAG, "Descarga fallida")
                    toast(ctx, "No se pudo descargar la actualización. Revisa la red e inténtalo de nuevo.")
                    return
                }
                if (sha256.isEmpty()) {
                    install(ctx, uri)
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
                            install(ctx, uri)
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

    private fun install(ctx: Context, uri: Uri) {
        val activity = activityRef?.get()
        if (!resumed || activity == null || activity.isFinishing) {
            // Android 10+ bloquea en silencio abrir el instalador desde segundo
            // plano: se guarda y se abre al volver a la app.
            pendingInstall = uri
            toast(ctx, "La actualización de Electronics Remote está lista. Abre la app para instalarla.")
            return
        }
        // Si falta el permiso «instalar apps desconocidas», el instalador del
        // sistema lo pide por sí mismo.
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { activity.startActivity(intent) }
            .onFailure { Log.e(TAG, "No se pudo abrir el instalador: $it") }
    }
}
