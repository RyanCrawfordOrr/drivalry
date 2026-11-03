package app.drivalry.tracking

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity

/**
 * Receives IN_VEHICLE ENTER/EXIT from the Activity Recognition Transition API
 * (docs/08-tracking-channel.md §6). Manifest-registered, so it also works after the app
 * process has been killed: ENTER starts a tentative trip (the exemption for activity
 * recognition events allows the foreground service to start from here), EXIT feeds the
 * "automotive exit + Bluetooth off" end rule.
 */
class ActivityTransitionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!ActivityTransitionResult.hasResult(intent)) return
        val result = ActivityTransitionResult.extractResult(intent) ?: return
        val runtime = TrackingRuntime.get(context)
        for (event in result.transitionEvents) {
            if (event.activityType != DetectedActivity.IN_VEHICLE) continue
            when (event.transitionType) {
                ActivityTransition.ACTIVITY_TRANSITION_ENTER -> {
                    runtime.machine.onVehicleEnter()
                    runtime.trigger("activity")
                }
                ActivityTransition.ACTIVITY_TRANSITION_EXIT -> runtime.machine.onVehicleExit()
            }
        }
    }
}
