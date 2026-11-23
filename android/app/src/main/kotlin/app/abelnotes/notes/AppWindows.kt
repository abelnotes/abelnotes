package app.abelnotes.notes

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Process-wide record of the app's windows. Each window runs its own Flutter
 * engine, and Dart-side locks don't reach across engines: this is the one
 * place both windows can ask which notebook the other has open.
 */
object WindowRegistry {
    private val windows = LinkedHashSet<Int>() // oldest first
    private val notebooks = HashMap<String, Int>() // notebook id -> window

    @Synchronized fun register(window: Int) { windows.add(window) }

    @Synchronized fun unregister(window: Int) {
        windows.remove(window)
        notebooks.values.removeAll { it == window }
    }

    @Synchronized fun claim(id: String, window: Int): Boolean {
        if (heldElsewhere(id, window)) return false
        notebooks[id] = window
        return true
    }

    @Synchronized fun release(id: String, window: Int) {
        if (notebooks[id] == window) notebooks.remove(id)
    }

    @Synchronized fun heldElsewhere(id: String, window: Int): Boolean {
        val holder = notebooks[id] ?: return false
        return holder != window && windows.contains(holder)
    }

    /** The oldest open window runs the library's background sync. */
    @Synchronized fun isLeader(window: Int) = windows.firstOrNull() == window

    @Synchronized fun count() = windows.size
}

/** The `abelnotes/windows` channel for one window. */
class AppWindowsChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val window = System.identityHashCode(activity)
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        WindowRegistry.register(window)
        open.add(this)
        channel.setMethodCallHandler { call, result ->
            val id = call.arguments as? String
            when (call.method) {
                "claim" -> result.success(id == null || WindowRegistry.claim(id, window))
                "release" -> { if (id != null) WindowRegistry.release(id, window); result.success(null) }
                "heldElsewhere" -> result.success(id != null && WindowRegistry.heldElsewhere(id, window))
                "isLeader" -> result.success(WindowRegistry.isLeader(window))
                "count" -> result.success(WindowRegistry.count())
                // A window saved this notebook: the others showing it reload.
                "notifySaved" -> {
                    if (id != null) open.filter { it !== this }.forEach {
                        it.channel.invokeMethod("saved", id)
                    }
                    result.success(null)
                }
                "openInNewWindow" -> {
                    if (id == null) { result.success(false); return@setMethodCallHandler }
                    activity.startActivity(
                        Intent(activity, WindowActivity::class.java)
                            .putExtra(EXTRA_NOTEBOOK, id)
                            .addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                                    Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT
                            )
                    )
                    result.success(true)
                }
                "takeLaunchNotebook" -> {
                    val launch = activity.intent?.getStringExtra(EXTRA_NOTEBOOK)
                    activity.intent?.removeExtra(EXTRA_NOTEBOOK)
                    result.success(launch)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        open.remove(this)
        channel.setMethodCallHandler(null)
        WindowRegistry.unregister(window)
    }

    companion object {
        private val open = mutableListOf<AppWindowsChannel>()
        const val CHANNEL = "abelnotes/windows"
        const val EXTRA_NOTEBOOK = "app.abelnotes.notes.OPEN_NOTEBOOK"
    }
}
