package app.drivalry.tracking

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Play services drops activity-transition, geofence and location PendingIntent
 * registrations on reboot and on app update; this receiver puts them back when tracking is
 * enabled. A trip that was in progress is resumed (its own timers end it if the car is
 * parked), and the "car Bluetooth connected" memory is cleared on boot because every ACL
 * link is gone after a restart.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val runtime = TrackingRuntime.get(context)
        if (action == Intent.ACTION_BOOT_COMPLETED) runtime.prefs.connectedCarDevices = emptySet()
        runtime.armIfEnabled()
        runtime.resumeServiceIfNeeded()
    }
}
