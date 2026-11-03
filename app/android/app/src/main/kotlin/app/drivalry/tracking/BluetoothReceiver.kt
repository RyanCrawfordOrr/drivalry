package app.drivalry.tracking

import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.IntentCompat

/**
 * Car Bluetooth as a trip trigger and as vehicle identification (docs/08-tracking-channel.md §6).
 *
 * ACL_CONNECTED to a car-like device starts a tentative trip (when tracking is enabled and
 * not paused) and emits `hint {kind: bluetooth, name}` for the current trip. The set of
 * connected car devices is remembered so an IN_VEHICLE EXIT only ends the trip once the
 * car's Bluetooth is gone too (§2). On API 31+ the device name and class need
 * BLUETOOTH_CONNECT, which is also what lets this receiver see the broadcast at all.
 */
class BluetoothReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != BluetoothDevice.ACTION_ACL_CONNECTED && action != BluetoothDevice.ACTION_ACL_DISCONNECTED) return
        val device = IntentCompat.getParcelableExtra(intent, BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
            ?: return
        val runtime = TrackingRuntime.get(context)
        val canQuery = Permissions.hasBluetoothConnect(context)
        val address = device.address ?: return

        when (action) {
            BluetoothDevice.ACTION_ACL_CONNECTED -> {
                if (!isCarLike(device, canQuery)) return
                val name = if (canQuery) runCatching { device.name }.getOrNull() else null
                runtime.prefs.connectedCarDevices = runtime.prefs.connectedCarDevices + address
                runtime.machine.onVehicleEnter()
                runtime.trigger("bluetooth")
                // Hint for whichever trip is now running (the one just started, or an earlier
                // one that is still active). It identifies the vehicle for the garage.
                val tripId = runtime.machine.tripId
                if (tripId != null && runtime.machine.phase != TripStateMachine.Phase.IDLE) {
                    runtime.events.hint(tripId, "bluetooth", name)
                }
            }
            BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                val connected = runtime.prefs.connectedCarDevices
                if (address !in connected) return
                runtime.prefs.connectedCarDevices = connected - address
                runtime.machine.onCarBluetoothDisconnected()
            }
        }
    }

    /**
     * Car kits advertise as CAR_AUDIO or HANDSFREE. Everything that is clearly not a car
     * (watches, keyboards, headphones) is ignored so it does not arm GPS for 120 s. When
     * the class cannot be read, the device is given the benefit of the doubt; a wrong
     * guess costs one discarded tentative trip.
     */
    private fun isCarLike(device: BluetoothDevice, canQuery: Boolean): Boolean {
        if (!canQuery) return true
        val cls = runCatching { device.bluetoothClass }.getOrNull() ?: return true
        return when (cls.deviceClass) {
            BluetoothClass.Device.AUDIO_VIDEO_CAR_AUDIO,
            BluetoothClass.Device.AUDIO_VIDEO_HANDSFREE,
            BluetoothClass.Device.AUDIO_VIDEO_UNCATEGORIZED,
            -> true
            else -> false
        }
    }
}
