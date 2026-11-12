package app.abelnotes.notes

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Official contract: https://open.oppomobile.com/documentation/page/info?id=13307
 * No vendor SDK/auth code is needed for the documented broadcast path.
 * Receiver is active only for a resumed editor; background events are never queued.
 */
internal class OplusPencilBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "abelnotes/oplus_pencil")
    private var interested = false
    private var resumed = false
    private var registered = false
    private var lastError: String? = null
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION || !interested || !resumed || !activity.hasWindowFocus()) return
            val mode = readMode()
            if (mode == 0) return
            Log.i(TAG, "double-tap received; mode=$mode")
            channel.invokeMethod("doubleTap", mapOf("mode" to mode))
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "attach" -> { interested = true; updateRegistration(); result.success(status()) }
                "detach" -> { interested = false; updateRegistration(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    fun onResume() { resumed = true; updateRegistration() }
    fun onPause() { resumed = false; updateRegistration() }
    fun dispose() { interested = false; updateRegistration(); channel.setMethodCallHandler(null) }

    private fun readMode(): Int = try {
        Settings.Global.getInt(activity.contentResolver, "ipe_pencil_double_click", -1)
    } catch (_: SecurityException) { -1 }

    private fun status(): Map<String, Any?> = mapOf(
        "registered" to registered, "systemMode" to readMode(),
        "model" to Build.MODEL, "androidSdk" to Build.VERSION.SDK_INT,
        "error" to lastError,
    )

    private fun updateRegistration() {
        if (interested && resumed && !registered) {
            try {
                val filter = IntentFilter(ACTION)
                // The sender is an external system service. Keep its permission
                // filter; do not replace it with an unprotected exported receiver.
                if (Build.VERSION.SDK_INT >= 33) {
                    activity.registerReceiver(receiver, filter, PERMISSION, null, Context.RECEIVER_EXPORTED)
                } else {
                    @Suppress("DEPRECATION")
                    activity.registerReceiver(receiver, filter, PERMISSION, null)
                }
                registered = true
                lastError = null
            } catch (e: SecurityException) {
                lastError = "permission-denied"
                Log.w(TAG, "pen receiver permission denied", e)
            } catch (e: IllegalArgumentException) {
                lastError = "receiver-unavailable"
                Log.w(TAG, "pen receiver unavailable", e)
            }
        } else if ((!interested || !resumed) && registered) {
            activity.unregisterReceiver(receiver)
            registered = false
        }
    }

    companion object {
        const val ACTION = "com.oplus.ipemanager.action.PENCIL_DOUBLE_CLICK"
        const val PERMISSION = "com.oplus.ipemanager.permission.receiver.DOUBLE_CLICK"
        private const val TAG = "AbelOplusPencil"
    }
}
