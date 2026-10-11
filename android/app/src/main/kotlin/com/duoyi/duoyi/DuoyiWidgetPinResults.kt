package com.duoyi.duoyi

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/** One application store and one handoff timer, shared by activities and callbacks. */
object DuoyiWidgetPinResults {
    private var store: DuoyiWidgetPinResultStore? = null
    private val handler = Handler(Looper.getMainLooper())
    private var cleanup: Runnable? = null

    @Synchronized
    fun record(context: Context, result: DuoyiWidgetPinResultCore.Record) = use(context) { it.record(result) }

    @Synchronized
    fun read(context: Context, requestId: String): Map<String, Any>? = use(context) { it.read(requestId) }

    @Synchronized
    fun clear(context: Context, requestId: String) = use(context) { it.clear(requestId) }

    @Synchronized
    fun reserveHandoff(context: Context, requestId: String) = use(context) { it.reserveHandoff(requestId) }

    @Synchronized
    fun releaseHandoff(context: Context, requestId: String) = use(context) { it.releaseHandoff(requestId) }

    @Synchronized
    fun beginWait(context: Context, requestId: String, owner: String, timeoutMillis: Long): String? =
        use(context) { it.beginWait(requestId, owner, timeoutMillis) }

    @Synchronized
    fun endWait(context: Context, requestId: String, owner: String, token: String) =
        use(context) { it.endWait(requestId, owner, token) }

    @Synchronized
    fun releaseOwner(context: Context, owner: String) = use(context) { it.releaseOwner(owner) }

    @Synchronized
    fun prune(context: Context) = use(context) { it.prune() }

    private fun <T> use(context: Context, operation: (DuoyiWidgetPinResultStore) -> T): T {
        val current = store ?: DuoyiWidgetPinResultStore(
            context.applicationContext.getSharedPreferences(
                DuoyiWidgetPinResultReceiver.prefsName,
                Context.MODE_PRIVATE,
            ),
            DuoyiWidgetPinResultRetention(nowMillis = SystemClock::uptimeMillis),
        ).also {
            store = it
            it.prune()
        }
        return try {
            operation(current)
        } finally {
            scheduleCleanup(current)
        }
    }

    private fun scheduleCleanup(current: DuoyiWidgetPinResultStore) {
        cleanup?.let { handler.removeCallbacks(it) }
        cleanup = null
        val delay = current.nextCleanupDelayMillis() ?: return
        val task = Runnable {
            synchronized(this) {
                current.prune()
                scheduleCleanup(current)
            }
        }
        cleanup = task
        // Handoff uses uptime too. Active engine-owned tokens have no expiry timer.
        handler.postDelayed(task, delay)
    }
}
