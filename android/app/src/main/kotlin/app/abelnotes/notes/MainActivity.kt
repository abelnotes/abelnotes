package app.abelnotes.notes

import android.content.Context
import android.net.ConnectivityManager
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pencilBridge: OplusPencilBridge? = null

    override fun onResume() { super.onResume(); pencilBridge?.onResume() }
    override fun onPause() { pencilBridge?.onPause(); super.onPause() }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pencilBridge?.dispose()
        pencilBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pencilBridge = OplusPencilBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // Lets the canvas slow its idle polling on metered data or battery saver.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "abelnotes/sync_thrift")
            .setMethodCallHandler { call, result ->
                if (call.method != "state") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                result.success(mapOf(
                    "metered" to (cm?.isActiveNetworkMetered ?: false),
                    "lowPower" to (pm?.isPowerSaveMode ?: false),
                ))
            }
    }
}
