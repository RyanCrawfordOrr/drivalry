package app.drivalry.tracking

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/** Builds the `Permissions` map of docs/08-tracking-channel.md §3.2 and the checks behind it. */
object Permissions {
    fun granted(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    fun hasFineLocation(context: Context) = granted(context, Manifest.permission.ACCESS_FINE_LOCATION)

    fun hasAnyLocation(context: Context) =
        hasFineLocation(context) || granted(context, Manifest.permission.ACCESS_COARSE_LOCATION)

    fun hasBackgroundLocation(context: Context) =
        granted(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)

    fun hasActivityRecognition(context: Context) =
        granted(context, Manifest.permission.ACTIVITY_RECOGNITION)

    fun hasBluetoothConnect(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            granted(context, Manifest.permission.BLUETOOTH_CONNECT)

    fun hasPostNotifications(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            granted(context, Manifest.permission.POST_NOTIFICATIONS)

    fun snapshot(context: Context, prefs: TrackingPrefs): Map<String, Any?> {
        val location = when {
            hasBackgroundLocation(context) && hasAnyLocation(context) -> "always"
            hasAnyLocation(context) -> "whileInUse"
            else -> "denied"
        }

        val motion = tri(
            granted = hasActivityRecognition(context),
            asked = prefs.wasPermissionAsked(Manifest.permission.ACTIVITY_RECOGNITION),
        )

        val notifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            tri(
                granted = granted(context, Manifest.permission.POST_NOTIFICATIONS),
                asked = prefs.wasPermissionAsked(Manifest.permission.POST_NOTIFICATIONS),
            )
        } else {
            if (NotificationManagerCompat.from(context).areNotificationsEnabled()) "granted" else "denied"
        }

        val bluetooth = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            tri(
                granted = granted(context, Manifest.permission.BLUETOOTH_CONNECT),
                asked = prefs.wasPermissionAsked(Manifest.permission.BLUETOOTH_CONNECT),
            )
        } else {
            "granted"
        }

        return linkedMapOf(
            "location" to location,
            "preciseLocation" to hasFineLocation(context),
            "motion" to motion,
            "notifications" to notifications,
            "bluetooth" to bluetooth,
        )
    }

    private fun tri(granted: Boolean, asked: Boolean): String = when {
        granted -> "granted"
        asked -> "denied"
        else -> "notDetermined"
    }
}
